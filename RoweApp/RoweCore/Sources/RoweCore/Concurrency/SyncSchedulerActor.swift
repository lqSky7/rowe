import Foundation

public enum SyncStatus: String, Sendable {
    case localOnly = "Local Only"
    case online = "Online"
    case syncing = "Syncing"
    case offline = "Offline"
}

public struct SyncDiagnostics: Hashable, Sendable {
    public var status: SyncStatus
    public var pendingCount: Int
    public var uploadingCount: Int
    public var syncedCount: Int
    public var lastSyncedAt: Date

    public init(
        status: SyncStatus = .online,
        pendingCount: Int = 0,
        uploadingCount: Int = 0,
        syncedCount: Int = 1,
        lastSyncedAt: Date = Date()
    ) {
        self.status = status
        self.pendingCount = pendingCount
        self.uploadingCount = uploadingCount
        self.syncedCount = syncedCount
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Transport boundary for the future Go sync backend.
public protocol SyncTransport: Sendable {
    func pushOperations(_ operationIds: [String]) async throws
}

public struct LocalNoOpSyncTransport: SyncTransport {
    public init() {}
    public func pushOperations(_ operationIds: [String]) async throws {
        // Placeholder until the Go backend is connected.
    }
}

public struct CallbackSyncTransport: SyncTransport {
    private let handler: @Sendable ([String]) async throws -> Void
    public init(_ handler: @escaping @Sendable ([String]) async throws -> Void) {
        self.handler = handler
    }
    public func pushOperations(_ operationIds: [String]) async throws {
        try await handler(operationIds)
    }
}

/// Implements Craft's recovered SyncStrategy debouncing tiers (0.14s / 1.0s / 3.0s)
/// with a 120s idle reset and 3s max debounce cap.
public actor SyncSchedulerActor {
    private var transport: any SyncTransport
    private var isRealtimeCollaboration: Bool = false
    private var syncOperationsSinceLastReset: Int = 0
    private var timeOfLastUserEdit: Date = .distantPast
    private var timeOfDebounceTimerStarted: Date?
    private var queuedOperationIds: [String] = []
    private var scheduledTask: Task<Void, Never>?
    private var diagnostics: SyncDiagnostics = SyncDiagnostics()
    private var onDiagnosticsChanged: (@Sendable (SyncDiagnostics) -> Void)?

    public init(transport: any SyncTransport = LocalNoOpSyncTransport()) {
        self.transport = transport
    }

    public func setDiagnosticsHandler(_ handler: @escaping @Sendable (SyncDiagnostics) -> Void) {
        onDiagnosticsChanged = handler
        handler(diagnostics)
    }

    public func setTransport(_ newTransport: any SyncTransport) {
        transport = newTransport
    }

    public func recordMutation(id: String = UUID().uuidString, now: Date = Date()) {
        queuedOperationIds.append(id)
        diagnostics.pendingCount = queuedOperationIds.count

        if now.timeIntervalSince(timeOfLastUserEdit) > 120.0 {
            syncOperationsSinceLastReset = 0
        }
        timeOfLastUserEdit = now
        syncOperationsSinceLastReset += 1

        let delay = computeDelay(now: now)
        if timeOfDebounceTimerStarted == nil {
            timeOfDebounceTimerStarted = now
        }

        scheduledTask?.cancel()
        scheduledTask = Task {
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await self.flushQueue()
        }
        emitDiagnostics()
    }

    public func syncNow() async {
        scheduledTask?.cancel()
        await flushQueue()
    }

    public func resetSyncState() {
        scheduledTask?.cancel()
        queuedOperationIds.removeAll()
        syncOperationsSinceLastReset = 0
        timeOfDebounceTimerStarted = nil
        diagnostics = SyncDiagnostics(status: .online, pendingCount: 0, uploadingCount: 0, syncedCount: 0, lastSyncedAt: Date())
        emitDiagnostics()
    }

    public func currentDiagnostics() -> SyncDiagnostics {
        diagnostics
    }

    private func computeDelay(now: Date) -> TimeInterval {
        if isRealtimeCollaboration { return 0.14 }
        if let started = timeOfDebounceTimerStarted, now.timeIntervalSince(started) > 3.0 {
            return 0.14
        }
        switch syncOperationsSinceLastReset {
        case ..<60: return 0.14
        case 60..<80: return 1.0
        default: return 3.0
        }
    }

    private func flushQueue() async {
        guard !queuedOperationIds.isEmpty else {
            diagnostics.lastSyncedAt = Date()
            diagnostics.status = .online
            emitDiagnostics()
            return
        }

        let batch = queuedOperationIds
        queuedOperationIds.removeAll()
        timeOfDebounceTimerStarted = nil

        diagnostics.status = .syncing
        diagnostics.pendingCount = 0
        diagnostics.uploadingCount = batch.count
        emitDiagnostics()

        do {
            try await transport.pushOperations(batch)
            diagnostics.uploadingCount = 0
            diagnostics.syncedCount += batch.count
            diagnostics.status = .online
            diagnostics.lastSyncedAt = Date()
        } catch {
            queuedOperationIds.insert(contentsOf: batch, at: 0)
            diagnostics.pendingCount = queuedOperationIds.count
            diagnostics.uploadingCount = 0
            diagnostics.status = .offline
        }
        emitDiagnostics()
    }

    private func emitDiagnostics() {
        onDiagnosticsChanged?(diagnostics)
    }
}

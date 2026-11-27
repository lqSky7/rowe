import Foundation

public struct WorkspaceSnapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var space: Space
    public var folders: [Folder]
    public var tags: [TagItem]
    public var sidebarSections: [SidebarSectionState]
    public var documents: [RoweDocument]
    public var sharedDocuments: [SharedDocumentItem]
    public var connections: [ConnectionItem]
    public var settings: AppSettings
    public var vaultEnvelope: VaultKeyEnvelope?
    public var authSession: AuthSession?
    public var serverURL: String?
    public var lastSyncServerTimeMs: Int64
    public var dirtyDocumentIds: [String]
    public var pendingRemoteDeleteIds: [String]
    public var focusBehavior: FocusBehaviorState

    public init(
        schemaVersion: Int = 1,
        space: Space,
        folders: [Folder],
        tags: [TagItem],
        sidebarSections: [SidebarSectionState],
        documents: [RoweDocument],
        sharedDocuments: [SharedDocumentItem],
        connections: [ConnectionItem],
        settings: AppSettings,
        vaultEnvelope: VaultKeyEnvelope? = nil,
        authSession: AuthSession? = nil,
        serverURL: String? = nil,
        lastSyncServerTimeMs: Int64 = 0,
        dirtyDocumentIds: [String] = [],
        pendingRemoteDeleteIds: [String] = [],
        focusBehavior: FocusBehaviorState = FocusBehaviorState()
    ) {
        self.schemaVersion = schemaVersion
        self.space = space
        self.folders = folders
        self.tags = tags
        self.sidebarSections = sidebarSections
        self.documents = documents
        self.sharedDocuments = sharedDocuments
        self.connections = connections
        self.settings = settings
        self.vaultEnvelope = vaultEnvelope
        self.authSession = authSession
        self.serverURL = serverURL
        self.lastSyncServerTimeMs = lastSyncServerTimeMs
        self.dirtyDocumentIds = dirtyDocumentIds
        self.pendingRemoteDeleteIds = pendingRemoteDeleteIds
        self.focusBehavior = focusBehavior
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, space, folders, tags, sidebarSections, documents, sharedDocuments, connections, settings
        case vaultEnvelope, authSession, serverURL, lastSyncServerTimeMs, dirtyDocumentIds, pendingRemoteDeleteIds, focusBehavior
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        space = try c.decode(Space.self, forKey: .space)
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        tags = try c.decodeIfPresent([TagItem].self, forKey: .tags) ?? []
        sidebarSections = try c.decodeIfPresent([SidebarSectionState].self, forKey: .sidebarSections) ?? []
        documents = try c.decodeIfPresent([RoweDocument].self, forKey: .documents) ?? []
        sharedDocuments = try c.decodeIfPresent([SharedDocumentItem].self, forKey: .sharedDocuments) ?? []
        connections = try c.decodeIfPresent([ConnectionItem].self, forKey: .connections) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        vaultEnvelope = try c.decodeIfPresent(VaultKeyEnvelope.self, forKey: .vaultEnvelope)
        authSession = try c.decodeIfPresent(AuthSession.self, forKey: .authSession)
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
        lastSyncServerTimeMs = try c.decodeIfPresent(Int64.self, forKey: .lastSyncServerTimeMs) ?? 0
        dirtyDocumentIds = try c.decodeIfPresent([String].self, forKey: .dirtyDocumentIds) ?? []
        pendingRemoteDeleteIds = try c.decodeIfPresent([String].self, forKey: .pendingRemoteDeleteIds) ?? []
        focusBehavior = try c.decodeIfPresent(FocusBehaviorState.self, forKey: .focusBehavior) ?? FocusBehaviorState()
    }
}

/// Actor-isolated persistence layer using atomic file replacement and coalesced background writes.
public actor RoweDatabaseActor {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingSaveTask: Task<Void, Never>?
    private var latestPendingSnapshot: WorkspaceSnapshot?

    public init(directoryURL: URL? = nil) {
        let baseDir: URL
        if let directoryURL {
            baseDir = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            baseDir = appSupport.appendingPathComponent("Rowe", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.fileURL = baseDir.appendingPathComponent("workspace.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, encoder in
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(fmt.string(from: date))
        }
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: str) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }
        self.decoder = dec
    }

    public func load() -> WorkspaceSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(WorkspaceSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public func scheduleSave(_ snapshot: WorkspaceSnapshot, debounceNanoseconds: UInt64 = 250_000_000) {
        latestPendingSnapshot = snapshot
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            if let snap = self.latestPendingSnapshot {
                self.writeAtomic(snap)
            }
        }
    }

    public func flushNow(_ snapshot: WorkspaceSnapshot) {
        pendingSaveTask?.cancel()
        latestPendingSnapshot = snapshot
        writeAtomic(snapshot)
    }

    private func writeAtomic(_ snapshot: WorkspaceSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Preserve previous intact snapshot on disk if encoding or disk write fails.
        }
    }

    public func computeStats(for documents: [RoweDocument]) -> WorkspaceStats {
        let activeDocs = documents.filter { !$0.isTrashed }
        var blockCount = 0
        var pageCount = 0
        var wordCount = 0
        var charCount = 0

        func walk(_ blocks: [Block]) {
            for block in blocks {
                blockCount += 1
                if block.textStyle == .pageRegular || block.textStyle == .pageCard {
                    pageCount += 1
                }
                charCount += block.content.count
                wordCount += block.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                if let table = block.tableData {
                    for row in table.cells {
                        for cell in row {
                            charCount += cell.rawContent.count
                            wordCount += cell.rawContent.split(whereSeparator: { $0.isWhitespace }).count
                        }
                    }
                }
                if let collection = block.collectionData {
                    for row in collection.rows {
                        for val in row.values.values {
                            charCount += val.count
                            wordCount += val.split(whereSeparator: { $0.isWhitespace }).count
                        }
                    }
                }
                if !block.subblocks.isEmpty {
                    walk(block.subblocks)
                }
            }
        }

        for doc in activeDocs {
            charCount += doc.title.count
            wordCount += doc.title.split(whereSeparator: { $0.isWhitespace }).count
            walk(doc.blocks)
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let readingMinutes = max(1, Int(ceil(Double(wordCount) / 220.0)))

        return WorkspaceStats(
            storageBytes: max(fileSize, Int64(charCount * 2)),
            documentCount: activeDocs.count,
            blockCount: blockCount,
            pageCount: pageCount,
            wordCount: wordCount,
            characterCount: charCount,
            estimatedReadingMinutes: wordCount == 0 ? 0 : readingMinutes
        )
    }
}

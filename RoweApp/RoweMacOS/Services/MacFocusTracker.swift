import AppKit
import Foundation
import Observation
import SQLite3
import RoweCore

/// Reads historical & recent Apple Screen Time usage directly from macOS's local
/// Screen Time Knowledge database (`~/Library/Application Support/Knowledge/knowledgeC.db`)
/// in read-only mode. Zero polling, zero AppleScript, instant 30-day baseline on Day 1.
enum MacScreenTimeReader {
    /// Core Data reference date offset (2001-01-01 00:00:00 UTC in Unix seconds).
    private static let coreDataEpochOffset: TimeInterval = 978_307_200.0

    static var knowledgeDBPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            .path
    }

    static var canReadScreenTimeDatabase: Bool {
        let path = knowledgeDBPath
        guard FileManager.default.isReadableFile(atPath: path) else { return false }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        if let db { sqlite3_close(db) }
        return rc == SQLITE_OK
    }

    /// Imports up to `daysBack` days of Apple Screen Time `/app/usage` and `/app/webUsage`
    /// records (including iCloud-synced iPhone/iPad Screen Time entries stored in `knowledgeC.db`).
    static func readHistoricalIntervals(
        daysBack: Int = 30,
        deviceId: String,
        allowlistedDomains: Set<String>,
        customTargets: [String]
    ) -> [UsageInterval] {
        let path = knowledgeDBPath
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else {
            return []
        }
        defer { sqlite3_close(db) }

        let cutoffUnix = Date().addingTimeInterval(-Double(daysBack) * 86400.0).timeIntervalSince1970
        let cutoffCoreData = cutoffUnix - coreDataEpochOffset

        // Read both native app usage (`/app/usage`) and Safari/Web Screen Time (`/app/webUsage`).
        let sql = """
            SELECT Z_PK, ZSTREAMNAME, ZVALUESTRING, ZSTARTDATE, ZENDDATE
            FROM ZOBJECT
            WHERE ZSTREAMNAME IN ('/app/usage', '/app/webUsage')
              AND ZSTARTDATE >= ?
              AND ZENDDATE > ZSTARTDATE
              AND ZVALUESTRING IS NOT NULL
            ORDER BY ZSTARTDATE ASC
            LIMIT 12000;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoffCoreData)

        let lowerAllow = Set(allowlistedDomains.map { $0.lowercased() })
        var results: [UsageInterval] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            guard let streamC = sqlite3_column_text(stmt, 1),
                  let valC = sqlite3_column_text(stmt, 2) else { continue }
            let stream = String(cString: streamC)
            let value = String(cString: valC)
            let startCD = sqlite3_column_double(stmt, 3)
            let endCD = sqlite3_column_double(stmt, 4)

            let duration = endCD - startCD
            guard duration >= 5.0 else { continue }

            let startDate = Date(timeIntervalSince1970: startCD + coreDataEpochOffset)
            let endDate = Date(timeIntervalSince1970: endCD + coreDataEpochOffset)

            var matchedSlug: String? = nil
            if stream == "/app/webUsage" {
                let candidateURL = value.contains("://") ? value : "https://\(value)"
                matchedSlug = CanonicalTargetRegistry.classifyBrowserURL(
                    candidateURL,
                    allowlistedDomains: lowerAllow,
                    customTargets: customTargets
                )?.slug
            } else {
                let valLower = value.lowercased()
                if !lowerAllow.contains(valLower) {
                    matchedSlug = CanonicalTargetRegistry.canonicalSlug(
                        bundleId: value,
                        appName: nil,
                        customTargets: customTargets
                    )
                }
            }

            guard let slug = matchedSlug else { continue }

            let interval = UsageInterval(
                id: "st-kc-\(pk)",
                deviceId: deviceId,
                canonicalTarget: slug,
                startUTC: startDate,
                endUTC: endDate,
                sourceFidelity: .macForeground
            )
            results.append(interval)
        }

        return results
    }
}

/// 100% Apple Screen Time-backed macOS Focus coordinator:
/// - Zero polling timers, zero AppleScript, zero Accessibility prompts.
/// - Imports 30 days of historical Apple Screen Time data on launch so nudges are calibrated on Day 1.
/// - Uses purely push-driven `NSWorkspace.didActivateApplicationNotification` (0% idle CPU) to offer
///   calm, non-blocking task nudges when switching into a tracked app.
@MainActor
@Observable
public final class MacFocusTracker {
    public static let shared = MacFocusTracker()

    public private(set) var hasScreenTimeAccess: Bool = MacScreenTimeReader.canReadScreenTimeDatabase
    public private(set) var lastImportedSessionCount: Int = 0
    public private(set) var lastImportDate: Date? = nil

    @ObservationIgnored private weak var store: WorkspaceStore?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var lastNudgedBundleId: String?
    @ObservationIgnored private var lastNudgedAt: Date = .distantPast

    private init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenTimeStatus(importIfAvailable: true)
            }
        }
    }

    public func start(with store: WorkspaceStore) {
        self.store = store
        refreshScreenTimeStatus(importIfAvailable: true)
        guard !isRunning else { return }
        isRunning = true

        // Purely event-driven app activation observer (0% CPU when idle, no polling timers).
        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                Task { @MainActor in
                    self?.handleAppActivated(app)
                }
            }
        )
    }

    public func stop() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        isRunning = false
    }

    public func refreshScreenTimeStatus(importIfAvailable: Bool = false) {
        let readable = MacScreenTimeReader.canReadScreenTimeDatabase
        hasScreenTimeAccess = readable
        if readable && importIfAvailable {
            importScreenTimeHistory()
        }
    }

    /// Opens macOS System Settings directly to Privacy & Security -> Full Disk Access
    /// so Rowe can read Apple's local Screen Time database (`knowledgeC.db`).
    public func requestScreenTimeAccess() {
        let modernURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url = modernURL, NSWorkspace.shared.open(url) {
            // Opened directly to Full Disk Access
        } else if let url = legacyURL {
            NSWorkspace.shared.open(url)
        }
        refreshScreenTimeStatus(importIfAvailable: true)
    }

    /// Reads the last 30 days of Apple Screen Time history and merges any new sessions into `WorkspaceStore`.
    public func importScreenTimeHistory(daysBack: Int = 30) {
        guard let store else { return }
        guard MacScreenTimeReader.canReadScreenTimeDatabase else {
            hasScreenTimeAccess = false
            return
        }
        hasScreenTimeAccess = true

        let deviceId = store.deviceId
        let allowlist = Set(store.focusBehavior.allowlistedDomains)
        let customTargets = store.focusBehavior.customDistractionTargets

        Task.detached(priority: .utility) {
            let imported = MacScreenTimeReader.readHistoricalIntervals(
                daysBack: daysBack,
                deviceId: deviceId,
                allowlistedDomains: allowlist,
                customTargets: customTargets
            )
            await MainActor.run { [weak self] in
                guard let self, let store = self.store else { return }
                let existingIds = Set(store.focusBehavior.intervals.map(\.id))
                var added = 0
                for interval in imported where !existingIds.contains(interval.id) {
                    store.recordFocusInterval(interval)
                    added += 1
                }
                self.lastImportedSessionCount = imported.count
                self.lastImportDate = Date()
                if added > 0 {
                    // Already persisted via recordFocusInterval
                }
            }
        }
    }

    private func handleAppActivated(_ frontApp: NSRunningApplication?) {
        guard let store, store.focusBehavior.isEnabled else { return }
        guard let app = frontApp ?? NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else {
            return
        }

        // Refresh latest Screen Time history silently on app switch (throttled to every 5 mins)
        if hasScreenTimeAccess, Date().timeIntervalSince(lastImportDate ?? .distantPast) > 300 {
            importScreenTimeHistory(daysBack: 7)
        }

        let allowlist = Set(store.focusBehavior.allowlistedDomains.map { $0.lowercased() })
        let appLower = app.localizedName?.lowercased() ?? ""
        if allowlist.contains(appLower) || allowlist.contains(bundleId.lowercased()) {
            return
        }

        guard let slug = CanonicalTargetRegistry.canonicalSlug(
            bundleId: bundleId,
            appName: app.localizedName,
            customTargets: store.focusBehavior.customDistractionTargets
        ) else {
            return
        }

        let now = Date()
        if lastNudgedBundleId == bundleId && now.timeIntervalSince(lastNudgedAt) < 120 {
            return
        }

        if let suggestion = store.evaluateFocusNudge(for: slug, at: now) {
            lastNudgedBundleId = bundleId
            lastNudgedAt = now
            FocusNudgeHUDController.shared.show(suggestion: suggestion, store: store)
        }
    }
}

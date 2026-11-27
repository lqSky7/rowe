import AppIntents
import Foundation
import UserNotifications
import RoweCore

/// Zero-blocking iOS Focus manager combining:
/// 1. Interactive `UNUserNotificationCenter` banners (`✓ Do this first` / `× Not now` / `Work / Study`)
/// 2. Instant 0-second `AppIntents` hooks for iOS Shortcuts ("When Instagram is opened/closed")
/// 3. Shared App Group bridge for `DeviceActivity` threshold events
@MainActor
public final class IOSFocusManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = IOSFocusManager()

    public static let categoryId = "ROWE_FOCUS_NUDGE"
    public static let actionAcceptId = "ROWE_FOCUS_ACCEPT"
    public static let actionDismissId = "ROWE_FOCUS_DISMISS"
    public static let actionWorkId = "ROWE_FOCUS_WORK"
    public static let appGroupSuite = "group.com.rowe.shared"
    private static let openSessionsKey = "rowe.focus.iosOpenSessions"
    private static let pendingDeviceActivityKey = "rowe.focus.deviceActivityQueue"

    public private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private weak var store: WorkspaceStore?
    private var pendingSuggestionsById: [String: FocusSuggestion] = [:]

    private override init() {
        super.init()
    }

    public func configure(with store: WorkspaceStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerNotificationCategories()
        Task {
            await refreshNotificationStatus()
            importSharedDeviceActivityEvents()
        }
    }

    public func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.notificationStatus = settings.authorizationStatus
    }

    @discardableResult
    public func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshNotificationStatus()
            return granted
        } catch {
            return false
        }
    }

    private func registerNotificationCategories() {
        let accept = UNNotificationAction(
            identifier: Self.actionAcceptId,
            title: "✓ Do this first",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: Self.actionDismissId,
            title: "× Not now",
            options: []
        )
        let markWork = UNNotificationAction(
            identifier: Self.actionWorkId,
            title: "Work / Study",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [accept, dismiss, markWork],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Shortcuts / AppIntents Entry Points (Zero Blocking)

    /// Called by `RoweAppOpenedIntent` when the user opens a tracked app on iOS.
    public func handleAppOpened(appName: String, at now: Date = Date()) async {
        guard let store, store.focusBehavior.isEnabled else { return }
        let allowlist = Set(store.focusBehavior.allowlistedDomains.map { $0.lowercased() })
        if allowlist.contains(appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return
        }
        guard let slug = CanonicalTargetRegistry.canonicalSlug(
            appName: appName,
            customTargets: store.focusBehavior.customDistractionTargets
        ) else {
            return
        }

        // Record exact open timestamp so `handleAppClosed` logs exact session duration
        var openMap = loadOpenSessions()
        openMap[slug] = now.timeIntervalSince1970
        saveOpenSessions(openMap)

        // Evaluate non-blocking nudge
        if let suggestion = store.evaluateFocusNudge(for: slug, at: now) {
            await postBanner(for: suggestion, isPreview: false)
        }
    }

    /// Called by `RoweAppClosedIntent` when the user leaves a tracked app on iOS.
    public func handleAppClosed(appName: String, at now: Date = Date()) async {
        guard let store else { return }
        guard let slug = CanonicalTargetRegistry.canonicalSlug(
            appName: appName,
            customTargets: store.focusBehavior.customDistractionTargets
        ) else {
            return
        }

        var openMap = loadOpenSessions()
        guard let startEpoch = openMap.removeValue(forKey: slug) else { return }
        saveOpenSessions(openMap)

        let startDate = Date(timeIntervalSince1970: startEpoch)
        guard now.timeIntervalSince(startDate) >= 5.0 else { return }

        let interval = UsageInterval(
            deviceId: store.deviceId,
            canonicalTarget: slug,
            startUTC: startDate,
            endUTC: now,
            sourceFidelity: .iosShortcut
        )
        store.recordFocusInterval(interval)
    }

    /// Imports quantized threshold events written by a `DeviceActivityMonitor` extension into the shared App Group.
    public func importSharedDeviceActivityEvents() {
        guard let store,
              let defaults = UserDefaults(suiteName: Self.appGroupSuite),
              let data = defaults.data(forKey: Self.pendingDeviceActivityKey),
              let queued = try? JSONDecoder().decode([UsageInterval].self, from: data),
              !queued.isEmpty else {
            return
        }
        for interval in queued {
            store.recordFocusInterval(interval)
        }
        defaults.removeObject(forKey: Self.pendingDeviceActivityKey)
    }

    // MARK: - Interactive Notification Banner Delivery

    public func sendPreviewBanner(for store: WorkspaceStore) async {
        if notificationStatus != .authorized {
            _ = await requestNotificationPermission()
        }
        let suggestion = store.makePreviewFocusSuggestion()
        await postBanner(for: suggestion, isPreview: true)
    }

    public func postBanner(for suggestion: FocusSuggestion, isPreview: Bool) async {
        pendingSuggestionsById[suggestion.id] = suggestion

        let content = UNMutableNotificationContent()
        content.title = suggestion.headline
        content.body = suggestion.detailLine
        content.categoryIdentifier = Self.categoryId
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "suggestionId": suggestion.id,
            "documentId": suggestion.task.documentId,
            "isPreview": isPreview
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.4, repeats: false)
        let request = UNNotificationRequest(identifier: "rowe-focus-\(suggestion.id)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let suggestionId = userInfo["suggestionId"] as? String
        let docId = userInfo["documentId"] as? String
        let isPreview = (userInfo["isPreview"] as? Bool) ?? false
        let actionId = response.actionIdentifier

        await MainActor.run {
            let suggestion = suggestionId.flatMap { self.pendingSuggestionsById.removeValue(forKey: $0) }
            guard let store = self.store else { return }

            switch actionId {
            case Self.actionAcceptId, UNNotificationDefaultActionIdentifier:
                if let suggestion, !isPreview {
                    store.recordFocusOutcome(.accepted, for: suggestion)
                }
                if let docId {
                    store.navigate(to: .document(docId))
                }
            case Self.actionDismissId, UNNotificationDismissActionIdentifier:
                if let suggestion, !isPreview {
                    store.recordFocusOutcome(.dismissed, for: suggestion)
                }
            case Self.actionWorkId:
                if let suggestion, !isPreview {
                    store.recordFocusOutcome(.markedProductive, for: suggestion)
                }
            default:
                break
            }
        }
    }

    // MARK: - Open Session Storage

    private func loadOpenSessions() -> [String: TimeInterval] {
        (UserDefaults.standard.dictionary(forKey: Self.openSessionsKey) as? [String: TimeInterval]) ?? [:]
    }

    private func saveOpenSessions(_ map: [String: TimeInterval]) {
        UserDefaults.standard.set(map, forKey: Self.openSessionsKey)
    }
}

// MARK: - iOS AppIntents for 0-Second Shortcuts Automation (Zero Blocking)

@available(iOS 16.0, *)
public struct RoweAppOpenedIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log App Opened for Focus Nudge"
    public static let description = IntentDescription("Lets Rowe observe when you open a social or video app and optionally suggest a quick task via a non-blocking banner.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "App Name", default: "Instagram")
    public var appName: String

    public init() {}
    public init(appName: String) {
        self.appName = appName
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await IOSFocusManager.shared.handleAppOpened(appName: appName)
        return .result()
    }
}

@available(iOS 16.0, *)
public struct RoweAppClosedIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log App Closed for Focus Rhythm"
    public static let description = IntentDescription("Records when you finish using an app so Rowe can learn your typical session length across Mac and iPhone.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "App Name", default: "Instagram")
    public var appName: String

    public init() {}
    public init(appName: String) {
        self.appName = appName
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await IOSFocusManager.shared.handleAppClosed(appName: appName)
        return .result()
    }
}

@available(iOS 16.0, *)
public struct RoweFocusShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RoweAppOpenedIntent(),
            phrases: ["Log app opened in \(.applicationName)"],
            shortTitle: "Log App Opened",
            systemImageName: "waveform.and.magnifyingglass"
        )
        AppShortcut(
            intent: RoweAppClosedIntent(),
            phrases: ["Log app closed in \(.applicationName)"],
            shortTitle: "Log App Closed",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}

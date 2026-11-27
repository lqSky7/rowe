import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import UserNotifications
import RoweCore

public extension DeviceActivityName {
    static let roweDailyFocus = Self("com.rowe.focus.daily")
}

public extension DeviceActivityEvent.Name {
    static let threshold1m = Self("com.rowe.focus.t1m")
    static let threshold5m = Self("com.rowe.focus.t5m")
    static let threshold15m = Self("com.rowe.focus.t15m")
    static let threshold30m = Self("com.rowe.focus.t30m")
    static let threshold45m = Self("com.rowe.focus.t45m")
    static let threshold60m = Self("com.rowe.focus.t60m")
}

public extension DeviceActivityReport.Context {
    static let roweCircadianHistory = Self("com.rowe.focus.circadianHistory")
}

/// 100% Native Apple Screen Time (`FamilyControls` + `DeviceActivity`) manager for Rowe on iOS.
/// - Zero Shortcuts / AppIntents hacks.
/// - Zero background polling — all monitoring runs in Apple's Screen Time daemon via `RoweDeviceActivityMonitor`.
/// - Reads existing historical Screen Time data via `RoweDeviceActivityReport` so insights work on Day 1.
@MainActor
@Observable
public final class IOSFocusManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = IOSFocusManager()

    public static let categoryId = "ROWE_FOCUS_NUDGE"
    public static let actionAcceptId = "ROWE_FOCUS_ACCEPT"
    public static let actionDismissId = "ROWE_FOCUS_DISMISS"
    public static let actionWorkId = "ROWE_FOCUS_WORK"
    public static let appGroupSuite = "group.com.rowe.shared"
    public static let selectionKey = "rowe.screentime.selection"
    public static let pendingDeviceActivityKey = "rowe.focus.deviceActivityQueue"
    public static let cachedTopTaskKey = "rowe.focus.cachedTopTask"
    public static let cachedDeviceIdKey = "rowe.focus.deviceId"

    public private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var screenTimeStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    public private(set) var lastAuthorizationError: String? = nil

    public var activitySelection: FamilyActivitySelection = FamilyActivitySelection() {
        didSet {
            persistSelection()
            if screenTimeStatus == .approved {
                startScreenTimeMonitoring()
            }
        }
    }

    @ObservationIgnored private weak var store: WorkspaceStore?
    @ObservationIgnored private var pendingSuggestionsById: [String: FocusSuggestion] = [:]
    @ObservationIgnored private let activityCenter = DeviceActivityCenter()

    private override init() {
        super.init()
        loadPersistedSelection()
    }

    public var isScreenTimeAuthorized: Bool {
        screenTimeStatus == .approved
    }

    public var selectedItemsCount: Int {
        activitySelection.applicationTokens.count
            + activitySelection.categoryTokens.count
            + activitySelection.webDomainTokens.count
    }

    public func configure(with store: WorkspaceStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerNotificationCategories()
        refreshScreenTimeStatus()
        syncQuickTaskCacheForExtension()
        Task {
            await refreshNotificationStatus()
            importSharedDeviceActivityEvents()
        }
    }

    public func refreshScreenTimeStatus() {
        screenTimeStatus = AuthorizationCenter.shared.authorizationStatus
        if screenTimeStatus == .approved, store?.focusBehavior.isEnabled == true {
            startScreenTimeMonitoring()
        }
    }

    @discardableResult
    public func requestScreenTimeAuthorization() async -> Bool {
        lastAuthorizationError = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            screenTimeStatus = AuthorizationCenter.shared.authorizationStatus
            if screenTimeStatus == .approved {
                startScreenTimeMonitoring()
                return true
            }
            return false
        } catch {
            screenTimeStatus = AuthorizationCenter.shared.authorizationStatus
            lastAuthorizationError = error.localizedDescription
            return false
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

    // MARK: - DeviceActivity Monitoring (OS-Driven, 0% App Battery)

    public func startScreenTimeMonitoring() {
        guard screenTimeStatus == .approved else { return }
        guard store?.focusBehavior.isEnabled ?? true else {
            stopScreenTimeMonitoring()
            return
        }

        syncQuickTaskCacheForExtension()

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let thresholds: [(DeviceActivityEvent.Name, Int)] = [
            (.threshold1m, 1),
            (.threshold5m, 5),
            (.threshold15m, 15),
            (.threshold30m, 30),
            (.threshold45m, 45),
            (.threshold60m, 60)
        ]

        let hasSelection = selectedItemsCount > 0
        for (name, mins) in thresholds {
            if hasSelection {
                events[name] = DeviceActivityEvent(
                    applications: activitySelection.applicationTokens,
                    categories: activitySelection.categoryTokens,
                    webDomains: activitySelection.webDomainTokens,
                    threshold: DateComponents(minute: mins)
                )
            } else {
                // Monitor all device activity thresholds until user narrows selection in FamilyActivityPicker
                events[name] = DeviceActivityEvent(
                    threshold: DateComponents(minute: mins)
                )
            }
        }

        activityCenter.stopMonitoring([.roweDailyFocus])
        try? activityCenter.startMonitoring(.roweDailyFocus, during: schedule, events: events)
    }

    public func stopScreenTimeMonitoring() {
        activityCenter.stopMonitoring([.roweDailyFocus])
    }

    /// Writes the user's top quick (unlocked) task title into the shared App Group so
    /// `RoweDeviceActivityMonitor` can include it in zero-blocking background banners.
    public func syncQuickTaskCacheForExtension() {
        guard let store, let defaults = UserDefaults(suiteName: Self.appGroupSuite) else { return }
        defaults.set(store.deviceId, forKey: Self.cachedDeviceIdKey)
        if let top = store.unlockedNudgeCandidateTasks().first {
            defaults.set(top.title, forKey: Self.cachedTopTaskKey)
        } else {
            defaults.removeObject(forKey: Self.cachedTopTaskKey)
        }
    }

    /// Imports threshold intervals recorded by `RoweDeviceActivityMonitor` into `WorkspaceStore`
    /// so iOS Screen Time rhythm syncs cleanly with macOS.
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

    // MARK: - Selection Persistence (Shared App Group)

    private func persistSelection() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite),
              let data = try? JSONEncoder().encode(activitySelection) else { return }
        defaults.set(data, forKey: Self.selectionKey)
    }

    private func loadPersistedSelection() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite),
              let data = defaults.data(forKey: Self.selectionKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        activitySelection = decoded
    }

    // MARK: - Interactive Notification Banner Delivery

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
}

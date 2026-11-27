import DeviceActivity
import Foundation
import UserNotifications

/// Native iOS Screen Time `DeviceActivityMonitor` extension:
/// Runs inside Apple's Screen Time daemon (0% main-app battery) and posts calm,
/// non-blocking task nudges when a monitored app/website usage threshold is reached.
final class RoweDeviceActivityMonitorExtension: DeviceActivityMonitor {
    private static let appGroupSuite = "group.com.rowe.shared"
    private static let pendingKey = "rowe.focus.deviceActivityQueue"
    private static let cachedTopTaskKey = "rowe.focus.cachedTopTask"
    private static let cachedDeviceIdKey = "rowe.focus.deviceId"

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let minutes = thresholdMinutes(for: event.rawValue)
        appendThresholdInterval(minutes: minutes)

        // Offer a calm non-blocking banner if the user has a quick unlocked task waiting
        if minutes == 5 || minutes == 15 || minutes == 30 {
            postNonBlockingBanner(minutes: minutes)
        }
    }

    private func thresholdMinutes(for rawName: String) -> Int {
        switch rawName {
        case "com.rowe.focus.t1m": return 1
        case "com.rowe.focus.t5m": return 5
        case "com.rowe.focus.t15m": return 15
        case "com.rowe.focus.t30m": return 30
        case "com.rowe.focus.t45m": return 45
        case "com.rowe.focus.t60m": return 60
        default: return 10
        }
    }

    private func appendThresholdInterval(minutes: Int) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite) else { return }
        let deviceId = defaults.string(forKey: Self.cachedDeviceIdKey) ?? "ios-screentime"
        let end = Date()
        let start = end.addingTimeInterval(-Double(minutes) * 60.0)

        struct QueuedInterval: Codable {
            let id: String
            let deviceId: String
            let canonicalTarget: String
            let startUTC: Date
            let endUTC: Date
            let tzOffsetMinutes: Int
            let sourceFidelity: String
        }

        var existing: [QueuedInterval] = []
        if let data = defaults.data(forKey: Self.pendingKey),
           let decoded = try? JSONDecoder().decode([QueuedInterval].self, from: data) {
            existing = decoded
        }

        existing.append(QueuedInterval(
            id: "st-ios-\(Int(end.timeIntervalSince1970))-\(minutes)",
            deviceId: deviceId,
            canonicalTarget: "canon:screentime_focus",
            startUTC: start,
            endUTC: end,
            tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
            sourceFidelity: "iosDeviceActivity"
        ))

        if let encoded = try? JSONEncoder().encode(existing) {
            defaults.set(encoded, forKey: Self.pendingKey)
        }
    }

    private func postNonBlockingBanner(minutes: Int) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite),
              let taskTitle = defaults.string(forKey: Self.cachedTopTaskKey),
              !taskTitle.isEmpty else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(minutes)m into your scroll session"
        content.body = "Knock out \"\(taskTitle)\" first, then scroll freely?"
        content.categoryIdentifier = "ROWE_FOCUS_NUDGE"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let req = UNNotificationRequest(
            identifier: "rowe-st-nudge-\(minutes)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req)
    }
}

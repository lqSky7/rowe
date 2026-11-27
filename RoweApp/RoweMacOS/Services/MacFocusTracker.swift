import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import RoweCore

/// Passive, zero-blocking macOS activity observer for Rowe's Adaptive Focus system.
/// - Never blocks, locks, or steals focus from any application.
/// - Tracks native distraction apps via `NSWorkspace` and browser distraction domains via local eTLD+1 inspection.
/// - Applies 120s HID idle cutoff with retroactive timestamp trim, sleep/screen-lock hard stops, and YouTube `/watch` rapid-hop detection.
@MainActor
@Observable
public final class MacFocusTracker {
    public static let shared = MacFocusTracker()

    public private(set) var hasAccessibilityPermission: Bool = AXIsProcessTrusted()

    @ObservationIgnored private weak var store: WorkspaceStore?
    @ObservationIgnored private var isRunning = false

    @ObservationIgnored private var activeTarget: String?
    @ObservationIgnored private var activeSessionStart: Date?
    @ObservationIgnored private var activeBrowserHost: String?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    // YouTube /watch rapid-hop detector: (videoId, firstSeenUTC) within rolling 10-minute window
    @ObservationIgnored private var recentYouTubeVideos: [(id: String, seenAt: Date)] = []
    @ObservationIgnored private var lastNudgedTargetSessionStart: Date?

    private static let idleCutoffSeconds: TimeInterval = 120.0
    private static let rapidHopWindowSeconds: TimeInterval = 10 * 60
    private static let rapidHopThreshold = 3

    private init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibilityStatus() }
        }
    }

    public func start(with store: WorkspaceStore) {
        self.store = store
        refreshAccessibilityStatus()
        guard !isRunning else { return }
        isRunning = true

        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.evaluateFrontmostContext() }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.flushCurrentSession(endTime: Date()) }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.flushCurrentSession(endTime: Date()) }
            }
        )
        workspaceObservers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.flushCurrentSession(endTime: Date()) }
            }
        )
        distributedObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.flushCurrentSession(endTime: Date()) }
            }
        )

        // Lightweight 20s heartbeat: checks HID idle, browser tab switches, and flushes long sessions safely.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeatTick() }
        }
        evaluateFrontmostContext()
    }

    public func stop() {
        flushCurrentSession(endTime: Date())
        pollTimer?.invalidate()
        pollTimer = nil
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        for obs in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        distributedObservers.removeAll()
        isRunning = false
    }

    public func refreshAccessibilityStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshAccessibilityStatus()
    }

    // MARK: - Heartbeat & Context Evaluation

    private func heartbeatTick() {
        guard let store, store.focusBehavior.isEnabled else {
            flushCurrentSession(endTime: Date())
            return
        }

        let idleSeconds = currentHIDIdleSeconds()
        if idleSeconds >= Self.idleCutoffSeconds {
            // Retroactively trim the session to the exact moment the user stopped interacting.
            let trueEnd = Date().addingTimeInterval(-idleSeconds)
            flushCurrentSession(endTime: trueEnd)
            return
        }

        evaluateFrontmostContext()
    }

    private func evaluateFrontmostContext() {
        guard let store, store.focusBehavior.isEnabled else {
            flushCurrentSession(endTime: Date())
            return
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            flushCurrentSession(endTime: Date())
            return
        }

        // Ignore Rowe itself
        if bundleId == Bundle.main.bundleIdentifier {
            flushCurrentSession(endTime: Date())
            return
        }

        let now = Date()
        let allowlist = Set(store.focusBehavior.allowlistedDomains)
        let customTargets = store.focusBehavior.customDistractionTargets

        var detectedTarget: String? = nil
        var isYouTubeWatch = false
        var rawURLForHop: String? = nil

        if CanonicalTargetRegistry.isBrowser(bundleId: bundleId) {
            if let urlStr = activeBrowserURL(for: bundleId) {
                rawURLForHop = urlStr
                if let classified = CanonicalTargetRegistry.classifyBrowserURL(
                    urlStr,
                    allowlistedDomains: allowlist,
                    customTargets: customTargets
                ) {
                    detectedTarget = classified.slug
                    isYouTubeWatch = classified.isYouTubeWatch
                }
            }
        } else {
            let appLower = frontApp.localizedName?.lowercased() ?? ""
            if allowlist.contains(appLower) || allowlist.contains(bundleId.lowercased()) {
                detectedTarget = nil
            } else {
                detectedTarget = CanonicalTargetRegistry.canonicalSlug(
                    bundleId: bundleId,
                    appName: frontApp.localizedName,
                    customTargets: customTargets
                )
            }
        }

        // Track YouTube /watch rapid-hopping vs focused lecture viewing
        if let slug = detectedTarget, slug == "canon:youtube", isYouTubeWatch, let urlStr = rawURLForHop {
            if let videoId = extractYouTubeVideoId(from: urlStr) {
                let cutoff = now.addingTimeInterval(-Self.rapidHopWindowSeconds)
                recentYouTubeVideos = recentYouTubeVideos.filter { $0.seenAt >= cutoff }
                if !recentYouTubeVideos.contains(where: { $0.id == videoId }) {
                    recentYouTubeVideos.append((id: videoId, seenAt: now))
                }
                // Under 3 distinct videos in 10 minutes -> assume focused tutorial/lecture; don't nudge yet
                if recentYouTubeVideos.count < Self.rapidHopThreshold {
                    transitionSession(to: detectedTarget, at: now, allowNudge: false)
                    return
                }
            }
        }

        transitionSession(to: detectedTarget, at: now, allowNudge: true)
    }

    private func transitionSession(to newTarget: String?, at now: Date, allowNudge: Bool) {
        if activeTarget != newTarget {
            flushCurrentSession(endTime: now)
            activeTarget = newTarget
            activeSessionStart = newTarget == nil ? nil : now
            lastNudgedTargetSessionStart = nil
        }

        guard allowNudge,
              let target = activeTarget,
              let sessionStart = activeSessionStart,
              lastNudgedTargetSessionStart != sessionStart,
              let store else {
            return
        }

        // Evaluate non-blocking nudge proposal
        if let suggestion = store.evaluateFocusNudge(for: target, at: now) {
            lastNudgedTargetSessionStart = sessionStart
            FocusNudgeHUDController.shared.show(suggestion: suggestion, store: store)
        }
    }

    private func flushCurrentSession(endTime: Date) {
        guard let target = activeTarget,
              let start = activeSessionStart,
              let store else {
            activeTarget = nil
            activeSessionStart = nil
            return
        }
        activeTarget = nil
        activeSessionStart = nil

        let clampedEnd = max(start, endTime)
        guard clampedEnd.timeIntervalSince(start) >= 5.0 else { return }

        let interval = UsageInterval(
            deviceId: store.deviceId,
            canonicalTarget: target,
            startUTC: start,
            endUTC: clampedEnd,
            sourceFidelity: .macForeground
        )
        store.recordFocusInterval(interval)
    }

    // MARK: - Local Browser Domain Inspection (Never Stored)

    private func activeBrowserURL(for bundleId: String) -> String? {
        let scriptSource: String?
        switch bundleId {
        case "com.apple.Safari":
            scriptSource = "tell application \"Safari\" to if (count of documents) > 0 then return URL of current tab of front window"
        case "com.google.Chrome", "com.google.Chrome.canary":
            scriptSource = "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "company.thebrowser.Browser":
            scriptSource = "tell application \"Arc\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "com.brave.Browser":
            scriptSource = "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "com.microsoft.edgemac":
            scriptSource = "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "com.vivaldi.Vivaldi":
            scriptSource = "tell application \"Vivaldi\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "com.kagi.kagimacOS":
            scriptSource = "tell application \"Orion\" to if (count of documents) > 0 then return URL of current tab of front window"
        default:
            scriptSource = nil
        }

        guard let source = scriptSource, let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        return descriptor.stringValue
    }

    private func extractYouTubeVideoId(from rawURL: String) -> String? {
        guard let comps = URLComponents(string: rawURL) else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        return nil
    }

    private func currentHIDIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

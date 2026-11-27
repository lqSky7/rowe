import Foundation

// MARK: - Canonical Target Registry (Cross-Device Normalization)

public enum CanonicalTargetRegistry {
    public struct TargetDescriptor: Codable, Hashable, Sendable, Identifiable {
        public var id: String { slug }
        public let slug: String
        public let displayName: String
        public let iconName: String
        public let domains: [String]
        public let macBundleIds: [String]
        public let aliases: [String]

        public init(
            slug: String,
            displayName: String,
            iconName: String,
            domains: [String] = [],
            macBundleIds: [String] = [],
            aliases: [String] = []
        ) {
            self.slug = slug
            self.displayName = displayName
            self.iconName = iconName
            self.domains = domains
            self.macBundleIds = macBundleIds
            self.aliases = aliases
        }
    }

    public static let builtInTargets: [TargetDescriptor] = [
        TargetDescriptor(
            slug: "canon:instagram",
            displayName: "Instagram",
            iconName: "camera.aperture",
            domains: ["instagram.com", "instagr.am"],
            macBundleIds: ["com.burbn.instagram"],
            aliases: ["insta", "instagram", "ig", "reels"]
        ),
        TargetDescriptor(
            slug: "canon:youtube_shorts",
            displayName: "YouTube Shorts",
            iconName: "play.rectangle.on.rectangle",
            domains: ["youtube.com/shorts"],
            macBundleIds: [],
            aliases: ["shorts", "yt shorts", "youtube shorts"]
        ),
        TargetDescriptor(
            slug: "canon:youtube",
            displayName: "YouTube",
            iconName: "play.rectangle",
            domains: ["youtube.com", "youtu.be", "m.youtube.com"],
            macBundleIds: ["com.google.ios.youtube"],
            aliases: ["youtube", "yt"]
        ),
        TargetDescriptor(
            slug: "canon:reddit",
            displayName: "Reddit",
            iconName: "bubble.left.and.bubble.right",
            domains: ["reddit.com", "old.reddit.com"],
            macBundleIds: ["com.reddit.Reddit"],
            aliases: ["reddit"]
        ),
        TargetDescriptor(
            slug: "canon:x",
            displayName: "X",
            iconName: "at",
            domains: ["x.com", "twitter.com"],
            macBundleIds: ["com.atebits.Tweetie2", "maccatalyst.com.atebits.Tweetie2"],
            aliases: ["x", "twitter"]
        ),
        TargetDescriptor(
            slug: "canon:tiktok",
            displayName: "TikTok",
            iconName: "music.note",
            domains: ["tiktok.com"],
            macBundleIds: ["com.zhiliaoapp.musically"],
            aliases: ["tiktok"]
        ),
        TargetDescriptor(
            slug: "canon:twitch",
            displayName: "Twitch",
            iconName: "tv",
            domains: ["twitch.tv"],
            macBundleIds: ["tv.twitch"],
            aliases: ["twitch"]
        ),
        TargetDescriptor(
            slug: "canon:netflix",
            displayName: "Netflix",
            iconName: "film",
            domains: ["netflix.com"],
            macBundleIds: ["com.netflix.Netflix"],
            aliases: ["netflix"]
        )
    ]

    /// Known browser bundle IDs — NEVER tracked as distraction targets on their own;
    /// only their active domain + path bucket is inspected locally.
    public static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",   // Arc
        "company.thebrowser.dia",       // Dia
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.kagi.kagimacOS"            // Orion
    ]

    public static func isBrowser(bundleId: String) -> Bool {
        browserBundleIds.contains(bundleId)
    }

    public static func displayName(for slug: String) -> String {
        if let found = builtInTargets.first(where: { $0.slug == slug }) {
            return found.displayName
        }
        return slug
            .replacingOccurrences(of: "canon:", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    public static func iconName(for slug: String) -> String {
        builtInTargets.first(where: { $0.slug == slug })?.iconName ?? "app.dashed"
    }

    /// Classifies a browser URL into a canonical distraction slug (or nil if productive/neutral).
    /// Extracts ONLY eTLD+1 + path bucket — never stores or logs full URLs or query strings.
    public static func classifyBrowserURL(
        _ rawURL: String,
        allowlistedDomains: Set<String> = [],
        customTargets: [String] = []
    ) -> (slug: String, isYouTubeWatch: Bool)? {
        guard let url = URL(string: rawURL), let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if allowlistedDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return nil
        }

        let path = url.path.lowercased()
        // Deterministic YouTube classifier: Shorts = immediate distraction; /watch requires rapid-hop check.
        if host == "youtube.com" || host == "m.youtube.com" || host == "youtu.be" {
            if path.hasPrefix("/shorts") {
                return ("canon:youtube_shorts", false)
            }
            if path.hasPrefix("/watch") {
                return ("canon:youtube", true)
            }
            // Home feed / subscriptions / trending = browse/doomscroll risk
            return ("canon:youtube", false)
        }

        for target in builtInTargets where target.slug != "canon:youtube" && target.slug != "canon:youtube_shorts" {
            if target.domains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                return (target.slug, false)
            }
        }

        for custom in customTargets {
            let clean = custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !clean.isEmpty else { continue }
            if host == clean || host.hasSuffix(".\(clean)") {
                return ("canon:\(clean)", false)
            }
        }

        return nil
    }

    /// Normalizes a native app bundle ID or human app name (e.g. from iOS Shortcuts) to a canonical slug.
    public static func canonicalSlug(
        bundleId: String? = nil,
        appName: String? = nil,
        customTargets: [String] = []
    ) -> String? {
        if let bundleId, !bundleId.isEmpty {
            if isBrowser(bundleId: bundleId) { return nil }
            if let match = builtInTargets.first(where: { $0.macBundleIds.contains(bundleId) }) {
                return match.slug
            }
        }
        if let appName = appName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !appName.isEmpty {
            if let match = builtInTargets.first(where: {
                $0.slug == appName || $0.displayName.lowercased() == appName || $0.aliases.contains(appName)
            }) {
                return match.slug
            }
            if customTargets.contains(where: { $0.lowercased() == appName }) {
                return "canon:\(appName.replacingOccurrences(of: " ", with: "_"))"
            }
        }
        return nil
    }
}

// MARK: - Behavioral Telemetry & Learning Models

public enum UsageSourceFidelity: String, Codable, Hashable, Sendable {
    case macForeground      // Exact active app / browser tab with HID idle trim
    case iosShortcut        // Exact 0s open/close via iOS AppIntents / Shortcuts
    case iosDeviceActivity  // Quantized Screen Time threshold bucket
}

public struct UsageInterval: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var deviceId: String
    public var canonicalTarget: String
    public var startUTC: Date
    public var endUTC: Date
    public var tzOffsetMinutes: Int
    public var sourceFidelity: UsageSourceFidelity

    public init(
        id: String = UUID().uuidString,
        deviceId: String,
        canonicalTarget: String,
        startUTC: Date,
        endUTC: Date,
        tzOffsetMinutes: Int = TimeZone.current.secondsFromGMT() / 60,
        sourceFidelity: UsageSourceFidelity
    ) {
        self.id = id
        self.deviceId = deviceId
        self.canonicalTarget = canonicalTarget
        self.startUTC = startUTC
        // Hard 4-hour single-interval safety cap against phantom sleep sessions
        let cappedEnd = min(endUTC, startUTC.addingTimeInterval(4 * 3600))
        self.endUTC = max(startUTC, cappedEnd)
        self.tzOffsetMinutes = tzOffsetMinutes
        self.sourceFidelity = sourceFidelity
    }

    public var durationSeconds: TimeInterval {
        max(0, endUTC.timeIntervalSince(startUTC))
    }

    public var durationMinutes: Double {
        durationSeconds / 60.0
    }
}

public enum DayType: String, Codable, Hashable, Sendable {
    case weekday
    case weekend

    public static func from(weekday: Int) -> DayType {
        (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }
}

/// Identifies a `(canonicalTarget, dayType, 2-hour circadian slot)` bucket.
public struct FocusSlotKey: Codable, Hashable, Sendable {
    public var canonicalTarget: String
    public var dayType: DayType
    public var twoHourSlot: Int // 0 = 00:00–02:00, ..., 11 = 22:00–24:00

    public init(canonicalTarget: String, dayType: DayType, twoHourSlot: Int) {
        self.canonicalTarget = canonicalTarget
        self.dayType = dayType
        self.twoHourSlot = max(0, min(11, twoHourSlot))
    }

    public var storageKey: String {
        "\(canonicalTarget)|\(dayType.rawValue)|\(twoHourSlot)"
    }

    public var humanTimeWindow: String {
        let startHour = twoHourSlot * 2
        let endHour = (startHour + 2) % 24
        func fmt(_ h: Int) -> String {
            if h == 0 { return "12 AM" }
            if h == 12 { return "12 PM" }
            return h < 12 ? "\(h) AM" : "\(h - 12) PM"
        }
        return "\(fmt(startHour))–\(fmt(endHour))"
    }

    public static func from(date: Date, tzOffsetMinutes: Int, target: String) -> FocusSlotKey {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: tzOffsetMinutes * 60) ?? .current
        let comps = cal.dateComponents([.weekday, .hour], from: date)
        let weekday = comps.weekday ?? 2
        let hour = comps.hour ?? 12
        return FocusSlotKey(
            canonicalTarget: target,
            dayType: DayType.from(weekday: weekday),
            twoHourSlot: hour / 2
        )
    }
}

/// Beta-EWMA receptivity model (`r = alpha / (alpha + beta)`).
/// Starts neutral at `alpha = 2, beta = 2` (`r = 0.50`) so one rejection never kills a slot.
public struct SlotReceptivity: Codable, Hashable, Sendable {
    public var alpha: Double
    public var beta: Double
    public var lastUpdatedUTC: Date
    public var lastNudgedUTC: Date?
    public var lastSilencedUTC: Date?
    public var lastProbeUTC: Date?
    public var acceptedCount: Int
    public var dismissedCount: Int

    public init(
        alpha: Double = 2.0,
        beta: Double = 2.0,
        lastUpdatedUTC: Date = Date(),
        lastNudgedUTC: Date? = nil,
        lastSilencedUTC: Date? = nil,
        lastProbeUTC: Date? = nil,
        acceptedCount: Int = 0,
        dismissedCount: Int = 0
    ) {
        self.alpha = alpha
        self.beta = beta
        self.lastUpdatedUTC = lastUpdatedUTC
        self.lastNudgedUTC = lastNudgedUTC
        self.lastSilencedUTC = lastSilencedUTC
        self.lastProbeUTC = lastProbeUTC
        self.acceptedCount = acceptedCount
        self.dismissedCount = dismissedCount
    }

    public var score: Double {
        let denom = alpha + beta
        return denom > 0 ? alpha / denom : 0.5
    }

    public var isAutoSilenced: Bool {
        score < 0.20
    }
}

public struct NudgeLease: Codable, Hashable, Sendable {
    public var canonicalTarget: String
    public var slotKey: String
    public var issuedAtUTC: Date
    public var cooldownUntilUTC: Date
    public var deviceId: String

    public init(
        canonicalTarget: String,
        slotKey: String,
        issuedAtUTC: Date,
        cooldownUntilUTC: Date,
        deviceId: String
    ) {
        self.canonicalTarget = canonicalTarget
        self.slotKey = slotKey
        self.issuedAtUTC = issuedAtUTC
        self.cooldownUntilUTC = cooldownUntilUTC
        self.deviceId = deviceId
    }
}

public enum NudgeOutcome: String, Codable, Hashable, Sendable {
    case accepted          // User tapped ✓ (Do task)
    case dismissed         // User tapped × (Not now)
    case ignored           // Auto-faded without interaction
    case markedProductive  // User tapped "Work/Study" (allowlist session)
}

public struct TaskNudgeStats: Codable, Hashable, Sendable {
    public var taskId: String
    public var estimatedMinutes: Int
    public var dismissCount: Int
    public var cooldownUntilUTC: Date?
    public var isExcluded: Bool
    public var lastEditedAt: Date?

    public init(
        taskId: String,
        estimatedMinutes: Int = 15,
        dismissCount: Int = 0,
        cooldownUntilUTC: Date? = nil,
        isExcluded: Bool = false,
        lastEditedAt: Date? = nil
    ) {
        self.taskId = taskId
        self.estimatedMinutes = estimatedMinutes
        self.dismissCount = dismissCount
        self.cooldownUntilUTC = cooldownUntilUTC
        self.isExcluded = isExcluded
        self.lastEditedAt = lastEditedAt
    }
}

/// Compile-time Zero-Knowledge firewall: `FocusNudgeEngine` ONLY accepts `NudgeCandidateTask`,
/// which can ONLY be constructed from unlocked, non-trashed documents (`!doc.isLocked && doc.encryptedPayload == nil`).
public struct NudgeCandidateTask: Identifiable, Hashable, Sendable {
    public let id: String
    public let documentId: String
    public let title: String
    public let scheduleDate: Date?
    public let deadlineDate: Date?
    public let updatedAt: Date

    public init?(from item: ResolvedTaskItem, in document: RoweDocument) {
        guard !document.isLocked,
              document.encryptedPayload == nil,
              !document.isTrashed,
              (item.block.task?.state ?? .pending) == .pending else {
            return nil
        }
        let cleanTitle = item.block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        self.id = item.block.id
        self.documentId = item.documentId
        self.title = cleanTitle
        self.scheduleDate = item.block.task?.scheduleDate
        self.deadlineDate = item.block.task?.deadlineDate
        self.updatedAt = item.block.updatedAt
    }

    /// Direct initializer for unit tests and previews (never used with locked notes).
    public init(
        id: String,
        documentId: String,
        title: String,
        scheduleDate: Date? = nil,
        deadlineDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.title = title
        self.scheduleDate = scheduleDate
        self.deadlineDate = deadlineDate
        self.updatedAt = updatedAt
    }
}

public struct FocusSuggestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let canonicalTarget: String
    public let displayAppName: String
    public let iconName: String
    public let headline: String
    public let detailLine: String
    public let task: NudgeCandidateTask
    public let estimatedMinutes: Int
    public let predictedScrollMinutes: Int?
    public let slotKey: FocusSlotKey
    public let isPersonalized: Bool
    public let isAutoProbe: Bool

    public init(
        id: String = UUID().uuidString,
        canonicalTarget: String,
        displayAppName: String,
        iconName: String,
        headline: String,
        detailLine: String,
        task: NudgeCandidateTask,
        estimatedMinutes: Int,
        predictedScrollMinutes: Int?,
        slotKey: FocusSlotKey,
        isPersonalized: Bool,
        isAutoProbe: Bool = false
    ) {
        self.id = id
        self.canonicalTarget = canonicalTarget
        self.displayAppName = displayAppName
        self.iconName = iconName
        self.headline = headline
        self.detailLine = detailLine
        self.task = task
        self.estimatedMinutes = estimatedMinutes
        self.predictedScrollMinutes = predictedScrollMinutes
        self.slotKey = slotKey
        self.isPersonalized = isPersonalized
        self.isAutoProbe = isAutoProbe
    }
}

/// Complete persistable & cross-device-syncable state for Rowe's Adaptive Focus system.
public struct FocusBehaviorState: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var intervals: [UsageInterval]
    public var receptivityBySlot: [String: SlotReceptivity]
    public var leases: [NudgeLease]
    public var taskStats: [String: TaskNudgeStats]
    public var globalCooldownUntilUTC: Date?
    public var dailyNudgeCount: Int
    public var consecutiveDismissesToday: Int
    public var lastNudgeDayKey: String
    public var allowlistedDomains: [String]
    public var customDistractionTargets: [String]
    public var updatedAt: Date

    public init(
        isEnabled: Bool = true,
        intervals: [UsageInterval] = [],
        receptivityBySlot: [String: SlotReceptivity] = [:],
        leases: [NudgeLease] = [],
        taskStats: [String: TaskNudgeStats] = [:],
        globalCooldownUntilUTC: Date? = nil,
        dailyNudgeCount: Int = 0,
        consecutiveDismissesToday: Int = 0,
        lastNudgeDayKey: String = "",
        allowlistedDomains: [String] = [],
        customDistractionTargets: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.isEnabled = isEnabled
        self.intervals = intervals
        self.receptivityBySlot = receptivityBySlot
        self.leases = leases
        self.taskStats = taskStats
        self.globalCooldownUntilUTC = globalCooldownUntilUTC
        self.dailyNudgeCount = dailyNudgeCount
        self.consecutiveDismissesToday = consecutiveDismissesToday
        self.lastNudgeDayKey = lastNudgeDayKey
        self.allowlistedDomains = allowlistedDomains
        self.customDistractionTargets = customDistractionTargets
        self.updatedAt = updatedAt
    }

    /// Merges remote cross-device focus state cleanly (union of intervals, latest receptivity & leases).
    public mutating func merge(with remote: FocusBehaviorState) {
        // Union usage intervals by ID, keeping rolling 45-day window
        var byId = Dictionary(uniqueKeysWithValues: intervals.map { ($0.id, $0) })
        for item in remote.intervals {
            if let existing = byId[item.id] {
                if item.endUTC > existing.endUTC { byId[item.id] = item }
            } else {
                byId[item.id] = item
            }
        }
        let cutoff = Date().addingTimeInterval(-45 * 86400)
        intervals = byId.values.filter { $0.endUTC >= cutoff }.sorted { $0.startUTC < $1.startUTC }

        // Latest receptivity per slot
        for (key, remRec) in remote.receptivityBySlot {
            if let locRec = receptivityBySlot[key] {
                if remRec.lastUpdatedUTC > locRec.lastUpdatedUTC {
                    receptivityBySlot[key] = remRec
                }
            } else {
                receptivityBySlot[key] = remRec
            }
        }

        // Keep newest active leases per target
        var leaseMap = Dictionary(uniqueKeysWithValues: leases.map { ($0.canonicalTarget, $0) })
        for lease in remote.leases {
            if let existing = leaseMap[lease.canonicalTarget] {
                if lease.issuedAtUTC > existing.issuedAtUTC { leaseMap[lease.canonicalTarget] = lease }
            } else {
                leaseMap[lease.canonicalTarget] = lease
            }
        }
        leases = Array(leaseMap.values)

        // Furthest global cooldown wins so dismissing on Mac suppresses iOS immediately
        if let remGlobal = remote.globalCooldownUntilUTC {
            if let locGlobal = globalCooldownUntilUTC {
                globalCooldownUntilUTC = max(locGlobal, remGlobal)
            } else {
                globalCooldownUntilUTC = remGlobal
            }
        }

        // Merge task nudge stats (keep higher dismissCount / latest edit)
        for (tid, remStat) in remote.taskStats {
            if let locStat = taskStats[tid] {
                if remStat.dismissCount > locStat.dismissCount {
                    taskStats[tid] = remStat
                }
            } else {
                taskStats[tid] = remStat
            }
        }

        let mergedAllow = Set(allowlistedDomains).union(remote.allowlistedDomains)
        allowlistedDomains = Array(mergedAllow).sorted()
        let mergedCustom = Set(customDistractionTargets).union(remote.customDistractionTargets)
        customDistractionTargets = Array(mergedCustom).sorted()
        updatedAt = max(updatedAt, remote.updatedAt)
    }
}

import Foundation

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

public enum AccentColorChoice: String, Codable, CaseIterable, Sendable {
    case slateSky = "Slate Sky"
    case babyPink = "Baby Pink"
    case dustyPeach = "Dusty Peach"
    case sageMist = "Sage Mist"
    case lavenderHaze = "Lavender"
    case periwinkle = "Periwinkle"
    case buttercream = "Buttercream"
    case dustyRose = "Dusty Rose"
    case warmSand = "Warm Sand"
    case graphite = "Graphite"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let direct = AccentColorChoice(rawValue: raw) {
            self = direct
            return
        }
        switch raw {
        case "Blue", "Cyan", "Multicolor": self = .slateSky
        case "Pink": self = .babyPink
        case "Orange": self = .dustyPeach
        case "Green", "Teal": self = .sageMist
        case "Purple", "Indigo": self = .lavenderHaze
        case "Yellow": self = .buttercream
        default: self = .slateSky
        }
    }

    public var hex: String {
        switch self {
        case .slateSky: "#8BA5BE"
        case .babyPink: "#F2B8C6"
        case .dustyPeach: "#E4B49A"
        case .sageMist: "#98B4A3"
        case .lavenderHaze: "#B6A8D4"
        case .periwinkle: "#99A8D4"
        case .buttercream: "#E2CFA0"
        case .dustyRose: "#CFA0AC"
        case .warmSand: "#C5B7A5"
        case .graphite: "#6E737D"
        }
    }

    /// Muted, lower-saturation shade for calm surface fills like Calendar date cards.
    public var dullHex: String {
        switch self {
        case .slateSky: "#6E8296"
        case .babyPink: "#C89BA6"
        case .dustyPeach: "#BA9582"
        case .sageMist: "#7C9386"
        case .lavenderHaze: "#9489AC"
        case .periwinkle: "#7E8AA8"
        case .buttercream: "#B7A986"
        case .dustyRose: "#A8848E"
        case .warmSand: "#9E9386"
        case .graphite: "#636770"
        }
    }
}


public enum CompletedTaskStyle: String, Codable, CaseIterable, Sendable {
    case strikethrough = "Strikethrough"
    case fadeOnly = "Fade Only"
    case hide = "Hide Completed"
}

public enum DateLinkStyle: String, Codable, CaseIterable, Sendable {
    case badge = "Badge"
    case inlineText = "Inline Text"
}

public enum WeekStartDay: String, Codable, CaseIterable, Sendable {
    case sunday = "Sunday"
    case monday = "Monday"
    case saturday = "Saturday"
}

public enum SearchMaxDepth: Int, Codable, CaseIterable, Comparable, Sendable {
    case currentView = 1
    case relatedScope = 2
    case everything = 3

    public static func < (lhs: SearchMaxDepth, rhs: SearchMaxDepth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .currentView: return "Current View"
        case .relatedScope: return "Related"
        case .everything: return "Everything"
        }
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var appearanceMode: AppearanceMode
    public var accentColor: AccentColorChoice
    public var enableSound: Bool
    public var enableHaptics: Bool
    public var applyDocumentStyleToApp: Bool
    public var reduceAnimations: Bool
    public var selectedAppIconIndex: Int
    public var allDocsViewStyleRaw: String
    public var allDocsSortOrderRaw: String
    public var showDailyNotesInAllDocs: Bool
    public var hasCompletedOnboarding: Bool

    public var completedTaskStyle: CompletedTaskStyle
    public var dateLinkStyle: DateLinkStyle
    public var weekStartDay: WeekStartDay
    public var defaultDayStartHour: Int
    public var quickEntryShortcut: String
    public var externalLocationsEnabled: Bool
    public var multiBlockInlineSelection: Bool

    public var pushNotificationsEnabled: Bool
    public var emailNotificationsEnabled: Bool
    public var reminderEmailsEnabled: Bool
    public var dailyEmailEnabled: Bool

    public var searchMaxDepth: SearchMaxDepth
    public var searchAutoDeepen: Bool
    public var searchCacheLimit: Int

    public init(
        appearanceMode: AppearanceMode = .system,
        accentColor: AccentColorChoice = .graphite,
        enableSound: Bool = false,
        enableHaptics: Bool = true,
        applyDocumentStyleToApp: Bool = true,
        reduceAnimations: Bool = false,
        selectedAppIconIndex: Int = 0,
        allDocsViewStyleRaw: String = "grid",
        allDocsSortOrderRaw: String = "Updated",
        showDailyNotesInAllDocs: Bool = true,
        hasCompletedOnboarding: Bool = false,
        completedTaskStyle: CompletedTaskStyle = .strikethrough,
        dateLinkStyle: DateLinkStyle = .badge,
        weekStartDay: WeekStartDay = .sunday,
        defaultDayStartHour: Int = 9,
        quickEntryShortcut: String = "⌃ Space",
        externalLocationsEnabled: Bool = false,
        multiBlockInlineSelection: Bool = true,
        pushNotificationsEnabled: Bool = true,
        emailNotificationsEnabled: Bool = false,
        reminderEmailsEnabled: Bool = false,
        dailyEmailEnabled: Bool = false,
        searchMaxDepth: SearchMaxDepth = .everything,
        searchAutoDeepen: Bool = true,
        searchCacheLimit: Int = 128
    ) {
        self.appearanceMode = appearanceMode
        self.accentColor = accentColor
        self.enableSound = enableSound
        self.enableHaptics = enableHaptics
        self.applyDocumentStyleToApp = applyDocumentStyleToApp
        self.reduceAnimations = reduceAnimations
        self.selectedAppIconIndex = selectedAppIconIndex
        self.allDocsViewStyleRaw = allDocsViewStyleRaw
        self.allDocsSortOrderRaw = allDocsSortOrderRaw
        self.showDailyNotesInAllDocs = showDailyNotesInAllDocs
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.completedTaskStyle = completedTaskStyle
        self.dateLinkStyle = dateLinkStyle
        self.weekStartDay = weekStartDay
        self.defaultDayStartHour = defaultDayStartHour
        self.quickEntryShortcut = quickEntryShortcut
        self.externalLocationsEnabled = externalLocationsEnabled
        self.multiBlockInlineSelection = multiBlockInlineSelection
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.emailNotificationsEnabled = emailNotificationsEnabled
        self.reminderEmailsEnabled = reminderEmailsEnabled
        self.dailyEmailEnabled = dailyEmailEnabled
        self.searchMaxDepth = searchMaxDepth
        self.searchAutoDeepen = searchAutoDeepen
        self.searchCacheLimit = searchCacheLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearanceMode = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        accentColor = try c.decodeIfPresent(AccentColorChoice.self, forKey: .accentColor) ?? .graphite
        enableSound = try c.decodeIfPresent(Bool.self, forKey: .enableSound) ?? false
        enableHaptics = try c.decodeIfPresent(Bool.self, forKey: .enableHaptics) ?? true
        applyDocumentStyleToApp = try c.decodeIfPresent(Bool.self, forKey: .applyDocumentStyleToApp) ?? true
        reduceAnimations = try c.decodeIfPresent(Bool.self, forKey: .reduceAnimations) ?? false
        selectedAppIconIndex = try c.decodeIfPresent(Int.self, forKey: .selectedAppIconIndex) ?? 0
        allDocsViewStyleRaw = try c.decodeIfPresent(String.self, forKey: .allDocsViewStyleRaw) ?? "grid"
        allDocsSortOrderRaw = try c.decodeIfPresent(String.self, forKey: .allDocsSortOrderRaw) ?? "Updated"
        showDailyNotesInAllDocs = try c.decodeIfPresent(Bool.self, forKey: .showDailyNotesInAllDocs) ?? true
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        completedTaskStyle = try c.decodeIfPresent(CompletedTaskStyle.self, forKey: .completedTaskStyle) ?? .strikethrough
        dateLinkStyle = try c.decodeIfPresent(DateLinkStyle.self, forKey: .dateLinkStyle) ?? .badge
        weekStartDay = try c.decodeIfPresent(WeekStartDay.self, forKey: .weekStartDay) ?? .sunday
        defaultDayStartHour = try c.decodeIfPresent(Int.self, forKey: .defaultDayStartHour) ?? 9
        quickEntryShortcut = try c.decodeIfPresent(String.self, forKey: .quickEntryShortcut) ?? "⌃ Space"
        externalLocationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .externalLocationsEnabled) ?? false
        multiBlockInlineSelection = try c.decodeIfPresent(Bool.self, forKey: .multiBlockInlineSelection) ?? true
        pushNotificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .pushNotificationsEnabled) ?? true
        emailNotificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .emailNotificationsEnabled) ?? false
        reminderEmailsEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEmailsEnabled) ?? false
        dailyEmailEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyEmailEnabled) ?? false
        searchMaxDepth = try c.decodeIfPresent(SearchMaxDepth.self, forKey: .searchMaxDepth) ?? .everything
        searchAutoDeepen = try c.decodeIfPresent(Bool.self, forKey: .searchAutoDeepen) ?? true
        searchCacheLimit = try c.decodeIfPresent(Int.self, forKey: .searchCacheLimit) ?? 128
    }
}

public struct WorkspaceStats: Hashable, Sendable {
    public var storageBytes: Int64
    public var documentCount: Int
    public var blockCount: Int
    public var pageCount: Int
    public var wordCount: Int
    public var characterCount: Int
    public var estimatedReadingMinutes: Int

    public init(
        storageBytes: Int64 = 0,
        documentCount: Int = 0,
        blockCount: Int = 0,
        pageCount: Int = 0,
        wordCount: Int = 0,
        characterCount: Int = 0,
        estimatedReadingMinutes: Int = 0
    ) {
        self.storageBytes = storageBytes
        self.documentCount = documentCount
        self.blockCount = blockCount
        self.pageCount = pageCount
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.estimatedReadingMinutes = estimatedReadingMinutes
    }
}

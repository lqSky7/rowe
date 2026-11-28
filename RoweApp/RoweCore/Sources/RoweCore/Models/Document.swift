import Foundation

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case serif = "Serif"
    case mono = "Mono"
    case rounded = "Round"
    case baskerville = "Baskerville"
    case georgia = "Georgia"
    case avenir = "Avenir"
    case palatino = "Palatino"

    public var badgeLabel: String {
        switch self {
        case .system: "Aa"
        case .serif: "Ss"
        case .mono: "00"
        case .rounded: "Rr"
        case .baskerville: "Bk"
        case .georgia: "Gg"
        case .avenir: "Av"
        case .palatino: "Pl"
        }
    }
}

public enum SeparatorStyle: String, Codable, CaseIterable, Sendable {
    case light = "Light"
    case regular = "Line"
    case strong = "Strong"
    case dotted = "Dotted"
    case wave = "Wave"
    case doodle = "Doodle"
    case washi = "Washi"
    case pageBreak = "Page Break"
}

public enum BackdropKind: String, Codable, CaseIterable, Sendable {
    case none
    case solid
    case gradient
    case sketch
}

public struct DocumentStyle: Codable, Hashable, Sendable {
    public var themeId: String
    public var backdropKind: BackdropKind
    public var backdropColorsHex: [String]
    public var documentColorHex: String?
    public var textColorHex: String?
    public var coverImageName: String?
    public var customBackdropBase64: String?
    public var separatorStyle: SeparatorStyle
    public var washiPatternId: String?
    public var customWashiBase64: String?
    public var fontFamily: FontFamily
    public var isWidePage: Bool

    public init(
        themeId: String = "original",
        backdropKind: BackdropKind = .none,
        backdropColorsHex: [String] = [],
        documentColorHex: String? = nil,
        textColorHex: String? = nil,
        coverImageName: String? = nil,
        customBackdropBase64: String? = nil,
        separatorStyle: SeparatorStyle = .regular,
        washiPatternId: String? = "peachy_peach",
        customWashiBase64: String? = nil,
        fontFamily: FontFamily = .system,
        isWidePage: Bool = false
    ) {
        self.themeId = themeId
        self.backdropKind = backdropKind
        self.backdropColorsHex = backdropColorsHex
        self.documentColorHex = documentColorHex
        self.textColorHex = textColorHex
        self.coverImageName = coverImageName
        self.customBackdropBase64 = customBackdropBase64
        self.separatorStyle = separatorStyle
        self.washiPatternId = washiPatternId
        self.customWashiBase64 = customWashiBase64
        self.fontFamily = fontFamily
        self.isWidePage = isWidePage
    }

    private enum CodingKeys: String, CodingKey {
        case themeId, backdropKind, backdropColorsHex, documentColorHex, textColorHex
        case coverImageName, customBackdropBase64, separatorStyle, washiPatternId, customWashiBase64
        case fontFamily, isWidePage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeId = try c.decodeIfPresent(String.self, forKey: .themeId) ?? "original"
        backdropKind = try c.decodeIfPresent(BackdropKind.self, forKey: .backdropKind) ?? .none
        backdropColorsHex = try c.decodeIfPresent([String].self, forKey: .backdropColorsHex) ?? []
        documentColorHex = try c.decodeIfPresent(String.self, forKey: .documentColorHex)
        textColorHex = try c.decodeIfPresent(String.self, forKey: .textColorHex)
        coverImageName = try c.decodeIfPresent(String.self, forKey: .coverImageName)
        customBackdropBase64 = try c.decodeIfPresent(String.self, forKey: .customBackdropBase64)
        separatorStyle = try c.decodeIfPresent(SeparatorStyle.self, forKey: .separatorStyle) ?? .regular
        washiPatternId = try c.decodeIfPresent(String.self, forKey: .washiPatternId) ?? "peachy_peach"
        customWashiBase64 = try c.decodeIfPresent(String.self, forKey: .customWashiBase64)
        fontFamily = try c.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? .system
        isWidePage = try c.decodeIfPresent(Bool.self, forKey: .isWidePage) ?? false
    }

    /// Returns true if an explicit light paper color is set, false if dark paper is set,
    /// or nil when using the adaptive system background.
    public var explicitPaperIsLight: Bool? {
        guard let hex = documentColorHex else { return nil }
        return Self.isHexLight(hex)
    }

    /// Guarantees readable ink against `documentColorHex` so white-on-light or dark-on-dark never occurs.
    public var safeTextColorHex: String? {
        guard let paperIsLight = explicitPaperIsLight else {
            return textColorHex
        }
        if let txt = textColorHex, Self.isHexLight(txt) != paperIsLight {
            return txt
        }
        return paperIsLight ? "#1F2225" : "#F2F3F5"
    }

    public static func isHexLight(_ hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return true }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return (0.299 * r + 0.587 * g + 0.114 * b) >= 0.55
    }
}

public struct ThemePreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let style: DocumentStyle
    public let previewIsDark: Bool

    public init(id: String, name: String, style: DocumentStyle, previewIsDark: Bool = false) {
        self.id = id
        self.name = name
        self.style = style
        self.previewIsDark = previewIsDark
    }

    public static let builtInPresets: [ThemePreset] = [
        ThemePreset(
            id: "original",
            name: "Original",
            style: DocumentStyle(themeId: "original", backdropKind: .none, fontFamily: .system)
        ),
        // Bundled Wallpaper Styles (built around /Wallpapers)
        ThemePreset(
            id: "apple_park",
            name: "Apple Park",
            style: DocumentStyle(
                themeId: "apple_park",
                backdropKind: .sketch,
                backdropColorsHex: ["#C7C9D6", "#8B8EA0"],
                documentColorHex: "#FFFFFF",
                textColorHex: "#1C1F24",
                coverImageName: "wp_apple_park",
                separatorStyle: .regular,
                fontFamily: .system
            )
        ),
        ThemePreset(
            id: "deep_cobalt",
            name: "Deep Cobalt",
            style: DocumentStyle(
                themeId: "deep_cobalt",
                backdropKind: .sketch,
                backdropColorsHex: ["#1A2638", "#2E405B"],
                documentColorHex: "#151C28",
                textColorHex: "#EEF3FA",
                coverImageName: "wp_blue_mac",
                separatorStyle: .light,
                fontFamily: .avenir
            ),
            previewIsDark: true
        ),
        ThemePreset(
            id: "indigo_night",
            name: "Indigo Night",
            style: DocumentStyle(
                themeId: "indigo_night",
                backdropKind: .sketch,
                backdropColorsHex: ["#141538", "#2B2D6E"],
                documentColorHex: "#12142A",
                textColorHex: "#F0F2FA",
                coverImageName: "wp_amber_wash",
                separatorStyle: .dotted,
                fontFamily: .mono
            ),
            previewIsDark: true
        ),
        ThemePreset(
            id: "alpine_dusk",
            name: "Alpine Dusk",
            style: DocumentStyle(
                themeId: "alpine_dusk",
                backdropKind: .sketch,
                backdropColorsHex: ["#3C3642", "#6A6073"],
                documentColorHex: "#1C1921",
                textColorHex: "#F2EFF5",
                coverImageName: "wp_alpine_ridge",
                separatorStyle: .doodle,
                fontFamily: .baskerville
            ),
            previewIsDark: true
        ),
        ThemePreset(
            id: "warm_slate",
            name: "Warm Slate",
            style: DocumentStyle(
                themeId: "warm_slate",
                backdropKind: .sketch,
                backdropColorsHex: ["#3A322F", "#655852"],
                documentColorHex: "#201C1B",
                textColorHex: "#F5EFEA",
                coverImageName: "wp_horizon_dusk",
                separatorStyle: .regular,
                fontFamily: .georgia
            ),
            previewIsDark: true
        ),
        ThemePreset(
            id: "ocean_drift",
            name: "Ocean Drift",
            style: DocumentStyle(
                themeId: "ocean_drift",
                backdropKind: .sketch,
                backdropColorsHex: ["#37648E", "#6B9CC4"],
                documentColorHex: "#FAFDFE",
                textColorHex: "#162636",
                coverImageName: "wp_velvet_noir",
                separatorStyle: .washi,
                washiPatternId: "groovy_water",
                fontFamily: .rounded
            )
        ),
        ThemePreset(
            id: "cedar_paper",
            name: "Cedar Paper",
            style: DocumentStyle(
                themeId: "cedar_paper",
                backdropKind: .sketch,
                backdropColorsHex: ["#735B47", "#A98E76"],
                documentColorHex: "#FBF8F3",
                textColorHex: "#2A211A",
                coverImageName: "wp_botanical_mist",
                separatorStyle: .washi,
                washiPatternId: "peachy_peach",
                fontFamily: .palatino
            )
        ),
        ThemePreset(
            id: "coastal_fog",
            name: "Coastal Fog",
            style: DocumentStyle(
                themeId: "coastal_fog",
                backdropKind: .sketch,
                backdropColorsHex: ["#637580", "#95A7B3"],
                documentColorHex: "#F9FBFD",
                textColorHex: "#1B242B",
                coverImageName: "wp_studio_glow",
                separatorStyle: .regular,
                fontFamily: .avenir
            )
        ),
        ThemePreset(
            id: "lavender_stone",
            name: "Lavender Stone",
            style: DocumentStyle(
                themeId: "lavender_stone",
                backdropKind: .sketch,
                backdropColorsHex: ["#7F7882", "#B2ABB5"],
                documentColorHex: "#FCFBFD",
                textColorHex: "#241F29",
                coverImageName: "wp_cobalt_silk",
                separatorStyle: .washi,
                washiPatternId: "childhood_clouds",
                fontFamily: .baskerville
            )
        ),
        ThemePreset(
            id: "silver_tide",
            name: "Silver Tide",
            style: DocumentStyle(
                themeId: "silver_tide",
                backdropKind: .sketch,
                backdropColorsHex: ["#848FA8", "#BAC3D6"],
                documentColorHex: "#FAFBFD",
                textColorHex: "#1C2230",
                coverImageName: "wp_midnight_wave",
                separatorStyle: .doodle,
                fontFamily: .system
            )
        ),
        ThemePreset(
            id: "gallery_stone",
            name: "Gallery Stone",
            style: DocumentStyle(
                themeId: "gallery_stone",
                backdropKind: .sketch,
                backdropColorsHex: ["#969291", "#C4C0BF"],
                documentColorHex: "#FDFCFB",
                textColorHex: "#232120",
                coverImageName: "wp_malfoid",
                separatorStyle: .washi,
                washiPatternId: "botanical_ink",
                fontFamily: .serif
            )
        ),
        ThemePreset(
            id: "warm_chalk",
            name: "Warm Chalk",
            style: DocumentStyle(
                themeId: "warm_chalk",
                backdropKind: .sketch,
                backdropColorsHex: ["#B5B0B0", "#DBD7D7"],
                documentColorHex: "#FFFDFB",
                textColorHex: "#262321",
                coverImageName: "wp_desert_sand",
                separatorStyle: .washi,
                washiPatternId: "sage_linen",
                fontFamily: .georgia
            )
        ),
        // Editorial Canvas Classics
        ThemePreset(
            id: "ivory_folds",
            name: "Ivory Folds",
            style: DocumentStyle(
                themeId: "ivory_folds",
                backdropKind: .sketch,
                backdropColorsHex: ["#FAF6EE", "#E6D9C3"],
                documentColorHex: "#FFFDF9",
                textColorHex: "#24201A",
                coverImageName: "ivory_folds",
                separatorStyle: .doodle,
                fontFamily: .baskerville
            )
        ),
        ThemePreset(
            id: "sage_wash",
            name: "Sage Mist",
            style: DocumentStyle(
                themeId: "sage_wash",
                backdropKind: .sketch,
                backdropColorsHex: ["#F2F5F0", "#C5D5CA"],
                documentColorHex: "#FBFCFA",
                textColorHex: "#1E2923",
                coverImageName: "sage_wash",
                separatorStyle: .washi,
                washiPatternId: "sage_linen",
                fontFamily: .palatino
            )
        ),
        ThemePreset(
            id: "obsidian_silk",
            name: "Obsidian Silk",
            style: DocumentStyle(
                themeId: "obsidian_silk",
                backdropKind: .sketch,
                backdropColorsHex: ["#14161D", "#2B3245"],
                documentColorHex: "#1C1E26",
                textColorHex: "#F1F3F7",
                coverImageName: "obsidian_silk",
                separatorStyle: .regular,
                fontFamily: .avenir
            ),
            previewIsDark: true
        ),
        ThemePreset(
            id: "terracotta_arch",
            name: "Terracotta Linen",
            style: DocumentStyle(
                themeId: "terracotta_arch",
                backdropKind: .sketch,
                backdropColorsHex: ["#F7ECE2", "#C97A53"],
                documentColorHex: "#FFFBF7",
                textColorHex: "#2D1E16",
                coverImageName: "terracotta_arch",
                separatorStyle: .washi,
                washiPatternId: "peachy_peach",
                fontFamily: .georgia
            )
        )
    ]
}

public struct RoweDocument: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var spaceId: String
    public var folderId: String?
    public var title: String
    public var blocks: [Block]
    public var style: DocumentStyle
    public var tags: [String]
    public var isStarred: Bool
    public var isDailyNote: Bool
    public var dailyNoteDateKey: String?
    public var isTaskDayDocument: Bool
    public var taskDayDateKey: String?
    public var isTrashed: Bool
    public var isLocked: Bool
    public var encryptedPayload: String?
    public var authorName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastViewedAt: Date
    public var publishedURL: String?

    /// Deterministic document ID prefix for hidden per-day calendar task documents.
    public static let taskDayDocumentIdPrefix = "tasks-day-"

    /// Returns true if this document is an internal hidden task container (per-day task doc or legacy Tasks Inbox)
    /// that must not appear in All Docs, Home, Folders, Sidebar, Trash, or Quick Open search.
    public var isHiddenTaskDocument: Bool {
        isTaskDayDocument
            || id.hasPrefix(Self.taskDayDocumentIdPrefix)
            || title == "Tasks Inbox"
            || title.hasPrefix("Tasks Inbox (Sync Conflict)")
    }

    public init(
        id: String = UUID().uuidString,
        spaceId: String,
        folderId: String? = nil,
        title: String = "",
        blocks: [Block] = [],
        style: DocumentStyle = DocumentStyle(),
        tags: [String] = [],
        isStarred: Bool = false,
        isDailyNote: Bool = false,
        dailyNoteDateKey: String? = nil,
        isTaskDayDocument: Bool = false,
        taskDayDateKey: String? = nil,
        isTrashed: Bool = false,
        isLocked: Bool = false,
        encryptedPayload: String? = nil,
        authorName: String = "Ca5 .",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastViewedAt: Date = Date(),
        publishedURL: String? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.folderId = folderId
        self.title = title
        self.blocks = blocks
        self.style = style
        self.tags = tags
        self.isStarred = isStarred
        self.isDailyNote = isDailyNote
        self.dailyNoteDateKey = dailyNoteDateKey
        self.isTaskDayDocument = isTaskDayDocument || id.hasPrefix(Self.taskDayDocumentIdPrefix)
        self.taskDayDateKey = taskDayDateKey ?? (id.hasPrefix(Self.taskDayDocumentIdPrefix) ? String(id.dropFirst(Self.taskDayDocumentIdPrefix.count)) : nil)
        self.isTrashed = isTrashed
        self.isLocked = isLocked
        self.encryptedPayload = encryptedPayload
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastViewedAt = lastViewedAt
        self.publishedURL = publishedURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, spaceId, folderId, title, blocks, style, tags, isStarred, isDailyNote, dailyNoteDateKey
        case isTaskDayDocument, taskDayDateKey
        case isTrashed, isLocked, encryptedPayload, authorName, createdAt, updatedAt, lastViewedAt, publishedURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        spaceId = try c.decode(String.self, forKey: .spaceId)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        style = try c.decodeIfPresent(DocumentStyle.self, forKey: .style) ?? DocumentStyle()
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        isDailyNote = try c.decodeIfPresent(Bool.self, forKey: .isDailyNote) ?? false
        dailyNoteDateKey = try c.decodeIfPresent(String.self, forKey: .dailyNoteDateKey)
        let decodedTaskDay = try c.decodeIfPresent(Bool.self, forKey: .isTaskDayDocument) ?? false
        isTaskDayDocument = decodedTaskDay || id.hasPrefix(Self.taskDayDocumentIdPrefix)
        taskDayDateKey = try c.decodeIfPresent(String.self, forKey: .taskDayDateKey)
            ?? (id.hasPrefix(Self.taskDayDocumentIdPrefix) ? String(id.dropFirst(Self.taskDayDocumentIdPrefix.count)) : nil)
        isTrashed = try c.decodeIfPresent(Bool.self, forKey: .isTrashed) ?? false
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        encryptedPayload = try c.decodeIfPresent(String.self, forKey: .encryptedPayload)
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? "Ca5 ."
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastViewedAt = try c.decodeIfPresent(Date.self, forKey: .lastViewedAt) ?? Date()
        publishedURL = try c.decodeIfPresent(String.self, forKey: .publishedURL)
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Document" : trimmed
    }

    public var previewSnippet: String {
        if isLocked {
            return "Locked Note · Enter PIN to view"
        }
        let texts = blocks.prefix(4).compactMap { block -> String? in
            let s = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
            if let col = block.collectionData { return col.title }
            return nil
        }
        return texts.isEmpty ? "Empty Document" : texts.joined(separator: " · ")
    }
}

public struct SharedDocumentItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var preview: String
    public var sharedByName: String
    public var sharedByInitial: String
    public var sharedByColorHex: String
    public var dateShared: Date
    public var lastViewed: Date
    public var documentId: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        preview: String = "--- ---",
        sharedByName: String,
        sharedByInitial: String,
        sharedByColorHex: String = "#8B3A1E",
        dateShared: Date,
        lastViewed: Date,
        documentId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.sharedByName = sharedByName
        self.sharedByInitial = sharedByInitial
        self.sharedByColorHex = sharedByColorHex
        self.dateShared = dateShared
        self.lastViewed = lastViewed
        self.documentId = documentId
    }
}

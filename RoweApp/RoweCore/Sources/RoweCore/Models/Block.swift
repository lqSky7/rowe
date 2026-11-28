import Foundation

/// Mirrors Craft's recovered v2BlockModelType kinds.
public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case video
    case url
    case line
    case file
    case drawing
    case code
    case table
    case object
    case objectList
    case whiteboard
}

public enum BlockTextStyle: String, Codable, CaseIterable, Sendable {
    case title
    case subtitle
    case heading
    case strong
    case body
    case caption
    case pageRegular
    case pageCard

    public var displayName: String {
        switch self {
        case .title: "Title"
        case .subtitle: "Subtitle"
        case .heading: "Heading"
        case .strong: "Strong"
        case .body: "Body"
        case .caption: "Caption"
        case .pageRegular: "Page"
        case .pageCard: "Card"
        }
    }

    public var shortBadge: String {
        switch self {
        case .title: "H1"
        case .subtitle: "H2"
        case .heading: "H3"
        case .strong: "St"
        case .body: "Aa"
        case .caption: "Ca"
        case .pageRegular: "Pg"
        case .pageCard: "Cd"
        }
    }
}

public enum BlockListStyle: String, Codable, CaseIterable, Sendable {
    case none
    case bullet
    case numbered
    case todo
    case toggle
}

/// Craft TaskCompletionState: 0 pending, 1 completed, 2 canceled.
public enum TaskCompletionState: Int, Codable, CaseIterable, Sendable {
    case pending = 0
    case completed = 1
    case canceled = 2
}

public enum BlockAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
    case justified
}

public enum BlockDecoration: String, Codable, CaseIterable, Sendable {
    case none
    case focus
    case block
}

public enum BlockColor: String, Codable, CaseIterable, Sendable {
    case primary = "Default"
    case gray = "Gray"
    case lightGray = "Light Gray"
    case purple = "Purple"
    case indigo = "Indigo"
    case cyan = "Cyan"
    case teal = "Teal"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case red = "Red"

    public var hex: String {
        switch self {
        case .primary: "#1F2225"
        case .gray: "#7C828D"
        case .lightGray: "#C4C7CE"
        case .purple: "#BD78C9"
        case .indigo: "#8C9CE0"
        case .cyan: "#7AB8CC"
        case .teal: "#6EB3AD"
        case .green: "#72B396"
        case .yellow: "#DFC370"
        case .orange: "#DCA36E"
        case .red: "#D97574"
        }
    }
}

/// UTF-16 code-unit inline formatting run matching Craft's v2BlockModelTextRunAttributes.
public struct TextRunAttributes: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var isBold: Bool
    public var isItalic: Bool
    public var isStrikethrough: Bool
    public var isCode: Bool
    public var highlightColor: String?
    public var textColorHex: String?
    public var linkURL: String?

    public init(
        location: Int,
        length: Int,
        isBold: Bool = false,
        isItalic: Bool = false,
        isStrikethrough: Bool = false,
        isCode: Bool = false,
        highlightColor: String? = nil,
        textColorHex: String? = nil,
        linkURL: String? = nil
    ) {
        self.location = max(0, location)
        self.length = max(0, length)
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.isCode = isCode
        self.highlightColor = highlightColor
        self.textColorHex = textColorHex
        self.linkURL = linkURL
    }

    public var upperBound: Int { location + length }

    public var isEmptyStyle: Bool {
        !isBold && !isItalic && !isStrikethrough && !isCode && highlightColor == nil && textColorHex == nil && linkURL == nil
    }

    public func hasSameStyle(as other: TextRunAttributes) -> Bool {
        isBold == other.isBold &&
        isItalic == other.isItalic &&
        isStrikethrough == other.isStrikethrough &&
        isCode == other.isCode &&
        highlightColor == other.highlightColor &&
        textColorHex == other.textColorHex &&
        linkURL == other.linkURL
    }

    /// Normalizes, clamps to UTF-16 length, drops empty runs, and merges contiguous matching runs.
    public static func normalize(_ runs: [TextRunAttributes], utf16Length: Int) -> [TextRunAttributes] {
        guard utf16Length > 0 else { return [] }
        let clamped = runs
            .compactMap { run -> TextRunAttributes? in
                guard !run.isEmptyStyle else { return nil }
                let start = max(0, min(run.location, utf16Length))
                let end = max(start, min(run.upperBound, utf16Length))
                let len = end - start
                guard len > 0 else { return nil }
                var copy = run
                copy.location = start
                copy.length = len
                return copy
            }
            .sorted { $0.location < $1.location }

        var merged: [TextRunAttributes] = []
        for run in clamped {
            if var last = merged.last, last.upperBound == run.location, last.hasSameStyle(as: run) {
                last.length += run.length
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// Splits a run list at a UTF-16 offset into (leadingRuns, trailingRuns shifted by -offset).
    public static func split(_ runs: [TextRunAttributes], at utf16Offset: Int, totalLength: Int) -> ([TextRunAttributes], [TextRunAttributes]) {
        let clampedOffset = max(0, min(utf16Offset, totalLength))
        var leading: [TextRunAttributes] = []
        var trailing: [TextRunAttributes] = []

        for run in runs {
            if run.upperBound <= clampedOffset {
                leading.append(run)
            } else if run.location >= clampedOffset {
                var shifted = run
                shifted.location -= clampedOffset
                trailing.append(shifted)
            } else {
                var left = run
                left.length = clampedOffset - run.location
                if left.length > 0 { leading.append(left) }

                var right = run
                right.location = 0
                right.length = run.upperBound - clampedOffset
                if right.length > 0 { trailing.append(right) }
            }
        }
        return (
            normalize(leading, utf16Length: clampedOffset),
            normalize(trailing, utf16Length: max(0, totalLength - clampedOffset))
        )
    }

    /// Shifts all runs by a positive UTF-16 offset (used when merging two blocks).
    public static func shifted(_ runs: [TextRunAttributes], by delta: Int) -> [TextRunAttributes] {
        runs.map { run in
            var copy = run
            copy.location = max(0, run.location + delta)
            return copy
        }
    }
}

public enum TableCellFormatKind: String, Codable, CaseIterable, Sendable {
    case text = "t"
    case number = "n"
    case percentage = "p"
    case currency = "c"
}

public struct TableCellFormat: Codable, Hashable, Sendable {
    public var kind: TableCellFormatKind
    public var precision: Int
    public var currencyCode: String

    public init(kind: TableCellFormatKind = .text, precision: Int = 2, currencyCode: String = "USD") {
        self.kind = kind
        self.precision = precision
        self.currencyCode = currencyCode
    }
}

public struct TableCell: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var rawContent: String
    public var format: TableCellFormat

    public init(id: String = UUID().uuidString, rawContent: String = "", format: TableCellFormat = TableCellFormat()) {
        self.id = id
        self.rawContent = rawContent
        self.format = format
    }
}

public struct TableData: Codable, Hashable, Sendable {
    public var columnCount: Int
    public var rowCount: Int
    public var hasHeaderRow: Bool
    public var hasHeaderColumn: Bool
    public var cells: [[TableCell]]

    public init(
        rows: Int = 3,
        columns: Int = 3,
        hasHeaderRow: Bool = true,
        hasHeaderColumn: Bool = false
    ) {
        let rCount = max(1, rows)
        let cCount = max(1, columns)
        self.rowCount = rCount
        self.columnCount = cCount
        self.hasHeaderRow = hasHeaderRow
        self.hasHeaderColumn = hasHeaderColumn
        self.cells = (0..<rCount).map { _ in
            (0..<cCount).map { _ in TableCell() }
        }
    }

    public mutating func appendRow() {
        let newRow = (0..<columnCount).map { _ in TableCell() }
        cells.append(newRow)
        rowCount = cells.count
    }

    public mutating func appendColumn() {
        for r in 0..<cells.count {
            cells[r].append(TableCell())
        }
        columnCount += 1
    }
}

public enum CollectionFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case singleSelect
    case url
    case number
    case date
    case checkbox
}

public struct CollectionColumn: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var type: CollectionFieldType
    public var width: Double

    public init(id: String = UUID().uuidString, title: String, type: CollectionFieldType = .text, width: Double = 140) {
        self.id = id
        self.title = title
        self.type = type
        self.width = width
    }
}

public struct CollectionRow: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var values: [String: String]

    public init(id: String = UUID().uuidString, values: [String: String] = [:]) {
        self.id = id
        self.values = values
    }
}

public enum CollectionViewMode: String, Codable, CaseIterable, Sendable {
    case table = "Table"
    case gallery = "Gallery"
    case kanban = "Kanban"
}

public struct CollectionData: Codable, Hashable, Sendable {
    public var title: String
    public var viewMode: CollectionViewMode
    public var columns: [CollectionColumn]
    public var rows: [CollectionRow]

    public init(
        title: String = "Collection",
        viewMode: CollectionViewMode = .table,
        columns: [CollectionColumn] = [],
        rows: [CollectionRow] = []
    ) {
        self.title = title
        self.viewMode = viewMode
        self.columns = columns
        self.rows = rows
    }
}

public struct Block: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var documentId: String
    public var kind: BlockKind
    public var content: String
    public var runs: [TextRunAttributes]
    public var textStyle: BlockTextStyle
    public var listStyle: BlockListStyle
    public var userDefinedListNumber: Int?
    public var indentLevel: Int
    public var alignment: BlockAlignment
    public var decoration: BlockDecoration
    public var color: BlockColor
    public var fontOverride: FontFamily?
    public var isBold: Bool
    public var isItalic: Bool
    public var isStrikethrough: Bool
    public var isInlineCode: Bool
    public var isToggleExpanded: Bool
    public var separatorStyle: SeparatorStyle
    public var codeLanguage: String
    public var urlString: String?
    public var fileName: String?
    public var task: TaskMetadata?
    public var tableData: TableData?
    public var collectionData: CollectionData?
    public var subblocks: [Block]
    public var updatedAt: Date
    public var deletedAt: Date?
    public var sortOrder: Double?

    public init(
        id: String = UUID().uuidString,
        documentId: String,
        kind: BlockKind = .text,
        content: String = "",
        runs: [TextRunAttributes] = [],
        textStyle: BlockTextStyle = .body,
        listStyle: BlockListStyle = .none,
        userDefinedListNumber: Int? = nil,
        indentLevel: Int = 0,
        alignment: BlockAlignment = .leading,
        decoration: BlockDecoration = .none,
        color: BlockColor = .primary,
        fontOverride: FontFamily? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isStrikethrough: Bool = false,
        isInlineCode: Bool = false,
        isToggleExpanded: Bool = true,
        separatorStyle: SeparatorStyle = .regular,
        codeLanguage: String = "swift",
        urlString: String? = nil,
        fileName: String? = nil,
        task: TaskMetadata? = nil,
        tableData: TableData? = nil,
        collectionData: CollectionData? = nil,
        subblocks: [Block] = [],
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        sortOrder: Double? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.kind = kind
        self.content = content
        self.runs = TextRunAttributes.normalize(runs, utf16Length: content.utf16.count)
        self.textStyle = textStyle
        self.listStyle = listStyle
        self.userDefinedListNumber = userDefinedListNumber
        self.indentLevel = max(0, min(indentLevel, 8))
        self.alignment = alignment
        self.decoration = decoration
        self.color = color
        self.fontOverride = fontOverride
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.isInlineCode = isInlineCode
        self.isToggleExpanded = isToggleExpanded
        self.separatorStyle = separatorStyle
        self.codeLanguage = codeLanguage
        self.urlString = urlString
        self.fileName = fileName
        self.task = task
        self.tableData = tableData
        self.collectionData = collectionData
        self.subblocks = subblocks
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, documentId, kind, content, runs, textStyle, listStyle, userDefinedListNumber
        case indentLevel, alignment, decoration, color, fontOverride
        case isBold, isItalic, isStrikethrough, isInlineCode, isToggleExpanded
        case separatorStyle, codeLanguage, urlString, fileName
        case task, tableData, collectionData, subblocks, updatedAt, deletedAt, sortOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        documentId = try c.decode(String.self, forKey: .documentId)
        kind = try c.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .text
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        let decodedRuns = try c.decodeIfPresent([TextRunAttributes].self, forKey: .runs) ?? []
        runs = TextRunAttributes.normalize(decodedRuns, utf16Length: content.utf16.count)
        textStyle = try c.decodeIfPresent(BlockTextStyle.self, forKey: .textStyle) ?? .body
        listStyle = try c.decodeIfPresent(BlockListStyle.self, forKey: .listStyle) ?? .none
        userDefinedListNumber = try c.decodeIfPresent(Int.self, forKey: .userDefinedListNumber)
        indentLevel = max(0, min(try c.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0, 8))
        alignment = try c.decodeIfPresent(BlockAlignment.self, forKey: .alignment) ?? .leading
        decoration = try c.decodeIfPresent(BlockDecoration.self, forKey: .decoration) ?? .none
        color = try c.decodeIfPresent(BlockColor.self, forKey: .color) ?? .primary
        fontOverride = try c.decodeIfPresent(FontFamily.self, forKey: .fontOverride)
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isStrikethrough = try c.decodeIfPresent(Bool.self, forKey: .isStrikethrough) ?? false
        isInlineCode = try c.decodeIfPresent(Bool.self, forKey: .isInlineCode) ?? false
        isToggleExpanded = try c.decodeIfPresent(Bool.self, forKey: .isToggleExpanded) ?? true
        separatorStyle = try c.decodeIfPresent(SeparatorStyle.self, forKey: .separatorStyle) ?? .regular
        codeLanguage = try c.decodeIfPresent(String.self, forKey: .codeLanguage) ?? "swift"
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        task = try c.decodeIfPresent(TaskMetadata.self, forKey: .task)
        tableData = try c.decodeIfPresent(TableData.self, forKey: .tableData)
        collectionData = try c.decodeIfPresent(CollectionData.self, forKey: .collectionData)
        subblocks = try c.decodeIfPresent([Block].self, forKey: .subblocks) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder)
    }

    public var effectiveSortOrder: Double {
        sortOrder ?? updatedAt.timeIntervalSince1970
    }

    /// Strict total order for tasks across all devices (commutative & deterministic).
    public static func canonicalTaskOrderComparator(_ a: Block, _ b: Block) -> Bool {
        let oa = a.effectiveSortOrder
        let ob = b.effectiveSortOrder
        if abs(oa - ob) > 1e-9 {
            return oa < ob
        }
        return a.id < b.id
    }

    public var isHeadingForTOC: Bool {
        deletedAt == nil && kind == .text && (textStyle == .title || textStyle == .subtitle || textStyle == .heading || textStyle == .pageRegular || textStyle == .pageCard)
    }

    public var isTask: Bool {
        deletedAt == nil && (listStyle == .todo || task != nil)
    }

    /// True for both live tasks and tombstoned (soft-deleted) task blocks.
    public var isTaskOrTombstone: Bool {
        listStyle == .todo || task != nil
    }

    public var isEditableTextBlock: Bool {
        kind == .text && textStyle != .pageRegular && textStyle != .pageCard
    }

    public var isEmptyPlainBody: Bool {
        kind == .text &&
        content.isEmpty &&
        textStyle == .body &&
        listStyle == .none &&
        decoration == .none
    }
}

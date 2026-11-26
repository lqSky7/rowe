import AppKit
import SwiftUI
import RoweCore

enum SlashSubmenu: String, CaseIterable, Equatable {
    case root
    case list
    case textStyle
    case actions
    case decorations
    case color
    case indentation
    case alignment
    case font
    case remindMe
    case dateTime
    case insertTable
    case insertSnippet
    case insertSeparator
    case collections

    var title: String {
        switch self {
        case .root: ""
        case .list: "List"
        case .textStyle: "Text Style"
        case .actions: "Actions"
        case .decorations: "Decorations"
        case .color: "Color"
        case .indentation: "Indentation"
        case .alignment: "Alignment"
        case .font: "Font"
        case .remindMe: "Remind me"
        case .dateTime: "Date & Time"
        case .insertTable: "Insert Table"
        case .insertSnippet: "Insert Snippet"
        case .insertSeparator: "Insert Separator"
        case .collections: "Collections"
        }
    }
}

enum SlashAction {
    case setList(BlockListStyle)
    case setTextStyle(BlockTextStyle)
    case setDecoration(BlockDecoration)
    case setColor(BlockColor)
    case indent(Int)
    case setAlignment(BlockAlignment)
    case setFont(FontFamily?)
    case insertDate(String)
    case setReminder(TimeInterval)
    case insertTable(rows: Int, cols: Int)
    case insertCodeBlock
    case insertSeparator(SeparatorStyle)
    case insertCollection(CollectionViewMode)
    case insertURL
    case openStyleGallery
    case clearFormat
    case duplicateBlock
    case deleteBlock
}

private struct SlashMenuEntry: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let badge: String?
    let colorHex: String?
    let keywords: [String]
    let submenu: SlashSubmenu?
    let action: SlashAction?

    init(
        id: String? = nil,
        title: String,
        icon: String? = nil,
        badge: String? = nil,
        colorHex: String? = nil,
        keywords: [String] = [],
        submenu: SlashSubmenu? = nil,
        action: SlashAction? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.icon = icon
        self.badge = badge
        self.colorHex = colorHex
        self.keywords = keywords
        self.submenu = submenu
        self.action = action
    }

    func matchScore(for query: String) -> Int? {
        let lowerTitle = title.lowercased()
        if lowerTitle == query { return 100 }
        if lowerTitle.hasPrefix(query) { return 85 }
        if lowerTitle.contains(query) { return 70 }
        if keywords.contains(where: { $0.lowercased() == query }) { return 65 }
        if keywords.contains(where: { $0.lowercased().hasPrefix(query) }) { return 55 }
        if keywords.contains(where: { $0.lowercased().contains(query) }) { return 40 }
        return nil
    }
}

/// End-to-end keyboard-navigable Liquid Glass `/` command palette.
/// - Esc steps back one level from submenus / clears active search before dismissing.
/// - Search covers both root categories (e.g. `/color`, `/list`, `/font`) and all leaf commands (e.g. `/red`, `/h1`, `/code`).
struct SlashMenuView: View {
    @Binding var isPresented: Bool
    var onAction: (SlashAction) -> Void

    @State private var submenu: SlashSubmenu = .root
    @State private var selectedIndex: Int = 0
    @State private var savedRootIndex: Int = 0
    @State private var filterText: String = ""
    @State private var keyMonitor: Any?
    @State private var keyboardScrollToken: Int = 0
    @Namespace private var selectionPillNS

    // Concentric radii: outer 16 - inset 6 = inner 10
    private let outerRadius: CGFloat = 16
    private let containerInset: CGFloat = 6
    private let rowRadius: CGFloat = 10
    private let rowHeight: CGFloat = 34
    private let rowSpacing: CGFloat = 2
    private let maxListHeight: CGFloat = 270

    private var entries: [SlashMenuEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            let pool = submenu == .root ? allSearchableEntries() : entriesFor(submenu)
            return pool
                .compactMap { entry -> (SlashMenuEntry, Int)? in
                    guard let score = entry.matchScore(for: q) else { return nil }
                    return (entry, score)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.0.title < rhs.0.title
                }
                .map(\.0)
        }
        return entriesFor(submenu)
    }

    private var dynamicListHeight: CGFloat {
        let count = max(1, entries.count)
        let natural = CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * rowSpacing + containerInset * 2
        return min(maxListHeight, natural)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !filterText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(submenu == .root ? "/\(filterText)" : "\(submenu.title) · \(filterText)")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Text("esc")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().opacity(0.25).padding(.horizontal, 8)
            } else if submenu != .root {
                Button {
                    popSubmenu()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(submenu.title)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text("esc")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.25).padding(.horizontal, 8)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: entries.count > 7) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        let items = entries
                        if items.isEmpty {
                            Text("No matching commands")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                                .padding(.horizontal, 10)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                let isSelected = idx == selectedIndex
                                Button {
                                    activate(item)
                                } label: {
                                    HStack(spacing: 10) {
                                        if let hex = item.colorHex {
                                            Circle()
                                                .fill(Color(hex: hex))
                                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75))
                                                .frame(width: 14, height: 14)
                                                .frame(width: 20)
                                        } else if let badge = item.badge {
                                            Text(badge)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(isSelected ? .primary : .secondary)
                                                .frame(width: 20)
                                        } else if let icon = item.icon {
                                            Image(systemName: icon)
                                                .font(.system(size: 13))
                                                .foregroundStyle(isSelected ? .primary : .secondary)
                                                .frame(width: 20)
                                        }

                                        Text(item.title)
                                            .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if item.submenu != nil {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: rowHeight)
                                    .background {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                                                .fill(Color.primary.opacity(0.12))
                                                .matchedGeometryEffect(id: "slashActivePill", in: selectionPillNS)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering && selectedIndex != idx {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
                                            selectedIndex = idx
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(containerInset)
                }
                .frame(height: dynamicListHeight)
                .onChange(of: keyboardScrollToken) { _, _ in
                    let items = entries
                    if selectedIndex >= 0 && selectedIndex < items.count {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            proxy.scrollTo(items[selectedIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .background(RoweNativeGlassBackdrop(cornerRadius: outerRadius))
        .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: submenu)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: dynamicListHeight)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            guard mods.isEmpty else { return event }

            switch event.keyCode {
            case 126: // Up Arrow
                moveSelection(-1)
                return nil
            case 125: // Down Arrow
                moveSelection(1)
                return nil
            case 124: // Right Arrow
                let items = entries
                if selectedIndex < items.count, let sub = items[selectedIndex].submenu {
                    enterSubmenu(sub)
                    return nil
                }
                return nil
            case 123: // Left Arrow
                if submenu != .root && filterText.isEmpty {
                    popSubmenu()
                    return nil
                }
                return nil
            case 36, 76: // Return / Enter
                let items = entries
                if selectedIndex < items.count {
                    activate(items[selectedIndex])
                }
                return nil
            case 53: // Escape: step back one level from submenu (or clear filter) before closing
                HapticsManager.shared.tap()
                if !filterText.isEmpty {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        filterText = ""
                        selectedIndex = 0
                    }
                } else if submenu != .root {
                    popSubmenu()
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }
                return nil
            case 51: // Backspace
                if !filterText.isEmpty {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        filterText.removeLast()
                        selectedIndex = 0
                    }
                    return nil
                } else if submenu != .root {
                    popSubmenu()
                    return nil
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                    return event
                }
            default:
                if let chars = event.characters, !chars.isEmpty,
                   chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " }) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        filterText.append(chars)
                        selectedIndex = 0
                    }
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
            selectedIndex = (selectedIndex + delta + count) % count
        }
        keyboardScrollToken += 1
        HapticsManager.shared.tap()
    }

    private func enterSubmenu(_ target: SlashSubmenu) {
        HapticsManager.shared.tap()
        savedRootIndex = selectedIndex
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            filterText = ""
            submenu = target
            selectedIndex = 0
        }
        keyboardScrollToken += 1
    }

    private func popSubmenu() {
        HapticsManager.shared.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            filterText = ""
            submenu = .root
            selectedIndex = min(savedRootIndex, max(0, entriesFor(.root).count - 1))
        }
        keyboardScrollToken += 1
    }

    private func activate(_ item: SlashMenuEntry) {
        if let sub = item.submenu {
            enterSubmenu(sub)
        } else if let action = item.action {
            HapticsManager.shared.tap()
            onAction(action)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                isPresented = false
            }
            submenu = .root
            filterText = ""
            selectedIndex = 0
        }
    }

    private func entriesFor(_ menu: SlashSubmenu) -> [SlashMenuEntry] {
        switch menu {
        case .root:
            return [
                SlashMenuEntry(id: "root-list", title: "List", icon: "list.bullet", keywords: ["bullet", "todo", "numbered", "toggle"], submenu: .list),
                SlashMenuEntry(id: "root-textstyle", title: "Text Style", icon: "textformat", keywords: ["heading", "title", "subtitle", "body", "h1", "h2", "h3"], submenu: .textStyle),
                SlashMenuEntry(id: "root-actions", title: "Actions", icon: "command", keywords: ["duplicate", "delete", "clear"], submenu: .actions),
                SlashMenuEntry(id: "root-decorations", title: "Decorations", icon: "text.quote", keywords: ["callout", "quote", "focus", "block"], submenu: .decorations),
                SlashMenuEntry(id: "root-color", title: "Color", icon: "paintbrush", keywords: ["colour", "tint", "text color", "paint"], submenu: .color),
                SlashMenuEntry(id: "root-indent", title: "Indentation", icon: "increase.indent", keywords: ["indent", "outdent", "tab"], submenu: .indentation),
                SlashMenuEntry(id: "root-align", title: "Alignment", icon: "text.alignleft", keywords: ["left", "center", "right", "justify"], submenu: .alignment),
                SlashMenuEntry(id: "root-font", title: "Font", icon: "textformat.alt", keywords: ["typeface", "serif", "mono", "rounded"], submenu: .font),
                SlashMenuEntry(id: "root-remind", title: "Remind me", icon: "alarm", keywords: ["reminder", "alarm", "schedule"], submenu: .remindMe),
                SlashMenuEntry(id: "root-datetime", title: "Date & Time", icon: "calendar", keywords: ["today", "time", "now"], submenu: .dateTime),
                SlashMenuEntry(id: "root-table", title: "Insert Table", icon: "tablecells", keywords: ["grid", "spreadsheet", "matrix"], submenu: .insertTable),
                SlashMenuEntry(id: "root-snippet", title: "Insert Snippet", icon: "chevron.left.forwardslash.chevron.right", keywords: ["code", "url", "link", "formula"], submenu: .insertSnippet),
                SlashMenuEntry(id: "root-separator", title: "Insert Separator", icon: "minus", keywords: ["divider", "line", "hr", "washi", "doodle", "page break"], submenu: .insertSeparator),
                SlashMenuEntry(id: "root-style", title: "Cover Image / Style", icon: "photo", keywords: ["theme", "wallpaper", "backdrop"], action: .openStyleGallery),
                SlashMenuEntry(id: "root-collections", title: "Collections", icon: "rectangle.3.group", keywords: ["database", "kanban", "gallery"], submenu: .collections),
                SlashMenuEntry(id: "root-clear", title: "Clear Format", icon: "xmark.square", keywords: ["reset", "plain"], action: .clearFormat),
                SlashMenuEntry(id: "root-delete", title: "Delete Block", icon: "trash", keywords: ["remove"], action: .deleteBlock)
            ]
        case .list:
            return [
                SlashMenuEntry(title: "Todo List", icon: "checkmark.square", keywords: ["task", "checkbox", "check", "list"], action: .setList(.todo)),
                SlashMenuEntry(title: "Toggle List", icon: "arrowtriangle.right.fill", keywords: ["collapse", "fold", "dropdown", "list"], action: .setList(.toggle)),
                SlashMenuEntry(title: "Bullet List", icon: "list.bullet", keywords: ["unordered", "ul", "dots", "list"], action: .setList(.bullet)),
                SlashMenuEntry(title: "Numbered List", icon: "list.number", keywords: ["ordered", "ol", "123", "list"], action: .setList(.numbered)),
                SlashMenuEntry(title: "No List", icon: "text.alignleft", keywords: ["plain", "unlist", "clear list"], action: .setList(.none))
            ]
        case .textStyle:
            return BlockTextStyle.allCases.map { style in
                let kws: [String]
                switch style {
                case .title: kws = ["h1", "heading 1", "text style"]
                case .subtitle: kws = ["h2", "heading 2", "text style"]
                case .heading: kws = ["h3", "heading 3", "text style"]
                case .strong: kws = ["h4", "bold", "text style"]
                case .body: kws = ["paragraph", "normal", "text"]
                case .caption: kws = ["small", "footnote", "meta"]
                case .pageRegular: kws = ["subpage", "page"]
                case .pageCard: kws = ["card", "box"]
                }
                return SlashMenuEntry(title: style.displayName, badge: style.shortBadge, keywords: kws, action: .setTextStyle(style))
            }
        case .actions:
            return [
                SlashMenuEntry(title: "Duplicate Block", icon: "plus.square.on.square", keywords: ["copy", "clone", "action"], action: .duplicateBlock),
                SlashMenuEntry(title: "Clear Format", icon: "xmark.square", keywords: ["reset", "plain", "action"], action: .clearFormat),
                SlashMenuEntry(title: "Delete Block", icon: "trash", keywords: ["remove", "action"], action: .deleteBlock)
            ]
        case .decorations:
            return [
                SlashMenuEntry(title: "Focus", icon: "text.quote", keywords: ["quote", "callout", "bar", "decoration"], action: .setDecoration(.focus)),
                SlashMenuEntry(title: "Block", icon: "rectangle.fill", keywords: ["box", "callout", "card", "decoration"], action: .setDecoration(.block)),
                SlashMenuEntry(title: "None", icon: "nosign", keywords: ["clear decoration", "plain"], action: .setDecoration(.none))
            ]
        case .color:
            return BlockColor.allCases.map { c in
                SlashMenuEntry(
                    id: "color-\(c.rawValue)",
                    title: c.rawValue,
                    colorHex: c.hex,
                    keywords: ["color", "colour", "tint", c == .primary ? "default" : c.rawValue.lowercased()],
                    action: .setColor(c)
                )
            }
        case .indentation:
            return [
                SlashMenuEntry(title: "Increase Indentation", icon: "increase.indent", keywords: ["indent", "tab"], action: .indent(1)),
                SlashMenuEntry(title: "Decrease Indentation", icon: "decrease.indent", keywords: ["outdent", "unindent"], action: .indent(-1))
            ]
        case .alignment:
            return [
                SlashMenuEntry(title: "Align Left", icon: "text.alignleft", keywords: ["alignment", "left"], action: .setAlignment(.leading)),
                SlashMenuEntry(title: "Align Center", icon: "text.aligncenter", keywords: ["alignment", "center", "middle"], action: .setAlignment(.center)),
                SlashMenuEntry(title: "Align Right", icon: "text.alignright", keywords: ["alignment", "right"], action: .setAlignment(.trailing)),
                SlashMenuEntry(title: "Justify", icon: "text.justify", keywords: ["alignment", "justified"], action: .setAlignment(.justified))
            ]
        case .font:
            return FontFamily.allCases.map {
                SlashMenuEntry(id: "font-\($0.rawValue)", title: $0.rawValue, badge: $0.badgeLabel, keywords: ["font", "typeface"], action: .setFont($0))
            }
        case .remindMe:
            return [
                SlashMenuEntry(title: "Remind in 1 Hour", icon: "alarm", keywords: ["reminder", "alarm"], action: .setReminder(3600)),
                SlashMenuEntry(title: "Remind Tomorrow 9:00 AM", icon: "sunrise", keywords: ["reminder", "tomorrow"], action: .setReminder(86400)),
                SlashMenuEntry(title: "Remind Next Week", icon: "calendar", keywords: ["reminder", "week"], action: .setReminder(7 * 86400))
            ]
        case .dateTime:
            let today = Date().formatted(date: .abbreviated, time: .omitted)
            let time = Date().formatted(date: .omitted, time: .shortened)
            return [
                SlashMenuEntry(title: "Today (\(today))", icon: "calendar", keywords: ["date", "today"], action: .insertDate("@\(today)")),
                SlashMenuEntry(title: "Current Time (\(time))", icon: "clock", keywords: ["time", "now"], action: .insertDate(time))
            ]
        case .insertTable:
            return (2...9).map { size in
                SlashMenuEntry(title: "Table – \(size) × \(size)", icon: "tablecells", keywords: ["table", "grid", "\(size)x\(size)"], action: .insertTable(rows: size, cols: size))
            }
        case .insertSnippet:
            return [
                SlashMenuEntry(title: "Code Block", icon: "chevron.left.forwardslash.chevron.right", keywords: ["code", "snippet", "programming", "syntax"], action: .insertCodeBlock),
                SlashMenuEntry(title: "Smart Link / URL", icon: "link", keywords: ["url", "link", "web", "snippet"], action: .insertURL),
                SlashMenuEntry(title: "Math Formula", icon: "x.squareroot", keywords: ["formula", "latex", "math", "equation"], action: .insertDate("$$E = mc^2$$"))
            ]
        case .insertSeparator:
            return SeparatorStyle.allCases.map { style in
                let label = style == .pageBreak ? "Page Break" : "\(style.rawValue) Separator"
                let icon = style == .pageBreak ? "rectangle.split.1x2" : (style == .washi ? "ticket" : (style == .doodle ? "scribble" : "minus"))
                return SlashMenuEntry(title: label, icon: icon, keywords: ["divider", "hr", "line", "separator", style.rawValue.lowercased()], action: .insertSeparator(style))
            }
        case .collections:
            return [
                SlashMenuEntry(title: "Table Collection", icon: "tablecells.badge.ellipsis", keywords: ["collection", "database"], action: .insertCollection(.table)),
                SlashMenuEntry(title: "Gallery Collection", icon: "square.grid.2x2", keywords: ["collection", "cards"], action: .insertCollection(.gallery)),
                SlashMenuEntry(title: "Kanban Board", icon: "rectangle.split.3x1", keywords: ["collection", "board", "kanban"], action: .insertCollection(.kanban))
            ]
        }
    }

    /// Searches root submenus (so `/color`, `/list`, `/font`, etc. immediately surface their menu)
    /// alongside all leaf actions (so `/red`, `/code`, `/h1`, `/table` work in one keystroke).
    private func allSearchableEntries() -> [SlashMenuEntry] {
        let rootSubmenus = entriesFor(.root).filter { $0.submenu != nil || $0.id == "root-style" }
        let leafMenus: [SlashSubmenu] = [
            .color, .list, .textStyle, .decorations, .insertSnippet, .insertSeparator,
            .insertTable, .collections, .alignment, .font, .indentation, .remindMe, .dateTime, .actions
        ]
        return rootSubmenus + leafMenus.flatMap { entriesFor($0) }
    }
}

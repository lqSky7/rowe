import AppKit
import SwiftUI
import RoweCore

struct BlockRowView: View {
    @Environment(\.colorScheme) private var effectiveColorScheme
    @Bindable var store: WorkspaceStore
    let document: RoweDocument
    let block: Block
    let listNumberIndex: Int
    var onOpenSlashMenu: (_ blockId: String, _ caretWindowRect: CGRect?) -> Void

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var collectionSearch = ""
    @State private var editingCellCoord: (row: Int, col: Int)?

    private var effectiveFontFamily: FontFamily {
        block.fontOverride ?? document.style.fontFamily
    }

    private var isBlockSelected: Bool {
        store.selectedBlockIds.contains(block.id)
    }

    private var isActiveBlock: Bool {
        store.activeBlockId == block.id
    }

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                // Drag / selection / context handle aligned to the first line of the block
                blockHandle
                    .padding(.top, handleTopPadding)

                blockContentBody
                    .frame(maxWidth: .infinity, alignment: blockFrameAlignment)
            }
            .padding(.leading, CGFloat(block.indentLevel) * 24)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isBlockSelected
                            ? Color.accentColor.opacity(0.085)
                            : (isActiveBlock ? Color.primary.opacity(0.025) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isBlockSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1.0)
                    )
                    .overlay(alignment: .leading) {
                        if isBlockSelected {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 2.5)
                                .padding(.vertical, 4)
                                .padding(.leading, 1)
                                .transition(.opacity)
                        }
                    }
                    .animation(CraftTheme.hoverEase(reduceMotion: reduceMotion), value: isBlockSelected)
                    .animation(CraftTheme.hoverEase(reduceMotion: reduceMotion), value: isActiveBlock)
            }
            .overlay(alignment: .bottom) {
                if isDropTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2.5)
                        .padding(.leading, CGFloat(block.indentLevel) * 24 + 26)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(CraftTheme.hoverEase(reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, raw.hasPrefix("block:") else { return false }
                let sourceId = String(raw.dropFirst("block:".count))
                guard sourceId != block.id else { return false }
                HapticsManager.shared.boundarySnap()
                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                    store.reorderBlock(in: document.id, sourceId: sourceId, targetId: block.id, placeAfter: true)
                }
                return true
            } isTargeted: { targeted in
                withAnimation(CraftTheme.hoverEase(reduceMotion: reduceMotion)) {
                    isDropTargeted = targeted
                }
            }

            // Legacy nested subblocks (if any exist)
            if !block.subblocks.isEmpty && (block.listStyle != .toggle || block.isToggleExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(block.subblocks.enumerated()), id: \.element.id) { idx, child in
                        BlockRowView(
                            store: store,
                            document: document,
                            block: child,
                            listNumberIndex: idx + 1,
                            onOpenSlashMenu: onOpenSlashMenu
                        )
                    }
                }
                .padding(.leading, 24)
                .transition(.roweUnblur)
            }
        }
    }

    private var handleTopPadding: CGFloat {
        if block.kind == .line { return 6 }
        switch block.textStyle {
        case .title: return 5
        case .subtitle: return 4
        case .heading: return 3
        default: return 1
        }
    }

    private var blockHandle: some View {
        Image(systemName: "circle.grid.2x3.fill")
            .font(.system(size: 10.5))
            .foregroundStyle(isBlockSelected ? Color.accentColor : Color.primary.opacity(0.65))
            .opacity(isHovered || isBlockSelected ? 0.95 : (isActiveBlock ? 0.32 : 0.0))
            .scaleEffect(isHovered || isBlockSelected ? 1.0 : 0.92)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isBlockSelected
                            ? Color.accentColor.opacity(0.18)
                            : (isHovered ? Color.primary.opacity(0.09) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
            .draggable("block:\(block.id)") {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(block.content.isEmpty ? "Block" : String(block.content.prefix(36)))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .onTapGesture {
                HapticsManager.shared.tap()
                let flags = NSEvent.modifierFlags
                NSApp.keyWindow?.makeFirstResponder(nil)
                if flags.contains(.shift) {
                    store.extendBlockSelection(in: document.id, to: block.id)
                } else if flags.contains(.command) {
                    store.toggleBlockSelection(block.id)
                } else {
                    store.selectSingleBlock(block.id)
                }
            }
            .contextMenu {
                Button("Open Command Menu (/)") { onOpenSlashMenu(block.id, nil) }
                Button("Duplicate") { store.duplicateBlock(in: document.id, blockId: block.id) }
                Button("Move Up") { store.moveBlock(in: document.id, blockId: block.id, offset: -1) }
                Button("Move Down") { store.moveBlock(in: document.id, blockId: block.id, offset: 1) }
                Divider()
                Button("Delete Block", role: .destructive) {
                    HapticsManager.shared.destructive()
                    store.deleteBlock(in: document.id, blockId: block.id)
                }
            }
            .help("Click to select · Drag to reorder · Right-click for options")
    }

    private var blockFrameAlignment: Alignment {
        switch block.alignment {
        case .leading, .justified: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    @ViewBuilder
    private var blockContentBody: some View {
        switch block.kind {
        case .line:
            separatorView
        case .code:
            codeBlockView
        case .table:
            tableBlockView
        case .objectList:
            collectionBlockView
        case .url:
            urlBlockView
        default:
            textBlockView
        }
    }

    // MARK: - Native AppKit Text / Todo / Toggle / Card Block

    private var pageInkColor: Color {
        if let hex = document.style.safeTextColorHex {
            return Color(hex: hex)
        }
        return .primary
    }

    private var resolvedNSColor: NSColor {
        if block.color != .primary {
            return NSColor(hex: block.color.hex)
        }
        if let hex = document.style.safeTextColorHex {
            return NSColor(hex: hex)
        }
        return NSColor.labelColor
    }

    private var textBlockView: some View {
        let taskState = block.task?.state ?? .pending
        let isCompletedTask = block.listStyle == .todo && taskState != .pending
        let shouldStrike = isCompletedTask && store.settings.completedTaskStyle == .strikethrough

        return HStack(alignment: .top, spacing: 8) {
            listPrefixView

            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    if block.content.isEmpty && isActiveBlock && block.textStyle == .body && block.listStyle == .none {
                        Text("Type '/' for commands…")
                            .font(CraftTheme.font(for: .body, family: effectiveFontFamily))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 3)
                            .allowsHitTesting(false)
                    } else if block.content.isEmpty && block.textStyle != .body {
                        Text(block.textStyle.displayName)
                            .font(CraftTheme.font(for: block.textStyle, family: effectiveFontFamily, isBold: block.isBold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 3)
                            .allowsHitTesting(false)
                    }

                    RoweBlockTextView(
                        block: block,
                        fontFamily: effectiveFontFamily,
                        textColor: resolvedNSColor,
                        isStruckCompletedTask: shouldStrike,
                        isActiveBlock: isActiveBlock,
                        caretRequest: store.caretRequest,
                        onContentChange: { newText, newRuns, caretOffset in
                            store.activeCaretUTF16Offset = caretOffset
                            store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { blk in
                                blk.content = newText
                                blk.runs = newRuns
                            }
                        },
                        onSelectionRangeChange: { offset, length in
                            store.activeCaretUTF16Offset = offset
                            store.activeSelectionLength = length
                        },
                        onFocusGained: {
                            store.activeBlockId = block.id
                            store.selectedBlockIds.removeAll()
                            store.editorSelectionMode = .inlineSelection
                        },
                        onReturnSplit: { utf16Offset in
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                store.splitBlock(in: document.id, blockId: block.id, atUTF16Offset: utf16Offset)
                            }
                        },
                        onCmdReturn: {
                            if block.listStyle == .todo {
                                let next: TaskCompletionState = (block.task?.state ?? .pending) == .pending ? .completed : .pending
                                if next == .completed { HapticsManager.shared.taskComplete() } else { HapticsManager.shared.tap() }
                                store.setTaskState(docId: document.id, blockId: block.id, state: next)
                            } else if block.listStyle == .toggle {
                                HapticsManager.shared.toggle()
                                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                    store.updateBlock(in: document.id, blockId: block.id) { $0.isToggleExpanded.toggle() }
                                }
                            }
                        },
                        onBackspaceAtStart: {
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                store.backspaceAtStart(in: document.id, blockId: block.id)
                            }
                        },
                        onForwardDeleteAtEnd: {
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                store.forwardDeleteAtEnd(in: document.id, blockId: block.id)
                            }
                        },
                        onIndent: { delta in
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                store.indentBlocks(in: document.id, blockIds: [block.id], delta: delta)
                            }
                        },
                        onMoveVertical: { direction, desiredX, extendSelection in
                            store.focusAdjacentBlock(
                                in: document.id,
                                from: block.id,
                                direction: direction,
                                desiredX: desiredX,
                                extendSelection: extendSelection
                            )
                        },
                        onEscalateSelectAll: {
                            HapticsManager.shared.tap()
                            store.selectAllBlocks(in: document.id)
                        },
                        onEscapeToBlockSelection: {
                            HapticsManager.shared.tap()
                            store.selectSingleBlock(block.id)
                        },
                        onOpenSlashMenu: { caretWindowRect in
                            onOpenSlashMenu(block.id, caretWindowRect)
                        },
                        onApplyPrefixTransform: { transform in
                            applyPrefixTransform(transform)
                        },
                        onPasteMultiline: { offset, text in
                            store.pasteMultilineText(in: document.id, blockId: block.id, atUTF16Offset: offset, text: text)
                        }
                    )
                }

                let formulas = extractInlineFormulas(from: block.content)
                if !formulas.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(formulas.enumerated()), id: \.offset) { _, latex in
                            HStack(spacing: 8) {
                                Image(systemName: "function")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(pageInkColor.opacity(0.45))
                                ScrollView(.horizontal, showsIndicators: false) {
                                    RoweMathView(latex: latex, fontSize: 15.5, inkColor: pageInkColor)
                                        .padding(.vertical, 2)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(pageInkColor.opacity(0.055))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(pageInkColor.opacity(0.09), lineWidth: 0.75)
                                    )
                            )
                            .onTapGesture {
                                store.enterInlineEditing(blockId: block.id, utf16Offset: block.content.utf16.count)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .transition(.roweUnblur)
                }
            }
        }
        .padding(.leading, block.decoration == .focus ? 12 : (block.decoration == .block ? 12 : 0))
        .padding(.vertical, block.decoration == .block || block.textStyle == .pageCard ? 10 : 2)
        .padding(.trailing, block.decoration == .block || block.textStyle == .pageCard ? 12 : 0)
        .background {
            if block.decoration == .block || block.textStyle == .pageCard {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
        }
        .overlay(alignment: .leading) {
            if block.decoration == .focus {
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 3.5)
                    .padding(.vertical, 2)
            }
        }
        .animation(CraftTheme.microSpring(reduceMotion: reduceMotion), value: block.decoration)
        .animation(CraftTheme.microSpring(reduceMotion: reduceMotion), value: block.textStyle)
    }

    private func applyPrefixTransform(_ transform: RoweBlockTextView.BlockPrefixTransform) {
        HapticsManager.shared.tap()
        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
            switch transform {
            case .textStyle(let style):
                store.updateBlock(in: document.id, blockId: block.id) { $0.textStyle = style }
            case .listStyle(let style, let checked, let number):
                store.updateBlock(in: document.id, blockId: block.id) { blk in
                    blk.listStyle = style
                    blk.userDefinedListNumber = number
                    if style == .todo {
                        blk.task = TaskMetadata(state: checked ? .completed : .pending)
                    }
                }
            case .decoration(let dec):
                store.updateBlock(in: document.id, blockId: block.id) { $0.decoration = dec }
            case .separator:
                store.insertOrUpdateSeparator(in: document.id, after: block.id, style: document.style.separatorStyle)
            case .codeBlock:
                let code = Block(documentId: document.id, kind: .code, content: "", codeLanguage: "swift")
                _ = store.insertStructuredBlock(in: document.id, after: block.id, block: code, focusTrailingBody: false)
            }
        }
    }

    @ViewBuilder
    private var listPrefixView: some View {
        switch block.listStyle {
        case .none:
            EmptyView()
        case .bullet:
            Circle()
                .fill(Color.primary.opacity(0.65))
                .frame(width: 5.5, height: 5.5)
                .padding(.top, 9.5)
        case .numbered:
            Text("\(listNumberIndex).")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 20, alignment: .trailing)
                .padding(.top, 2)
        case .todo:
            TaskCheckboxControl(state: block.task?.state ?? .pending) { newState in
                store.setTaskState(docId: document.id, blockId: block.id, state: newState)
            }
            .padding(.top, 1.5)
        case .toggle:
            Button {
                HapticsManager.shared.toggle()
                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                    store.updateBlock(in: document.id, blockId: block.id) { $0.isToggleExpanded.toggle() }
                }
            } label: {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(block.isToggleExpanded ? 90 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.78), value: block.isToggleExpanded)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Selectable Separator, Code, URL

    private var separatorInkColor: Color {
        pageInkColor
    }

    private var separatorView: some View {
        let effectiveStyle: SeparatorStyle = (block.separatorStyle == .regular && (document.style.separatorStyle == .washi || document.style.separatorStyle == .doodle))
            ? document.style.separatorStyle
            : block.separatorStyle
        let ink = separatorInkColor

        return Group {
            switch effectiveStyle {
            case .light:
                Rectangle().fill(ink.opacity(0.16)).frame(height: 1)
            case .regular:
                Rectangle().fill(ink.opacity(0.28)).frame(height: 1.5)
            case .strong:
                Rectangle().fill(ink.opacity(0.52)).frame(height: 2.5)
            case .dotted:
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(ink.opacity(0.45)).frame(width: 4, height: 4)
                    }
                    Spacer()
                }
            case .wave:
                Text("〰〰〰〰〰")
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            case .doodle:
                DoodleSeparatorView(color: ink)
            case .washi:
                WashiTapeSeparatorView(
                    patternId: document.style.washiPatternId ?? "peachy_peach",
                    customImageBase64: document.style.customWashiBase64,
                    height: 24
                )
            case .pageBreak:
                HStack(spacing: 8) {
                    Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
                    Text("PAGE BREAK")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.45))
                    Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticsManager.shared.tap()
            NSApp.keyWindow?.makeFirstResponder(nil)
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) {
                store.extendBlockSelection(in: document.id, to: block.id)
            } else if flags.contains(.command) {
                store.toggleBlockSelection(block.id)
            } else {
                store.selectSingleBlock(block.id)
            }
        }
    }

    private var codeBlockView: some View {
        let isLightPaper = document.style.explicitPaperIsLight ?? (effectiveColorScheme == .light)
        let detectedLang = RoweSyntaxHighlighter.detectLanguage(for: block.content, hint: block.codeLanguage)
        let codeBaseInk: NSColor = isLightPaper ? NSColor(hex: "#2B2F36") : NSColor(hex: "#E6EAF0")

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoweGlassMenuPicker(
                    items: RoweSyntaxHighlighter.supportedLanguages,
                    selection: Binding(
                        get: { block.codeLanguage.isEmpty ? "auto" : block.codeLanguage.lowercased() },
                        set: { lang in
                            store.updateBlock(in: document.id, blockId: block.id) { $0.codeLanguage = lang }
                        }
                    ),
                    titleForItem: { lang in
                        if lang == "auto" {
                            return "Auto (\(detectedLang.capitalized))"
                        }
                        switch lang {
                        case "javascript": return "JavaScript"
                        case "typescript": return "TypeScript"
                        case "json": return "JSON"
                        case "sql": return "SQL"
                        default: return lang.capitalized
                        }
                    }
                )

                Spacer()
                Button {
                    HapticsManager.shared.tap()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(block.content, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(RowePressScaleButtonStyle())
            }
            RoweCodeTextView(
                code: block.content,
                language: block.codeLanguage,
                isLightPaper: isLightPaper,
                baseInkColor: codeBaseInk,
                onCodeChange: { newVal in
                    store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { $0.content = newVal }
                },
                onFocusGained: {
                    store.activeBlockId = block.id
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isLightPaper ? Color.black.opacity(0.045) : Color.white.opacity(0.055))
        )
        .onTapGesture {
            store.activeBlockId = block.id
        }
    }

    private var urlBlockView: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField("https://...", text: Binding(
                get: { block.urlString ?? block.content },
                set: { val in
                    store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) {
                        $0.urlString = val
                        $0.content = val
                    }
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .foregroundStyle(pageInkColor)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .onTapGesture {
            store.selectSingleBlock(block.id)
        }
    }

    // MARK: - Table Block with Live FormulaEngine

    @ViewBuilder
    private var tableBlockView: some View {
        if let table = block.tableData {
            let evaluated = store.evaluatedTables[block.id]

            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(0..<table.cells.count, id: \.self) { rowIdx in
                            HStack(spacing: 0) {
                                ForEach(0..<table.cells[rowIdx].count, id: \.self) { colIdx in
                                    let cell = table.cells[rowIdx][colIdx]
                                    let isHeader = (rowIdx == 0 && table.hasHeaderRow) || (colIdx == 0 && table.hasHeaderColumn)
                                    let isEditing = editingCellCoord?.row == rowIdx && editingCellCoord?.col == colIdx
                                    let evalDisplay = (evaluated != nil && rowIdx < evaluated!.count && colIdx < evaluated![rowIdx].count)
                                        ? evaluated![rowIdx][colIdx].displayText
                                        : cell.rawContent

                                    Group {
                                        if isEditing {
                                            TextField("", text: Binding(
                                                get: { cell.rawContent },
                                                set: { newVal in
                                                    store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { blk in
                                                        blk.tableData?.cells[rowIdx][colIdx].rawContent = newVal
                                                    }
                                                }
                                            ))
                                            .textFieldStyle(.plain)
                                            .onSubmit { editingCellCoord = nil }
                                        } else {
                                            Text(evalDisplay.isEmpty ? " " : evalDisplay)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    HapticsManager.shared.tap()
                                                    store.activeBlockId = block.id
                                                    editingCellCoord = (rowIdx, colIdx)
                                                }
                                        }
                                    }
                                    .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
                                    .foregroundStyle(evalDisplay.hasPrefix("#") ? Color.red : pageInkColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(width: 120, alignment: .leading)
                                    .background(isHeader ? Color.primary.opacity(0.05) : Color.clear)
                                    .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 0.75))
                }

                HStack(spacing: 10) {
                    Button("+ Row") {
                        HapticsManager.shared.tap()
                        store.updateBlock(in: document.id, blockId: block.id) { $0.tableData?.appendRow() }
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                    Button("+ Column") {
                        HapticsManager.shared.tap()
                        store.updateBlock(in: document.id, blockId: block.id) { $0.tableData?.appendColumn() }
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Collection Block (Table / Gallery / Kanban)

    @ViewBuilder
    private var collectionBlockView: some View {
        if let collection = block.collectionData {
            let visibleRows = collection.rows.filter { row in
                guard !collectionSearch.isEmpty else { return true }
                return row.values.values.contains(where: { $0.localizedCaseInsensitiveContains(collectionSearch) })
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(collection.title)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("Filter…", text: $collectionSearch)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 110)
                    }
                    .roweGlassInput(cornerRadius: 14)

                    GlassCircleButton(systemImage: "plus", helpText: "Add Row", size: 28) {
                        store.updateBlock(in: document.id, blockId: block.id) { blk in
                            guard var col = blk.collectionData else { return }
                            var vals: [String: String] = [:]
                            if let firstCol = col.columns.first { vals[firstCol.id] = "New Item" }
                            col.rows.append(CollectionRow(values: vals))
                            blk.collectionData = col
                        }
                    }
                }

                LiquidGlassSegmentedControl(
                    items: CollectionViewMode.allCases,
                    selection: Binding(
                        get: { collection.viewMode },
                        set: { mode in
                            store.updateBlock(in: document.id, blockId: block.id) { $0.collectionData?.viewMode = mode }
                        }
                    ),
                    height: 30,
                    title: \.rawValue
                )
                .frame(width: 240)

                switch collection.viewMode {
                case .table:
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Text("#")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34)
                                ForEach(collection.columns) { col in
                                    HStack(spacing: 4) {
                                        Image(systemName: col.type == .url ? "link" : (col.type == .singleSelect ? "tag" : "textformat"))
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                        Text(col.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: col.width, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.03))
                            .overlay(alignment: .bottom) { Divider().opacity(0.35) }

                            ForEach(Array(visibleRows.enumerated()), id: \.element.id) { idx, row in
                                HStack(spacing: 0) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34)
                                    ForEach(collection.columns) { col in
                                        let value = row.values[col.id] ?? ""
                                        Group {
                                            if col.type == .singleSelect && !value.isEmpty {
                                                Text(value)
                                                    .font(.system(size: 11.5, weight: .medium))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pillTint(for: value)))
                                            } else {
                                                TextField("", text: Binding(
                                                    get: { value },
                                                    set: { updated in
                                                        store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { blk in
                                                            if let rIdx = blk.collectionData?.rows.firstIndex(where: { $0.id == row.id }) {
                                                                blk.collectionData?.rows[rIdx].values[col.id] = updated
                                                            }
                                                        }
                                                    }
                                                ))
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 13))
                                                .foregroundStyle(col.type == .url ? .secondary : .primary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(width: col.width, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 8)
                                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
                    }
                case .gallery:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(visibleRows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(collection.columns.prefix(3)) { col in
                                    let val = row.values[col.id] ?? ""
                                    if col.id == collection.columns.first?.id {
                                        Text(val.isEmpty ? "Untitled" : val)
                                            .font(.system(size: 13.5, weight: .semibold))
                                    } else if !val.isEmpty {
                                        Text(val)
                                            .font(.system(size: 11.5))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(pillTint(for: val)))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                        }
                    }
                case .kanban:
                    let groupCol = collection.columns.first(where: { $0.type == .singleSelect }) ?? collection.columns.first
                    let groups = Array(Set(visibleRows.compactMap { row in groupCol.flatMap { row.values[$0.id] } })).sorted()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(groups, id: \.self) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.isEmpty ? "Unassigned" : group)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(pillTint(for: group)))

                                    ForEach(visibleRows.filter { ($0.values[groupCol?.id ?? ""] ?? "") == group }) { row in
                                        Text(row.values[collection.columns.first?.id ?? ""] ?? "Item")
                                            .font(.system(size: 13, weight: .medium))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                    }
                                }
                                .padding(10)
                                .frame(width: 210, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func extractInlineFormulas(from text: String) -> [String] {
        var results: [String] = []
        let pattern = #"\$\$([\s\S]+?)\$\$|(?<!\$)\$([^\$\n]+?)\$(?!\$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r1 = match.range(at: 1)
            let r2 = match.range(at: 2)
            let r = (r1.location != NSNotFound) ? r1 : r2
            if r.location != NSNotFound {
                let inner = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty { results.append(inner) }
            }
        }
        return results
    }

    private func pillTint(for value: String) -> Color {
        switch value.lowercased() {
        case "usa", "active": Color.green.opacity(0.18)
        case "canada", "review": Color.cyan.opacity(0.18)
        case "europe", "fresh grad": Color.mint.opacity(0.22)
        case "india", "intern": Color.yellow.opacity(0.28)
        case "indonesia": Color.purple.opacity(0.16)
        case "malaysia", "planned": Color.blue.opacity(0.16)
        default: Color.primary.opacity(0.08)
        }
    }
}

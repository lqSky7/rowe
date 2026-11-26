import SwiftUI
import UIKit
import RoweCore

struct IOSDocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var appColorScheme
    @Bindable var store: WorkspaceStore
    let document: RoweDocument

    @State private var isBlockSelectionMode = false
    @State private var showStyleSheet = false
    @State private var showInsertSheet = false
    @State private var showTOCSheet = false
    @State private var showColorSheet = false
    @FocusState private var focusedBlockId: String?
    @FocusState private var isTitleFocused: Bool

    private var visibleBlocks: [Block] {
        store.visibleBlocks(in: document.id)
    }

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    private var paperColorScheme: ColorScheme {
        guard let isLight = document.style.explicitPaperIsLight else { return appColorScheme }
        return isLight ? .light : .dark
    }

    private var pageSurfaceColor: Color {
        if let hex = document.style.documentColorHex { return Color(hex: hex) }
        return Color(uiColor: .systemBackground)
    }

    private var pageInkColor: Color {
        if let hex = document.style.safeTextColorHex { return Color(hex: hex) }
        return .primary
    }

    private var activeBlock: Block? {
        let id = store.selectedBlockIds.first ?? store.activeBlockId ?? visibleBlocks.first?.id
        return visibleBlocks.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            documentBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topEditorBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if document.isLocked && !store.isDocumentUnlocked(document.id) {
                    lockedCoverView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    editorScrollBody
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: store.isDocumentUnlocked(document.id))

            // Bottom Floating Bar (Block Format Sheet when in block selection mode per IMG_5046, else normal pill per IMG_5045)
            if store.isDocumentUnlocked(document.id) {
                if isBlockSelectionMode {
                    blockSelectionFormatSheet
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    normalBottomBar
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: isBlockSelectionMode)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        Button {
                            IOSHaptics.shared.tap()
                            showInsertSheet = true
                        } label: { Image(systemName: "plus.circle.fill") }

                        Button {
                            IOSHaptics.shared.tap()
                            store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "bold")
                        } label: { Text("B").fontWeight(.bold) }

                        Button {
                            IOSHaptics.shared.tap()
                            store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "italic")
                        } label: { Text("I").italic() }

                        Button {
                            IOSHaptics.shared.tap()
                            updateTargetBlocks {
                                $0.listStyle = ($0.listStyle == .todo) ? .none : .todo
                                if $0.listStyle == .todo && $0.task == nil { $0.task = TaskMetadata() }
                            }
                        } label: { Image(systemName: "checkmark.square") }

                        Button {
                            IOSHaptics.shared.tap()
                            updateTargetBlocks { $0.indentLevel = max(0, $0.indentLevel - 1) }
                        } label: { Image(systemName: "decrease.indent") }

                        Button {
                            IOSHaptics.shared.tap()
                            updateTargetBlocks { $0.indentLevel = min(8, $0.indentLevel + 1) }
                        } label: { Image(systemName: "increase.indent") }

                        Button {
                            IOSHaptics.shared.tap()
                            store.undo(in: document.id)
                        } label: { Image(systemName: "arrow.uturn.backward") }

                        Button {
                            IOSHaptics.shared.tap()
                            store.redo(in: document.id)
                        } label: { Image(systemName: "arrow.uturn.forward") }
                    }
                    .font(.system(size: 15))
                }
                Spacer()
                Button {
                    IOSHaptics.shared.tap()
                    focusedBlockId = nil
                    isTitleFocused = false
                    IOSKeyboard.dismiss()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showStyleSheet) {
            IOSStyleGallerySheet(store: store, document: document)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showInsertSheet) {
            insertBlockSheet
                .presentationDetents([.medium])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showTOCSheet) {
            tocSheet
                .presentationDetents([.medium])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showColorSheet) {
            colorPickerSheet
                .presentationDetents([.height(230)])
                .presentationCornerRadius(28)
        }
    }

    // MARK: - Top Bar (IMG_5045)

    private var topEditorBar: some View {
        HStack(spacing: 10) {
            if isBlockSelectionMode {
                IOSGlassPillButton("Done", systemImage: "checkmark") {
                    exitBlockSelection()
                }
                Text("\(store.selectedBlockIds.count) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else {
                IOSGlassCircleButton(systemImage: "chevron.left", size: 40, iconSize: 16) {
                    IOSKeyboard.dismiss()
                    dismiss()
                }
            }

            Spacer()

            HStack(spacing: 12) {
                // Animated Lock / Unlock Toggle
                Button {
                    IOSHaptics.shared.tap()
                    IOSKeyboard.dismiss()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                        store.requestToggleLock(for: document.id)
                    }
                } label: {
                    let isLocked = document.isLocked
                    let isUnlocked = store.isDocumentUnlocked(document.id)
                    Image(systemName: isLocked ? (isUnlocked ? "lock.open.fill" : "lock.fill") : "lock.open")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isLocked ? (isUnlocked ? .green : .orange) : .primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(RowePressScaleStyle())

                ShareLink(item: document.displayTitle + "\n\n" + document.blocks.map(\.content).joined(separator: "\n")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }

                Menu {
                    Button("Document Style", systemImage: "paintbrush") { showStyleSheet = true }
                    Button("Table of Contents", systemImage: "list.bullet.indent") { showTOCSheet = true }
                    Button("Select Blocks", systemImage: "checkmark.circle") {
                        IOSKeyboard.dismiss()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                            isBlockSelectionMode = true
                            if let first = visibleBlocks.first { store.selectSingleBlock(first.id) }
                        }
                    }
                    Divider()
                    Button(document.isStarred ? "Unstar" : "Star Document", systemImage: document.isStarred ? "star.slash" : "star") {
                        store.toggleStarDocument(docId: document.id)
                    }
                    if document.isLocked && store.isDocumentUnlocked(document.id) {
                        Button("Remove Lock Permanently", systemImage: "lock.slash") {
                            store.removeLockPermanently(docId: document.id)
                        }
                    }
                    Button("Move to Trash", systemImage: "trash", role: .destructive) {
                        IOSHaptics.shared.destructive()
                        store.moveDocumentToTrash(docId: document.id)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .roweIOSGlassCapsule(interactive: true)
        }
    }

    // MARK: - Scrollable Paper Canvas (Multi-Card Page Breaks + Swipe-Left Block Selection)

    private var editorScrollBody: some View {
        let segments = splitIntoPageSegments(visibleBlocks)
        let hasCardSurface = document.style.backdropKind != .none || document.style.coverImageName != nil || segments.count > 1

        return ScrollView {
            VStack(spacing: 18) {
                ForEach(Array(segments.enumerated()), id: \.offset) { segIdx, segment in
                    if let breakId = segment.leadingBreakId {
                        Button {
                            IOSHaptics.shared.tap()
                            withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                                store.deleteBlock(in: document.id, blockId: breakId)
                            }
                        } label: {
                            Label("Page Break · Tap to Remove", systemImage: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .roweIOSGlassCapsule(interactive: true)
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if segIdx == 0 {
                            TextField(
                                "Page Title",
                                text: Binding(
                                    get: { document.title },
                                    set: { store.updateDocumentTitle(docId: document.id, title: $0) }
                                ),
                                axis: .vertical
                            )
                            .focused($isTitleFocused)
                            .font(IOSTheme.font(for: .title, family: document.style.fontFamily, isBold: true))
                            .foregroundStyle(pageInkColor)
                            .padding(.bottom, 6)
                        }

                        ForEach(segment.blocks) { block in
                            iosBlockRow(block)
                        }

                        if segIdx == segments.count - 1 {
                            Color.clear
                                .frame(height: 160)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isBlockSelectionMode {
                                        exitBlockSelection()
                                    } else if focusedBlockId != nil || isTitleFocused {
                                        focusedBlockId = nil
                                        isTitleFocused = false
                                        IOSKeyboard.dismiss()
                                    } else {
                                        let b = store.insertBlock(in: document.id, after: visibleBlocks.last?.id)
                                        focusedBlockId = b.id
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, hasCardSurface ? 20 : 18)
                    .padding(.vertical, hasCardSurface ? 22 : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if hasCardSurface {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(pageSurfaceColor)
                                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                        }
                    }
                    .environment(\.colorScheme, paperColorScheme)
                }
            }
            .padding(.horizontal, hasCardSurface ? 12 : 0)
            .padding(.top, 8)
            .padding(.bottom, 180)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Block Row with Swipe-Left to Select + Trailing Checkmark (IMG_5046)

    private func iosBlockRow(_ block: Block) -> some View {
        let isSelected = store.selectedBlockIds.contains(block.id)
        let ink = block.color == .primary ? pageInkColor : Color(hex: block.color.hex)

        return HStack(alignment: .center, spacing: 10) {
            Group {
                if block.kind == .line {
                    iosSeparatorView(for: block)
                } else if block.kind == .code {
                    TextEditor(text: Binding(
                        get: { block.content },
                        set: { val in store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { $0.content = val } }
                    ))
                    .font(.system(size: 13.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pageInkColor.opacity(0.06)))
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        if block.listStyle == .todo {
                            let done = (block.task?.state ?? .pending) != .pending
                            Button {
                                IOSHaptics.shared.taskComplete()
                                store.setTaskState(docId: document.id, blockId: block.id, state: done ? .pending : .completed)
                            } label: {
                                Image(systemName: done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18))
                                    .foregroundStyle(done ? Color.accentColor : pageInkColor.opacity(0.45))
                                    .padding(.top, 2)
                            }
                            .buttonStyle(.plain)
                        } else if block.listStyle == .bullet {
                            Circle()
                                .fill(pageInkColor.opacity(0.65))
                                .frame(width: 6, height: 6)
                                .padding(.top, 9)
                        } else if block.listStyle == .toggle {
                            Button {
                                IOSHaptics.shared.toggle()
                                withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                                    store.updateBlock(in: document.id, blockId: block.id) { $0.isToggleExpanded.toggle() }
                                }
                            } label: {
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(pageInkColor.opacity(0.55))
                                    .rotationEffect(.degrees(block.isToggleExpanded ? 90 : 0))
                                    .padding(.top, 6)
                            }
                            .buttonStyle(.plain)
                        }

                        TextField(
                            block.textStyle == .body ? "Write something…" : block.textStyle.displayName,
                            text: Binding(
                                get: { block.content },
                                set: { val in
                                    store.activeBlockId = block.id
                                    store.updateBlock(in: document.id, blockId: block.id, coalesceUndo: true) { $0.content = val }
                                }
                            ),
                            axis: .vertical
                        )
                        .focused($focusedBlockId, equals: block.id)
                        .font(IOSTheme.font(for: block.textStyle, family: block.fontOverride ?? document.style.fontFamily, isBold: block.isBold))
                        .italic(block.isItalic)
                        .strikethrough(block.isStrikethrough || (block.listStyle == .todo && (block.task?.state ?? .pending) != .pending))
                        .foregroundStyle(ink)
                        .disabled(isBlockSelectionMode)
                        .onTapGesture {
                            if isBlockSelectionMode {
                                toggleSelection(for: block.id)
                            } else {
                                store.activeBlockId = block.id
                            }
                        }
                    }
                    .padding(.leading, block.decoration == .focus ? 12 : (block.decoration == .block ? 12 : 0))
                    .padding(.vertical, block.decoration == .block || block.textStyle == .pageCard ? 10 : 3)
                    .padding(.trailing, block.decoration == .block || block.textStyle == .pageCard ? 10 : 0)
                    .background {
                        if block.decoration == .block || block.textStyle == .pageCard {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(pageInkColor.opacity(0.06))
                        }
                    }
                    .overlay(alignment: .leading) {
                        if block.decoration == .focus {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 3.5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing selection checkmark circle (slides in when swiping left, matching IMG_5046!)
            if isBlockSelectionMode {
                Button {
                    toggleSelection(for: block.id)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : pageInkColor.opacity(0.28), lineWidth: 1.8)
                            .frame(width: 24, height: 24)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .buttonStyle(RowePressScaleStyle())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.leading, CGFloat(block.indentLevel) * 18)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isBlockSelectionMode {
                toggleSelection(for: block.id)
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { val in
                    // Swipe left opens block selection & selects this block!
                    if val.translation.width < -38 && abs(val.translation.width) > abs(val.translation.height) * 1.4 {
                        IOSHaptics.shared.snap()
                        IOSKeyboard.dismiss()
                        focusedBlockId = nil
                        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                            isBlockSelectionMode = true
                            store.selectSingleBlock(block.id)
                        }
                    } else if isBlockSelectionMode && val.translation.width > 48 && abs(val.translation.width) > abs(val.translation.height) * 1.4 {
                        exitBlockSelection()
                    }
                }
        )
    }

    @ViewBuilder
    private func iosSeparatorView(for block: Block) -> some View {
        let effective: SeparatorStyle = (block.separatorStyle == .regular && (document.style.separatorStyle == .washi || document.style.separatorStyle == .doodle))
            ? document.style.separatorStyle : block.separatorStyle
        Group {
            switch effective {
            case .light: Rectangle().fill(pageInkColor.opacity(0.18)).frame(height: 1)
            case .regular: Rectangle().fill(pageInkColor.opacity(0.32)).frame(height: 1.5)
            case .strong: Rectangle().fill(pageInkColor.opacity(0.55)).frame(height: 2.5)
            case .dotted:
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(pageInkColor.opacity(0.45)).frame(width: 4, height: 4) }
                    Spacer()
                }
            case .doodle: IOSDoodleSeparatorView(color: pageInkColor)
            case .washi: IOSWashiSeparatorView(patternId: document.style.washiPatternId ?? "peachy_peach", height: 22)
            default: Rectangle().fill(pageInkColor.opacity(0.28)).frame(height: 1.5)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Bottom Bars (IMG_5045 & IMG_5046)

    private var normalBottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 18) {
                Button {
                    IOSHaptics.shared.tap()
                    IOSKeyboard.dismiss()
                    showStyleSheet = true
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 17, weight: .medium))
                }

                Button {
                    IOSHaptics.shared.tap()
                    IOSKeyboard.dismiss()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                        isBlockSelectionMode = true
                        if let id = store.activeBlockId ?? visibleBlocks.first?.id {
                            store.selectSingleBlock(id)
                        }
                    }
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 17, weight: .medium))
                }

                Button {
                    IOSHaptics.shared.tap()
                    IOSKeyboard.dismiss()
                    showTOCSheet = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .roweIOSGlassCapsule(interactive: true)

            Spacer()

            IOSGlassCircleButton(systemImage: "plus", size: 50, iconSize: 20) {
                IOSKeyboard.dismiss()
                showInsertSheet = true
            }
        }
    }

    /// Floating Liquid Glass Block Format Card matching IMG_5046!
    private var blockSelectionFormatSheet: some View {
        VStack(spacing: 10) {
            // Row 1: Heading | Body | Page | More...
            HStack(spacing: 8) {
                formatStyleBtn("Heading", active: activeBlock?.textStyle == .heading) {
                    updateTargetBlocks { $0.textStyle = .heading }
                }
                formatStyleBtn("Body", active: activeBlock?.textStyle == .body) {
                    updateTargetBlocks { $0.textStyle = .body }
                }
                formatStyleBtn("Page", icon: "doc.plaintext", active: activeBlock?.textStyle == .pageRegular) {
                    updateTargetBlocks { $0.textStyle = .pageRegular }
                }
                Menu {
                    Button("Title") { updateTargetBlocks { $0.textStyle = .title } }
                    Button("Subtitle") { updateTargetBlocks { $0.textStyle = .subtitle } }
                    Button("Strong") { updateTargetBlocks { $0.textStyle = .strong } }
                    Button("Caption") { updateTargetBlocks { $0.textStyle = .caption } }
                    Button("Card") { updateTargetBlocks { $0.textStyle = .pageCard } }
                } label: {
                    Text("More…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
            }

            // Row 2: Todo | Toggle | Bullet | Numbered | Outdent | Indent
            HStack(spacing: 8) {
                formatIconTile("checkmark.square", active: activeBlock?.listStyle == .todo) {
                    updateTargetBlocks {
                        $0.listStyle = ($0.listStyle == .todo) ? .none : .todo
                        if $0.listStyle == .todo && $0.task == nil { $0.task = TaskMetadata() }
                    }
                }
                formatIconTile("arrowtriangle.right.fill", active: activeBlock?.listStyle == .toggle) {
                    updateTargetBlocks { $0.listStyle = ($0.listStyle == .toggle) ? .none : .toggle }
                }
                formatIconTile("list.bullet", active: activeBlock?.listStyle == .bullet) {
                    updateTargetBlocks { $0.listStyle = ($0.listStyle == .bullet) ? .none : .bullet }
                }
                formatIconTile("list.number", active: activeBlock?.listStyle == .numbered) {
                    updateTargetBlocks { $0.listStyle = ($0.listStyle == .numbered) ? .none : .numbered }
                }
                formatIconTile("decrease.indent", active: false) {
                    updateTargetBlocks { $0.indentLevel = max(0, $0.indentLevel - 1) }
                }
                formatIconTile("increase.indent", active: false) {
                    updateTargetBlocks { $0.indentLevel = min(8, $0.indentLevel + 1) }
                }
            }

            // Row 3: Focus | Block | Color Wheel | (...)
            HStack(spacing: 10) {
                Button {
                    IOSHaptics.shared.tap()
                    updateTargetBlocks { $0.decoration = ($0.decoration == .focus) ? .none : .focus }
                } label: {
                    HStack(spacing: 6) {
                        Capsule().fill(Color.primary).frame(width: 2.5, height: 18)
                        Text("Focus").font(.system(size: 14.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(activeBlock?.decoration == .focus ? 0.18 : 0.08))
                    )
                }
                .buttonStyle(RowePressScaleStyle())

                Button {
                    IOSHaptics.shared.tap()
                    updateTargetBlocks { $0.decoration = ($0.decoration == .block) ? .none : .block }
                } label: {
                    Text("Block")
                        .font(.system(size: 14.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(activeBlock?.decoration == .block ? 0.18 : 0.08))
                        )
                }
                .buttonStyle(RowePressScaleStyle())

                Button {
                    IOSHaptics.shared.tap()
                    showColorSheet = true
                } label: {
                    Circle()
                        .fill(Color(hex: (activeBlock?.color ?? .primary).hex))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                                    lineWidth: 3
                                )
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(RowePressScaleStyle())

                Menu {
                    Button("Move Up", systemImage: "arrow.up") {
                        store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: -1)
                    }
                    Button("Move Down", systemImage: "arrow.down") {
                        store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: 1)
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        store.duplicateBlocks(in: document.id, blockIds: store.selectedBlockIds)
                    }
                    Divider()
                    Button("Delete Selected", systemImage: "trash", role: .destructive) {
                        IOSHaptics.shared.destructive()
                        store.deleteBlocks(in: document.id, blockIds: store.selectedBlockIds)
                        exitBlockSelection()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .padding(14)
        .roweIOSGlassRoundedRect(radius: 26, interactive: true)
    }

    private func formatStyleBtn(_ title: String, icon: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(title).font(.system(size: 14.5, weight: active ? .bold : .medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.16) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(RowePressScaleStyle())
    }

    private func formatIconTile(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(RowePressScaleStyle())
    }

    // MARK: - Zero-Knowledge Locked Note Cover (with GlassGlow Shield)

    private var lockedCoverView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 74, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .glassGlow(
                    GlassGlowPalette(
                        primary: Color(red: 0.72, green: 0.80, blue: 0.88),
                        secondary: Color(red: 0.60, green: 0.69, blue: 0.79),
                        accent: Color(red: 0.82, green: 0.86, blue: 0.90)
                    ),
                    speed: 0.75,
                    glow: 1.0
                )

            Text(document.displayTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(pageInkColor)

            Text("Encrypted on your device with AES-256-GCM. Enter your PIN to unlock.")
                .font(.system(size: 14))
                .foregroundStyle(pageInkColor.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            IOSGlassPillButton("Enter PIN to Unlock", systemImage: "key.fill") {
                store.pinPromptRequest = .unlockDocument(docId: document.id)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Supporting Sheets

    private var insertBlockSheet: some View {
        NavigationStack {
            List {
                Section("Blocks") {
                    insertRow("Heading", icon: "textformat.size.larger") {
                        _ = store.insertBlock(in: document.id, after: store.activeBlockId, block: Block(documentId: document.id, content: "", textStyle: .heading))
                    }
                    insertRow("Task Checkbox", icon: "checkmark.square") {
                        _ = store.insertBlock(in: document.id, after: store.activeBlockId, block: Block(documentId: document.id, content: "", listStyle: .todo, task: TaskMetadata()))
                    }
                    insertRow("Bullet Item", icon: "list.bullet") {
                        _ = store.insertBlock(in: document.id, after: store.activeBlockId, block: Block(documentId: document.id, content: "", listStyle: .bullet))
                    }
                    insertRow("Code Block", icon: "chevron.left.forwardslash.chevron.right") {
                        _ = store.insertStructuredBlock(in: document.id, after: store.activeBlockId, block: Block(documentId: document.id, kind: .code, content: "", codeLanguage: "swift"), focusTrailingBody: false)
                    }
                }
                Section("Separators & Pages") {
                    insertRow("Separator", icon: "minus") {
                        store.insertOrUpdateSeparator(in: document.id, after: store.activeBlockId, style: document.style.separatorStyle)
                    }
                    insertRow("Page Break", icon: "rectangle.split.1x2") {
                        store.insertOrUpdateSeparator(in: document.id, after: store.activeBlockId, style: .pageBreak)
                    }
                }
            }
            .navigationTitle("Insert")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func insertRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
            showInsertSheet = false
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private var tocSheet: some View {
        let headings = document.blocks.filter(\.isHeadingForTOC)
        return NavigationStack {
            List {
                if headings.isEmpty {
                    ContentUnavailableView("No Headings Yet", systemImage: "list.bullet.indent")
                } else {
                    ForEach(headings) { h in
                        Button(h.content.isEmpty ? "Untitled Section" : h.content) {
                            focusedBlockId = h.id
                            showTOCSheet = false
                        }
                    }
                }
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var colorPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Block Color").font(.headline).padding(.top, 14)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                ForEach(BlockColor.allCases, id: \.self) { color in
                    Button {
                        IOSHaptics.shared.tap()
                        store.applyColorToSelectionOrBlocks(in: document.id, color: color)
                        showColorSheet = false
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func toggleSelection(for blockId: String) {
        IOSHaptics.shared.toggle()
        withAnimation(IOSTheme.microSpring(reduceMotion: reduceMotion)) {
            store.toggleBlockSelection(blockId)
            if store.selectedBlockIds.isEmpty {
                isBlockSelectionMode = false
            }
        }
    }

    private func exitBlockSelection() {
        IOSHaptics.shared.tap()
        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
            isBlockSelectionMode = false
            store.clearBlockSelection()
        }
    }

    private func updateTargetBlocks(_ mutate: (inout Block) -> Void) {
        let targets: Set<String> = store.selectedBlockIds.isEmpty
            ? ((store.activeBlockId ?? visibleBlocks.first?.id).map { [$0] } ?? [])
            : store.selectedBlockIds
        guard !targets.isEmpty else { return }
        store.mutateBlocks(in: document.id) { blocks in
            for i in blocks.indices where targets.contains(blocks[i].id) {
                mutate(&blocks[i])
            }
        }
    }

    private struct PageSegment {
        let leadingBreakId: String?
        let blocks: [Block]
    }

    private func splitIntoPageSegments(_ blocks: [Block]) -> [PageSegment] {
        var segs: [PageSegment] = []
        var breakId: String? = nil
        var current: [Block] = []
        for b in blocks {
            if b.kind == .line && b.separatorStyle == .pageBreak {
                segs.append(PageSegment(leadingBreakId: breakId, blocks: current))
                breakId = b.id
                current = []
            } else {
                current.append(b)
            }
        }
        segs.append(PageSegment(leadingBreakId: breakId, blocks: current))
        return segs
    }

    @ViewBuilder
    private var documentBackdrop: some View {
        if let cover = document.style.coverImageName {
            IOSCoverArtwork(artworkName: cover)
        } else if document.style.backdropColorsHex.count >= 2 {
            LinearGradient(
                colors: document.style.backdropColorsHex.map(Color.init(hex:)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            pageSurfaceColor
        }
    }
}

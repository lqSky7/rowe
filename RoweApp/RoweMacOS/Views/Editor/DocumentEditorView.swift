import AppKit
import SwiftUI
import RoweCore

struct DocumentEditorView: View {
    @Environment(\.colorScheme) private var appColorScheme
    @Bindable var store: WorkspaceStore
    let document: RoweDocument
    @Binding var inspectorTab: InspectorTab
    @Binding var documentSidebarTab: DocumentSidebarTab
    @Binding var scrollTargetBlockId: String?

    @State private var isSlashMenuOpen = false
    @State private var slashTargetBlockId: String?
    @State private var blockFrames: [String: CGRect] = [:]
    @State private var isSharePopoverOpen = false
    @State private var blockKeyMonitor: Any?
    @State private var blockMarqueeStart: CGPoint? = nil
    @State private var blockMarqueeCurrent: CGPoint? = nil
    @FocusState private var isTitleFocused: Bool

    private var blockMarqueeRect: CGRect? {
        guard let s = blockMarqueeStart, let c = blockMarqueeCurrent else { return nil }
        let w = abs(c.x - s.x), h = abs(c.y - s.y)
        guard w > 6 || h > 6 else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: w, height: h)
    }

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

    private var pageBackgroundColor: Color {
        if let hex = document.style.documentColorHex {
            return Color(hex: hex)
        }
        return Color(nsColor: .textBackgroundColor)
    }

    private var pageTextColor: Color {
        if let hex = document.style.safeTextColorHex {
            return Color(hex: hex)
        }
        return .primary
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { editorGeo in
                ZStack(alignment: .topLeading) {
                    documentBackdrop
                        .frame(width: editorGeo.size.width, height: editorGeo.size.height)

                    VStack(spacing: 0) {
                        floatingEditorHeader
                            .padding(.leading, store.isLeftSidebarVisible ? 18 : 58)
                            .padding(.trailing, 18)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            .animation(CraftTheme.craftSpring(reduceMotion: reduceMotion), value: store.isLeftSidebarVisible)

                        if document.isLocked && !store.isDocumentUnlocked(document.id) {
                            lockedDocumentCover(editorWidth: editorGeo.size.width)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                let pageWidth = min(
                                    max(320, editorGeo.size.width - 56),
                                    document.style.isWidePage ? CraftTheme.widePageWidth : CraftTheme.normalPageWidth
                                )
                                let segments = splitIntoPageSegments(visibleBlocks)
                                let hasCardSurface = document.style.backdropKind != .none || document.style.customBackdropBase64 != nil || segments.count > 1

                                VStack(spacing: 20) {
                                    ForEach(Array(segments.enumerated()), id: \.offset) { segIdx, segment in
                                        if let breakId = segment.leadingBreakId {
                                            HStack {
                                                Spacer()
                                                Button {
                                                    HapticsManager.shared.tap()
                                                    withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                                        store.deleteBlock(in: document.id, blockId: breakId)
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "xmark")
                                                            .font(.system(size: 9, weight: .bold))
                                                        Text("Remove Page Break")
                                                            .font(.system(size: 10.5, weight: .medium))
                                                    }
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 3.5)
                                                }
                                                .buttonStyle(RowePressScaleButtonStyle())
                                                .roweGlassCapsule(interactive: true)
                                                .opacity(0.65)
                                                Spacer()
                                            }
                                            .padding(.vertical, -8)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            if segIdx == 0 {
                                                TextField(
                                                    "Page Title",
                                                    text: Binding(
                                                        get: { document.title },
                                                        set: { store.updateDocumentTitle(docId: document.id, title: $0) }
                                                    ),
                                                    axis: .vertical
                                                )
                                                .textFieldStyle(.plain)
                                                .focused($isTitleFocused)
                                                .font(CraftTheme.font(for: .title, family: document.style.fontFamily, isBold: true))
                                                .foregroundStyle(pageTextColor)
                                                .padding(.leading, 27)
                                                .padding(.bottom, 10)
                                                .onSubmit {
                                                    if let first = visibleBlocks.first {
                                                        store.enterInlineEditing(blockId: first.id, utf16Offset: 0)
                                                    }
                                                }
                                                .onChange(of: isTitleFocused) { _, focused in
                                                    if focused && !store.selectedBlockIds.isEmpty {
                                                        store.clearBlockSelection()
                                                    }
                                                }
                                            }

                                            LazyVStack(alignment: .leading, spacing: 4) {
                                                ForEach(segment.blocks) { block in
                                                    let globalIdx = visibleBlocks.firstIndex(where: { $0.id == block.id }) ?? 0
                                                    BlockRowView(
                                                        store: store,
                                                        document: document,
                                                        block: block,
                                                        listNumberIndex: computeListIndex(in: visibleBlocks, at: globalIdx),
                                                        onOpenSlashMenu: { blockId, _ in
                                                            slashTargetBlockId = blockId
                                                            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                                                isSlashMenuOpen = true
                                                            }
                                                        }
                                                    )
                                                    .id(block.id)
                                                    .transition(.roweUnblur)
                                                    .onGeometryChange(for: CGRect.self) { geo in
                                                        geo.frame(in: .named("editorCanvas"))
                                                    } action: { rect in
                                                        blockFrames[block.id] = rect
                                                    }
                                                }
                                            }

                                            if segIdx == segments.count - 1 {
                                                Color.clear
                                                    .frame(height: segments.count > 1 ? 80 : 180)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        if !store.selectedBlockIds.isEmpty {
                                                            store.clearBlockSelection()
                                                            return
                                                        }
                                                        if let last = visibleBlocks.last, last.content.isEmpty && last.isEditableTextBlock {
                                                            store.enterInlineEditing(blockId: last.id, utf16Offset: 0)
                                                        } else {
                                                            _ = store.insertBlock(in: document.id, after: visibleBlocks.last?.id)
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal, 44)
                                        .padding(.vertical, segIdx == 0 ? 36 : 28)
                                        .frame(width: pageWidth, alignment: .leading)
                                        .background {
                                            if hasCardSurface {
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(pageBackgroundColor)
                                                    .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                                                    .onTapGesture {
                                                        if !store.selectedBlockIds.isEmpty { store.clearBlockSelection() }
                                                    }
                                            }
                                        }
                                        .environment(\.colorScheme, paperColorScheme)
                                    }
                                }
                                .animation(
                                    reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.8),
                                    value: document.style.isWidePage
                                )
                                .padding(.horizontal, 28)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if !store.selectedBlockIds.isEmpty { store.clearBlockSelection() }
                                        }
                                )
                            }
                            .onChange(of: scrollTargetBlockId) { _, target in
                                guard let target else { return }
                                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                    proxy.scrollTo(target, anchor: .center)
                                }
                                store.enterInlineEditing(blockId: target, utf16Offset: 0)
                                scrollTargetBlockId = nil
                            }
                            .onChange(of: store.caretRequest?.id) { _, _ in
                                if let req = store.caretRequest, req.blockId == nil {
                                    isTitleFocused = true
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 12, coordinateSpace: .named("editorCanvas"))
                                .onChanged { value in
                                    let startBlock = blockFrames.first(where: { $0.value.contains(value.startLocation) })?.key
                                    let currentBlock = blockFrames.first(where: { $0.value.contains(value.location) })?.key
                                    let crossedBlocks = (startBlock == nil) || (currentBlock != nil && currentBlock != startBlock)
                                    if blockMarqueeStart == nil && crossedBlocks {
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                        blockMarqueeStart = value.startLocation
                                    }
                                    if blockMarqueeStart != nil {
                                        blockMarqueeCurrent = value.location
                                        if let marquee = blockMarqueeRect {
                                            let hitIds = Set(blockFrames.compactMap { id, rect in
                                                rect.intersects(marquee) ? id : nil
                                            })
                                            if !hitIds.isEmpty {
                                                store.selectedBlockIds = hitIds
                                                store.activeBlockId = visibleBlocks.first(where: { hitIds.contains($0.id) })?.id
                                                store.editorSelectionMode = .blockSelection
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    blockMarqueeStart = nil
                                    blockMarqueeCurrent = nil
                                }
                        )
                        }
                    }
                    .animation(CraftTheme.craftSpring(reduceMotion: reduceMotion), value: store.isDocumentUnlocked(document.id))

                    if let marquee = blockMarqueeRect {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.1)
                            )
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                            .allowsHitTesting(false)
                    }

                    // Bottom floating navigation pill (expands into a large interactive Liquid Glass bar when blocks are selected)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if !store.selectedBlockIds.isEmpty {
                                HStack(spacing: 14) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.accentColor)
                                        Text("\(store.selectedBlockIds.count) Selected")
                                            .font(.system(size: 13.5, weight: .semibold))
                                    }

                                    Divider().frame(height: 24).opacity(0.3)

                                    blockBarAction("Up", icon: "arrow.up") {
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: -1)
                                        }
                                    }
                                    blockBarAction("Down", icon: "arrow.down") {
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: 1)
                                        }
                                    }
                                    blockBarAction("Outdent", icon: "decrease.indent") {
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.indentBlocks(in: document.id, blockIds: store.selectedBlockIds, delta: -1)
                                        }
                                    }
                                    blockBarAction("Indent", icon: "increase.indent") {
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.indentBlocks(in: document.id, blockIds: store.selectedBlockIds, delta: 1)
                                        }
                                    }

                                    Divider().frame(height: 24).opacity(0.3)

                                    blockBarAction("Copy", icon: "doc.on.doc") {
                                        copySelectedBlocksToPasteboard()
                                    }
                                    blockBarAction("Duplicate", icon: "plus.square.on.square") {
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.duplicateBlocks(in: document.id, blockIds: store.selectedBlockIds)
                                        }
                                    }
                                    blockBarAction("Delete", icon: "trash", isDestructive: true) {
                                        HapticsManager.shared.destructive()
                                        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                            store.deleteBlocks(in: document.id, blockIds: store.selectedBlockIds)
                                        }
                                    }

                                    Divider().frame(height: 24).opacity(0.3)

                                    GlassCircleButton(systemImage: "xmark", helpText: "Clear Selection (Esc)", size: 28, iconSize: 11) {
                                        store.clearBlockSelection()
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .roweGlassCapsule(interactive: true)
                                .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
                                .transition(.roweUnblur)
                                .padding(.bottom, 18)
                            } else {
                                HStack(spacing: 12) {
                                    Button {
                                        HapticsManager.shared.tap()
                                        slashTargetBlockId = store.activeBlockId ?? visibleBlocks.last?.id
                                        withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                            isSlashMenuOpen.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(RowePressScaleButtonStyle())
                                    .help("Open Command Menu (/)")

                                    Divider().frame(height: 14).opacity(0.3)

                                    Button {
                                        HapticsManager.shared.tap()
                                        withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                            store.isRightInspectorVisible.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .buttonStyle(RowePressScaleButtonStyle())
                                    .help("Toggle Inspector")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .roweGlassCapsule(interactive: true)
                                .padding(.bottom, 16)
                            }
                            Spacer()
                        }
                        .animation(CraftTheme.craftSpring(reduceMotion: reduceMotion), value: store.selectedBlockIds.isEmpty)
                    }

                    // Cursor-anchored, keyboard-navigable Liquid Glass Slash Menu
                    if isSlashMenuOpen {
                        Color.clear
                            .frame(width: editorGeo.size.width, height: editorGeo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                                    isSlashMenuOpen = false
                                }
                            }

                        let pos = slashMenuOrigin(in: editorGeo.size)
                        SlashMenuView(isPresented: $isSlashMenuOpen) { action in
                            applySlashAction(action)
                        }
                        .offset(x: pos.x, y: pos.y)
                        .transition(.rowePopoverUnblur)
                    }
                }
                .coordinateSpace(name: "editorCanvas")
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if store.isRightInspectorVisible {
                Divider().opacity(0.35)
                RightInspectorView(
                    store: store,
                    document: document,
                    selectedTab: $inspectorTab,
                    onInsertAction: { action in
                        slashTargetBlockId = store.activeBlockId ?? visibleBlocks.last?.id
                        applySlashAction(action)
                    },
                    onFindInPage: {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                            store.isLeftSidebarVisible = true
                            documentSidebarTab = .find
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $store.isStyleGalleryPresented) {
            StyleGalleryModal(
                selectedThemeId: document.style.themeId,
                onSelect: { preset in
                    store.updateDocumentStyle(docId: document.id) { $0 = preset.style }
                    store.isStyleGalleryPresented = false
                },
                onClose: {
                    store.isStyleGalleryPresented = false
                }
            )
        }
        .onAppear { installBlockSelectionKeyMonitor() }
        .onDisappear { removeBlockSelectionKeyMonitor() }
    }

    // MARK: - Block Selection Keyboard Handler (Spec 04 & Spec 02)

    private func installBlockSelectionKeyMonitor() {
        removeBlockSelectionKeyMonitor()
        blockKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Let Slash Menu, Quick Open, Task Editor, Login, or PIN sheet handle keys when open
            guard !isSlashMenuOpen, !store.isQuickOpenPresented, store.activeTaskEditor == nil,
                  store.pinPromptRequest == nil, !store.isLoginSheetPresented else {
                return event
            }
            // If user is typing inside Title and presses Down Arrow, jump into first block
            if isTitleFocused && event.keyCode == 125 && event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                if let first = visibleBlocks.first {
                    isTitleFocused = false
                    if first.isEditableTextBlock {
                        store.enterInlineEditing(blockId: first.id, utf16Offset: 0)
                    } else {
                        store.selectSingleBlock(first.id)
                    }
                    return nil
                }
            }

            // Only intercept block-level navigation when in blockSelection mode (not typing in NSTextView)
            guard store.editorSelectionMode == .blockSelection, !store.selectedBlockIds.isEmpty else {
                return event
            }

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let activeId = store.activeBlockId ?? store.selectedBlockIds.first

            // Alt+Cmd+Up / Down: reorder selected blocks
            if mods == [.command, .option] {
                if event.keyCode == 126 {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                        store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: -1)
                    }
                    return nil
                } else if event.keyCode == 125 {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                        store.moveBlocks(in: document.id, blockIds: store.selectedBlockIds, offset: 1)
                    }
                    return nil
                }
            }

            // Cmd shortcuts in blockSelection
            if mods == .command, let ch = event.charactersIgnoringModifiers?.lowercased() {
                switch ch {
                case "a":
                    HapticsManager.shared.tap()
                    store.selectAllBlocks(in: document.id)
                    return nil
                case "d":
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                        store.duplicateBlocks(in: document.id, blockIds: store.selectedBlockIds)
                    }
                    return nil
                case "c":
                    copySelectedBlocksToPasteboard()
                    HapticsManager.shared.tap()
                    return nil
                case "x":
                    copySelectedBlocksToPasteboard()
                    HapticsManager.shared.destructive()
                    withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                        store.deleteBlocks(in: document.id, blockIds: store.selectedBlockIds)
                    }
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case 126: // Up Arrow
                if let activeId {
                    HapticsManager.shared.tap()
                    store.focusAdjacentBlock(in: document.id, from: activeId, direction: -1, desiredX: 0, extendSelection: mods == .shift)
                }
                return nil
            case 125: // Down Arrow
                if let activeId {
                    HapticsManager.shared.tap()
                    store.focusAdjacentBlock(in: document.id, from: activeId, direction: 1, desiredX: 0, extendSelection: mods == .shift)
                }
                return nil
            case 36, 76: // Return -> enter inline editing on active text block
                if let activeId, let blk = visibleBlocks.first(where: { $0.id == activeId }), blk.isEditableTextBlock {
                    store.enterInlineEditing(blockId: activeId, utf16Offset: blk.content.utf16.count)
                    return nil
                }
                return event
            case 51, 117: // Backspace / Forward Delete -> delete all selected blocks
                HapticsManager.shared.destructive()
                withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                    store.deleteBlocks(in: document.id, blockIds: store.selectedBlockIds)
                }
                return nil
            case 48: // Tab / Shift+Tab -> indent/outdent all selected blocks
                HapticsManager.shared.tap()
                withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                    store.indentBlocks(in: document.id, blockIds: store.selectedBlockIds, delta: mods == .shift ? -1 : 1)
                }
                return nil
            case 53: // Escape -> clear blockSelection
                HapticsManager.shared.tap()
                store.clearBlockSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeBlockSelectionKeyMonitor() {
        if let m = blockKeyMonitor {
            NSEvent.removeMonitor(m)
            blockKeyMonitor = nil
        }
    }

    private func blockBarAction(_ label: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowePressScaleButtonStyle())
    }

    private func copySelectedBlocksToPasteboard() {
        let text = visibleBlocks
            .filter { store.selectedBlockIds.contains($0.id) }
            .map(\.content)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Anchors the slash menu directly under the active block (flipping above when near the bottom edge).
    private func slashMenuOrigin(in canvasSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 280
        let menuMaxHeight: CGFloat = 290
        let padding: CGFloat = 16

        guard let targetId = slashTargetBlockId ?? store.activeBlockId,
              let rect = blockFrames[targetId] else {
            return CGPoint(
                x: max(padding, (canvasSize.width - menuWidth) / 2),
                y: max(60, (canvasSize.height - menuMaxHeight) / 3)
            )
        }

        let desiredX = rect.minX + 28
        let clampedX = min(max(padding, desiredX), max(padding, canvasSize.width - menuWidth - padding))

        let belowY = rect.maxY + 4
        let clampedY: CGFloat
        if belowY + menuMaxHeight <= canvasSize.height - padding {
            clampedY = max(56, belowY)
        } else {
            clampedY = max(56, rect.minY - menuMaxHeight - 4)
        }
        return CGPoint(x: clampedX, y: clampedY)
    }

    private var floatingEditorHeader: some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemImage: "chevron.left", helpText: "Go Back (⌘←)") {
                store.goBack()
            }
            .opacity(store.canGoBack ? 1.0 : 0.45)

            GlassCircleButton(systemImage: "plus", helpText: "Insert Block (/)") {
                slashTargetBlockId = store.activeBlockId ?? visibleBlocks.last?.id
                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                    isSlashMenuOpen.toggle()
                }
            }

            Spacer()

            lockToggleButton

            Button {
                HapticsManager.shared.tap()
                isSharePopoverOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("Share")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(RowePressScaleButtonStyle())
            .roweGlassCapsule(interactive: true)
            .popover(isPresented: $isSharePopoverOpen, arrowEdge: .bottom) {
                SharePopoverView(store: store, document: document)
            }

            HStack(spacing: 4) {
                inspectorToggleButton(icon: "textformat", tab: .format)
                inspectorToggleButton(icon: "paintbrush", tab: .style)
                inspectorToggleButton(icon: "info.circle", tab: .info)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .roweGlassCapsule()
        }
    }

    private func inspectorToggleButton(icon: String, tab: InspectorTab) -> some View {
        let isActive = store.isRightInspectorVisible && inspectorTab == tab
        return Button {
            HapticsManager.shared.tap()
            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                if store.isRightInspectorVisible && inspectorTab == tab {
                    store.isRightInspectorVisible = false
                } else {
                    inspectorTab = tab
                    store.isRightInspectorVisible = true
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 26, height: 24)
                .background(Capsule().fill(isActive ? Color.primary.opacity(0.11) : Color.clear))
        }
        .buttonStyle(RowePressScaleButtonStyle())
    }

    private var lockToggleButton: some View {
        let isLocked = document.isLocked
        let isUnlockedInRam = store.isDocumentUnlocked(document.id)
        let iconName: String = isLocked ? (isUnlockedInRam ? "lock.open.fill" : "lock.fill") : "lock.open"
        let helpLabel: String = isLocked
            ? (isUnlockedInRam ? "Re-lock Note" : "Unlock Note with PIN")
            : "Lock Note with PIN"
        let tint: Color = isLocked ? (isUnlockedInRam ? .green : .orange) : .primary

        return Button {
            HapticsManager.shared.tap()
            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                store.requestToggleLock(for: document.id)
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(RowePressScaleButtonStyle())
        .frame(width: 32, height: 32)
        .roweGlass(in: Circle(), interactive: true)
        .help(helpLabel)
    }

    private func lockedDocumentCover(editorWidth: CGFloat) -> some View {
        let pageWidth = min(
            max(320, editorWidth - 56),
            document.style.isWidePage ? CraftTheme.widePageWidth : CraftTheme.normalPageWidth
        )
        return VStack {
            Spacer(minLength: 40)
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 66, height: 66)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text(document.displayTitle)
                    .font(CraftTheme.font(for: .heading, family: document.style.fontFamily, isBold: true))
                    .foregroundStyle(pageTextColor)
                Text("End-to-end encrypted with your PIN. Unreadable even in the database.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(pageTextColor.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                GlassPillButton("Enter PIN to Unlock", systemImage: "key.fill") {
                    store.pinPromptRequest = .unlockDocument(docId: document.id)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 52)
            .frame(width: pageWidth)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(pageBackgroundColor)
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
            )
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct PageSegment {
        let leadingBreakId: String?
        let blocks: [Block]
    }

    private func splitIntoPageSegments(_ blocks: [Block]) -> [PageSegment] {
        var segments: [PageSegment] = []
        var currentBreakId: String? = nil
        var currentBlocks: [Block] = []
        for block in blocks {
            if block.kind == .line && block.separatorStyle == .pageBreak {
                segments.append(PageSegment(leadingBreakId: currentBreakId, blocks: currentBlocks))
                currentBreakId = block.id
                currentBlocks = []
            } else {
                currentBlocks.append(block)
            }
        }
        segments.append(PageSegment(leadingBreakId: currentBreakId, blocks: currentBlocks))
        return segments
    }

    @ViewBuilder
    private var documentBackdrop: some View {
        if let b64 = document.style.customBackdropBase64,
           let data = Data(base64Encoded: b64),
           let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let cover = document.style.coverImageName {
            CraftCoverArtwork(artworkName: cover)
        } else {
            switch document.style.backdropKind {
            case .none:
                pageBackgroundColor
            case .solid:
                Color(hex: document.style.backdropColorsHex.first ?? "#F5F5F7")
            case .gradient, .sketch:
                LinearGradient(
                    colors: document.style.backdropColorsHex.isEmpty
                        ? [Color(hex: "#FAF6EA"), Color(hex: "#ECE6D4")]
                        : document.style.backdropColorsHex.map(Color.init(hex:)),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func computeListIndex(in blocks: [Block], at idx: Int) -> Int {
        if let explicit = blocks[idx].userDefinedListNumber {
            return explicit
        }
        let targetIndent = blocks[idx].indentLevel
        var count = 1
        var cursor = idx - 1
        while cursor >= 0 {
            let prev = blocks[cursor]
            if prev.indentLevel > targetIndent {
                cursor -= 1
                continue
            }
            if prev.indentLevel == targetIndent && prev.listStyle == .numbered {
                if let explicit = prev.userDefinedListNumber {
                    return explicit + count
                }
                count += 1
                cursor -= 1
            } else {
                break
            }
        }
        return count
    }

    private func applySlashAction(_ action: SlashAction) {
        let targetId = slashTargetBlockId ?? store.activeBlockId ?? visibleBlocks.last?.id
        let targetIds: Set<String> = store.selectedBlockIds.isEmpty
            ? (targetId.map { [$0] } ?? [])
            : store.selectedBlockIds

        if let targetId {
            store.updateBlock(in: document.id, blockId: targetId) { blk in
                if blk.content == "/" {
                    blk.content = ""
                } else if blk.content.hasSuffix(" /") {
                    blk.content = String(blk.content.dropLast(2))
                } else if blk.content.hasSuffix("/") {
                    blk.content = String(blk.content.dropLast(1))
                }
            }
        }

        func mutateTargets(_ fn: (inout Block) -> Void) {
            guard !targetIds.isEmpty else { return }
            store.mutateBlocks(in: document.id) { blocks in
                for i in blocks.indices where targetIds.contains(blocks[i].id) {
                    fn(&blocks[i])
                }
            }
        }

        withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
            switch action {
            case .setList(let style):
                mutateTargets { blk in
                    blk.listStyle = style
                    if style == .todo && blk.task == nil { blk.task = TaskMetadata() }
                }
            case .setTextStyle(let style):
                mutateTargets { $0.textStyle = style }
            case .setDecoration(let dec):
                mutateTargets { $0.decoration = dec }
            case .setColor(let color):
                store.applyColorToSelectionOrBlocks(in: document.id, color: color)
            case .indent(let delta):
                store.indentBlocks(in: document.id, blockIds: targetIds, delta: delta)
            case .setAlignment(let align):
                mutateTargets { $0.alignment = align }
            case .setFont(let family):
                mutateTargets { $0.fontOverride = family }
            case .insertDate(let text):
                guard let targetId else { return }
                store.updateBlock(in: document.id, blockId: targetId) { $0.content += ($0.content.isEmpty ? "" : " ") + text }
            case .setReminder(let offset):
                mutateTargets { blk in
                    blk.listStyle = .todo
                    var meta = blk.task ?? TaskMetadata()
                    meta.reminderDate = Date().addingTimeInterval(offset)
                    meta.scheduleDate = meta.scheduleDate ?? Calendar.current.startOfDay(for: Date())
                    blk.task = meta
                }
            case .insertTable(let rows, let cols):
                let tableBlock = Block(documentId: document.id, kind: .table, content: "", tableData: TableData(rows: rows, columns: cols))
                _ = store.insertStructuredBlock(in: document.id, after: targetId, block: tableBlock, focusTrailingBody: false)
            case .insertCodeBlock:
                let codeBlock = Block(documentId: document.id, kind: .code, content: "", codeLanguage: "auto")
                _ = store.insertStructuredBlock(in: document.id, after: targetId, block: codeBlock, focusTrailingBody: false)
            case .insertSeparator(let style):
                store.insertOrUpdateSeparator(in: document.id, after: targetId, style: style)
            case .insertCollection(let mode):
                let nameCol = CollectionColumn(title: "Title", type: .text, width: 170)
                let statusCol = CollectionColumn(title: "Status", type: .singleSelect, width: 120)
                let col = CollectionData(
                    title: "New Collection",
                    viewMode: mode,
                    columns: [nameCol, statusCol],
                    rows: [CollectionRow(values: [nameCol.id: "First Item", statusCol.id: "Active"])]
                )
                let block = Block(documentId: document.id, kind: .objectList, content: col.title, collectionData: col)
                _ = store.insertStructuredBlock(in: document.id, after: targetId, block: block, focusTrailingBody: false)
            case .insertURL:
                let urlBlock = Block(documentId: document.id, kind: .url, content: "", urlString: "")
                _ = store.insertStructuredBlock(in: document.id, after: targetId, block: urlBlock, focusTrailingBody: false)
            case .openStyleGallery:
                store.isStyleGalleryPresented = true
            case .clearFormat:
                mutateTargets { blk in
                    blk.textStyle = .body
                    blk.listStyle = .none
                    blk.decoration = .none
                    blk.color = .primary
                    blk.fontOverride = nil
                    blk.isBold = false
                    blk.isItalic = false
                    blk.isStrikethrough = false
                    blk.isInlineCode = false
                    blk.runs = []
                }
            case .duplicateBlock:
                store.duplicateBlocks(in: document.id, blockIds: targetIds)
            case .deleteBlock:
                HapticsManager.shared.destructive()
                store.deleteBlocks(in: document.id, blockIds: targetIds)
            }
        }
    }
}

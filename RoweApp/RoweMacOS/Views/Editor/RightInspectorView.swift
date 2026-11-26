import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoweCore

enum InspectorTab: String, CaseIterable {
    case insert = "Insert"
    case format = "Format"
    case style = "Style"
    case info = "Info"
}

enum InfoSubTab: String, CaseIterable {
    case pageInfo = "Page Info"
    case actions = "Actions"
}

struct RightInspectorView: View {
    @Bindable var store: WorkspaceStore
    let document: RoweDocument
    @Binding var selectedTab: InspectorTab
    var onInsertAction: (SlashAction) -> Void
    var onFindInPage: () -> Void

    @State private var infoSubTab: InfoSubTab = .pageInfo
    @State private var insertSearchText: String = ""
    @State private var showWashiGallery = false

    private var activeBlock: Block? {
        guard let id = store.activeBlockId else { return document.blocks.first }
        return document.blocks.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            LiquidGlassSegmentedControl(
                items: InspectorTab.allCases,
                selection: $selectedTab,
                height: 30,
                title: \.rawValue
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.3).padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .insert:
                        insertTabBody
                    case .format:
                        formatTabBody
                    case .style:
                        styleTabBody
                    case .info:
                        infoTabBody
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 268)
        .background(.ultraThinMaterial)
    }

    // MARK: - Insert Tab

    @ViewBuilder
    private var insertTabBody: some View {
        Text("Click any item to insert into the document")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            TextField("Search", text: $insertSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            Text("⇧⌘↩")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
        }
        .roweGlassInput(cornerRadius: 11)

        inspectorSectionLabel("SUGGESTED")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            insertTile("Card", icon: "rectangle.on.rectangle") { onInsertAction(.setTextStyle(.pageCard)) }
            insertTile("Code Block", icon: "chevron.left.forwardslash.chevron.right") { onInsertAction(.insertCodeBlock) }
            insertTile("Page", icon: "doc.plaintext") { onInsertAction(.setTextStyle(.pageRegular)) }
            insertTile("Task List", icon: "checkmark.square") { onInsertAction(.setList(.todo)) }
        }

        inspectorSectionLabel("RICH BLOCKS")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            insertTile("Table", icon: "tablecells") { onInsertAction(.insertTable(rows: 3, cols: 3)) }
            insertTile("Smart Link", icon: "link") { onInsertAction(.insertURL) }
            insertTile("Code Block", icon: "terminal") { onInsertAction(.insertCodeBlock) }
            insertTile("Formula", icon: "x.squareroot") { onInsertAction(.insertDate("$$E = mc^2$$")) }
        }

        inspectorSectionLabel("COLLECTIONS")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
            insertTile("Table", icon: "tablecells.badge.ellipsis") { onInsertAction(.insertCollection(.table)) }
            insertTile("Gallery", icon: "square.grid.2x2") { onInsertAction(.insertCollection(.gallery)) }
            insertTile("Kanban", icon: "rectangle.split.3x1") { onInsertAction(.insertCollection(.kanban)) }
        }

        inspectorSectionLabel("SEPARATORS")
        HStack(spacing: 8) {
            insertTile("Light", icon: "ellipsis") { onInsertAction(.insertSeparator(.light)) }
            insertTile("Dotted", icon: "line.3.horizontal") { onInsertAction(.insertSeparator(.dotted)) }
            insertTile("Line", icon: "minus") { onInsertAction(.insertSeparator(.regular)) }
            insertTile("Strong", icon: "minus.rectangle.fill") { onInsertAction(.insertSeparator(.strong)) }
        }
    }

    private func insertTile(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.075))
                    .frame(height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    )
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowePressScaleButtonStyle())
    }

    // MARK: - Format Tab

    @ViewBuilder
    private var formatTabBody: some View {
        inspectorSectionLabel("TITLES")
        HStack(spacing: 6) {
            formatPill("Title", active: activeBlock?.textStyle == .title) { updateActive { $0.textStyle = .title } }
            formatPill("Subtitle", active: activeBlock?.textStyle == .subtitle) { updateActive { $0.textStyle = .subtitle } }
            formatPill("Heading", active: activeBlock?.textStyle == .heading) { updateActive { $0.textStyle = .heading } }
        }

        inspectorSectionLabel("CONTENT")
        HStack(spacing: 6) {
            formatPill("Strong", active: activeBlock?.textStyle == .strong) { updateActive { $0.textStyle = .strong } }
            formatPill("Body", active: activeBlock?.textStyle == .body) { updateActive { $0.textStyle = .body } }
            formatPill("Caption", active: activeBlock?.textStyle == .caption) { updateActive { $0.textStyle = .caption } }
        }

        inspectorSectionLabel("GROUPS")
        HStack(spacing: 8) {
            formatIconPill("Page", icon: "doc.plaintext", active: activeBlock?.textStyle == .pageRegular) {
                updateActive { $0.textStyle = .pageRegular }
            }
            formatIconPill("Card", icon: "rectangle.on.rectangle", active: activeBlock?.textStyle == .pageCard) {
                updateActive { $0.textStyle = .pageCard }
            }
        }

        // Inline styles (applies to selected text range if highlighted, else whole active/selected blocks)
        HStack(spacing: 4) {
            toggleSegment("B", active: activeBlock?.isBold ?? false) {
                HapticsManager.shared.tap()
                store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "bold")
            }
            toggleSegment("I", active: activeBlock?.isItalic ?? false) {
                HapticsManager.shared.tap()
                store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "italic")
            }
            toggleSegment("S", active: activeBlock?.isStrikethrough ?? false) {
                HapticsManager.shared.tap()
                store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "strike")
            }
            toggleSegment("</>", active: activeBlock?.isInlineCode ?? false) {
                HapticsManager.shared.tap()
                store.toggleStyleFlagOnSelectionOrBlocks(in: document.id, flag: "code")
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

        // List styles
        HStack(spacing: 4) {
            iconSegment("checkmark.square", active: activeBlock?.listStyle == .todo) {
                updateActive {
                    $0.listStyle = ($0.listStyle == .todo) ? .none : .todo
                    if $0.listStyle == .todo && $0.task == nil { $0.task = TaskMetadata() }
                }
            }
            iconSegment("arrowtriangle.right.fill", active: activeBlock?.listStyle == .toggle) {
                updateActive { $0.listStyle = ($0.listStyle == .toggle) ? .none : .toggle }
            }
            iconSegment("list.bullet", active: activeBlock?.listStyle == .bullet) {
                updateActive { $0.listStyle = ($0.listStyle == .bullet) ? .none : .bullet }
            }
            iconSegment("list.number", active: activeBlock?.listStyle == .numbered) {
                updateActive { $0.listStyle = ($0.listStyle == .numbered) ? .none : .numbered }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

        // Indent & alignment
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                iconSegment("decrease.indent", active: false) { updateActive { $0.indentLevel = max(0, $0.indentLevel - 1) } }
                iconSegment("increase.indent", active: false) { updateActive { $0.indentLevel = min(8, $0.indentLevel + 1) } }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

            HStack(spacing: 2) {
                iconSegment("text.alignleft", active: activeBlock?.alignment == .leading) { updateActive { $0.alignment = .leading } }
                iconSegment("text.aligncenter", active: activeBlock?.alignment == .center) { updateActive { $0.alignment = .center } }
                iconSegment("text.alignright", active: activeBlock?.alignment == .trailing) { updateActive { $0.alignment = .trailing } }
                iconSegment("text.justify", active: activeBlock?.alignment == .justified) { updateActive { $0.alignment = .justified } }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }

        inspectorSectionLabel("DECORATIONS")
        HStack(spacing: 8) {
            formatIconPill("Focus", icon: "line.diagonal", active: activeBlock?.decoration == .focus) {
                updateActive { $0.decoration = ($0.decoration == .focus) ? .none : .focus }
            }
            formatIconPill("Block", icon: "rectangle.fill", active: activeBlock?.decoration == .block) {
                updateActive { $0.decoration = ($0.decoration == .block) ? .none : .block }
            }
        }

        inspectorSectionLabel("COLOR")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
            ForEach(BlockColor.allCases, id: \.self) { color in
                let isSelected = activeBlock?.color == color
                Button {
                    HapticsManager.shared.tap()
                    store.applyColorToSelectionOrBlocks(in: document.id, color: color)
                } label: {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0)
                                .padding(-3)
                        )
                }
                .buttonStyle(RowePressScaleButtonStyle())
            }
        }
    }

    // MARK: - Style Tab

    @ViewBuilder
    private var styleTabBody: some View {
        // Preview card
        ZStack {
            Group {
                if let cover = document.style.coverImageName {
                    CraftCoverArtwork(artworkName: cover)
                } else if document.style.backdropColorsHex.count >= 2 {
                    LinearGradient(
                        colors: document.style.backdropColorsHex.map(Color.init(hex:)),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.primary.opacity(0.08)
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(document.style.documentColorHex.map(Color.init(hex:)) ?? Color.white)
                .frame(width: 68, height: 92)
                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                .overlay(alignment: .topLeading) {
                    Text(ThemePreset.builtInPresets.first(where: { $0.id == document.style.themeId })?.name ?? "Original")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(document.style.textColorHex.map(Color.init(hex:)) ?? Color(hex: "#1F2225"))
                        .padding(6)
                }
        }

        HStack(spacing: 8) {
            Button {
                HapticsManager.shared.tap()
                store.isStyleGalleryPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 11))
                    Text("All Styles")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                HapticsManager.shared.tap()
                if let next = ThemePreset.builtInPresets.randomElement() {
                    store.updateDocumentStyle(docId: document.id) { $0 = next.style }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 11))
                    Text("Tailored Style")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }

        inspectorSectionLabel("BACKDROP WALLPAPER")
        HStack(spacing: 8) {
            Text("Custom Image").font(.system(size: 13))
            Spacer()
            if document.style.customBackdropBase64 != nil {
                GlassCircleButton(systemImage: "xmark", helpText: "Clear Custom Backdrop", size: 26, iconSize: 10) {
                    store.updateDocumentStyle(docId: document.id) { $0.customBackdropBase64 = nil }
                }
            }
            GlassCircleButton(systemImage: "plus", helpText: "Choose Wallpaper Image", size: 28, iconSize: 11) {
                pickCustomBackdrop()
            }
        }

        inspectorSectionLabel("SEPARATOR STYLE")
        HStack(spacing: 8) {
            GlassCircleButton(systemImage: "line.3.horizontal", helpText: "Line Separator", size: 32, iconSize: 12) {
                store.updateDocumentStyle(docId: document.id) { $0.separatorStyle = .regular }
            }
            .overlay(Circle().strokeBorder(document.style.separatorStyle == .regular ? Color.accentColor : Color.clear, lineWidth: 1.5))

            GlassCircleButton(systemImage: "ticket", helpText: "Washi Tape Gallery", size: 32, iconSize: 12) {
                showWashiGallery.toggle()
            }
            .overlay(Circle().strokeBorder(document.style.separatorStyle == .washi ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .popover(isPresented: $showWashiGallery, arrowEdge: .leading) {
                washiGalleryPopover
            }

            Button {
                HapticsManager.shared.tap()
                store.updateDocumentStyle(docId: document.id) { $0.separatorStyle = .doodle }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scribble")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Doodle")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(RowePressScaleButtonStyle())
            .roweGlassCapsule(interactive: true)
            .overlay(Capsule().strokeBorder(document.style.separatorStyle == .doodle ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }

        inspectorSectionLabel("FONT")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(FontFamily.allCases, id: \.self) { fam in
                let isSelected = document.style.fontFamily == fam
                Button {
                    HapticsManager.shared.tap()
                    store.updateDocumentStyle(docId: document.id) { $0.fontFamily = fam }
                } label: {
                    VStack(spacing: 2) {
                        Text(fam.badgeLabel)
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        Text(fam.rawValue)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05)))
                }
                .buttonStyle(RowePressScaleButtonStyle())
            }
        }

        inspectorSectionLabel("ADVANCED")
        Toggle("Wide Page", isOn: Binding(
            get: { document.style.isWidePage },
            set: { newVal in
                HapticsManager.shared.toggle()
                withAnimation(store.settings.reduceAnimations ? .easeInOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.8)) {
                    store.updateDocumentStyle(docId: document.id) { $0.isWidePage = newVal }
                }
            }
        ))
        .font(.system(size: 13))
    }

    // MARK: - Info & Actions Tab

    @ViewBuilder
    private var infoTabBody: some View {
        LiquidGlassSegmentedControl(
            items: InfoSubTab.allCases,
            selection: $infoSubTab,
            height: 32,
            title: \.rawValue
        )

        if infoSubTab == .pageInfo {
            inspectorSectionLabel("PROPERTIES")
            VStack(alignment: .leading, spacing: 8) {
                propertyRow(icon: "calendar", label: "Created:", value: document.createdAt.craftRelativeString)
                propertyRow(icon: "clock", label: "Updated:", value: document.updatedAt.craftRelativeString)
                propertyRow(icon: "person.circle", label: "Author:", value: document.authorName)
            }

            inspectorSectionLabel("ACTIONS")
            VStack(spacing: 6) {
                infoActionButton(
                    document.isLocked
                        ? (store.isDocumentUnlocked(document.id) ? "Re-lock Note" : "Unlock Note")
                        : "Lock Note with PIN",
                    icon: document.isLocked ? "lock.fill" : "lock.open"
                ) {
                    store.requestToggleLock(for: document.id)
                }
                if document.isLocked && store.isDocumentUnlocked(document.id) {
                    infoActionButton("Remove Lock Permanently", icon: "lock.slash") {
                        store.removeLockPermanently(docId: document.id)
                    }
                }
                infoActionButton(document.isStarred ? "Unstar Document" : "Star Document", icon: document.isStarred ? "star.fill" : "star") {
                    store.toggleStarDocument(docId: document.id)
                }
                infoActionButton("Duplicate Document", icon: "plus.square.on.square") {
                    store.duplicateDocument(docId: document.id)
                }
                infoActionButton("Delete", icon: "trash", isDestructive: true) {
                    HapticsManager.shared.destructive()
                    store.moveDocumentToTrash(docId: document.id)
                }
            }

            inspectorSectionLabel("STATS · FULL DOCUMENT")
            let wordCount = document.blocks.reduce(0) { $0 + $1.content.split(whereSeparator: \.isWhitespace).count }
            let charCount = document.blocks.reduce(0) { $0 + $1.content.count }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(document.blocks.count) blocks · \(wordCount) words · \(charCount) chars")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                shortcutActionRow("Find in Page", icon: "magnifyingglass", shortcut: "⌘F") { onFindInPage() }
                shortcutActionRow("Quick Open", icon: "doc.text.magnifyingglass", shortcut: "⌘O") { store.isQuickOpenPresented = true }
                Divider().opacity(0.3).padding(.vertical, 4)
                shortcutActionRow("Move Up", icon: "arrow.up", shortcut: "⌥⌘↑") {
                    if let id = store.activeBlockId { store.moveBlock(in: document.id, blockId: id, offset: -1) }
                }
                shortcutActionRow("Move Down", icon: "arrow.down", shortcut: "⌥⌘↓") {
                    if let id = store.activeBlockId { store.moveBlock(in: document.id, blockId: id, offset: 1) }
                }
                shortcutActionRow("Move to Top", icon: "arrow.up.to.line", shortcut: "⌥⇧⌘↑") {
                    if let id = store.activeBlockId { store.moveBlockToEdge(in: document.id, blockId: id, top: true) }
                }
                shortcutActionRow("Move to Bottom", icon: "arrow.down.to.line", shortcut: "⌥⇧⌘↓") {
                    if let id = store.activeBlockId { store.moveBlockToEdge(in: document.id, blockId: id, top: false) }
                }
                Divider().opacity(0.3).padding(.vertical, 4)
                shortcutActionRow("Copy Markdown", icon: "doc.on.doc", shortcut: "") {
                    Task {
                        let md = await store.exportDocumentMarkdown(document)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                    }
                }
                shortcutActionRow("Copy Plain Text", icon: "doc.plaintext", shortcut: "") {
                    Task {
                        let txt = await store.exportDocumentPlainText(document)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(txt, forType: .string)
                    }
                }
                shortcutActionRow("Duplicate Block", icon: "plus.square.on.square", shortcut: "⌘D") {
                    if let id = store.activeBlockId { store.duplicateBlock(in: document.id, blockId: id) }
                }
                shortcutActionRow("Delete Block", icon: "trash", shortcut: "⌫") {
                    if let id = store.activeBlockId {
                        HapticsManager.shared.destructive()
                        store.deleteBlock(in: document.id, blockId: id)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateActive(_ mutate: (inout Block) -> Void) {
        HapticsManager.shared.tap()
        let targets: Set<String> = store.selectedBlockIds.isEmpty
            ? ((store.activeBlockId ?? document.blocks.first?.id).map { [$0] } ?? [])
            : store.selectedBlockIds
        guard !targets.isEmpty else { return }
        store.mutateBlocks(in: document.id) { blocks in
            for i in blocks.indices where targets.contains(blocks[i].id) {
                mutate(&blocks[i])
            }
        }
    }

    private func inspectorSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func formatPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func formatIconPill(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12.5, weight: active ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Color.primary.opacity(0.16) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func toggleSegment(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.primary.opacity(0.14) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func iconSegment(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.primary.opacity(0.14) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func propertyRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium))
            Spacer()
        }
    }

    private func infoActionButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isDestructive ? Color.red.opacity(0.1) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func shortcutActionRow(_ title: String, icon: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
                Text(title).font(.system(size: 12.5))
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var washiGalleryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(WashiTapePreset.all) { preset in
                        let selected = document.style.separatorStyle == .washi && document.style.washiPatternId == preset.id
                        Button {
                            HapticsManager.shared.tap()
                            store.updateDocumentStyle(docId: document.id) {
                                $0.separatorStyle = .washi
                                $0.washiPatternId = preset.id
                            }
                            showWashiGallery = false
                        } label: {
                            VStack(spacing: 5) {
                                WashiTapeSeparatorView(patternId: preset.id, height: 34)
                                    .overlay(
                                        WashiTapeShape()
                                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                Text(preset.name)
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(RowePressScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 280)

            Divider().opacity(0.25)

            HStack(spacing: 8) {
                GlassPillButton("Upload Washi", systemImage: "photo.badge.plus") {
                    pickCustomWashi()
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(RoweNativeGlassBackdrop(cornerRadius: 16))
        .presentationBackground(.clear)
    }

    private func pickCustomBackdrop() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url),
              let b64 = TaskImageEncoder.encodeToBase64(img, maxDimension: 1800) else { return }
        HapticsManager.shared.tap()
        store.updateDocumentStyle(docId: document.id) {
            $0.customBackdropBase64 = b64
            $0.backdropKind = .sketch
        }
    }

    private func pickCustomWashi() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url),
              let b64 = TaskImageEncoder.encodeToBase64(img, maxDimension: 900) else { return }
        HapticsManager.shared.tap()
        store.updateDocumentStyle(docId: document.id) {
            $0.separatorStyle = .washi
            $0.washiPatternId = "custom"
            $0.customWashiBase64 = b64
        }
        showWashiGallery = false
    }
}

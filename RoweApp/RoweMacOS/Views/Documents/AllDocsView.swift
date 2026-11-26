import SwiftUI
import RoweCore

struct AllDocsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    let filterTitle: String
    let folderId: String?
    let tagFilter: String?
    let isTrashMode: Bool

    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var hoveredDocId: String?
    @State private var selectedDocIds: Set<String> = []
    @State private var docFrames: [String: CGRect] = [:]
    @State private var dragStartPoint: CGPoint? = nil
    @State private var dragCurrentPoint: CGPoint? = nil

    init(
        store: WorkspaceStore,
        filterTitle: String = "All Docs",
        folderId: String? = nil,
        tagFilter: String? = nil,
        isTrashMode: Bool = false
    ) {
        self.store = store
        self.filterTitle = filterTitle
        self.folderId = folderId
        self.tagFilter = tagFilter
        self.isTrashMode = isTrashMode
    }

    private var viewStyle: AllDocsViewStyle {
        AllDocsViewStyle(rawValue: store.settings.allDocsViewStyleRaw) ?? .grid
    }

    private var sortOrder: AllDocsSortOrder {
        AllDocsSortOrder(rawValue: store.settings.allDocsSortOrderRaw) ?? .updatedDesc
    }

    private var viewStyleBinding: Binding<AllDocsViewStyle> {
        Binding(
            get: { viewStyle },
            set: { newStyle in
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    store.updateSettings { $0.allDocsViewStyleRaw = newStyle.rawValue }
                }
            }
        )
    }

    private var filteredDocuments: [RoweDocument] {
        var list = store.documents.filter { $0.isTrashed == isTrashMode }
        if let folderId {
            list = list.filter { $0.folderId == folderId }
        }
        if let tagFilter {
            list = list.filter { $0.tags.contains(tagFilter) }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.displayTitle.lowercased().contains(q) || $0.previewSnippet.lowercased().contains(q)
            }
        }
        switch sortOrder {
        case .updatedDesc: list.sort { $0.updatedAt > $1.updatedAt }
        case .createdDesc: list.sort { $0.createdAt > $1.createdAt }
        case .lastViewedDesc: list.sort { $0.lastViewedAt > $1.lastViewedAt }
        case .titleAsc: list.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
        return list
    }

    private var groupedDocuments: [(String, [RoweDocument])] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = filteredDocuments.filter { $0.updatedAt >= cutoff }
        let older = filteredDocuments.filter { $0.updatedAt < cutoff }

        var groups: [(String, [RoweDocument])] = []
        if !recent.isEmpty {
            groups.append(("Last 30 days", recent))
        }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        var byMonth: [String: [RoweDocument]] = [:]
        var monthOrder: [String] = []
        for doc in older {
            let key = monthFormatter.string(from: doc.updatedAt)
            if byMonth[key] == nil { monthOrder.append(key) }
            byMonth[key, default: []].append(doc)
        }
        for key in monthOrder {
            if let docs = byMonth[key] {
                groups.append((key, docs))
            }
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.leading, store.isLeftSidebarVisible ? 20 : 58)
                .padding(.trailing, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: store.isLeftSidebarVisible)

            if filteredDocuments.isEmpty {
                emptyState
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            Group {
                                switch viewStyle {
                                case .list:
                                    listLayout
                                        .transition(.opacity)
                                case .grid:
                                    gridLayout(cardWidth: 196, isGallery: false)
                                        .transition(.opacity)
                                case .gallery:
                                    gridLayout(cardWidth: 256, isGallery: true)
                                        .transition(.opacity)
                                }
                            }
                            .padding(.bottom, selectedDocIds.isEmpty ? 0 : 72)

                            if let rect = selectionMarqueeRect {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                                    )
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                            }
                        }
                        .coordinateSpace(name: "allDocsCanvas")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !selectedDocIds.isEmpty {
                                selectedDocIds.removeAll()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .named("allDocsCanvas"))
                                .onChanged { value in
                                    if dragStartPoint == nil { dragStartPoint = value.startLocation }
                                    dragCurrentPoint = value.location
                                    if let marquee = selectionMarqueeRect {
                                        let hitIds = docFrames.compactMap { id, frame in
                                            frame.intersects(marquee) ? id : nil
                                        }
                                        selectedDocIds = Set(hitIds)
                                    }
                                }
                                .onEnded { _ in
                                    dragStartPoint = nil
                                    dragCurrentPoint = nil
                                }
                        )
                    }

                    if !selectedDocIds.isEmpty {
                        bulkSelectionBar
                            .padding(.bottom, 16)
                            .transition(.roweUnblur)
                    }
                }
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: selectedDocIds.isEmpty)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if !isTrashMode {
                GlassCircleButton(systemImage: "plus", helpText: "New Document (⌘N)") {
                    store.createDocument(folderId: folderId)
                }
            }

            Text(filterTitle)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            if isSearchExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Filter documents…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 170)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .roweGlassInput(cornerRadius: 16)
                .transition(.roweUnblur)
            }

            LiquidGlassSegmentedControl(
                items: [AllDocsViewStyle.gallery, .grid, .list],
                selection: viewStyleBinding,
                height: 30
            ) { style, isSelected in
                Image(systemName: style == .gallery ? "rectangle.grid.1x2" : (style == .grid ? "square.grid.2x2" : "line.3.horizontal"))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: 112)

            RoweGlassCircleMenu(
                systemImage: "arrow.up.arrow.down",
                helpText: "Sort",
                size: 32,
                items: AllDocsSortOrder.allCases.map { order in
                    RoweGlassActionMenuItem(
                        title: order.rawValue,
                        isSelected: sortOrder == order
                    ) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.updateSettings { $0.allDocsSortOrderRaw = order.rawValue }
                        }
                    }
                }
            )

            GlassCircleButton(systemImage: "magnifyingglass", helpText: "Search") {
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    isSearchExpanded.toggle()
                }
            }
        }
    }

    // MARK: - List Layout

    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Last Viewed")
                    .frame(width: 110, alignment: .leading)
                Text(sortOrder == .updatedDesc ? "Updated ↓" : "Updated")
                    .fontWeight(sortOrder == .updatedDesc ? .semibold : .regular)
                    .foregroundStyle(sortOrder == .updatedDesc ? .primary : .secondary)
                    .frame(width: 110, alignment: .leading)
                Text("Created")
                    .frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)

            Divider().opacity(0.35).padding(.horizontal, 20)

            ForEach(groupedDocuments, id: \.0) { groupTitle, docs in
                Text(groupTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                ForEach(docs) { doc in
                    documentListRow(doc)
                }
            }
        }
        .padding(.bottom, 32)
    }

    private func documentListRow(_ doc: RoweDocument) -> some View {
        let folderName = store.folders.first(where: { $0.id == doc.folderId })?.name
        let isHovered = hoveredDocId == doc.id

        let isSelected = selectedDocIds.contains(doc.id)
        return Button {
            HapticsManager.shared.tap()
            if NSEvent.modifierFlags.contains(.command) || !selectedDocIds.isEmpty {
                if isSelected { selectedDocIds.remove(doc.id) } else { selectedDocIds.insert(doc.id) }
            } else if !isTrashMode {
                store.navigate(to: .document(doc.id))
            }
        } label: {
            HStack(spacing: 12) {
                documentMiniThumbnail(doc)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if doc.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                        }
                        if doc.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        }
                        Text(doc.displayTitle)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        if let folderName {
                            Image(systemName: "folder")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Text(folderName)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                        }
                        Text(doc.previewSnippet)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(doc.lastViewedAt.craftRelativeString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)

                Text(doc.updatedAt.craftRelativeString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)

                Text(doc.createdAt.craftRelativeString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            .animation(CraftTheme.hoverEase(reduceMotion: store.settings.reduceAnimations), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("allDocsCanvas")) } action: { docFrames[doc.id] = $0 }
        .onHover { hovering in
            hoveredDocId = hovering ? doc.id : (hoveredDocId == doc.id ? nil : hoveredDocId)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.25).padding(.horizontal, 28)
        }
        .contextMenu { documentContextMenu(doc) }
    }

    // MARK: - Craft-Style Grid & Gallery Cards (High-Contrast Mini Block Previews + Cover Artwork)

    private func gridLayout(cardWidth: CGFloat, isGallery: Bool) -> some View {
        let columns = [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 64), spacing: 18)]
        return LazyVGrid(columns: columns, spacing: 22) {
            ForEach(filteredDocuments) { doc in
                documentPreviewCard(doc, isGallery: isGallery)
            }
        }
        .padding(24)
    }

    private func documentPreviewCard(_ doc: RoweDocument, isGallery: Bool) -> some View {
        let isHovered = hoveredDocId == doc.id
        let folderName = store.folders.first(where: { $0.id == doc.folderId })?.name
        let palette = cardPalette(for: doc)
        let cardHeight: CGFloat = isGallery ? 196 : 154
        let coverName = resolvedCoverArtworkName(for: doc)

        let isSelected = selectedDocIds.contains(doc.id)
        return Button {
            HapticsManager.shared.tap()
            if NSEvent.modifierFlags.contains(.command) || !selectedDocIds.isEmpty {
                if isSelected { selectedDocIds.remove(doc.id) } else { selectedDocIds.insert(doc.id) }
            } else if !isTrashMode {
                store.navigate(to: .document(doc.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    // Optional editorial cover artwork header (shown on Gallery cards or themed docs)
                    if let coverName, isGallery || doc.style.coverImageName != nil {
                        CraftCoverArtwork(artworkName: coverName)
                            .frame(height: isGallery ? 62 : 42)
                            .clipped()
                    } else if doc.style.backdropKind == .gradient && doc.style.backdropColorsHex.count >= 2 {
                        LinearGradient(
                            colors: doc.style.backdropColorsHex.map(Color.init(hex:)),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: isGallery ? 54 : 36)
                    }

                    // Crisp high-contrast miniature document content preview
                    VStack(alignment: .leading, spacing: 5) {
                        Text(doc.displayTitle)
                            .font(.system(
                                size: isGallery ? 13.5 : 12.5,
                                weight: .bold,
                                design: doc.style.fontFamily == .serif ? .serif : (doc.style.fontFamily == .mono ? .monospaced : .default)
                            ))
                            .foregroundStyle(palette.primaryInk)
                            .lineLimit(1)

                        if doc.isLocked {
                            VStack(spacing: 6) {
                                Spacer(minLength: 4)
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.orange.opacity(0.85))
                                Text("Locked Note")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(palette.secondaryInk)
                                Spacer(minLength: 4)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            let previewBlocks = Array(doc.blocks.filter {
                                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                $0.kind == .line || $0.kind == .table || $0.kind == .objectList
                            }.prefix(isGallery ? 6 : 5))

                            if previewBlocks.isEmpty {
                                Text("Start writing…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondaryInk.opacity(0.7))
                                    .padding(.top, 2)
                            } else {
                                VStack(alignment: .leading, spacing: 3.5) {
                                    ForEach(previewBlocks) { blk in
                                        miniBlockPreviewRow(blk, palette: palette)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: cardHeight, alignment: .topLeading)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.45) : palette.border),
                            lineWidth: isSelected ? 2.2 : (isHovered ? 1.25 : 0.75)
                        )
                )
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.accentColor)
                                .background(Circle().fill(Color.white))
                        } else if doc.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(8)
                }
                .shadow(color: .black.opacity(isSelected ? 0.14 : 0.08), radius: 6, y: 2)
                .animation(CraftTheme.hoverEase(reduceMotion: store.settings.reduceAnimations), value: isHovered)
                .animation(CraftTheme.hoverEase(reduceMotion: store.settings.reduceAnimations), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let folderName {
                            Text(folderName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Text(doc.updatedAt.craftRelativeString)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDocId = hovering ? doc.id : (hoveredDocId == doc.id ? nil : hoveredDocId)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("allDocsCanvas")) } action: { docFrames[doc.id] = $0 }
        .contextMenu { documentContextMenu(doc) }
    }

    @ViewBuilder
    private func miniBlockPreviewRow(_ block: Block, palette: CardColorPalette) -> some View {
        switch block.kind {
        case .line:
            Rectangle()
                .fill(palette.secondaryInk.opacity(0.28))
                .frame(height: 1)
                .padding(.vertical, 2)
        case .code:
            Text(block.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.primaryInk.opacity(0.06)))
        case .table, .objectList:
            HStack(spacing: 4) {
                Image(systemName: "tablecells")
                    .font(.system(size: 8.5))
                Text(block.collectionData?.title ?? "Table")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(palette.primaryInk.opacity(0.06)))
        default:
            HStack(alignment: .center, spacing: 5) {
                if block.listStyle == .todo {
                    let done = (block.task?.state ?? .pending) != .pending
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 8.5))
                        .foregroundStyle(done ? palette.secondaryInk.opacity(0.75) : palette.secondaryInk)
                } else if block.listStyle == .bullet {
                    Circle()
                        .fill(palette.secondaryInk.opacity(0.7))
                        .frame(width: 3, height: 3)
                }
                Text(block.content)
                    .font(.system(
                        size: (block.textStyle == .title || block.textStyle == .subtitle || block.textStyle == .heading) ? 11 : 10.5,
                        weight: (block.textStyle == .title || block.textStyle == .subtitle || block.textStyle == .heading) ? .semibold : .regular
                    ))
                    .strikethrough(block.listStyle == .todo && (block.task?.state ?? .pending) != .pending)
                    .foregroundStyle(
                        (block.textStyle == .title || block.textStyle == .subtitle || block.textStyle == .heading)
                            ? palette.primaryInk.opacity(0.92)
                            : palette.secondaryInk
                    )
                    .lineLimit(1)
            }
        }
    }

    private struct CardColorPalette {
        let surface: Color
        let primaryInk: Color
        let secondaryInk: Color
        let border: Color
    }

    /// Computes guaranteed high-contrast card surface and ink colors in both Light and Dark modes.
    private func cardPalette(for doc: RoweDocument) -> CardColorPalette {
        if let bgHex = doc.style.documentColorHex {
            let primary = doc.style.textColorHex.map(Color.init(hex:)) ?? Color(hex: "#1F2225")
            return CardColorPalette(
                surface: Color(hex: bgHex),
                primaryInk: primary,
                secondaryInk: primary.opacity(0.66),
                border: primary.opacity(0.12)
            )
        }
        if colorScheme == .dark {
            return CardColorPalette(
                surface: Color(hex: "#25262B"),
                primaryInk: Color(hex: "#F2F3F5"),
                secondaryInk: Color(hex: "#A4A8B3"),
                border: Color.white.opacity(0.09)
            )
        }
        return CardColorPalette(
            surface: Color.white,
            primaryInk: Color(hex: "#1F2225"),
            secondaryInk: Color(hex: "#5F646E"),
            border: Color.black.opacity(0.08)
        )
    }

    private func resolvedCoverArtworkName(for doc: RoweDocument) -> String? {
        if let explicit = doc.style.coverImageName { return explicit }
        return nil
    }

    @ViewBuilder
    private func documentContextMenu(_ doc: RoweDocument) -> some View {
        if isTrashMode {
            Button("Restore Document") {
                HapticsManager.shared.tap()
                store.restoreDocument(docId: doc.id)
            }
            Button("Delete Permanently", role: .destructive) {
                HapticsManager.shared.destructive()
                store.permanentlyDeleteDocument(docId: doc.id)
            }
        } else {
            Button("Open in New Tab") {
                store.openNewTab(destination: .document(doc.id))
            }
            Button(doc.isStarred ? "Unstar Document" : "Star Document") {
                HapticsManager.shared.toggle()
                store.toggleStarDocument(docId: doc.id)
            }
            Button("Duplicate") {
                store.duplicateDocument(docId: doc.id)
            }
            Menu("Move to Folder") {
                Button("None") { store.moveDocument(docId: doc.id, toFolderId: nil) }
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.moveDocument(docId: doc.id, toFolderId: folder.id) }
                }
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                HapticsManager.shared.destructive()
                store.moveDocumentToTrash(docId: doc.id)
            }
        }
    }

    private func documentMiniThumbnail(_ doc: RoweDocument) -> some View {
        let palette = cardPalette(for: doc)
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.surface)
                .frame(width: 28, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(palette.border, lineWidth: 0.75))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2.5) {
                RoundedRectangle(cornerRadius: 1).fill(palette.primaryInk.opacity(0.55)).frame(width: 14, height: 2)
                RoundedRectangle(cornerRadius: 1).fill(palette.secondaryInk.opacity(0.4)).frame(width: 18, height: 1.5)
                RoundedRectangle(cornerRadius: 1).fill(palette.secondaryInk.opacity(0.4)).frame(width: 15, height: 1.5)
                RoundedRectangle(cornerRadius: 1).fill(palette.secondaryInk.opacity(0.3)).frame(width: 12, height: 1.5)
            }
        }
    }

    private var selectionMarqueeRect: CGRect? {
        guard let start = dragStartPoint, let cur = dragCurrentPoint else { return nil }
        let minX = min(start.x, cur.x)
        let minY = min(start.y, cur.y)
        let w = abs(cur.x - start.x)
        let h = abs(cur.y - start.y)
        guard w > 4 || h > 4 else { return nil }
        return CGRect(x: minX, y: minY, width: w, height: h)
    }

    private var bulkSelectionBar: some View {
        HStack(spacing: 14) {
            Text("\(selectedDocIds.count) Selected")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.numericText())

            Divider().frame(height: 18).opacity(0.3)

            if isTrashMode {
                Button {
                    HapticsManager.shared.tap()
                    for id in selectedDocIds { store.restoreDocument(docId: id) }
                    selectedDocIds.removeAll()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(RowePressScaleButtonStyle())

                Button {
                    HapticsManager.shared.destructive()
                    for id in selectedDocIds { store.permanentlyDeleteDocument(docId: id) }
                    selectedDocIds.removeAll()
                } label: {
                    Label("Delete Forever", systemImage: "trash")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(RowePressScaleButtonStyle())
            } else {
                Button {
                    HapticsManager.shared.tap()
                    for id in selectedDocIds { store.toggleStarDocument(docId: id) }
                } label: {
                    Label("Star", systemImage: "star")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(RowePressScaleButtonStyle())

                Button {
                    HapticsManager.shared.destructive()
                    for id in selectedDocIds { store.moveDocumentToTrash(docId: id) }
                    selectedDocIds.removeAll()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(RowePressScaleButtonStyle())
            }

            Divider().frame(height: 18).opacity(0.3)

            GlassCircleButton(systemImage: "xmark", helpText: "Clear Selection", size: 26, iconSize: 10) {
                selectedDocIds.removeAll()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .roweGlassCapsule(interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isTrashMode ? "trash" : "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(isTrashMode ? "Trash is empty" : "No documents yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if !isTrashMode {
                GlassPillButton("Create Document", systemImage: "plus") {
                    store.createDocument(folderId: folderId)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

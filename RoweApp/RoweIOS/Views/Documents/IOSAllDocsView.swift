import SwiftUI
import RoweCore

enum IOSDocsDisplayStyle: String, CaseIterable {
    case waterfall = "Waterfall"
    case grid = "Grid"
    case list = "List"

    var icon: String {
        switch self {
        case .waterfall: "rectangle.3.group"
        case .grid: "square.grid.2x2"
        case .list: "rectangle.grid.1x2"
        }
    }
}

struct IOSAllDocsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    let filterTitle: String
    let folderId: String?
    let isTrashMode: Bool
    let zoomNamespace: Namespace.ID
    var onOpenDoc: (String) -> Void

    @State private var searchText: String = ""
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    private var displayStyle: IOSDocsDisplayStyle {
        switch store.settings.allDocsViewStyleRaw {
        case "gallery", "Waterfall": .waterfall
        case "list", "List": .list
        default: .grid
        }
    }

    private var sortOrder: AllDocsSortOrder {
        AllDocsSortOrder(rawValue: store.settings.allDocsSortOrderRaw) ?? .updatedDesc
    }

    private var filteredDocs: [RoweDocument] {
        var list = store.documents.filter { $0.isTrashed == isTrashMode }
        if let folderId {
            list = list.filter { $0.folderId == folderId }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
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

    private var groupedDocs: [(String, [RoweDocument])] {
        let cal = Calendar.current
        let today = filteredDocs.filter { cal.isDateInToday($0.updatedAt) }
        let rest = filteredDocs.filter { !cal.isDateInToday($0.updatedAt) }
        var groups: [(String, [RoweDocument])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !rest.isEmpty { groups.append(("Earlier", rest)) }
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Top Bar matching IMG_5042 & IMG_5043
                HStack {
                    IOSGlassCircleButton(systemImage: "chevron.left", size: 40, iconSize: 16) {
                        IOSKeyboard.dismiss()
                        dismiss()
                    }

                    Spacer()

                    Button {
                        IOSHaptics.shared.tap()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIds.removeAll() }
                        }
                    } label: {
                        Text(isSelecting ? "Done" : "Select")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .roweIOSGlassCapsule(interactive: true)

                    Menu {
                        Menu {
                            ForEach(AllDocsSortOrder.allCases, id: \.self) { order in
                                Button {
                                    store.updateSettings { $0.allDocsSortOrderRaw = order.rawValue }
                                } label: {
                                    Label(order.rawValue, systemImage: sortOrder == order ? "checkmark" : "")
                                }
                            }
                        } label: {
                            Label("Sort By · \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                        }

                        Menu {
                            ForEach(IOSDocsDisplayStyle.allCases, id: \.self) { style in
                                Button {
                                    store.updateSettings {
                                        $0.allDocsViewStyleRaw = style == .waterfall ? "gallery" : (style == .list ? "list" : "grid")
                                    }
                                } label: {
                                    Label(style.rawValue, systemImage: displayStyle == style ? "checkmark" : style.icon)
                                }
                            }
                        } label: {
                            Label("Display Style · \(displayStyle.rawValue)", systemImage: "square.grid.2x2")
                        }


                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .roweIOSGlass(in: Circle(), interactive: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                HStack(alignment: .firstTextBaseline) {
                    Text(filterTitle)
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    if isSelecting && !selectedIds.isEmpty {
                        Button(role: .destructive) {
                            IOSHaptics.shared.destructive()
                            withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                for id in selectedIds {
                                    if isTrashMode {
                                        store.permanentlyDeleteDocument(docId: id)
                                    } else {
                                        store.moveDocumentToTrash(docId: id)
                                    }
                                }
                                selectedIds.removeAll()
                                isSelecting = false
                            }
                        } label: {
                            Label("Delete (\(selectedIds.count))", systemImage: "trash")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.red)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(.horizontal, 18)

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .focused($isSearchFocused)
                        .font(.system(size: 15))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .padding(.horizontal, 18)

                if filteredDocs.isEmpty {
                    VStack(spacing: 14) {
                        RoweEmptyStateArtwork(
                            kind: isTrashMode ? .trashEmpty : .documents,
                            accent: Color(hex: store.settings.accentColor.hex),
                            size: 96
                        )
                        Text(isTrashMode ? "Trash is Empty" : "No Documents")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(isTrashMode ? "Deleted documents appear here." : "Tap + to create a new document.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)
                } else {
                    ForEach(groupedDocs, id: \.0) { sectionTitle, docs in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sectionTitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)

                            switch displayStyle {
                            case .list:
                                VStack(spacing: 0) {
                                    ForEach(docs) { doc in
                                        VStack(spacing: 0) {
                                            listRow(doc)
                                            Divider().opacity(0.2).padding(.leading, 18)
                                        }
                                        .transition(.roweUnblur)
                                    }
                                }
                            case .grid:
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                                    ForEach(docs) { doc in
                                        gridCard(doc, height: 184)
                                            .transition(.roweUnblur)
                                    }
                                }
                                .padding(.horizontal, 18)
                            case .waterfall:
                                VStack(spacing: 16) {
                                    ForEach(docs) { doc in
                                        gridCard(doc, height: 220)
                                            .transition(.roweUnblur)
                                    }
                                }
                                .padding(.horizontal, 18)
                            }
                        }
                        .transition(.roweUnblur)
                    }
                }
            }
            .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: filteredDocs.map(\.id))
            .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: displayStyle)
            .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: isSelecting)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .iosPullDownToSearch(isPresented: $store.isQuickOpenPresented, reduceMotion: store.settings.reduceAnimations)
        .onTapGesture {
            if isSearchFocused {
                isSearchFocused = false
                IOSKeyboard.dismiss()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func handleTap(_ doc: RoweDocument) {
        IOSHaptics.shared.tap()
        IOSKeyboard.dismiss()
        if isSelecting {
            if selectedIds.contains(doc.id) { selectedIds.remove(doc.id) } else { selectedIds.insert(doc.id) }
        } else if !isTrashMode {
            onOpenDoc(doc.id)
        }
    }

    private func gridCard(_ doc: RoweDocument, height: CGFloat) -> some View {
        let surface = doc.style.documentColorHex.map(Color.init(hex:)) ?? (colorScheme == .dark ? Color(hex: "#1E1F24") : .white)
        let ink = doc.style.textColorHex.map(Color.init(hex:)) ?? (colorScheme == .dark ? Color(hex: "#F2F3F5") : Color(hex: "#1C1E22"))
        let isPicked = selectedIds.contains(doc.id)

        return Button { handleTap(doc) } label: {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    if let cover = doc.style.coverImageName {
                        IOSCoverArtwork(artworkName: cover)
                    } else {
                        surface
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            if doc.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                            }
                            Text(doc.displayTitle)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                        }
                        if doc.isLocked {
                            Spacer()
                            Label("End-to-End Encrypted", systemImage: "lock.shield.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                            Spacer()
                        } else {
                            Text(doc.previewSnippet)
                                .font(.system(size: 12.5))
                                .foregroundStyle(ink.opacity(0.70))
                                .lineLimit(5)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(surface.opacity(doc.style.coverImageName != nil ? 0.88 : 1.0))
                    )
                    .padding(doc.style.coverImageName != nil ? 7 : 0)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isPicked ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isPicked ? 2.5 : 0.75)
                )

                if isSelecting {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isPicked ? Color.accentColor : .white.opacity(0.8))
                        .padding(12)
                }
            }
        }
        .buttonStyle(RowePressScaleStyle())
        .matchedTransitionSource(id: "doc-\(doc.id)", in: zoomNamespace)
        .contextMenu { documentContextMenu(doc) }
    }

    @ViewBuilder
    private func documentContextMenu(_ doc: RoweDocument) -> some View {
        if isTrashMode {
            Section {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    IOSHaptics.shared.tap()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.restoreDocument(docId: doc.id)
                    }
                }
            }
            Section {
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    IOSHaptics.shared.destructive()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.permanentlyDeleteDocument(docId: doc.id)
                    }
                }
            }
        } else {
            Section {
                Button("Open", systemImage: "arrow.right.circle.fill") {
                    IOSHaptics.shared.tap()
                    onOpenDoc(doc.id)
                }
                Button(doc.isStarred ? "Unstar" : "Star", systemImage: doc.isStarred ? "star.slash" : "star") {
                    IOSHaptics.shared.toggle()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.toggleStarDocument(docId: doc.id)
                    }
                }
                Button(doc.isLocked ? "Unlock / Re-lock" : "Lock with PIN", systemImage: doc.isLocked ? "lock.open" : "lock") {
                    IOSHaptics.shared.tap()
                    store.requestToggleLock(for: doc.id)
                }
            }
            Section {
                Menu("Move to Folder", systemImage: "folder") {
                    Button("All Docs (None)", systemImage: doc.folderId == nil ? "checkmark" : "tray") {
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.moveDocument(docId: doc.id, toFolderId: nil)
                        }
                    }
                    ForEach(store.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                        Button(folder.name, systemImage: doc.folderId == folder.id ? "checkmark" : folder.iconName) {
                            withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                store.moveDocument(docId: doc.id, toFolderId: folder.id)
                            }
                        }
                    }
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    IOSHaptics.shared.tap()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.duplicateDocument(docId: doc.id)
                    }
                }
                Button("Copy Title", systemImage: "doc.on.doc") {
                    IOSHaptics.shared.tap()
                    UIPasteboard.general.string = doc.displayTitle
                }
            }
            Section {
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    IOSHaptics.shared.destructive()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.moveDocumentToTrash(docId: doc.id)
                    }
                }
            }
        }
    }

    private func listRow(_ doc: RoweDocument) -> some View {
        Button { handleTap(doc) } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selectedIds.contains(doc.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selectedIds.contains(doc.id) ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if doc.isLocked {
                            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.orange)
                        }
                        if doc.isStarred {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        }
                        Text(doc.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(doc.previewSnippet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(doc.updatedAt.craftRelativeString)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "doc-\(doc.id)", in: zoomNamespace)
        .contextMenu { documentContextMenu(doc) }
    }
}

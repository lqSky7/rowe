import SwiftUI
import UniformTypeIdentifiers
import RoweCore

struct WorkspaceSidebarView: View {
    @Bindable var store: WorkspaceStore
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isImportingMarkdown = false

    private var starredSection: SidebarSectionState {
        store.sidebarSections.first(where: { $0.type == .starred }) ?? SidebarSectionState(type: .starred)
    }
    private var foldersSection: SidebarSectionState {
        store.sidebarSections.first(where: { $0.type == .folders }) ?? SidebarSectionState(type: .folders)
    }
    private var tagsSection: SidebarSectionState {
        store.sidebarSections.first(where: { $0.type == .tags }) ?? SidebarSectionState(type: .tags)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                GlassCircleButton(systemImage: "sidebar.left", helpText: "Hide Sidebar (⌘[)", size: 30) {
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.toggleLeftSidebar()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if store.tabs.count > 1 {
                        SidebarTabsSection(store: store)

                        Divider()
                            .opacity(0.35)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                    }

                    sidebarActionRow(title: "New Document", icon: "doc.badge.plus", isSelected: false) {
                        store.createDocument()
                    }

                    Divider()
                        .opacity(0.35)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                    sidebarActionRow(title: "All Docs", icon: "doc.text", isSelected: store.currentDestination == .allDocs) {
                        store.navigate(to: .allDocs)
                    }
                    sidebarActionRow(title: "Tasks", icon: "checkmark.circle", isSelected: store.currentDestination == .tasks) {
                        store.navigate(to: .tasks)
                    }
                    sidebarActionRow(title: "Calendar", icon: "calendar", isSelected: store.currentDestination == .calendar) {
                        store.navigate(to: .calendar)
                    }

                    Divider()
                        .opacity(0.35)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                    sidebarActionRow(title: "Connections", icon: "cloud", isSelected: store.currentDestination == .connections) {
                        store.navigate(to: .connections)
                    }
                    sidebarActionRow(title: "Shared with Me", icon: "person.2.wave.2", isSelected: store.currentDestination == .sharedWithMe) {
                        store.navigate(to: .sharedWithMe)
                    }

                    // Starred (drag to reorder, right-click to unstar)
                    sectionHeader("Starred", type: .starred, isCollapsed: starredSection.isCollapsed)
                    if !starredSection.isCollapsed {
                        let starred = store.documents.filter { $0.isStarred && !$0.isTrashed }
                        if starred.isEmpty {
                            Text("Star key documents for quick access")
                                .font(.system(size: 11.5))
                                .italic()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                        } else {
                            ForEach(starred) { doc in
                                sidebarActionRow(
                                    title: doc.displayTitle,
                                    icon: "star.fill",
                                    iconColor: .yellow,
                                    isSelected: store.currentDestination == .document(doc.id)
                                ) {
                                    store.navigate(to: .document(doc.id))
                                }
                                .draggable("starred:\(doc.id)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("starred:") else { return false }
                                    let sourceId = String(raw.dropFirst("starred:".count))
                                    HapticsManager.shared.boundarySnap()
                                    store.reorderStarredDocument(sourceId: sourceId, targetId: doc.id)
                                    return true
                                }
                                .contextMenu {
                                    Button("Open in New Tab") { store.openNewTab(destination: .document(doc.id)) }
                                    Button("Unpin from Starred") {
                                        HapticsManager.shared.toggle()
                                        store.toggleStarDocument(docId: doc.id)
                                    }
                                }
                            }
                        }
                    }

                    // Folders (drag to reorder, right-click to delete)
                    HStack {
                        sectionHeader("Folders", type: .folders, isCollapsed: foldersSection.isCollapsed)
                        Spacer()
                        GlassCircleButton(systemImage: "plus", helpText: "New Folder", size: 22, iconSize: 10) {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                isCreatingFolder.toggle()
                            }
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 10)
                    }

                    if isCreatingFolder {
                        HStack(spacing: 6) {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit {
                                    store.createFolder(name: newFolderName)
                                    newFolderName = ""
                                    isCreatingFolder = false
                                }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }

                    if !foldersSection.isCollapsed {
                        ForEach(store.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                            sidebarFolderRow(folder)
                                .draggable("folder:\(folder.id)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("folder:") else { return false }
                                    let sourceId = String(raw.dropFirst("folder:".count))
                                    HapticsManager.shared.boundarySnap()
                                    store.reorderFolder(sourceId: sourceId, targetId: folder.id)
                                    return true
                                }
                                .contextMenu {
                                    Button("Delete Folder", role: .destructive) {
                                        HapticsManager.shared.destructive()
                                        store.deleteFolder(id: folder.id)
                                    }
                                }
                        }
                    }

                    // Tags (drag to reorder, right-click to unpin)
                    sectionHeader("Tags", type: .tags, isCollapsed: tagsSection.isCollapsed)
                    if !tagsSection.isCollapsed {
                        let pinned = store.tags.filter(\.isPinned)
                        if pinned.isEmpty {
                            Text("Pin your key tags for quick access")
                                .font(.system(size: 11.5))
                                .italic()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                        } else {
                            ForEach(pinned) { tag in
                                sidebarActionRow(
                                    title: tag.name,
                                    icon: "number",
                                    isSelected: store.currentDestination == .tag(tag.name)
                                ) {
                                    store.navigate(to: .tag(tag.name))
                                }
                                .draggable("tag:\(tag.id)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("tag:") else { return false }
                                    let sourceId = String(raw.dropFirst("tag:".count))
                                    HapticsManager.shared.boundarySnap()
                                    store.reorderTag(sourceId: sourceId, targetId: tag.id)
                                    return true
                                }
                                .contextMenu {
                                    Button("Unpin Tag") {
                                        HapticsManager.shared.toggle()
                                        store.unpinTag(id: tag.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.28).padding(.horizontal, 14)

            spaceHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            bottomUtilityBar
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
        .fileImporter(
            isPresented: $isImportingMarkdown,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let name = url.deletingPathExtension().lastPathComponent
                Task {
                    await store.importMarkdownFile(content: text, filename: name)
                }
            }
        }
    }

    private var spaceHeader: some View {
        HStack(spacing: 8) {
            SpaceAvatarView(space: store.space, size: 24, cornerRadius: 7)
            Text(store.space.name)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticsManager.shared.tap()
            store.navigate(to: .settings)
        }
    }

    private func sectionHeader(_ title: String, type: SidebarSectionType, isCollapsed: Bool) -> some View {
        Button {
            HapticsManager.shared.toggle()
            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                store.toggleSidebarSection(type)
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarActionRow(
        title: String,
        icon: String,
        iconColor: Color = .secondary,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Color.primary : iconColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarFolderRow(_ folder: Folder) -> some View {
        let isSelected = store.currentDestination == .folder(folder.id)
        return Button {
            HapticsManager.shared.tap()
            store.navigate(to: .folder(folder.id))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Image(systemName: folder.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(folder.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomUtilityBar: some View {
        HStack(spacing: 14) {
            Button {
                HapticsManager.shared.tap()
                store.navigate(to: .trash)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(store.currentDestination == .trash ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Trash")

            Button {
                HapticsManager.shared.tap()
                let panel = NSOpenPanel()
                panel.title = "Import from Craft or Markdown"
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK, !panel.urls.isEmpty {
                    let urls = panel.urls
                    Task { _ = await store.importCraftExport(from: urls) }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Import from Craft / Markdown")

            Button {
                HapticsManager.shared.tap()
                store.navigate(to: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(store.currentDestination == .settings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")

            Button {
                HapticsManager.shared.tap()
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    if store.isSignedIn {
                        store.selectedSettingsSectionId = SettingsCategory.account.rawValue
                        store.navigate(to: .settings)
                    } else {
                        store.isLoginSheetPresented = true
                    }
                }
            } label: {
                Image(systemName: store.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(store.isSignedIn ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(store.isSignedIn ? "Signed in (\(store.authSession?.user.email ?? ""))" : "Sign In / Sync Account")

            Spacer()

            Button {
                HapticsManager.shared.tap()
                store.isQuickOpenPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quick Open (⌘O)")
        }
    }
}

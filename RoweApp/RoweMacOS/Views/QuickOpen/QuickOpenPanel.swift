import AppKit
import SwiftUI
import RoweCore

private enum QuickOpenItem: Identifiable {
    case searchHit(GlobalSearchHit)
    case recentDoc(RoweDocument)
    case createDoc(String)
    case createTask(String)
    case newDocument

    var id: String {
        switch self {
        case .searchHit(let h): return "hit-\(h.id)"
        case .recentDoc(let d): return "doc-\(d.id)"
        case .createDoc(let q): return "create-doc-\(q)"
        case .createTask(let q): return "create-task-\(q)"
        case .newDocument: return "action-new-doc"
        }
    }
}

/// Global Cmd+K contextual search palette powered by SearchIndexActor's inverted index,
/// LRU cache, and 3-tier deepening (Current View -> Related -> Everything).
struct QuickOpenPanel: View {
    @Bindable var store: WorkspaceStore
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var keyMonitor: Any?
    @FocusState private var isFocused: Bool

    private var contextDisplayName: String {
        store.tabTitle(for: store.currentDestination)
    }

    private var items: [QuickOpenItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var list: [QuickOpenItem] = [.newDocument]
            list.append(contentsOf: store.documents.filter { !$0.isTrashed }.prefix(8).map { .recentDoc($0) })
            return list
        }

        var list: [QuickOpenItem] = store.contextualSearchResponse.hits.map { .searchHit($0) }
        if list.isEmpty {
            list.append(.createDoc(trimmed))
            list.append(.createTask(trimmed))
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                TextField("Search \(contextDisplayName) or anything…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit {
                        activateSelected()
                    }
                Button {
                    HapticsManager.shared.tap()
                    store.isQuickOpenPresented = false
                } label: {
                    Text("ESC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(14)

            // Context & search depth status strip
            HStack(spacing: 8) {
                Label("Context: \(contextDisplayName)", systemImage: "scope")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let reached = store.contextualSearchResponse.reachedDepth
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Depth: \(reached.label)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(reached == .currentView ? Color.accentColor : .secondary)

                    if store.contextualSearchResponse.servedFromCache {
                        Text("Cached")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }

                Spacer()

                Text("Max: \(store.settings.searchMaxDepth.label)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        let currentItems = items
                        ForEach(Array(currentItems.enumerated()), id: \.element.id) { idx, item in
                            rowView(for: item, isSelected: idx == selectedIndex)
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering { selectedIndex = idx }
                                }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 370)
                .onChange(of: selectedIndex) { _, newIdx in
                    let currentItems = items
                    if newIdx >= 0 && newIdx < currentItems.count {
                        proxy.scrollTo(currentItems[newIdx].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 560)
        .roweGlassRoundedRect(radius: 18)
        .onAppear {
            selectedIndex = 0
            installKeyMonitor()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 40_000_000)
                isFocused = true
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            store.performContextualSearch(query: newValue)
        }
    }

    @ViewBuilder
    private func rowView(for item: QuickOpenItem, isSelected: Bool) -> some View {
        switch item {
        case .searchHit(let hit):
            quickJumpRow(
                hit.title,
                icon: iconForHit(hit.kind),
                subtitle: hit.subtitle,
                badge: hit.scopeLabel,
                isPrimaryScope: hit.depthTier == .currentView,
                isSelected: isSelected
            ) {
                activate(item)
            }
        case .recentDoc(let doc):
            quickJumpRow(doc.displayTitle, icon: "doc.text", subtitle: doc.previewSnippet, badge: nil, isPrimaryScope: false, isSelected: isSelected) {
                activate(item)
            }
        case .createDoc(let title):
            quickJumpRow("Create \"\(title)\"", icon: "plus.circle", subtitle: "New document with this title", badge: nil, isPrimaryScope: false, isSelected: isSelected) {
                activate(item)
            }
        case .createTask(let title):
            quickJumpRow("Add Task: \"\(title)\"", icon: "checkmark.square", subtitle: "Schedule for Today in Inbox", badge: nil, isPrimaryScope: false, isSelected: isSelected) {
                activate(item)
            }
        case .newDocument:
            quickJumpRow("New Document", icon: "doc.badge.plus", subtitle: "Create blank page", badge: "⌘N", isPrimaryScope: false, isSelected: isSelected) {
                activate(item)
            }
        }
    }

    private func iconForHit(_ kind: GlobalSearchHitKind) -> String {
        switch kind {
        case .document: return "doc.text"
        case .block: return "text.alignleft"
        case .task: return "checkmark.square"
        case .folder: return "folder"
        case .tag: return "number"
        case .connection: return "cloud"
        case .sharedDocument: return "person.2"
        case .settingsSection: return "gearshape"
        }
    }

    private func quickJumpRow(
        _ title: String,
        icon: String,
        subtitle: String,
        badge: String?,
        isPrimaryScope: Bool,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: isPrimaryScope ? .semibold : .regular))
                        .foregroundStyle(isPrimaryScope ? Color.accentColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule().fill(isPrimaryScope ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.11) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activateSelected() {
        let current = items
        guard !current.isEmpty else { return }
        let idx = min(max(0, selectedIndex), current.count - 1)
        activate(current[idx])
    }

    private func activate(_ item: QuickOpenItem) {
        HapticsManager.shared.tap()
        store.isQuickOpenPresented = false
        switch item {
        case .searchHit(let hit):
            switch hit.kind {
            case .document(let docId):
                store.navigate(to: .document(docId))
            case .block(let docId, let blockId):
                store.navigate(to: .document(docId))
                store.activeBlockId = blockId
            case .task(let docId, let blockId):
                if let resolved = store.allTasks().first(where: { $0.documentId == docId && $0.block.id == blockId }) {
                    store.activeTaskEditor = .edit(resolved)
                } else {
                    store.navigate(to: .document(docId))
                }
            case .folder(let folderId):
                store.navigate(to: .folder(folderId))
            case .tag(let name):
                store.navigate(to: .tag(name))
            case .connection:
                store.navigate(to: .connections)
            case .sharedDocument:
                store.navigate(to: .sharedWithMe)
            case .settingsSection(let sectionId):
                store.selectedSettingsSectionId = sectionId
                store.navigate(to: .settings)
            }
        case .recentDoc(let doc):
            store.navigate(to: .document(doc.id))
        case .createDoc(let title):
            store.createDocument(title: title)
        case .createTask(let title):
            _ = store.addInboxTask(title: title, scheduleDate: Calendar.current.startOfDay(for: Date()))
        case .newDocument:
            store.createDocument()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                HapticsManager.shared.tap()
                store.isQuickOpenPresented = false
                return nil
            case 126: // Up Arrow
                let count = items.count
                if count > 0 {
                    selectedIndex = (selectedIndex - 1 + count) % count
                    HapticsManager.shared.tap()
                }
                return nil
            case 125: // Down Arrow
                let count = items.count
                if count > 0 {
                    selectedIndex = (selectedIndex + 1) % count
                    HapticsManager.shared.tap()
                }
                return nil
            case 36, 76: // Return / Enter
                activateSelected()
                return nil
            default:
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
}

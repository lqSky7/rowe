import SwiftUI
import RoweCore

enum DocumentSidebarTab: String, CaseIterable, Hashable {
    case toc
    case tasks
    case calendar
    case attachments
    case find

    var icon: String {
        switch self {
        case .toc: "list.bullet"
        case .tasks: "checkmark.circle"
        case .calendar: "calendar"
        case .attachments: "paperclip"
        case .find: "doc.text.magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .toc: "Table of Contents"
        case .tasks: "Doc Tasks"
        case .calendar: "Calendar Tasks"
        case .attachments: "Attachments"
        case .find: "Find"
        }
    }
}

struct DocumentSidebarView: View {
    @Bindable var store: WorkspaceStore
    let document: RoweDocument
    @Binding var selectedTab: DocumentSidebarTab
    var onScrollToBlock: (String) -> Void

    @State private var findQuery: String = ""
    @State private var searchOptions = SearchOptions()
    @State private var currentMatchIndex: Int = 0
    @State private var showFindOptionsPopover = false
    @State private var showTabsDrawer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topNavigationRow
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .padding(.bottom, 8)

            headerCard
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider().opacity(0.3).padding(.horizontal, 14)

            LiquidGlassSegmentedControl(
                items: DocumentSidebarTab.allCases,
                selection: $selectedTab,
                height: 34,
                systemImage: \.icon,
                accessibilityLabel: \.title
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch selectedTab {
                    case .toc:
                        tableOfContentsBody
                    case .tasks:
                        tasksBody
                    case .calendar:
                        calendarTasksBody
                    case .attachments:
                        attachmentsBody
                    case .find:
                        findBody
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)
        }
    }

    private var topNavigationRow: some View {
        HStack(spacing: 8) {
            Spacer()

            GlassCircleButton(systemImage: "sidebar.left", helpText: "Hide Sidebar (⌘[)", size: 32) {
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    store.toggleLeftSidebar()
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: document.blocks.contains(where: { $0.kind == .objectList || $0.kind == .table }) ? "tablecells" : "doc.text")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(document.updatedAt.craftRelativeString)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var tableOfContentsBody: some View {
        Text("Table of Contents")
            .font(.system(size: 13, weight: .semibold))

        let headings = document.blocks.filter(\.isHeadingForTOC)
        if headings.isEmpty {
            Text("Use titles, pages or cards to create a table of contents.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(headings) { block in
                    Button {
                        HapticsManager.shared.tap()
                        onScrollToBlock(block.id)
                    } label: {
                        HStack(spacing: 6) {
                            if block.textStyle == .pageRegular || block.textStyle == .pageCard {
                                Image(systemName: "doc.plaintext")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text(block.content.isEmpty ? "Untitled Section" : block.content)
                                .font(.system(size: 12.5, weight: block.textStyle == .title ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.leading, block.textStyle == .heading ? 12 : (block.textStyle == .subtitle ? 6 : 0))
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tasksBody: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }

        let tasks = document.blocks.filter(\.isTask)
        if tasks.isEmpty {
            Text("Tasks inside this document will appear here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tasks) { block in
                    let state = block.task?.state ?? .pending
                    HStack(alignment: .top, spacing: 8) {
                        TaskCheckboxControl(state: state) { newState in
                            store.setTaskState(docId: document.id, blockId: block.id, state: newState)
                        }
                        AnimatedStrikethroughText(
                            block.content.isEmpty ? "Untitled Task" : block.content,
                            isStruck: state != .pending,
                            font: .system(size: 12.5),
                            lineLimit: 2,
                            reduceMotion: store.settings.reduceAnimations
                        )
                        .onTapGesture {
                            onScrollToBlock(block.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var calendarTasksBody: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let all = store.allTasks().filter { ($0.block.task?.state ?? .pending) == .pending }
        let todayTasks = all.filter { item in
            guard let d = item.block.task?.scheduleDate else { return false }
            return cal.isDate(d, inSameDayAs: today)
        }
        let upcomingTasks = all.filter { item in
            guard let d = item.block.task?.scheduleDate else { return false }
            return d > today
        }

        HStack {
            Text("Calendar Tasks")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            GlassCircleButton(systemImage: "plus", helpText: "New Task (⌘J)", size: 22, iconSize: 10) {
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    store.activeTaskEditor = .create(defaultDate: today)
                }
            }
        }

        if todayTasks.isEmpty && upcomingTasks.isEmpty {
            Text("No pending calendar tasks. Press + or ⌘J to add one.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if !todayTasks.isEmpty {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(todayTasks) { item in
                    sidebarCalendarTaskRow(item)
                }
            }
            if !upcomingTasks.isEmpty {
                Text("Upcoming")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                ForEach(upcomingTasks.prefix(8)) { item in
                    sidebarCalendarTaskRow(item)
                }
            }
        }
    }

    private func sidebarCalendarTaskRow(_ item: ResolvedTaskItem) -> some View {
        let state = item.block.task?.state ?? .pending
        return HStack(alignment: .top, spacing: 8) {
            TaskCheckboxControl(state: state) { newState in
                store.setTaskState(docId: item.documentId, blockId: item.block.id, state: newState)
            }
            VStack(alignment: .leading, spacing: 2) {
                AnimatedStrikethroughText(
                    item.block.content.isEmpty ? "Untitled Task" : item.block.content,
                    isStruck: state != .pending,
                    font: .system(size: 12.5),
                    lineLimit: 2,
                    reduceMotion: store.settings.reduceAnimations
                )
                if let sched = item.block.task?.scheduleDate {
                    Text(sched.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .onTapGesture {
                HapticsManager.shared.tap()
                store.activeTaskEditor = .edit(item)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var attachmentsBody: some View {
        Text("Attachments")
            .font(.system(size: 13, weight: .semibold))

        let attachments = document.blocks.filter {
            $0.kind == .image || $0.kind == .file || $0.kind == .url || $0.kind == .video
        }
        if attachments.isEmpty {
            Text("Images, Links and Files added to this document will appear here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(attachments) { item in
                Button {
                    HapticsManager.shared.tap()
                    onScrollToBlock(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.kind == .url ? "link" : (item.kind == .image ? "photo" : "doc"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(item.fileName ?? item.urlString ?? item.content)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var findBody: some View {
        HStack {
            Text("Find")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                HapticsManager.shared.tap()
                showFindOptionsPopover.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFindOptionsPopover) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Regular Expression", isOn: $searchOptions.useRegex)
                    Toggle("Case Insensitive", isOn: $searchOptions.caseInsensitive)
                    Toggle("Ignore Diacritics", isOn: $searchOptions.diacriticsInsensitive)
                }
                .padding(12)
                .frame(width: 210)
            }
        }

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Text in document", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
        .roweGlassInput(cornerRadius: 11)
        .onChange(of: findQuery) { _, newValue in
            currentMatchIndex = 0
            store.performInDocumentFind(docId: document.id, query: newValue, options: searchOptions)
        }
        .onChange(of: searchOptions) { _, _ in
            currentMatchIndex = 0
            store.performInDocumentFind(docId: document.id, query: findQuery, options: searchOptions)
        }

        HStack {
            let count = store.inDocumentMatches.count
            Text(count == 0 ? "No results in doc" : "\(min(currentMatchIndex + 1, count)) of \(count) results")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                Button {
                    guard !store.inDocumentMatches.isEmpty else { return }
                    HapticsManager.shared.tap()
                    currentMatchIndex = (currentMatchIndex - 1 + store.inDocumentMatches.count) % store.inDocumentMatches.count
                    onScrollToBlock(store.inDocumentMatches[currentMatchIndex].blockId)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    guard !store.inDocumentMatches.isEmpty else { return }
                    HapticsManager.shared.tap()
                    currentMatchIndex = (currentMatchIndex + 1) % store.inDocumentMatches.count
                    onScrollToBlock(store.inDocumentMatches[currentMatchIndex].blockId)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }

        if !store.inDocumentMatches.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(store.inDocumentMatches.enumerated()), id: \.element.id) { idx, match in
                    Button {
                        HapticsManager.shared.tap()
                        currentMatchIndex = idx
                        onScrollToBlock(match.blockId)
                    } label: {
                        Text(match.preview)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(idx == currentMatchIndex ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

import SwiftUI
import UIKit
import RoweCore

enum IOSTab: Int, CaseIterable, Hashable {
    case home = 0
    case tasks = 1
    case calendar = 2

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checkmark.square.fill"
        case .calendar: "calendar"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        }
    }
}

enum IOSRoute: Hashable {
    case allDocs(folderId: String?, title: String, isTrash: Bool)
    case document(String)
    case settings
    case connections
    case sharedWithMe
}

/// Root iOS shell:
/// - Native `CompactTabBarController` (`UITabBarController`) with constrained `tabBar.frame`
///   to preserve native Liquid Glass material and droplet animations on bottom-left
/// - Floating Liquid Glass circular '+' button on bottom-right
/// - Full-screen GlassGlow Onboarding on first launch, plus Login & PIN Lock overlays.
struct IOSRootShellView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Bindable var store: WorkspaceStore

    @State private var selectedTab: IOSTab = .home
    @State private var homePath: [IOSRoute] = []
    @State private var tasksPath: [IOSRoute] = []
    @State private var calendarPath: [IOSRoute] = []
    @State private var showQuickAddSheet = false
    @State private var quickAddDefaultDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var editingTaskItem: ResolvedTaskItem? = nil
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "rowe.hasCompletedOnboarding")

    private var preferredScheme: ColorScheme? {
        switch store.settings.appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var resolvedAccent: Color {
        if store.settings.accentColor == .graphite && (preferredScheme ?? systemColorScheme) == .dark {
            return Color(hex: "#F3F4F6")
        }
        return Color(hex: store.settings.accentColor.hex)
    }

    private var activePath: [IOSRoute] {
        switch selectedTab {
        case .home: homePath
        case .tasks: tasksPath
        case .calendar: calendarPath
        }
    }

    private var isInsideDocument: Bool {
        if case .document = activePath.last { return true }
        return false
    }

    private var isInsideSettings: Bool {
        if case .settings = activePath.last { return true }
        return false
    }

    private var shouldHideBottomControls: Bool {
        isInsideDocument || isInsideSettings
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CompactTabBarContainer(
                store: store,
                selectedTab: $selectedTab,
                homePath: $homePath,
                tasksPath: $tasksPath,
                calendarPath: $calendarPath,
                hidesTabBar: shouldHideBottomControls,
                resolvedAccent: resolvedAccent,
                onOpenQuickAdd: { targetDate in
                    editingTaskItem = nil
                    quickAddDefaultDate = Calendar.current.startOfDay(for: targetDate ?? Date())
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showQuickAddSheet = true
                    }
                },
                onEditTask: { item in
                    editingTaskItem = item
                    quickAddDefaultDate = item.block.task?.scheduleDate ?? Calendar.current.startOfDay(for: Date())
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showQuickAddSheet = true
                    }
                },
                onReplayOnboarding: { showOnboarding = true }
            )
            .ignoresSafeArea()

            // Floating Liquid Glass '+' button aligned to the bottom alongside the iOS 26 tab bar pill
            if !shouldHideBottomControls {
                IOSGlassCircleButton(systemImage: "plus", size: 56, iconSize: 22) {
                    IOSKeyboard.dismiss()
                    if selectedTab == .calendar || selectedTab == .tasks {
                        editingTaskItem = nil
                        quickAddDefaultDate = Calendar.current.startOfDay(for: Date())
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showQuickAddSheet = true
                        }
                    } else {
                        let doc = store.createDocument(openImmediately: false)
                        homePath.append(.document(doc.id))
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, 17)
                .ignoresSafeArea(.container, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Unified Floating Task Composer (Create & Edit) above keyboard
            if showQuickAddSheet {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        IOSKeyboard.dismiss()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showQuickAddSheet = false
                            editingTaskItem = nil
                        }
                    }

                IOSQuickAddTaskCard(
                    store: store,
                    initialDate: quickAddDefaultDate,
                    editingItem: editingTaskItem
                ) {
                    IOSKeyboard.dismiss()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showQuickAddSheet = false
                        editingTaskItem = nil
                    }
                }
                .id(editingTaskItem?.id ?? "create-new-task")
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Global Contextual Search (pull-down from anywhere on iOS, matching macOS QuickOpenPanel)
            if store.isQuickOpenPresented {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        IOSKeyboard.dismiss()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.isQuickOpenPresented = false
                        }
                    }

                IOSQuickOpenView(
                    store: store,
                    resolvedAccent: resolvedAccent,
                    onNavigateRoute: { route, targetTab in
                        if let targetTab { selectedTab = targetTab }
                        switch selectedTab {
                        case .home: homePath.append(route)
                        case .tasks: tasksPath.append(route)
                        case .calendar: calendarPath.append(route)
                        }
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.roweConvergeUnblur)
            }
        }
        .preferredColorScheme(preferredScheme)
        .tint(resolvedAccent)
        .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: shouldHideBottomControls)
        .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: showQuickAddSheet)
        .overlay {
            if showOnboarding {
                RoweOnboardingView(
                    store: store,
                    onSignInRequested: { store.isLoginSheetPresented = true },
                    onFinish: {
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showOnboarding = false
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $store.isLoginSheetPresented) {
            IOSLoginSheet(store: store)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
        .sheet(item: $store.pinPromptRequest) { req in
            IOSPinLockSheet(store: store, request: req) {
                store.pinPromptRequest = nil
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(28)
        }
        .onChange(of: store.hasLoadedFromDisk) { _, loaded in
            if loaded && !store.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: store.settings.hasCompletedOnboarding) { _, completed in
            showOnboarding = !completed
        }
        .onAppear {
            IOSHaptics.shared.isEnabled = store.settings.enableHaptics
            if store.hasLoadedFromDisk && !store.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
}

// MARK: - Native UIKit Compact UITabBarController (No Private APIs)

final class CompactTabBarController: UITabBarController {
    var hidesCompactTabBar: Bool = false {
        didSet {
            if tabBar.isHidden != hidesCompactTabBar {
                tabBar.isHidden = hidesCompactTabBar
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.itemPositioning = .centered
        tabBar.itemSpacing = 22
        tabBar.itemWidth = 60
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .never
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Flush leading x=0 so iOS 26's built-in Liquid Glass pill inset aligns crisply (~18pt from left edge)
        let maxAvailable = max(210, view.bounds.width - 96)
        let targetWidth = min(max(244, view.bounds.width * 0.64), min(280, maxAvailable))
        let currentFrame = tabBar.frame
        let xPosition: CGFloat = 0

        tabBar.frame = CGRect(
            x: xPosition,
            y: currentFrame.origin.y,
            width: targetWidth,
            height: currentFrame.height
        )
    }
}

private struct CompactTabBarContainer: UIViewControllerRepresentable {
    @Bindable var store: WorkspaceStore
    @Binding var selectedTab: IOSTab
    @Binding var homePath: [IOSRoute]
    @Binding var tasksPath: [IOSRoute]
    @Binding var calendarPath: [IOSRoute]
    let hidesTabBar: Bool
    let resolvedAccent: Color
    let onOpenQuickAdd: (Date?) -> Void
    let onEditTask: (ResolvedTaskItem) -> Void
    let onReplayOnboarding: () -> Void

    @Namespace private var homeZoomNS
    @Namespace private var tasksZoomNS
    @Namespace private var calendarZoomNS

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CompactTabBarController {
        let controller = CompactTabBarController()
        controller.delegate = context.coordinator

        let homeVC = makeTabHostingController(tab: .home, rootView: AnyView(homeNavStack))
        let tasksVC = makeTabHostingController(tab: .tasks, rootView: AnyView(tasksNavStack))
        let calVC = makeTabHostingController(tab: .calendar, rootView: AnyView(calendarNavStack))

        controller.viewControllers = [homeVC, tasksVC, calVC]
        controller.selectedIndex = selectedTab.rawValue
        controller.tabBar.tintColor = UIColor(resolvedAccent)
        controller.hidesCompactTabBar = hidesTabBar
        return controller
    }

    func updateUIViewController(_ uiViewController: CompactTabBarController, context: Context) {
        context.coordinator.parent = self
        if uiViewController.selectedIndex != selectedTab.rawValue {
            uiViewController.selectedIndex = selectedTab.rawValue
        }
        uiViewController.tabBar.tintColor = UIColor(resolvedAccent)
        uiViewController.hidesCompactTabBar = hidesTabBar

        if let vcs = uiViewController.viewControllers, vcs.count == 3 {
            (vcs[0] as? UIHostingController<AnyView>)?.rootView = AnyView(homeNavStack)
            (vcs[1] as? UIHostingController<AnyView>)?.rootView = AnyView(tasksNavStack)
            (vcs[2] as? UIHostingController<AnyView>)?.rootView = AnyView(calendarNavStack)
        }
    }

    private func makeTabHostingController(tab: IOSTab, rootView: AnyView) -> UIHostingController<AnyView> {
        let vc = UIHostingController(rootView: rootView)
        let item = UITabBarItem(title: nil, image: UIImage(systemName: tab.icon), tag: tab.rawValue)
        item.accessibilityLabel = tab.label
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        vc.tabBarItem = item
        return vc
    }

    private var homeNavStack: some View {
        NavigationStack(path: $homePath) {
            IOSHomeView(
                store: store,
                zoomNamespace: homeZoomNS,
                onOpenDoc: { id in homePath.append(.document(id)) },
                onOpenAllDocs: { folderId, title, isTrash in
                    homePath.append(.allDocs(folderId: folderId, title: title, isTrash: isTrash))
                },
                onOpenSettings: { homePath.append(.settings) },
                onOpenConnections: { homePath.append(.connections) },
                onOpenShared: { homePath.append(.sharedWithMe) }
            )
            .navigationDestination(for: IOSRoute.self) { route in
                destinationView(for: route, path: $homePath, zoomNS: homeZoomNS)
            }
            .background(IOSSwipeBackEnabler().frame(width: 0, height: 0))
        }
    }

    private var tasksNavStack: some View {
        NavigationStack(path: $tasksPath) {
            IOSCalendarTasksView(
                store: store,
                mode: .allTasks,
                zoomNamespace: tasksZoomNS,
                onOpenSettings: { tasksPath.append(.settings) },
                onOpenQuickAdd: onOpenQuickAdd,
                onEditTask: onEditTask
            )
            .navigationDestination(for: IOSRoute.self) { route in
                destinationView(for: route, path: $tasksPath, zoomNS: tasksZoomNS)
            }
            .background(IOSSwipeBackEnabler().frame(width: 0, height: 0))
        }
    }

    private var calendarNavStack: some View {
        NavigationStack(path: $calendarPath) {
            IOSCalendarTasksView(
                store: store,
                mode: .calendar,
                zoomNamespace: calendarZoomNS,
                onOpenSettings: { calendarPath.append(.settings) },
                onOpenQuickAdd: onOpenQuickAdd,
                onEditTask: onEditTask
            )
            .navigationDestination(for: IOSRoute.self) { route in
                destinationView(for: route, path: $calendarPath, zoomNS: calendarZoomNS)
            }
            .background(IOSSwipeBackEnabler().frame(width: 0, height: 0))
        }
    }

    @ViewBuilder
    private func destinationView(for route: IOSRoute, path: Binding<[IOSRoute]>, zoomNS: Namespace.ID) -> some View {
        switch route {
        case .allDocs(let folderId, let title, let isTrash):
            let srcId = isTrash ? "row-trash" : (folderId.map { "folder-\($0)" } ?? "row-alldocs")
            IOSAllDocsView(
                store: store,
                filterTitle: title,
                folderId: folderId,
                isTrashMode: isTrash,
                zoomNamespace: zoomNS,
                onOpenDoc: { id in path.wrappedValue.append(.document(id)) }
            )
            .navigationTransition(.zoom(sourceID: srcId, in: zoomNS))
        case .document(let docId):
            Group {
                if let doc = store.documents.first(where: { $0.id == docId }) {
                    IOSDocumentEditorView(store: store, document: doc)
                        .onDisappear {
                            store.pruneEmptyDocumentIfNeeded(docId: docId)
                        }
                } else {
                    ContentUnavailableView("Document Not Found", systemImage: "doc.questionmark")
                }
            }
            .navigationTransition(.zoom(sourceID: "doc-\(docId)", in: zoomNS))
        case .settings:
            IOSSettingsView(store: store, onReplayOnboarding: onReplayOnboarding)
                .navigationTransition(.zoom(sourceID: "settings-avatar", in: zoomNS))
        case .connections:
            IOSConnectionsView(store: store)
                .navigationTransition(.zoom(sourceID: "row-connections", in: zoomNS))
        case .sharedWithMe:
            IOSSharedPlaceholderView(store: store)
                .navigationTransition(.zoom(sourceID: "row-shared", in: zoomNS))
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: CompactTabBarContainer
        init(parent: CompactTabBarContainer) { self.parent = parent }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            IOSHaptics.shared.toggle()
            IOSKeyboard.dismiss()
            if let tab = IOSTab(rawValue: tabBarController.selectedIndex) {
                parent.selectedTab = tab
            }
        }
    }
}



private struct IOSSharedPlaceholderView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        List {
            if store.sharedDocuments.isEmpty {
                VStack(spacing: 14) {
                    RoweEmptyStateArtwork(
                        kind: .sharedSpace,
                        accent: Color(hex: store.settings.accentColor.hex),
                        size: 92
                    )
                    Text("No Shared Docs")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Documents shared with your space will appear here.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.sharedDocuments) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text("Shared by \(item.sharedByName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Shared with Me")
    }
}

// MARK: - Ported Global Contextual Search (QuickOpenPanel parity)

private enum IOSQuickOpenItem: Identifiable {
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

private struct IOSQuickOpenView: View {
    @Bindable var store: WorkspaceStore
    let resolvedAccent: Color
    var onNavigateRoute: (IOSRoute, IOSTab?) -> Void

    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    private var contextDisplayName: String {
        store.tabTitle(for: store.currentDestination)
    }

    private var items: [IOSQuickOpenItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var list: [IOSQuickOpenItem] = [.newDocument]
            list.append(contentsOf: store.documents.filter { !$0.isTrashed }.prefix(8).map { .recentDoc($0) })
            return list
        }
        var list: [IOSQuickOpenItem] = store.contextualSearchResponse.hits.map { .searchHit($0) }
        if list.isEmpty {
            list.append(.createDoc(trimmed))
            list.append(.createTask(trimmed))
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.24))
                .frame(width: 38, height: 4.5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(resolvedAccent)

                TextField("Search \(contextDisplayName) or anything…", text: $query)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if let first = items.first { activate(first) }
                    }

                Menu {
                    Section("Maximum Search Depth") {
                        ForEach(SearchMaxDepth.allCases, id: \.self) { depth in
                            Button {
                                store.updateSettings { $0.searchMaxDepth = depth }
                                store.performContextualSearch(query: query)
                            } label: {
                                Label(depth.label, systemImage: store.settings.searchMaxDepth == depth ? "checkmark" : "")
                            }
                        }
                    }
                    Toggle("Auto-Deepen", isOn: Binding(
                        get: { store.settings.searchAutoDeepen },
                        set: { val in
                            store.updateSettings { $0.searchAutoDeepen = val }
                            store.performContextualSearch(query: query)
                        }
                    ))
                    Button("Clear Query Cache", systemImage: "trash") {
                        store.clearSearchCache()
                    }
                    Button("Rebuild Index", systemImage: "arrow.clockwise") {
                        store.rebuildSearchIndex()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }

                Button {
                    if !query.isEmpty {
                        query = ""
                    } else {
                        dismissSearch()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.10)))
                }
                .buttonStyle(RowePressScaleStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.25)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        rowView(for: item)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.2)

            HStack(spacing: 8) {
                Label("Context: \(contextDisplayName)", systemImage: "scope")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                let activeLabel = query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? store.settings.searchMaxDepth.label
                    : store.contextualSearchResponse.reachedDepth.label
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(activeLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !query.trimmingCharacters(in: .whitespaces).isEmpty && store.contextualSearchResponse.servedFromCache {
                    Text("Cached")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .roweIOSGlassRoundedRect(radius: 26, interactive: true)
        .iosDragToDismiss { dismissSearch() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { isFocused = true }
        }
        .onChange(of: query) { _, newValue in
            store.performContextualSearch(query: newValue)
        }
    }

    private func dismissSearch() {
        IOSKeyboard.dismiss()
        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
            store.isQuickOpenPresented = false
        }
    }

    @ViewBuilder
    private func rowView(for item: IOSQuickOpenItem) -> some View {
        switch item {
        case .searchHit(let hit):
            searchRow(
                hit.title,
                icon: iconForHit(hit.kind),
                subtitle: hit.subtitle,
                badge: hit.scopeLabel,
                isPrimaryScope: hit.depthTier == .currentView
            ) { activate(item) }
        case .recentDoc(let doc):
            searchRow(doc.displayTitle, icon: "doc.text", subtitle: doc.previewSnippet, badge: nil, isPrimaryScope: false) {
                activate(item)
            }
        case .createDoc(let title):
            searchRow("Create \"\(title)\"", icon: "plus.circle", subtitle: "New document with this title", badge: nil, isPrimaryScope: false) {
                activate(item)
            }
        case .createTask(let title):
            searchRow("Add Task: \"\(title)\"", icon: "checkmark.square", subtitle: "Schedule for Today in Inbox", badge: nil, isPrimaryScope: false) {
                activate(item)
            }
        case .newDocument:
            searchRow("New Document", icon: "doc.badge.plus", subtitle: "Create blank page", badge: nil, isPrimaryScope: false) {
                activate(item)
            }
        }
    }

    private func iconForHit(_ kind: GlobalSearchHitKind) -> String {
        switch kind {
        case .document: "doc.text"
        case .block: "text.alignleft"
        case .task: "checkmark.square"
        case .folder: "folder"
        case .tag: "number"
        case .connection: "cloud"
        case .sharedDocument: "person.2"
        case .settingsSection: "gearshape"
        }
    }

    private func searchRow(_ title: String, icon: String, subtitle: String, badge: String?, isPrimaryScope: Bool, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isPrimaryScope ? resolvedAccent : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: isPrimaryScope ? .semibold : .regular))
                        .foregroundStyle(isPrimaryScope ? resolvedAccent : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(isPrimaryScope ? resolvedAccent.opacity(0.14) : Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowePressScaleStyle())
    }

    private func activate(_ item: IOSQuickOpenItem) {
        IOSHaptics.shared.tap()
        dismissSearch()
        switch item {
        case .searchHit(let hit):
            switch hit.kind {
            case .document(let docId):
                onNavigateRoute(.document(docId), nil)
            case .block(let docId, let blockId):
                store.activeBlockId = blockId
                onNavigateRoute(.document(docId), nil)
            case .task(let docId, _):
                onNavigateRoute(.document(docId), nil)
            case .folder(let folderId):
                let name = store.folders.first(where: { $0.id == folderId })?.name ?? "Folder"
                onNavigateRoute(.allDocs(folderId: folderId, title: name, isTrash: false), .home)
            case .tag(let name):
                onNavigateRoute(.allDocs(folderId: nil, title: "#\(name)", isTrash: false), .home)
            case .connection:
                onNavigateRoute(.connections, .home)
            case .sharedDocument:
                onNavigateRoute(.sharedWithMe, .home)
            case .settingsSection:
                onNavigateRoute(.settings, nil)
            }
        case .recentDoc(let doc):
            onNavigateRoute(.document(doc.id), nil)
        case .createDoc(let title):
            let doc = store.createDocument(title: title, openImmediately: false)
            onNavigateRoute(.document(doc.id), nil)
        case .createTask(let title):
            _ = store.addInboxTask(title: title, scheduleDate: Calendar.current.startOfDay(for: Date()))
        case .newDocument:
            let doc = store.createDocument(openImmediately: false)
            onNavigateRoute(.document(doc.id), nil)
        }
    }
}

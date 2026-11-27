import AppKit
import SwiftUI
import RoweCore

/// Main desktop window shell with sidebar-managed vertical tabs (maximizing vertical
/// canvas space) and Craft's tiered resizable left sidebar (200pt min, 152-200pt snap,
/// 280/400pt caps across 640/880pt breakpoints).
struct CraftWindowShell: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Bindable var store: WorkspaceStore
    @State private var inspectorTab: InspectorTab = .info
    @State private var documentSidebarTab: DocumentSidebarTab = .toc
    @State private var scrollTargetBlockId: String?
    @State private var dragStartSidebarWidth: Double?
    @State private var globalKeyMonitor: Any?
    @State private var sidebarPage: Int = 1
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "rowe.hasCompletedOnboarding")

    private var isDarkAppearance: Bool {
        switch store.settings.appearanceMode {
        case .light: false
        case .dark: true
        case .system: systemColorScheme == .dark
        }
    }

    private func applyAppAppearance(_ mode: AppearanceMode) {
        let target: NSAppearance? = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = target
        for window in NSApp.windows {
            window.appearance = target
        }
    }

    /// Uses high-contrast accent shades in Light Mode and calm pastels in Dark Mode.
    private var resolvedAccentColor: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: isDarkAppearance))
    }

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let appliedSidebarWidth = computeAppliedSidebarWidth(containerWidth: containerWidth)
            let sidebarShown = store.isLeftSidebarVisible && !store.isFocusMode && appliedSidebarWidth > 0

            ZStack(alignment: .topLeading) {
                RoweWindowConfigurator(hideTrafficLights: !sidebarShown)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    if sidebarShown {
                        ZStack(alignment: .trailing) {
                            leftSidebarContent
                                .frame(width: appliedSidebarWidth)
                                .background(MacSidebarBackdrop())

                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 6)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                        .onChanged { value in
                                            if dragStartSidebarWidth == nil {
                                                dragStartSidebarWidth = store.leftSidebarWidth
                                            }
                                            let proposed = (dragStartSidebarWidth ?? 240) + value.translation.width
                                            applySidebarResize(proposed: proposed, containerWidth: containerWidth)
                                        }
                                        .onEnded { _ in
                                            dragStartSidebarWidth = nil
                                        }
                                )
                        }
                        .ignoresSafeArea(edges: .top)
                    }

                    ZStack {
                        mainContentRouter
                            .id(store.currentDestination)
                            .transition(.opacity)
                    }
                    .animation(
                        store.settings.reduceAnimations ? .linear(duration: 0.08) : .easeInOut(duration: 0.18),
                        value: store.currentDestination
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 8)
                    .padding(.leading, sidebarShown ? 0 : 8)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(edges: .top)

                // Floating glass sidebar-reopen button aligned dead-level with top bar buttons
                if !sidebarShown && !store.isFocusMode {
                    GlassCircleButton(systemImage: "sidebar.left", helpText: "Show Sidebar (⌘[)", size: 32) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.toggleLeftSidebar()
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 22)
                    .ignoresSafeArea(edges: .top)
                }

                if store.isQuickOpenPresented {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                store.isQuickOpenPresented = false
                            }
                        }

                    QuickOpenPanel(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.roweConvergeUnblur)
                }

                if let taskRequest = store.activeTaskEditor {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture { store.activeTaskEditor = nil }

                    TaskEditorPopover(store: store, request: taskRequest) {
                        store.activeTaskEditor = nil
                    }
                    .offset(x: 44, y: -56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.roweUnblur)
                }

                if store.isLoginSheetPresented {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { store.isLoginSheetPresented = false }

                    LoginModalView(store: store) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.isLoginSheetPresented = false
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.roweConvergeUnblur)
                }

                if let pinReq = store.pinPromptRequest {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { store.pinPromptRequest = nil }

                    PinLockSheet(store: store, request: pinReq) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.pinPromptRequest = nil
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.roweConvergeUnblur)
                }

                if showOnboarding {
                    RoweOnboardingView(
                        store: store,
                        onSignInRequested: {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                store.isLoginSheetPresented = true
                            }
                        },
                        onFinish: {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                showOnboarding = false
                            }
                        }
                    )
                    .ignoresSafeArea()
                    .transition(.roweConvergeUnblur)
                }
            }
        }
        .tint(resolvedAccentColor)
        .onChange(of: store.settings.appearanceMode) { _, mode in
            applyAppAppearance(mode)
        }
        .onChange(of: store.hasLoadedFromDisk) { _, loaded in
            if loaded {
                applyAppAppearance(store.settings.appearanceMode)
                if !store.settings.hasCompletedOnboarding {
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showOnboarding = true
                    }
                }
            }
        }
        .onChange(of: store.settings.hasCompletedOnboarding) { _, completed in
            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                showOnboarding = !completed
            }
        }
        .onAppear {
            applyAppAppearance(store.settings.appearanceMode)
            HapticsManager.shared.isEnabled = store.settings.enableHaptics
            SoundManager.shared.isEnabled = store.settings.enableSound
            RoweAppIconRenderer.applyDockIcon(
                variantIndex: store.settings.selectedAppIconIndex,
                accentHex: store.settings.accentColor.hex
            )
            if store.hasLoadedFromDisk && !store.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
            installGlobalShortcutMonitor()
            MacFocusTracker.shared.start(with: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.handleAppBecameActive()
        }
        .onDisappear {
            if let m = globalKeyMonitor {
                NSEvent.removeMonitor(m)
                globalKeyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private var leftSidebarContent: some View {
        if case .document(let docId) = store.currentDestination,
           let doc = store.documents.first(where: { $0.id == docId }) {
            ZStack(alignment: .bottom) {
                Group {
                    if sidebarPage == 0 {
                        WorkspaceSidebarView(store: store)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        DocumentSidebarView(
                            store: store,
                            document: doc,
                            selectedTab: $documentSidebarTab,
                            onScrollToBlock: { blockId in
                                scrollTargetBlockId = blockId
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 34)
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: sidebarPage)

                HStack(spacing: 9) {
                    ForEach(0..<2, id: \.self) { idx in
                        Circle()
                            .fill(sidebarPage == idx ? Color.primary.opacity(0.88) : Color.primary.opacity(0.28))
                            .frame(width: 7, height: 7)
                            .scaleEffect(sidebarPage == idx ? 1.15 : 1.0)
                            .onTapGesture {
                                HapticsManager.shared.tap()
                                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                    sidebarPage = idx
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .roweGlassCapsule(interactive: true)
                .contentShape(Capsule())
                .onTapGesture {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        sidebarPage = (sidebarPage == 0) ? 1 : 0
                    }
                }
                .padding(.bottom, 10)
                .help("Two-finger swipe or click to switch between Workspace & Document Sidebar")
            }
            .background(
                SidebarTwoFingerSwipeMonitor(
                    onSwipeToWorkspace: {
                        guard sidebarPage != 0 else { return }
                        HapticsManager.shared.tap()
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            sidebarPage = 0
                        }
                    },
                    onSwipeToDocument: {
                        guard sidebarPage != 1 else { return }
                        HapticsManager.shared.tap()
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            sidebarPage = 1
                        }
                    }
                )
                .allowsHitTesting(false)
            )
            .clipped()
        } else {
            WorkspaceSidebarView(store: store)
        }
    }

    @ViewBuilder
    private var mainContentRouter: some View {
        switch store.currentDestination {
        case .allDocs:
            AllDocsView(store: store, filterTitle: "All Docs")
        case .folder(let folderId):
            let name = store.folders.first(where: { $0.id == folderId })?.name ?? "Folder"
            AllDocsView(store: store, filterTitle: name, folderId: folderId)
        case .tag(let tagName):
            AllDocsView(store: store, filterTitle: "#\(tagName)", tagFilter: tagName)
        case .trash:
            AllDocsView(store: store, filterTitle: "Trash", isTrashMode: true)
        case .tasks:
            AllTasksView(store: store)
        case .calendar:
            CalendarTasksView(store: store)
        case .connections:
            ConnectionsView(store: store)
        case .sharedWithMe:
            SharedWithMeView(store: store)
        case .settings:
            SettingsView(store: store)
        case .document(let docId):
            if let doc = store.documents.first(where: { $0.id == docId }) {
                DocumentEditorView(
                    store: store,
                    document: doc,
                    inspectorTab: $inspectorTab,
                    documentSidebarTab: $documentSidebarTab,
                    scrollTargetBlockId: $scrollTargetBlockId
                )
            } else {
                AllDocsView(store: store, filterTitle: "All Docs")
            }
        }
    }

    /// Mirrors Craft's recovered LukiSplitViewController width tiering:
    /// <= 640 -> 0 cap, 640..<880 -> 280 cap, > 880 -> 400 cap.
    private func computeAppliedSidebarWidth(containerWidth: Double) -> Double {
        let cap: Double
        if containerWidth <= 640 {
            cap = 0
        } else if containerWidth <= 880 {
            cap = 280
        } else {
            cap = 400
        }
        guard cap > 0 else { return 0 }
        return min(max(200, store.leftSidebarWidth), cap)
    }

    private func applySidebarResize(proposed: Double, containerWidth: Double) {
        if proposed < 152 { return }
        let cap = containerWidth <= 880 ? 280.0 : 400.0
        let snapped: Double
        if proposed < 200 {
            if store.leftSidebarWidth != 200 {
                HapticsManager.shared.boundarySnap()
            }
            snapped = 200
        } else {
            snapped = min(proposed.rounded(), cap)
        }
        store.leftSidebarWidth = snapped
    }

    /// Guarantees ⌘[ (sidebar toggle) and ⌘L (new task on Calendar) fire reliably from any responder.
    private func installGlobalShortcutMonitor() {
        if let existing = globalKeyMonitor {
            NSEvent.removeMonitor(existing)
            globalKeyMonitor = nil
        }
        globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods == .command, (event.keyCode == 33 || event.charactersIgnoringModifiers == "[") {
                HapticsManager.shared.toggle()
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    store.toggleLeftSidebar()
                }
                return nil
            }
            if mods == .command, (event.keyCode == 37 || event.charactersIgnoringModifiers?.lowercased() == "l") {
                HapticsManager.shared.tap()
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    if store.activeTaskEditor != nil {
                        store.activeTaskEditor = nil
                    } else {
                        store.activeTaskEditor = .create(defaultDate: Calendar.current.startOfDay(for: Date()))
                    }
                }
                return nil
            }
            return event
        }
    }
}

/// Captures native macOS two-finger horizontal trackpad swipes over the sidebar
/// without interfering with vertical scrolling or momentum bounce.
private struct SidebarTwoFingerSwipeMonitor: NSViewRepresentable {
    var onSwipeToWorkspace: () -> Void
    var onSwipeToDocument: () -> Void

    func makeNSView(context: Context) -> SwipeCatcherView {
        let view = SwipeCatcherView()
        view.onSwipeToWorkspace = onSwipeToWorkspace
        view.onSwipeToDocument = onSwipeToDocument
        return view
    }

    func updateNSView(_ nsView: SwipeCatcherView, context: Context) {
        nsView.onSwipeToWorkspace = onSwipeToWorkspace
        nsView.onSwipeToDocument = onSwipeToDocument
    }

    static func dismantleNSView(_ nsView: SwipeCatcherView, coordinator: ()) {
        nsView.teardownMonitor()
    }

    final class SwipeCatcherView: NSView {
        var onSwipeToWorkspace: (() -> Void)?
        var onSwipeToDocument: (() -> Void)?
        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var didTriggerThisGesture = false
        private var lastTriggerUptime: TimeInterval = 0

        /// Never intercept clicks, hovers, or drags — only measure bounds for the scrollWheel monitor.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.handleScroll(event)
                    return event
                }
            } else if window == nil {
                teardownMonitor()
            }
        }

        func teardownMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handleScroll(_ event: NSEvent) {
            guard event.window === self.window else { return }

            // Always reset gesture state even if fingers lifted outside sidebar bounds.
            if event.phase == .began {
                accumulatedX = 0
                didTriggerThisGesture = false
            } else if event.phase == .ended || event.phase == .cancelled {
                accumulatedX = 0
                didTriggerThisGesture = false
                return
            }

            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.contains(localPoint) else { return }

            // Ignore inertia/momentum phase so a single swipe never double-flips.
            guard event.momentumPhase.isEmpty, !didTriggerThisGesture else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastTriggerUptime > 0.35 else { return }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) * 1.15 else { return }

            accumulatedX += dx
            let threshold: CGFloat = 20
            if accumulatedX >= threshold {
                didTriggerThisGesture = true
                lastTriggerUptime = now
                accumulatedX = 0
                onSwipeToWorkspace?()
            } else if accumulatedX <= -threshold {
                didTriggerThisGesture = true
                lastTriggerUptime = now
                accumulatedX = 0
                onSwipeToDocument?()
            }
        }
    }
}

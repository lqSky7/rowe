import SwiftUI
import RoweCore

enum IOSTab: String, CaseIterable, Hashable {
    case home
    case tasks
    case calendar

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

/// Root iOS shell matching the Craft iOS reference layout:
/// - Floating Liquid Glass 3-tab pill on bottom-left (Home, Tasks, Calendar)
/// - Floating Liquid Glass circular '+' button on bottom-right (no purple AI orb)
/// - Full-screen GlassGlow Onboarding on first launch, plus Login & PIN Lock overlays.
struct IOSRootShellView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Bindable var store: WorkspaceStore

    @State private var selectedTab: IOSTab = .home
    @State private var navPath: [IOSRoute] = []
    @State private var showQuickAddSheet = false
    @State private var showOnboarding = false
    @Namespace private var tabHighlightNS

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

    private var isInsideDocument: Bool {
        if case .document = navPath.last { return true }
        return false
    }

    private var isInsideSettings: Bool {
        if case .settings = navPath.last { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $navPath) {
                Group {
                    switch selectedTab {
                    case .home:
                        IOSHomeView(
                            store: store,
                            onOpenDoc: { id in navPath.append(.document(id)) },
                            onOpenAllDocs: { folderId, title, isTrash in
                                navPath.append(.allDocs(folderId: folderId, title: title, isTrash: isTrash))
                            },
                            onOpenSettings: { navPath.append(.settings) },
                            onOpenConnections: { navPath.append(.connections) },
                            onOpenShared: { navPath.append(.sharedWithMe) }
                        )
                    case .tasks:
                        IOSCalendarTasksView(
                            store: store,
                            mode: .allTasks,
                            onOpenSettings: { navPath.append(.settings) },
                            onOpenQuickAdd: { showQuickAddSheet = true }
                        )
                    case .calendar:
                        IOSCalendarTasksView(
                            store: store,
                            mode: .calendar,
                            onOpenSettings: { navPath.append(.settings) },
                            onOpenQuickAdd: { showQuickAddSheet = true }
                        )
                    }
                }
                .navigationDestination(for: IOSRoute.self) { route in
                    switch route {
                    case .allDocs(let folderId, let title, let isTrash):
                        IOSAllDocsView(
                            store: store,
                            filterTitle: title,
                            folderId: folderId,
                            isTrashMode: isTrash,
                            onOpenDoc: { id in navPath.append(.document(id)) }
                        )
                    case .document(let docId):
                        if let doc = store.documents.first(where: { $0.id == docId }) {
                            IOSDocumentEditorView(store: store, document: doc)
                        } else {
                            ContentUnavailableView("Document Not Found", systemImage: "doc.questionmark")
                        }
                    case .settings:
                        IOSSettingsView(store: store, onReplayOnboarding: { showOnboarding = true })
                    case .connections:
                        IOSConnectionsPlaceholderView(store: store)
                    case .sharedWithMe:
                        IOSSharedPlaceholderView(store: store)
                    }
                }
            }

            // Floating bottom Liquid Glass bar (hidden inside document editor & settings)
            if !isInsideDocument && !isInsideSettings {
                floatingBottomBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Floating Quick Add Card above keyboard (matches IMG_5055)
            if showQuickAddSheet {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        IOSKeyboard.dismiss()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showQuickAddSheet = false
                        }
                    }

                IOSQuickAddTaskCard(store: store) {
                    IOSKeyboard.dismiss()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showQuickAddSheet = false
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(preferredScheme)
        .tint(resolvedAccent)
        .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: isInsideDocument)
        .animation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: showQuickAddSheet)
        .fullScreenCover(isPresented: $showOnboarding) {
            RoweOnboardingView(
                store: store,
                onSignInRequested: { store.isLoginSheetPresented = true },
                onFinish: { showOnboarding = false }
            )
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
        .onAppear {
            IOSHaptics.shared.isEnabled = store.settings.enableHaptics
            if !store.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }

    private var floatingBottomBar: some View {
        HStack(spacing: 12) {
            // Left floating 3-tab Liquid Glass capsule
            HStack(spacing: 4) {
                ForEach(IOSTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        IOSHaptics.shared.toggle()
                        IOSKeyboard.dismiss()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            selectedTab = tab
                            navPath.removeAll()
                        }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? resolvedAccent : .primary.opacity(0.75))
                            .frame(width: 58, height: 44)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.11))
                                        .matchedGeometryEffect(id: "iosTabPill", in: tabHighlightNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .accessibilityLabel(tab.label)
                }
            }
            .padding(5)
            .roweIOSGlassCapsule(interactive: true)

            Spacer()

            // Right floating Liquid Glass '+' button ONLY (clean, no purple AI button)
            IOSGlassCircleButton(systemImage: "plus", size: 54, iconSize: 22) {
                IOSKeyboard.dismiss()
                if selectedTab == .calendar || selectedTab == .tasks {
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showQuickAddSheet = true
                    }
                } else {
                    let doc = store.createDocument(openImmediately: false)
                    navPath.append(.document(doc.id))
                }
            }
        }
    }
}

private struct IOSConnectionsPlaceholderView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        List {
            ForEach(store.connections) { conn in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conn.name).font(.headline)
                    Text(conn.endpointURL).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Connections")
    }
}

private struct IOSSharedPlaceholderView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        List {
            if store.sharedDocuments.isEmpty {
                ContentUnavailableView("No Shared Docs", systemImage: "person.2.wave.2")
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

import SwiftUI
import RoweCore

@main
struct RoweIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            IOSRootShellView(store: store)
                .onAppear {
                    IOSFocusManager.shared.configure(with: store)
                    store.onTaskMutatedForLiveSync = { title in
                        IOSLiveActivitySyncManager.shared.syncTaskInBackground(store: store, taskTitle: title)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        store.handleAppBecameActive()
                        IOSFocusManager.shared.importSharedDeviceActivityEvents()
                    case .background, .inactive:
                        IOSLiveActivitySyncManager.shared.flushPendingOnBackground(store: store)
                    @unknown default:
                        break
                    }
                }
        }
    }
}

import SwiftUI
import RoweCore

@main
struct RoweIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            IOSRootShellView(store: store)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.handleAppBecameActive()
                    }
                }
        }
    }
}

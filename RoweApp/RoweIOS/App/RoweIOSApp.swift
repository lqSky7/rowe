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
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.handleAppBecameActive()
                        IOSFocusManager.shared.importSharedDeviceActivityEvents()
                    }
                }
        }
    }
}

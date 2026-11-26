import SwiftUI
import RoweCore

@main
struct RoweIOSApp: App {
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            IOSRootShellView(store: store)
        }
    }
}

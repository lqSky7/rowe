import AppKit
import SwiftUI
import RoweCore

@main
struct RoweApp: App {
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup("Rowe") {
            CraftWindowShell(store: store)
                .frame(minWidth: 900, minHeight: 620)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    HapticsManager.shared.tap()
                    store.createDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    HapticsManager.shared.tap()
                    store.openNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Task") {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.activeTaskEditor = .create(defaultDate: Calendar.current.startOfDay(for: Date()))
                    }
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("New Task on Calendar") {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        if store.activeTaskEditor != nil {
                            store.activeTaskEditor = nil
                        } else {
                            store.activeTaskEditor = .create(defaultDate: Calendar.current.startOfDay(for: Date()))
                        }
                    }
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Close Tab") {
                    HapticsManager.shared.tap()
                    store.closeTab(id: store.activeTabId)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    performContextAwareUndo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    performContextAwareRedo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Navigate") {
                Button("Global Search") {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.isQuickOpenPresented.toggle()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Quick Open") {
                    HapticsManager.shared.tap()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.isQuickOpenPresented.toggle()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("All Documents") { store.navigate(to: .allDocs) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Shared with Me") { store.navigate(to: .sharedWithMe) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Tasks") { store.navigate(to: .tasks) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Calendar") { store.navigate(to: .calendar) }
                    .keyboardShortcut("5", modifiers: [.command, .option])

                Divider()

                Button("Back") { store.goBack() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward") { store.goForward() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }

            CommandMenu("View") {
                Button("Toggle Left Sidebar") {
                    HapticsManager.shared.toggle()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.toggleLeftSidebar()
                    }
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Focus Mode") {
                    HapticsManager.shared.toggle()
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        store.isFocusMode.toggle()
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    HapticsManager.shared.tap()
                    store.navigate(to: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// Routes Cmd+Z to native AppKit text undo when typing inside modals/TextFields/CodeBlocks,
    /// and to WorkspaceStore's block-snapshot undo when editing document blocks.
    private func shouldUseNativeTextUndo() -> Bool {
        if store.activeTaskEditor != nil || store.isQuickOpenPresented || store.activeDocument == nil {
            return true
        }
        if let responder = NSApp.keyWindow?.firstResponder {
            if responder is RoweNSTextView {
                return false
            }
            if responder is NSTextView || responder is NSText {
                return true
            }
        }
        return false
    }

    private func performContextAwareUndo() {
        if shouldUseNativeTextUndo() {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        } else if let doc = store.activeDocument {
            store.undo(in: doc.id)
        }
    }

    private func performContextAwareRedo() {
        if shouldUseNativeTextUndo() {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        } else if let doc = store.activeDocument {
            store.redo(in: doc.id)
        }
    }
}

import SwiftUI
import RoweCore

/// Clean open-documents switcher shown in the Workspace Sidebar only when multiple tabs/documents are open.
/// Uses fixed 30pt row heights so hovering to reveal the close button never shifts rows below.
struct SidebarTabsSection: View {
    @Bindable var store: WorkspaceStore
    @State private var hoveredTabId: String?

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    var body: some View {
        if store.tabs.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Open")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)

                ForEach(store.tabs) { tab in
                    let isActive = tab.id == store.activeTabId
                    let showClose = isActive || hoveredTabId == tab.id

                    HStack(spacing: 8) {
                        Image(systemName: iconForDestination(tab.destination))
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            .frame(width: 16)

                        Text(store.tabTitle(for: tab.destination))
                            .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Button {
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                store.closeTab(id: tab.id)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(RowePressScaleButtonStyle())
                        .opacity(showClose ? 1 : 0)
                        .allowsHitTesting(showClose)
                        .help("Close (⌘W)")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isActive
                                    ? Color.primary.opacity(0.09)
                                    : (hoveredTabId == tab.id ? Color.primary.opacity(0.045) : Color.clear)
                            )
                    }
                    .animation(CraftTheme.hoverEase(reduceMotion: reduceMotion), value: hoveredTabId)
                    .animation(CraftTheme.hoverEase(reduceMotion: reduceMotion), value: isActive)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticsManager.shared.tap()
                        store.activeTabId = tab.id
                    }
                    .onHover { hovering in
                        hoveredTabId = hovering ? tab.id : (hoveredTabId == tab.id ? nil : hoveredTabId)
                    }
                }

                Divider()
                    .opacity(0.35)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .transition(.roweUnblur)
        }
    }

    private func iconForDestination(_ dest: WorkspaceDestination) -> String {
        switch dest {
        case .allDocs: "doc.text"
        case .tasks: "checkmark.circle"
        case .calendar: "calendar"
        case .connections: "cloud"
        case .sharedWithMe: "person.2"
        case .folder: "folder"
        case .tag: "number"
        case .trash: "trash"
        case .settings: "gearshape"
        case .document: "doc.plaintext"
        }
    }
}

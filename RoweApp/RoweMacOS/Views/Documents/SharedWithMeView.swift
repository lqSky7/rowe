import SwiftUI
import RoweCore

struct SharedWithMeView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GlassCircleButton(systemImage: "chevron.left", helpText: "Back") {
                    store.goBack()
                }
                Text("Shared with Me")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.leading, store.isLeftSidebarVisible ? 20 : 58)
            .padding(.trailing, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: store.isLeftSidebarVisible)

            if store.sharedDocuments.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.2")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("No shared documents yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Documents shared with you by collaborators will appear here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Shared by").frame(width: 160, alignment: .leading)
                    Text("Date Shared").frame(width: 120, alignment: .leading)
                    Text("Last Viewed").frame(width: 120, alignment: .leading)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 8)

                Divider().opacity(0.35).padding(.horizontal, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.sharedDocuments) { item in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(hex: "#F4F0E8"))
                                    .frame(width: 28, height: 36)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13.5, weight: .medium))
                                    Text(item.preview)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: item.sharedByColorHex))
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Text(item.sharedByInitial)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white)
                                        )
                                    Text(item.sharedByName)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 160, alignment: .leading)

                                Text(item.dateShared.craftRelativeString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                Text(item.lastViewed.craftRelativeString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Remove from Shared with Me", role: .destructive) {
                                    HapticsManager.shared.destructive()
                                    store.removeSharedDocument(id: item.id)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Divider().opacity(0.25).padding(.horizontal, 28)
                            }
                        }
                    }
                }
            }
        }
    }
}

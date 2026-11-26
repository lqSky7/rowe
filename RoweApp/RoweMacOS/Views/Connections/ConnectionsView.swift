import AppKit
import SwiftUI
import RoweCore

struct ConnectionsView: View {
    @Bindable var store: WorkspaceStore
    @State private var selectedConnection: ConnectionItem?

    private var mcpConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .mcp }
    }

    private var apiConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .api }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#B8CBD6").opacity(0.45), Color(hex: "#DCE6EC").opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    GlassCircleButton(systemImage: "chevron.left", helpText: "Back") {
                        store.goBack()
                    }

                    RoweGlassCircleMenu(
                        systemImage: "plus",
                        helpText: "New Connection",
                        size: 32,
                        items: [
                            RoweGlassActionMenuItem(title: "New MCP Connection", icon: "cpu") {
                                selectedConnection = store.addConnection(kind: .mcp)
                            },
                            RoweGlassActionMenuItem(title: "New API Connection", icon: "network") {
                                selectedConnection = store.addConnection(kind: .api)
                            }
                        ]
                    )

                    Text("Connections")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .padding(.leading, store.isLeftSidebarVisible ? 20 : 58)
                .padding(.trailing, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: store.isLeftSidebarVisible)

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        connectionSection(
                            title: "Your MCP Connections",
                            subtitle: "For AI tools to access your docs",
                            items: mcpConnections,
                            kind: .mcp
                        )

                        connectionSection(
                            title: "Your API Connections",
                            subtitle: "For building workflows and shortcuts",
                            items: apiConnections,
                            kind: .api
                        )
                    }
                    .frame(maxWidth: 740, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }

            if let conn = selectedConnection {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .onTapGesture { selectedConnection = nil }

                ConnectionDetailsPopover(
                    connection: conn,
                    onUpdate: { updated in
                        store.updateConnection(updated)
                        selectedConnection = updated
                    },
                    onDelete: {
                        HapticsManager.shared.destructive()
                        store.deleteConnection(id: conn.id)
                        selectedConnection = nil
                    },
                    onClose: {
                        selectedConnection = nil
                    }
                )
                .transition(.roweUnblur)
            }
        }
    }

    private func connectionSection(title: String, subtitle: String, items: [ConnectionItem], kind: ConnectionKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    HapticsManager.shared.tap()
                    selectedConnection = store.addConnection(kind: kind)
                } label: {
                    Image(systemName: "plus.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    Button {
                        HapticsManager.shared.tap()
                        selectedConnection = item
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.documentScope.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 14)

                            // Mini stacked document cards preview
                            HStack(spacing: -14) {
                                ForEach(0..<3, id: \.self) { idx in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white)
                                        .frame(width: 58, height: 64)
                                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                        .overlay(alignment: .topLeading) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.3)).frame(width: 28, height: 2.5)
                                                RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.15)).frame(width: 36, height: 2)
                                                RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.15)).frame(width: 24, height: 2)
                                            }
                                            .padding(7)
                                        }
                                        .offset(y: CGFloat(idx) * 2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(16)
                        .frame(height: 156, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ConnectionDetailsPopover: View {
    @State var connection: ConnectionItem
    var onUpdate: (ConnectionItem) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var copiedBanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(connection.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    HapticsManager.shared.tap()
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.3)

            detailRow(icon: "character.cursor.ibeam", label: "Name") {
                TextField("Name", text: $connection.name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: connection.name) { _, _ in onUpdate(connection) }
            }

            detailRow(icon: "link", label: "URL") {
                Button {
                    HapticsManager.shared.tap()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(connection.endpointURL, forType: .string)
                    copiedBanner = true
                } label: {
                    Text(copiedBanner ? "Copied!" : connection.endpointURL)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            detailRow(icon: "doc.text", label: "Documents") {
                RoweGlassMenuPicker(
                    items: ConnectionDocumentScope.allCases,
                    selection: $connection.documentScope,
                    titleForItem: \.rawValue
                ) { _ in onUpdate(connection) }
            }

            detailRow(icon: "lock", label: "Permission Level") {
                RoweGlassMenuPicker(
                    items: ConnectionPermission.allCases,
                    selection: $connection.permission,
                    titleForItem: \.rawValue
                ) { _ in onUpdate(connection) }
            }

            detailRow(icon: "shield", label: "Access Mode") {
                RoweGlassMenuPicker(
                    items: ConnectionAccessMode.allCases,
                    selection: $connection.accessMode,
                    titleForItem: \.rawValue
                ) { _ in onUpdate(connection) }
            }

            Divider().opacity(0.3)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete this \(connection.kind.rawValue)", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 390)
        .roweGlassRoundedRect(radius: 18)
    }

    private func detailRow<Content: View>(icon: String, label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
            Spacer()
            trailing()
        }
        .padding(.vertical, 3)
    }
}

import AppKit
import SwiftUI
import RoweCore

struct ConnectionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    @State private var selectedConnection: ConnectionItem?
    @State private var copiedId: String?

    private var mcpConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .mcp }
    }

    private var apiConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .api }
    }

    private static let mcpPalette = GlassGlowPalette(
        Color(red: 0.76, green: 0.87, blue: 0.99),
        Color(red: 0.56, green: 0.72, blue: 0.96),
        Color(red: 0.86, green: 0.92, blue: 1.0)
    )

    private static let apiPalette = GlassGlowPalette(
        Color(red: 0.98, green: 0.85, blue: 0.76),
        Color(red: 0.92, green: 0.72, blue: 0.64),
        Color(red: 0.99, green: 0.91, blue: 0.84)
    )

    private static let heroPalette = GlassGlowPalette(
        Color(white: 0.96),
        Color(red: 0.74, green: 0.85, blue: 0.97),
        Color(red: 0.86, green: 0.90, blue: 0.95)
    )

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.leading, store.isLeftSidebarVisible ? 20 : 58)
                    .padding(.trailing, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: store.isLeftSidebarVisible)

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        heroBanner

                        connectionSection(
                            title: "MCP Connections",
                            subtitle: "Model Context Protocol endpoints for AI assistants",
                            items: mcpConnections,
                            kind: .mcp,
                            palette: Self.mcpPalette
                        )

                        connectionSection(
                            title: "API Connections",
                            subtitle: "REST & Webhook endpoints for automations and shortcuts",
                            items: apiConnections,
                            kind: .api,
                            palette: Self.apiPalette
                        )
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity)
                }
            }

            if let conn = selectedConnection {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            selectedConnection = nil
                        }
                    }

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
                .transition(.roweConvergeUnblur)
            }
        }
    }

    private var topBar: some View {
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

            Text("\(store.connections.count) Active")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .roweGlassCapsule(interactive: false)
        }
    }

    private var heroBanner: some View {
        HStack(spacing: 24) {
            ZStack {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: "#16181D"))
                        .frame(width: 84, height: 84)
                }
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .glassGlow(Self.heroPalette, speed: 0.76, glow: 1.05)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Rowe to Your Tools")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Expose scoped workspace access over MCP or REST API with granular read/write permissions.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    GlassPillButton("Add MCP Server", systemImage: "cpu") {
                        selectedConnection = store.addConnection(kind: .mcp)
                    }
                    GlassPillButton("Add API Endpoint", systemImage: "network") {
                        selectedConnection = store.addConnection(kind: .api)
                    }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                )
        )
    }

    private func connectionSection(
        title: String,
        subtitle: String,
        items: [ConnectionItem],
        kind: ConnectionKind,
        palette: GlassGlowPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassPillButton("New", systemImage: "plus") {
                    selectedConnection = store.addConnection(kind: kind)
                }
            }

            if items.isEmpty {
                Button {
                    HapticsManager.shared.tap()
                    selectedConnection = store.addConnection(kind: kind)
                } label: {
                    HStack(spacing: 14) {
                        glowIconBadge(icon: kind == .mcp ? "cpu" : "network", palette: palette)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No \(kind.rawValue) connections yet")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Click to create your first \(kind.rawValue) endpoint")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    )
                }
                .buttonStyle(RowePressScaleButtonStyle())
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        connectionCard(item: item, palette: palette)
                    }
                }
            }
        }
    }

    private func glowIconBadge(icon: String, palette: GlassGlowPalette) -> some View {
        ZStack {
            if colorScheme == .light {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#16181D"))
                    .frame(width: 42, height: 42)
            }
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .glassGlow(palette, speed: 0.72, glow: 0.95)
        }
    }

    private func connectionCard(item: ConnectionItem, palette: GlassGlowPalette) -> some View {
        Button {
            HapticsManager.shared.tap()
            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                selectedConnection = item
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    glowIconBadge(icon: item.kind == .mcp ? "cpu" : "network", palette: palette)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(item.documentScope.rawValue)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                // Endpoint URL pill with quick-copy
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(item.endpointURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        HapticsManager.shared.tap()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.endpointURL, forType: .string)
                        copiedId = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if copiedId == item.id { copiedId = nil }
                        }
                    } label: {
                        Image(systemName: copiedId == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(copiedId == item.id ? Color.green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                )

                HStack(spacing: 6) {
                    badgePill(item.permission.rawValue, icon: "lock")
                    badgePill(item.accessMode.rawValue, icon: "shield")
                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(RowePressScaleButtonStyle())
    }

    private func badgePill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
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
                        .foregroundStyle(copiedBanner ? .green : .secondary)
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
        .frame(width: 400)
        .background(RoweNativeGlassBackdrop(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.85)
        )
        .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
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

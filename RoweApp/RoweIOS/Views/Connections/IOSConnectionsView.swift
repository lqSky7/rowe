import SwiftUI
import UIKit
import RoweCore

/// Full-featured iOS Connections view with custom vector artwork, draft-safe creation
/// (closing without tapping Create never leaves a ghost connection), and spring+unblur motion.
struct IOSConnectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore

    @State private var activeEditor: ConnectionEditorMode?
    @State private var copiedId: String?

    private enum ConnectionEditorMode: Identifiable {
        case create(ConnectionItem)
        case edit(ConnectionItem)

        var id: String {
            switch self {
            case .create(let c): return "create-\(c.id)"
            case .edit(let c): return "edit-\(c.id)"
            }
        }
    }

    private var accent: Color {
        Color(hex: store.settings.accentColor.hex)
    }

    private var mcpConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .mcp }
    }

    private var apiConnections: [ConnectionItem] {
        store.connections.filter { $0.kind == .api }
    }

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Top Bar
                HStack {
                    IOSGlassCircleButton(systemImage: "chevron.left", size: 40, iconSize: 16) {
                        dismiss()
                    }
                    Spacer()
                    Menu {
                        Button("New MCP Connection", systemImage: "cpu") {
                            IOSHaptics.shared.tap()
                            activeEditor = .create(store.makeDraftConnection(kind: .mcp))
                        }
                        Button("New API Connection", systemImage: "network") {
                            IOSHaptics.shared.tap()
                            activeEditor = .create(store.makeDraftConnection(kind: .api))
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .roweIOSGlass(in: Circle(), interactive: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                // Title
                HStack(alignment: .firstTextBaseline) {
                    Text("Connections")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Text("\(store.connections.count) Active")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 18)

                // Bespoke Vector Hero Card (no shader glow)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        ConnectionsHeroArtwork(accentColor: accent)
                            .frame(width: 82, height: 82)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connect Rowe to Your Tools")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Scoped MCP & REST endpoints with granular read/write access.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            IOSHaptics.shared.tap()
                            activeEditor = .create(store.makeDraftConnection(kind: .mcp))
                        } label: {
                            Label("Add MCP", systemImage: "cpu")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(RowePressScaleStyle())

                        Button {
                            IOSHaptics.shared.tap()
                            activeEditor = .create(store.makeDraftConnection(kind: .api))
                        } label: {
                            Label("Add API", systemImage: "network")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                )
                .padding(.horizontal, 18)

                connectionSection(title: "MCP Connections", items: mcpConnections, kind: .mcp)
                connectionSection(title: "API Connections", items: apiConnections, kind: .api)
            }
            .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: store.connections.map(\.id))
            .padding(.bottom, 100)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeEditor) { mode in
            switch mode {
            case .create(let draft):
                IOSConnectionEditorSheet(
                    connection: draft,
                    isNew: true,
                    accent: accent,
                    onSave: { created in
                        IOSHaptics.shared.taskComplete()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                            store.saveConnection(created)
                        }
                        activeEditor = nil
                    },
                    onDelete: nil,
                    onCancel: { activeEditor = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            case .edit(let existing):
                IOSConnectionEditorSheet(
                    connection: existing,
                    isNew: false,
                    accent: accent,
                    onSave: { updated in
                        IOSHaptics.shared.tap()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                            store.updateConnection(updated)
                        }
                        activeEditor = nil
                    },
                    onDelete: {
                        IOSHaptics.shared.destructive()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                            store.deleteConnection(id: existing.id)
                        }
                        activeEditor = nil
                    },
                    onCancel: { activeEditor = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
    }

    private func connectionSection(title: String, items: [ConnectionItem], kind: ConnectionKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    IOSHaptics.shared.tap()
                    activeEditor = .create(store.makeDraftConnection(kind: kind))
                } label: {
                    Text("New")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(RowePressScaleStyle())
            }
            .padding(.horizontal, 18)

            if items.isEmpty {
                Button {
                    IOSHaptics.shared.tap()
                    activeEditor = .create(store.makeDraftConnection(kind: kind))
                } label: {
                    HStack(spacing: 14) {
                        ConnectionKindVectorBadge(kind: kind, accentColor: accent, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No \(kind.rawValue) connections yet")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Tap to configure a new \(kind.rawValue) endpoint")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.11), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    )
                }
                .buttonStyle(RowePressScaleStyle())
                .padding(.horizontal, 18)
                .transition(.roweUnblur)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        connectionCard(item)
                            .transition(.roweUnblur)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func connectionCard(_ item: ConnectionItem) -> some View {
        Button {
            IOSHaptics.shared.tap()
            activeEditor = .edit(item)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ConnectionKindVectorBadge(kind: item.kind, accentColor: accent, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(item.documentScope.rawValue)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.endpointURL)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        IOSHaptics.shared.tap()
                        UIPasteboard.general.string = item.endpointURL
                        copiedId = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            if copiedId == item.id { copiedId = nil }
                        }
                    } label: {
                        Image(systemName: copiedId == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(copiedId == item.id ? Color.green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))

                HStack(spacing: 8) {
                    badge(item.permission.rawValue, icon: "lock")
                    badge(item.accessMode.rawValue, icon: "shield")
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(RowePressScaleStyle())
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct IOSConnectionEditorSheet: View {
    @State var connection: ConnectionItem
    let isNew: Bool
    let accent: Color
    var onSave: (ConnectionItem) -> Void
    var onDelete: (() -> Void)?
    var onCancel: () -> Void

    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Details") {
                    TextField("Connection Name", text: $connection.name)
                    Button {
                        IOSHaptics.shared.tap()
                        UIPasteboard.general.string = connection.endpointURL
                        copied = true
                    } label: {
                        HStack {
                            Text("Endpoint URL")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(copied ? "Copied!" : connection.endpointURL)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(copied ? .green : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section("Scope & Permissions") {
                    Picker("Documents", selection: $connection.documentScope) {
                        ForEach(ConnectionDocumentScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    Picker("Permission", selection: $connection.permission) {
                        ForEach(ConnectionPermission.allCases, id: \.self) { perm in
                            Text(perm.rawValue).tag(perm)
                        }
                    }
                    Picker("Access Mode", selection: $connection.accessMode) {
                        ForEach(ConnectionAccessMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                if let onDelete, !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete Connection", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New \(connection.kind.rawValue)" : "Edit \(connection.kind.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") {
                        onSave(connection)
                    }
                    .fontWeight(.semibold)
                    .disabled(connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

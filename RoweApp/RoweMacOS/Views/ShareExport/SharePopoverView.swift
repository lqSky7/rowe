import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoweCore

enum SharePopoverTab: String, CaseIterable {
    case share = "Share"
    case publish = "Publish"
    case export = "Export"
    case transfer = "Transfer"
}

struct SharePopoverView: View {
    @Bindable var store: WorkspaceStore
    let document: RoweDocument

    @State private var selectedTab: SharePopoverTab = .share
    @State private var inviteEmail: String = ""
    @State private var accessPolicy: String = "Only collaborators can access"
    @State private var statusBanner: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LiquidGlassSegmentedControl(
                items: SharePopoverTab.allCases,
                selection: $selectedTab,
                height: 32,
                title: \.rawValue
            )

            switch selectedTab {
            case .share:
                shareTabBody
            case .publish:
                publishTabBody
            case .export:
                exportTabBody
            case .transfer:
                transferTabBody
            }

            if let statusBanner {
                Text(statusBanner)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder
    private var shareTabBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Invite to Collaborate", systemImage: "person.2")
                .font(.system(size: 13.5, weight: .semibold))
            Text("For easy collaboration with anyone once sync backend is connected.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            TextField("Add emails to invite people", text: $inviteEmail)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.15)))
                .onSubmit {
                    if !inviteEmail.isEmpty {
                        HapticsManager.shared.tap()
                        statusBanner = "Invite queued for \(inviteEmail)"
                        inviteEmail = ""
                    }
                }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))

        HStack(spacing: 8) {
            Menu {
                Button("Only collaborators can access") { accessPolicy = "Only collaborators can access" }
                Button("Anyone with link can view") { accessPolicy = "Anyone with link can view" }
                Button("Anyone with link can edit") { accessPolicy = "Anyone with link can edit" }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                    Text(accessPolicy)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.14)))
            }
            .menuStyle(.borderlessButton)
            .tint(.secondary)

            Button {
                HapticsManager.shared.tap()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("rowe://doc/\(document.id)", forType: .string)
                statusBanner = "Copied deep link to clipboard"
            } label: {
                Text("Copy Link")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(RowePressScaleButtonStyle())
        }
    }

    @ViewBuilder
    private var publishTabBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Publish to the Web", systemImage: "globe")
                .font(.system(size: 13.5, weight: .semibold))
            Text("Publish your doc to the web with a secret link and control who sees it.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            let previewInk = Color(hex: document.style.safeTextColorHex ?? "#1F2225")
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(document.style.documentColorHex.map(Color.init(hex:)) ?? Color.white)
                        .padding(16)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(document.displayTitle)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(previewInk)
                                Text(document.previewSnippet)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(previewInk.opacity(0.65))
                                    .lineLimit(4)
                            }
                            .padding(26)
                        }
                }

            Button {
                HapticsManager.shared.tap()
                let url = "https://rowe.local/share/\(document.id.prefix(8))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                statusBanner = "Local preview link copied: \(url)"
            } label: {
                Text("Create Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(RowePressScaleButtonStyle())
        }
    }

    @ViewBuilder
    private var exportTabBody: some View {
        VStack(spacing: 6) {
            exportRow("Markdown", icon: "doc.text") {
                Task {
                    let md = await store.exportDocumentMarkdown(document)
                    saveExportedString(md, defaultFilename: "\(document.displayTitle).md", contentType: .plainText)
                }
            }
            exportRow("HTML / Web Page", icon: "globe") {
                Task {
                    let html = await store.exportDocumentHTML(document)
                    saveExportedString(html, defaultFilename: "\(document.displayTitle).html", contentType: .html)
                }
            }
            exportRow("Plain Text", icon: "doc.plaintext") {
                Task {
                    let txt = await store.exportDocumentPlainText(document)
                    saveExportedString(txt, defaultFilename: "\(document.displayTitle).txt", contentType: .plainText)
                }
            }
            exportRow("Print", icon: "printer") {
                HapticsManager.shared.tap()
                statusBanner = "Use File → Print (⌘P) to print or save as PDF"
            }
            exportRow("Duplicate", icon: "doc.on.doc") {
                store.duplicateDocument(docId: document.id)
                statusBanner = "Document duplicated"
            }
            exportRow("Copy Deep Link…", icon: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("rowe://doc/\(document.id)", forType: .string)
                statusBanner = "Copied rowe://doc/\(document.id)"
            }
        }
    }

    @ViewBuilder
    private var transferTabBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transfer Document")
                .font(.system(size: 13.5, weight: .semibold))
            Text("Move this document into another folder in your space.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach(store.folders) { folder in
                Button {
                    HapticsManager.shared.tap()
                    store.moveDocument(docId: document.id, toFolderId: folder.id)
                    statusBanner = "Moved to \(folder.name)"
                } label: {
                    HStack {
                        Image(systemName: folder.iconName)
                            .foregroundStyle(.secondary)
                        Text(folder.name)
                            .font(.system(size: 13))
                        Spacer()
                        if document.folderId == folder.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exportRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13.5))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func saveExportedString(_ text: String, defaultFilename: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [contentType]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            statusBanner = "Saved to \(url.lastPathComponent)"
        }
    }
}

import SwiftUI
import RoweCore

struct IOSHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    var onOpenDoc: (String) -> Void
    var onOpenAllDocs: (String?, String, Bool) -> Void
    var onOpenSettings: () -> Void
    var onOpenConnections: () -> Void
    var onOpenShared: () -> Void

    @State private var searchText: String = ""
    @State private var searchMode: String = "Keyword"
    @State private var showStarredOnly: Bool = false
    @FocusState private var isSearchFocused: Bool

    private var activeDocs: [RoweDocument] {
        let base = store.documents.filter { !$0.isTrashed }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? base : base.filter {
            $0.displayTitle.lowercased().contains(q) || $0.previewSnippet.lowercased().contains(q)
        }
        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var trashedCount: Int {
        store.documents.filter(\.isTrashed).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Bar: Avatar + (...) & Sync/Account Bell Pill
                HStack {
                    Button {
                        IOSHaptics.shared.tap()
                        IOSKeyboard.dismiss()
                        onOpenSettings()
                    } label: {
                        IOSSpaceAvatar(space: store.space, size: 38, cornerRadius: 11)
                    }
                    .buttonStyle(RowePressScaleStyle())

                    Spacer()

                    HStack(spacing: 14) {
                        Menu {
                            Button("New Document", systemImage: "doc.badge.plus") {
                                let d = store.createDocument(openImmediately: false)
                                onOpenDoc(d.id)
                            }
                            Button("Daily Note", systemImage: "calendar.badge.plus") {
                                store.openOrCreateDailyNote()
                                if let active = store.activeDocument { onOpenDoc(active.id) }
                            }
                            if store.hasVaultPin && !store.unlockedDocumentIds.isEmpty {
                                Button("Lock All Open Notes", systemImage: "lock.fill") {
                                    store.relockAllDocuments()
                                }
                            }
                            Divider()
                            Button(store.isSignedIn ? "Sync Now" : "Sign In to Sync", systemImage: "arrow.triangle.2.circlepath") {
                                if store.isSignedIn {
                                    Task { await store.syncWithBackend() }
                                } else {
                                    store.isLoginSheetPresented = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }

                        Button {
                            IOSHaptics.shared.tap()
                            if store.isSignedIn {
                                Task { await store.syncWithBackend() }
                            } else {
                                store.isLoginSheetPresented = true
                            }
                        } label: {
                            Image(systemName: store.isSignedIn ? "bell.badge" : "bell")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .roweIOSGlassCapsule(interactive: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                // Large Home Title
                Text("Home")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.horizontal, 18)

                // Search Bar with Keyword Filter Chip
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search in \(store.space.name)", text: $searchText)
                        .focused($isSearchFocused)
                        .font(.system(size: 15))
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Menu {
                        Button("Keyword") { searchMode = "Keyword" }
                        Button("Title Only") { searchMode = "Title" }
                    } label: {
                        HStack(spacing: 4) {
                            Text(searchMode)
                                .font(.system(size: 13.5, weight: .medium))
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .padding(.horizontal, 18)

                // Horizontal Recent Documents Carousel
                if !activeDocs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(activeDocs.prefix(10)) { doc in
                                IOSHomeRecentCard(doc: doc, colorScheme: colorScheme) {
                                    IOSHaptics.shared.tap()
                                    IOSKeyboard.dismiss()
                                    onOpenDoc(doc.id)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }

                // Navigation Rows (matching IMG_5041)
                VStack(spacing: 0) {
                    homeRow(icon: "doc.text.fill", title: "All Docs", count: activeDocs.count) {
                        onOpenAllDocs(nil, "All Docs", false)
                    }
                    Divider().opacity(0.25).padding(.leading, 50)
                    homeRow(icon: "cloud", title: "Connections", count: store.connections.count) {
                        onOpenConnections()
                    }
                    Divider().opacity(0.25).padding(.leading, 50)
                    homeRow(icon: "person.2.wave.2", title: "Shared with Me", count: store.sharedDocuments.count) {
                        onOpenShared()
                    }
                    Divider().opacity(0.25).padding(.leading, 50)
                    homeRow(icon: "trash", title: "Recently Deleted", count: trashedCount) {
                        onOpenAllDocs(nil, "Recently Deleted", true)
                    }
                }
                .padding(.horizontal, 18)

                // Folders Quick List
                if !store.folders.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folders")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)

                        VStack(spacing: 0) {
                            ForEach(store.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                                let count = store.documents.filter { !$0.isTrashed && $0.folderId == folder.id }.count
                                homeRow(icon: folder.iconName, title: folder.name, count: count) {
                                    onOpenAllDocs(folder.id, folder.name, false)
                                }
                                if folder.id != store.folders.last?.id {
                                    Divider().opacity(0.2).padding(.leading, 50)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }

                // Customize Home Pill
                HStack {
                    Spacer()
                    Button {
                        IOSHaptics.shared.tap()
                        onOpenSettings()
                    } label: {
                        Text("Customize Home")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(RowePressScaleStyle())
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .iosPullDownToSearch(isPresented: $store.isQuickOpenPresented, reduceMotion: store.settings.reduceAnimations)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSearchFocused {
                isSearchFocused = false
                IOSKeyboard.dismiss()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func homeRow(icon: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            IOSKeyboard.dismiss()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IOSHomeRecentCard: View {
    let doc: RoweDocument
    let colorScheme: ColorScheme
    let action: () -> Void

    private var surfaceColor: Color {
        if let hex = doc.style.documentColorHex { return Color(hex: hex) }
        return colorScheme == .dark ? Color(hex: "#1E1F24") : .white
    }

    private var inkColor: Color {
        if let hex = doc.style.textColorHex { return Color(hex: hex) }
        return colorScheme == .dark ? Color(hex: "#F2F3F5") : Color(hex: "#1C1E22")
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                // Wallpaper backdrop or card surface
                if let cover = doc.style.coverImageName {
                    IOSCoverArtwork(artworkName: cover)
                } else {
                    surfaceColor
                }

                // Inner paper preview inset (Craft style)
                VStack(alignment: .leading, spacing: 6) {
                    Text(doc.displayTitle)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(inkColor)
                        .lineLimit(2)

                    if doc.isLocked {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.orange)
                                Text("Locked")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(inkColor.opacity(0.65))
                            }
                            Spacer()
                        }
                        Spacer()
                    } else {
                        Text(doc.previewSnippet)
                            .font(.system(size: 11.5))
                            .foregroundStyle(inkColor.opacity(0.68))
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(surfaceColor.opacity(doc.style.coverImageName != nil ? 0.90 : 1.0))
                )
                .padding(doc.style.coverImageName != nil ? 6 : 0)
            }
            .frame(width: 152, height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        }
        .buttonStyle(RowePressScaleStyle())
    }
}

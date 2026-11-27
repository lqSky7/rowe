import PhotosUI
import SwiftUI
import RoweCore

/// Full iOS Settings hierarchy matching IMG_5050–IMG_5054, enhanced with subtle GlassGlow accents.
struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore
    var onReplayOnboarding: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    IOSGlassCircleButton(systemImage: "chevron.left", size: 40, iconSize: 16) {
                        dismiss()
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                // Space Avatar with subtle GlassGlow crest
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        IOSSpaceAvatar(space: store.space, size: 88, cornerRadius: 24)
                        Text(store.isSignedIn ? "Synced" : "Local")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white))
                            .offset(x: 6, y: 6)
                    }
                    Text(store.space.name)
                        .font(.system(size: 20, weight: .bold))
                }
                .padding(.vertical, 4)

                // Space Settings Group
                settingsSection("Space Settings") {
                    NavigationLink { IOSSpaceStatsView(store: store) } label: {
                        settingsRow("Stats", icon: "chart.pie")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.2).padding(.leading, 42)
                    NavigationLink { IOSSpaceDetailView(store: store) } label: {
                        settingsRow("Space Settings", icon: "gearshape")
                    }
                    .buttonStyle(.plain)
                }

                // General Settings Group
                settingsSection("General Settings") {
                    NavigationLink { IOSAppearanceSettingsView(store: store) } label: {
                        settingsRow("Appearance & Sound", icon: "textformat")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.2).padding(.leading, 42)
                    NavigationLink { IOSFocusPatternsView(store: store) } label: {
                        settingsRow("Focus Patterns", icon: "waveform.and.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.2).padding(.leading, 42)
                    Button {
                        IOSHaptics.shared.tap()
                        if store.hasVaultPin {
                            store.pinPromptRequest = .changePin
                        } else {
                            store.pinPromptRequest = .setupPin(lockDocumentId: nil)
                        }
                    } label: {
                        settingsRow(store.hasVaultPin ? "Security · PIN Lock On" : "Security · Set Up PIN", icon: "lock")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.2).padding(.leading, 42)
                    NavigationLink { IOSSearchSettingsView(store: store) } label: {
                        settingsRow("Global Search & Index", icon: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.2).padding(.leading, 42)
                    NavigationLink { IOSAccountSettingsView(store: store) } label: {
                        settingsRow("Account Settings", icon: "person.circle")
                    }
                    .buttonStyle(.plain)
                }

                // GlassGlow Showcase / Reset Onboarding
                Button {
                    IOSHaptics.shared.tap()
                    store.updateSettings { $0.hasCompletedOnboarding = false }
                    onReplayOnboarding()
                } label: {
                    HStack(spacing: 14) {
                        RoweRibbonMark()
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 26)
                            .glassGlow(RoweOnboardingView.monochromePalette, speed: 0.7, glow: 0.9)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rowe for iOS")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Reset & Replay Onboarding")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(RowePressScaleStyle())
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 50)
        }
        .iosPullDownToSearch(isPresented: $store.isQuickOpenPresented, reduceMotion: store.settings.reduceAnimations)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 18)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 18)
        }
    }

    private func settingsRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16.5))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// Matches IMG_5052 with live `.contentTransition(.numericText())` values.
private struct IOSSpaceStatsView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        let bytesStr = ByteCountFormatter.string(fromByteCount: store.stats.storageBytes, countStyle: .file)
        let hrs = store.stats.estimatedReadingMinutes / 60
        let mins = store.stats.estimatedReadingMinutes % 60

        ScrollView {
            VStack(spacing: 14) {
                statCard {
                    statItem("Storage Used", value: "\(bytesStr) / Local")
                }
                statCard {
                    statItem("Documents", value: "\(store.stats.documentCount)")
                    Divider().opacity(0.25)
                    statItem("Blocks", value: "\(store.stats.blockCount)")
                    Divider().opacity(0.25)
                    statItem("Pages", value: "\(store.stats.pageCount)")
                    Divider().opacity(0.25)
                    statItem("Words", value: "\(store.stats.wordCount)")
                    Divider().opacity(0.25)
                    statItem("Characters", value: "\(store.stats.characterCount)")
                    Divider().opacity(0.25)
                    statItem("Reading Time", value: hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m")
                }
            }
            .padding(18)
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private func statItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold)).contentTransition(.numericText())
        }
    }
}

/// Matches IMG_5053 with PhotosPicker avatar upload.
private struct IOSSpaceDetailView: View {
    @Bindable var store: WorkspaceStore
    @State private var spaceName = ""
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        IOSSpaceAvatar(space: store.space, size: 108, cornerRadius: 26)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.8)))
                            .offset(x: 6, y: 6)
                    }
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            store.updateAvatarImageBase64(data.base64EncodedString())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Space Name").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    TextField("Space Name", text: $spaceName)
                        .font(.system(size: 17, weight: .medium))
                        .onChange(of: spaceName) { _, val in store.updateSpaceName(val) }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                .padding(.horizontal, 18)
            }
            .padding(.top, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { IOSKeyboard.dismiss() }
        .navigationTitle("Space Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { spaceName = store.space.name }
    }
}

/// Matches IMG_5054 (3-iPhone System/Light/Dark picker + 10 accent color circles + Sound & Haptics).
private struct IOSAppearanceSettingsView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 3-iPhone Appearance Picker
                HStack(spacing: 16) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        let selected = store.settings.appearanceMode == mode
                        Button {
                            IOSHaptics.shared.tap()
                            store.updateSettings { $0.appearanceMode = mode }
                        } label: {
                            VStack(spacing: 8) {
                                phonePreview(mode: mode)
                                    .frame(height: 112)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1)
                                    )
                                Text(mode.rawValue)
                                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.accentColor : .primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.07)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Interface Accent Color").font(.system(size: 16, weight: .bold))
                    Text("Controls across the app will use the selected accent color.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(AccentColorChoice.allCases, id: \.self) { choice in
                            let selected = store.settings.accentColor == choice
                            Button {
                                IOSHaptics.shared.tap()
                                store.updateSettings { $0.accentColor = choice }
                            } label: {
                                Circle()
                                    .fill(Color(hex: choice.hex))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color(uiColor: .systemBackground), lineWidth: selected ? 3 : 0)
                                            .padding(4)
                                    )
                            }
                            .buttonStyle(RowePressScaleStyle())
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sound & Haptics").font(.system(size: 16, weight: .bold))
                    VStack(spacing: 12) {
                        Toggle("Enable Sound", isOn: Binding(
                            get: { store.settings.enableSound },
                            set: { val in store.updateSettings { $0.enableSound = val } }
                        ))
                        Divider().opacity(0.25)
                        Toggle("Enable Haptics", isOn: Binding(
                            get: { store.settings.enableHaptics },
                            set: { val in
                                store.updateSettings { $0.enableHaptics = val }
                                IOSHaptics.shared.isEnabled = val
                                if val { IOSHaptics.shared.tap() }
                            }
                        ))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Application Icon").font(.system(size: 16, weight: .bold))
                    Text("Choose between Light and Dark home screen icons.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        appIconOption(title: "Light", index: 0, isDark: false)
                        appIconOption(title: "Dark", index: 1, isDark: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
                }
            }
            .padding(18)
        }
        .navigationTitle("Appearance & Sound")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appIconOption(title: String, index: Int, isDark: Bool) -> some View {
        let isSelected = store.settings.selectedAppIconIndex == index
        return Button {
            IOSHaptics.shared.tap()
            store.updateSettings { $0.selectedAppIconIndex = index }
            if UIApplication.shared.supportsAlternateIcons {
                UIApplication.shared.setAlternateIconName(isDark ? "AppIconDark" : nil) { _ in }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color(hex: "#1C1D22"), Color(hex: "#0D0E12")]
                                    : [Color(hex: "#FCFBF8"), Color(hex: "#E8E3D8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                        )

                    RoweRibbonMark()
                        .stroke(style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(isDark ? Color.white : Color(hex: "#191B1E"))
                        .frame(width: 34, height: 26)
                }
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.2)
                        .padding(-3)
                )

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(RowePressScaleStyle())
    }

    private func phonePreview(mode: AppearanceMode) -> some View {
        ZStack {
            if mode == .system {
                HStack(spacing: 0) {
                    Color.white
                    Color(hex: "#15161A")
                }
            } else {
                mode == .light ? Color.white : Color(hex: "#15161A")
            }
            VStack(spacing: 6) {
                Capsule().fill(Color.black.opacity(0.7)).frame(width: 24, height: 5).padding(.top, 8)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Matches IMG_5051 with Cloud Sync Sign In, Sync Now, and Log Out.
private struct IOSAccountSettingsView: View {
    @Bindable var store: WorkspaceStore
    @State private var name = ""
    @State private var email = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                IOSSpaceAvatar(space: store.space, size: 96, cornerRadius: 48)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        TextField("Display Name", text: $name)
                            .font(.system(size: 16, weight: .medium))
                            .onChange(of: name) { _, v in store.updateProfile(authorName: v) }
                    }
                    Divider().opacity(0.25)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email Address").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        TextField("you@example.com", text: $email)
                            .font(.system(size: 16))
                            .onChange(of: email) { _, v in store.updateProfile(email: v) }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))

                if store.isSignedIn {
                    Button {
                        IOSHaptics.shared.tap()
                        Task { await store.syncWithBackend() }
                    } label: {
                        HStack {
                            Text("Sync Now (\(store.authSession?.serverURL ?? ""))")
                                .font(.system(size: 15.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        IOSHaptics.shared.destructive()
                        Task { await store.signOut() }
                    } label: {
                        HStack {
                            Text("Log Out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        IOSHaptics.shared.tap()
                        store.isLoginSheetPresented = true
                    } label: {
                        HStack {
                            Text("Sign In / Sync Account")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Image(systemName: "person.badge.key")
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { IOSKeyboard.dismiss() }
        .navigationTitle("Account Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = store.space.authorName
            email = store.space.email
        }
    }
}

/// Global Search & Index customization matching macOS Settings -> Advanced.
private struct IOSSearchSettingsView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Maximum Search Depth")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Controls how far pull-down search deepens when nothing is found in your current view.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Picker("Max Depth", selection: Binding(
                        get: { store.settings.searchMaxDepth },
                        set: { depth in store.updateSettings { $0.searchMaxDepth = depth } }
                    )) {
                        ForEach(SearchMaxDepth.allCases, id: \.self) { depth in
                            Text(depth.label).tag(depth)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-Deepen When Current View Is Sparse", isOn: Binding(
                        get: { store.settings.searchAutoDeepen },
                        set: { val in
                            IOSHaptics.shared.toggle()
                            store.updateSettings { $0.searchAutoDeepen = val }
                        }
                    ))

                    Divider().opacity(0.25)

                    Text("Query Cache Limit")
                        .font(.system(size: 15, weight: .semibold))
                    Picker("Cache Limit", selection: Binding(
                        get: { store.settings.searchCacheLimit },
                        set: { limit in store.updateSettings { $0.searchCacheLimit = limit } }
                    )) {
                        ForEach([0, 32, 64, 128, 256], id: \.self) { limit in
                            Text(limit == 0 ? "Off" : "\(limit)").tag(limit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("\(store.searchIndexStats.indexedRecordCount) items · \(store.searchIndexStats.uniqueTokenCount) tokens · \(store.searchIndexStats.cachedQueryCount) cached")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())

                    HStack(spacing: 10) {
                        Button {
                            IOSHaptics.shared.tap()
                            store.clearSearchCache()
                        } label: {
                            Label("Clear Cache", systemImage: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(RowePressScaleStyle())

                        Button {
                            IOSHaptics.shared.tap()
                            store.rebuildSearchIndex()
                        } label: {
                            Label("Rebuild Index", systemImage: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            .padding(18)
        }
        .navigationTitle("Global Search & Index")
        .navigationBarTitleDisplayMode(.inline)
    }
}

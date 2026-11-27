import SwiftUI
import RoweCore

enum SettingsCategory: String, CaseIterable {
    case spaceSettings = "Space Settings"
    case stats = "Stats"
    case appearance = "Appearance & Sound"
    case focusPatterns = "Focus Patterns"
    case advanced = "Advanced"
    case account = "Account Settings"
    case notifications = "Notifications"
    case diagnostics = "Diagnostics"
    case about = "About"

    var icon: String {
        switch self {
        case .spaceSettings: "gearshape"
        case .stats: "chart.pie"
        case .appearance: "textformat"
        case .focusPatterns: "waveform.and.magnifyingglass"
        case .advanced: "slider.horizontal.3"
        case .account: "person"
        case .notifications: "bell"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var store: WorkspaceStore
    @State private var editedSpaceName: String = ""

    private var selectedCategory: SettingsCategory {
        SettingsCategory(rawValue: store.selectedSettingsSectionId) ?? .appearance
    }
    @State private var editedAuthorName: String = ""
    @State private var editedEmail: String = ""
    @State private var editedBio: String = ""
    @State private var craftImportStatus: String?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 220)
                .background(MacSidebarBackdrop())

            Divider().opacity(0.35)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    GlassCircleButton(systemImage: "xmark", helpText: "Close Settings") {
                        store.navigate(to: .allDocs)
                    }
                    GlassCircleButton(systemImage: "chevron.left", helpText: "Back") {
                        store.goBack()
                    }
                    Text(selectedCategory.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedCategory {
                        case .spaceSettings: spaceSettingsBody
                        case .stats: statsBody
                        case .appearance: appearanceBody
                        case .focusPatterns: FocusPatternsSettingsView(store: store)
                        case .advanced: advancedBody
                        case .account: accountBody
                        case .notifications: notificationsBody
                        case .diagnostics: diagnosticsBody
                        case .about: aboutBody
                        }
                    }
                    .frame(maxWidth: 660, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            editedSpaceName = store.space.name
            editedAuthorName = store.space.authorName
            editedEmail = store.space.email
            editedBio = store.space.bio
        }
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        SpaceAvatarView(space: store.space, size: 68, cornerRadius: 16)
                        Text(store.isSignedIn ? "Synced" : "Local")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(store.isSignedIn ? Color.green.opacity(0.85) : Color.black.opacity(0.82)))
                            .offset(x: 4, y: 4)
                    }
                    Text(store.space.name)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                settingsGroupHeader("Space Settings")
                settingsNavRow(.stats)
                settingsNavRow(.spaceSettings)

                settingsGroupHeader("General Settings")
                settingsNavRow(.appearance)
                settingsNavRow(.focusPatterns)
                settingsNavRow(.advanced)

                settingsGroupHeader("Your Account")
                settingsNavRow(.account)
                settingsNavRow(.notifications)

                Divider().opacity(0.3).padding(.vertical, 8)
                settingsNavRow(.diagnostics)
                settingsNavRow(.about)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    private func settingsGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func settingsNavRow(_ cat: SettingsCategory) -> some View {
        let selected = selectedCategory == cat
        return Button {
            HapticsManager.shared.tap()
            store.selectedSettingsSectionId = cat.rawValue
        } label: {
            HStack(spacing: 9) {
                Image(systemName: cat.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(width: 18)
                Text(cat.rawValue)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.primary.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Space Settings (with Local Avatar Picker)

    @ViewBuilder
    private var spaceSettingsBody: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                SpaceAvatarView(space: store.space, size: 96, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 3)

                GlassCircleButton(systemImage: "photo.badge.plus", helpText: "Choose Profile Picture", size: 32) {
                    if let b64 = SpaceAvatarView.pickAvatarImageBase64() {
                        store.updateAvatarImageBase64(b64)
                    }
                }
                .offset(x: 6, y: 6)
            }

            if store.space.avatarImageBase64 != nil {
                Button("Remove Picture") {
                    HapticsManager.shared.tap()
                    store.updateAvatarImageBase64(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        settingsCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Space Name")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("Space Name", text: $editedSpaceName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .onSubmit { store.updateSpaceName(editedSpaceName) }
                    .onChange(of: editedSpaceName) { _, val in store.updateSpaceName(val) }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Import from Craft")
                .font(.system(size: 13, weight: .semibold))
            settingsCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import All Docs from Craft App")
                            .font(.system(size: 13, weight: .medium))
                        Text("Select a Craft Markdown or JSON export folder to import all docs and preserve folders.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassPillButton("Import Folder", systemImage: "square.and.arrow.down.on.square") {
                        importFromCraftPicker()
                    }
                }
                if let status = craftImportStatus {
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .transition(.roweUnblur)
                }
            }
        }
    }

    private func importFromCraftPicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Craft Export Folder or Documents"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task {
            let count = await store.importCraftExport(from: urls)
            withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                craftImportStatus = count > 0
                    ? "Imported \(count) document\(count == 1 ? "" : "s") from Craft."
                    : "No Markdown or Craft JSON files found in that folder."
            }
        }
    }

    @ViewBuilder
    private var statsBody: some View {
        let bytesFormatted = ByteCountFormatter.string(fromByteCount: store.stats.storageBytes, countStyle: .file)
        settingsCard {
            statRow("Storage Used", value: "\(bytesFormatted) / Local Disk")
        }
        settingsCard {
            statRow("Documents", value: "\(store.stats.documentCount)")
            Divider().opacity(0.25)
            statRow("Blocks", value: "\(store.stats.blockCount)")
            Divider().opacity(0.25)
            statRow("Pages", value: "\(store.stats.pageCount)")
            Divider().opacity(0.25)
            statRow("Words", value: "\(store.stats.wordCount)")
            Divider().opacity(0.25)
            statRow("Characters", value: "\(store.stats.characterCount)")
            Divider().opacity(0.25)
            let hrs = store.stats.estimatedReadingMinutes / 60
            let mins = store.stats.estimatedReadingMinutes % 60
            statRow("Reading Time", value: hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m")
        }
    }

    @ViewBuilder
    private var appearanceBody: some View {
        HStack(spacing: 16) {
            RoweGlassGlowArtworkView(kind: .documents, size: 54, speed: 0.72, glow: 1.05)
            VStack(alignment: .leading, spacing: 3) {
                Text("Appearance & Craft")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Customize theme, accent color, sound, and tactile document feel.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))

        HStack(spacing: 18) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let isSelected = store.settings.appearanceMode == mode
                Button {
                    HapticsManager.shared.tap()
                    store.updateSettings { $0.appearanceMode = mode }
                } label: {
                    VStack(spacing: 8) {
                        AppearanceModeArtwork(mode: mode)
                            .frame(height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.75)
                            )
                        Text(mode.rawValue)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))

        VStack(alignment: .leading, spacing: 8) {
            Text("Interface Accent Color")
                .font(.system(size: 13, weight: .semibold))
            Text("Controls across the app will use the selected accent color.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(AccentColorChoice.allCases, id: \.self) { choice in
                    let isSelected = store.settings.accentColor == choice
                    Button {
                        HapticsManager.shared.tap()
                        store.updateSettings { $0.accentColor = choice }
                    } label: {
                        Circle()
                            .fill(Color(hex: choice.hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Sound & Haptics")
                .font(.system(size: 13, weight: .semibold))
            settingsCard {
                Toggle("Enable Sound", isOn: Binding(
                    get: { store.settings.enableSound },
                    set: { val in
                        store.updateSettings { $0.enableSound = val }
                        SoundManager.shared.isEnabled = val
                        HapticsManager.shared.toggle()
                    }
                ))
                Divider().opacity(0.25)
                Toggle("Enable Haptics", isOn: Binding(
                    get: { store.settings.enableHaptics },
                    set: { val in
                        store.updateSettings { $0.enableHaptics = val }
                        HapticsManager.shared.isEnabled = val
                        if val { HapticsManager.shared.taskCrossOutBuzz() }
                    }
                ))
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Additional Options")
                .font(.system(size: 13, weight: .semibold))
            settingsCard {
                Toggle("Apply Document Style to the App", isOn: Binding(
                    get: { store.settings.applyDocumentStyleToApp },
                    set: { val in
                        HapticsManager.shared.toggle()
                        store.updateSettings { $0.applyDocumentStyleToApp = val }
                    }
                ))
                Divider().opacity(0.25)
                Toggle("Reduce Animations", isOn: Binding(
                    get: { store.settings.reduceAnimations },
                    set: { val in
                        HapticsManager.shared.toggle()
                        store.updateSettings { $0.reduceAnimations = val }
                    }
                ))
                Divider().opacity(0.25)
                Toggle("Crazy Task Compose Animation", isOn: Binding(
                    get: { store.settings.crazyTaskComposeAnimation },
                    set: { val in
                        HapticsManager.shared.toggle()
                        store.updateSettings { $0.crazyTaskComposeAnimation = val }
                    }
                ))
                Divider().opacity(0.25)
                Toggle("Crazy Sync Animation", isOn: Binding(
                    get: { store.settings.crazySyncAnimation },
                    set: { val in
                        HapticsManager.shared.toggle()
                        store.updateSettings { $0.crazySyncAnimation = val }
                    }
                ))
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Application Icon")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose between Light and Dark macOS application icons.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(RoweIconVariant.allCases) { variant in
                    let isSelected = store.settings.selectedAppIconIndex == variant.rawValue
                    Button {
                        HapticsManager.shared.tap()
                        store.updateSettings { $0.selectedAppIconIndex = variant.rawValue }
                        RoweAppIconRenderer.applyDockIcon(
                            variantIndex: variant.rawValue,
                            accentHex: store.settings.accentColor.hex
                        )
                    } label: {
                        VStack(spacing: 6) {
                            RoweAppIconPreview(
                                variant: variant,
                                accentHex: store.settings.accentColor.hex,
                                size: 54
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.2)
                                    .padding(-3)
                            )
                            Text(variant.label)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private var advancedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global Search & Index (⌘K)").font(.system(size: 13, weight: .semibold))
            settingsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maximum Search Depth")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Controls how far ⌘K deepens when nothing is found in your current view.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    LiquidGlassSegmentedControl(
                        items: SearchMaxDepth.allCases,
                        selection: Binding(
                            get: { store.settings.searchMaxDepth },
                            set: { depth in store.updateSettings { $0.searchMaxDepth = depth } }
                        ),
                        height: 30,
                        title: \.label
                    )
                }

                Divider().opacity(0.25)

                Toggle("Auto-Deepen When Current View Is Sparse", isOn: Binding(
                    get: { store.settings.searchAutoDeepen },
                    set: { val in
                        HapticsManager.shared.toggle()
                        store.updateSettings { $0.searchAutoDeepen = val }
                    }
                ))

                Divider().opacity(0.25)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Query Cache Limit")
                        .font(.system(size: 12.5, weight: .medium))
                    LiquidGlassSegmentedControl(
                        items: [0, 32, 64, 128, 256],
                        selection: Binding(
                            get: { store.settings.searchCacheLimit },
                            set: { limit in store.updateSettings { $0.searchCacheLimit = limit } }
                        ),
                        height: 30,
                        title: { $0 == 0 ? "Off" : "\($0)" }
                    )
                }

                Divider().opacity(0.25)

                HStack(spacing: 8) {
                    Text("\(store.searchIndexStats.indexedRecordCount) items · \(store.searchIndexStats.uniqueTokenCount) tokens · \(store.searchIndexStats.cachedQueryCount) cached")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    GlassPillButton("Clear Cache", systemImage: "trash") {
                        store.clearSearchCache()
                    }
                    GlassPillButton("Rebuild Index", systemImage: "arrow.clockwise") {
                        store.rebuildSearchIndex()
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance").font(.system(size: 13, weight: .semibold))
            settingsCard {
                HStack {
                    Text("Completed Tasks in Docs")
                        .font(.system(size: 13))
                    Spacer()
                    RoweGlassMenuPicker(
                        items: CompletedTaskStyle.allCases,
                        selection: Binding(
                            get: { store.settings.completedTaskStyle },
                            set: { val in store.updateSettings { $0.completedTaskStyle = val } }
                        ),
                        titleForItem: \.rawValue
                    )
                }
                Divider().opacity(0.25)
                HStack {
                    Text("Date Links")
                        .font(.system(size: 13))
                    Spacer()
                    RoweGlassMenuPicker(
                        items: DateLinkStyle.allCases,
                        selection: Binding(
                            get: { store.settings.dateLinkStyle },
                            set: { val in store.updateSettings { $0.dateLinkStyle = val } }
                        ),
                        titleForItem: \.rawValue
                    )
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar").font(.system(size: 13, weight: .semibold))
            settingsCard {
                HStack {
                    Text("Start Week On")
                        .font(.system(size: 13))
                    Spacer()
                    RoweGlassMenuPicker(
                        items: WeekStartDay.allCases,
                        selection: Binding(
                            get: { store.settings.weekStartDay },
                            set: { val in store.updateSettings { $0.weekStartDay = val } }
                        ),
                        titleForItem: \.rawValue
                    )
                }
                Divider().opacity(0.25)
                HStack {
                    Text("Default Start of Day")
                        .font(.system(size: 13))
                    Spacer()
                    RoweGlassStepper(
                        value: Binding(
                            get: { store.settings.defaultDayStartHour },
                            set: { val in store.updateSettings { $0.defaultDayStartHour = val } }
                        ),
                        range: 5...12,
                        displayValue: "\(store.settings.defaultDayStartHour):00"
                    )
                }
            }
        }

        settingsCard {
            Toggle("Select text across multiple blocks – Beta", isOn: Binding(
                get: { store.settings.multiBlockInlineSelection },
                set: { val in
                    HapticsManager.shared.toggle()
                    store.updateSettings { $0.multiBlockInlineSelection = val }
                }
            ))
        }
    }

    @ViewBuilder
    private var notificationsBody: some View {
        settingsCard {
            Toggle("Push Notifications", isOn: Binding(
                get: { store.settings.pushNotificationsEnabled },
                set: { val in store.updateSettings { $0.pushNotificationsEnabled = val } }
            ))
            Divider().opacity(0.25)
            Toggle("Email Notifications", isOn: Binding(
                get: { store.settings.emailNotificationsEnabled },
                set: { val in store.updateSettings { $0.emailNotificationsEnabled = val } }
            ))
            Divider().opacity(0.25)
            Toggle("Receive Daily Email", isOn: Binding(
                get: { store.settings.dailyEmailEnabled },
                set: { val in store.updateSettings { $0.dailyEmailEnabled = val } }
            ))
        }
    }

    @ViewBuilder
    private var diagnosticsBody: some View {
        settingsCard {
            statRow("Space", value: store.space.name)
            Divider().opacity(0.25)
            statRow(store.syncDiagnostics.status.rawValue, value: store.syncDiagnostics.lastSyncedAt.formatted(date: .numeric, time: .standard))
            Divider().opacity(0.25)
            Button {
                HapticsManager.shared.tap()
                store.triggerSyncNow()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }

        settingsCard {
            statRow(
                "Sync History",
                value: "New: \(store.syncDiagnostics.pendingCount) > Uploading: \(store.syncDiagnostics.uploadingCount) > Synced: \(store.syncDiagnostics.syncedCount)"
            )
        }

        settingsCard {
            Button(role: .destructive) {
                HapticsManager.shared.destructive()
                store.resetSync()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reset Sync Now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("Resets the local sync scheduler queue. Your local documents remain intact.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Local Account Profile

    @ViewBuilder
    private var accountBody: some View {
        HStack(spacing: 16) {
            SpaceAvatarView(space: store.space, size: 64, cornerRadius: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(editedAuthorName.isEmpty ? "Local Profile" : editedAuthorName)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    GlassPillButton("Choose Photo", systemImage: "photo") {
                        if let b64 = SpaceAvatarView.pickAvatarImageBase64() {
                            store.updateAvatarImageBase64(b64)
                        }
                    }
                    if store.space.avatarImageBase64 != nil {
                        Button("Remove") {
                            HapticsManager.shared.tap()
                            store.updateAvatarImageBase64(nil)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))

        settingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name").font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField("Your Name", text: $editedAuthorName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium))
                    .onChange(of: editedAuthorName) { _, val in store.updateProfile(authorName: val) }
            }
            Divider().opacity(0.25)
            VStack(alignment: .leading, spacing: 4) {
                Text("Email").font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField("you@example.com", text: $editedEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .onChange(of: editedEmail) { _, val in store.updateProfile(email: val) }
            }
            Divider().opacity(0.25)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bio").font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField("Short note about yourself…", text: $editedBio)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .onChange(of: editedBio) { _, val in store.updateProfile(bio: val) }
            }
            Divider().opacity(0.25)
            HStack(spacing: 14) {
                RoweGlassGlowArtworkView(kind: .syncOrbit, size: 46, speed: 0.72, glow: 1.0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud Sync Account")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    if let sess = store.authSession {
                        Text("Signed in as \(sess.user.email) · \(sess.serverURL)")
                            .font(.system(size: 13, weight: .medium))
                        if let syncMsg = store.lastSyncStatusMessage {
                            Text(syncMsg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Local Mode — sign in to sync across devices")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                Spacer()
                if store.isSignedIn {
                    HStack(spacing: 8) {
                        GlassPillButton("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await store.syncWithBackend() }
                        }
                        GlassPillButton("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", tint: .red) {
                            Task { await store.signOut() }
                        }
                    }
                } else {
                    GlassPillButton("Sign In", systemImage: "person.badge.key") {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            store.isLoginSheetPresented = true
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Locked Notes (Zero-Knowledge PIN)")
                .font(.system(size: 13, weight: .semibold))
            settingsCard {
                HStack(spacing: 14) {
                    RoweGlassGlowArtworkView(kind: .vaultLock, size: 46, speed: 0.72, glow: 1.0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.hasVaultPin ? "PIN Lock Enabled (\(store.vaultEnvelope?.pinLength ?? 6)-Digit)" : "No Lock PIN Set")
                            .font(.system(size: 13, weight: .medium))
                        Text("Locked notes are encrypted with AES-256-GCM on-device before syncing.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.hasVaultPin {
                        HStack(spacing: 8) {
                            if !store.unlockedDocumentIds.isEmpty {
                                GlassPillButton("Lock All", systemImage: "lock.fill") {
                                    store.relockAllDocuments()
                                }
                            }
                            GlassPillButton("Change PIN", systemImage: "key") {
                                store.pinPromptRequest = .changePin
                            }
                        }
                    } else {
                        GlassPillButton("Set Up PIN", systemImage: "lock.badge.plus") {
                            store.pinPromptRequest = .setupPin(lockDocumentId: nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aboutBody: some View {
        // GlassGlow Metal hero card in Settings -> About
        HStack(spacing: 18) {
            RoweRibbonMark()
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white)
                .frame(width: 72, height: 54)
                .glassGlow(
                    GlassGlowPalette(
                        Color(white: 0.96),
                        Color(white: 0.56),
                        Color(white: 0.22)
                    ),
                    speed: 0.72,
                    glow: 0.95
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Rowe for macOS")
                    .font(.system(size: 16, weight: .bold))
                Text("Shared RoweCore (Swift 6) · Liquid Glass · Zero-Knowledge Vault")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GlassPillButton("Reset Onboarding", systemImage: "sparkles") {
                store.updateSettings { $0.hasCompletedOnboarding = false }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))

        settingsCard {
            statRow("App", value: "Rowe for macOS")
            Divider().opacity(0.25)
            statRow("Architecture", value: "Shared RoweCore (Swift 6) + SwiftUI Liquid Glass + GlassGlow Metal")
            Divider().opacity(0.25)
            statRow("Trackpad Haptics", value: "Force Touch Taptic Patterns Enabled")
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func statRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13.5, weight: .medium))
        }
    }
}

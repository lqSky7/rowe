import DeviceActivity
import FamilyControls
import SwiftUI
import UserNotifications
import RoweCore

/// Native iOS Settings Form for Rowe's Apple Screen Time-powered Adaptive Focus system.
/// Uses `FamilyControls` + `DeviceActivityReport` (instant 7-day historical Screen Time on Day 1)
/// + native `FamilyActivityPicker` (zero package-name typing) + `info.circle` dialogs.
struct IOSFocusPatternsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var focusManager = IOSFocusManager.shared
    @State private var bannerSent: Bool = false
    @State private var activeInfo: FocusInfoTopic?
    @State private var showActivityPicker: Bool = false
    @State private var showSiteSelector: Bool = false

    private enum FocusInfoTopic: String, Identifiable {
        case nudges
        case screentime
        case circadian
        case learned
        case allowlist

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nudges: "Adaptive Task Nudges"
            case .screentime: "Apple Screen Time"
            case .circadian: "Circadian Rhythm"
            case .learned: "Learned Windows"
            case .allowlist: "Work & Study Allowlist"
            }
        }

        var message: String {
            switch self {
            case .nudges:
                "Rowe reads your Apple Screen Time patterns and offers a quick (≤ 25 min) unlocked task before long sessions. It never blocks apps, never reads PIN-locked notes, and stays silent when you have no quick tasks."
            case .screentime:
                "Uses Apple's native FamilyControls & DeviceActivity frameworks so monitoring runs inside iOS Screen Time with 0% background battery drain, and your existing 7-day Screen Time history is usable immediately."
            case .circadian:
                "Displays your past 7 days of Apple Screen Time grouped into 2-hour windows alongside your top apps—available immediately from your existing Screen Time history."
            case .learned:
                "As you accept or dismiss nudges, Rowe learns which hours welcome a quick task and automatically mutes hours where you prefer to unwind, gently re-checking once every ~3 weeks."
            case .allowlist:
                "Sites and apps listed here are always treated as productive across your devices."
            }
        }
    }

    private var sevenDayFilter: DeviceActivityFilter {
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: weekAgo, end: now)),
            users: .all,
            devices: .init([.iPhone, .iPad, .mac])
        )
    }

    private var silencedSlots: [(key: String, label: String, rec: SlotReceptivity)] {
        store.focusBehavior.receptivityBySlot
            .filter { $0.value.isAutoSilenced }
            .map { (key, rec) in (key, humanLabel(forStorageKey: key), rec) }
            .sorted { $0.label < $1.label }
    }

    private var learnedActiveSlots: [(key: String, label: String, rec: SlotReceptivity)] {
        store.focusBehavior.receptivityBySlot
            .filter { !$0.value.isAutoSilenced && ($0.value.acceptedCount + $0.value.dismissedCount) > 0 }
            .map { (key, rec) in (key, humanLabel(forStorageKey: key), rec) }
            .sorted { $0.rec.score > $1.rec.score }
    }

    var body: some View {
        Form {
            focusOverviewSection
            screenTimeAccessSection
            focusNudgesSection
            circadianHistorySection
            learnedWindowsSection
            allowlistSection
        }
        .navigationTitle("Focus Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .familyActivityPicker(isPresented: $showActivityPicker, selection: $focusManager.activitySelection)
        .sheet(isPresented: $showSiteSelector) {
            IOSAllowlistSelectorSheet(store: store)
        }
        .alert(
            activeInfo?.title ?? "",
            isPresented: Binding(
                get: { activeInfo != nil },
                set: { if !$0 { activeInfo = nil } }
            ),
            presenting: activeInfo
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { topic in
            Text(topic.message)
        }
        .task {
            focusManager.refreshScreenTimeStatus()
            await focusManager.refreshNotificationStatus()
        }
    }

    private var focusOverviewSection: some View {
        Section {
            HStack(spacing: 16) {
                RoweGlassGlowArtworkView(kind: .focusPermissions, size: 54, speed: 0.72, glow: 1.05)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Adaptive Focus")
                        .font(.headline)
                    Text("Powered by Apple Screen Time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var screenTimeAccessSection: some View {
        Section {
            if focusManager.isScreenTimeAuthorized {
                HStack {
                    Label("Screen Time", systemImage: "hourglass")
                    Spacer()
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Button {
                    IOSHaptics.shared.tap()
                    showActivityPicker = true
                } label: {
                    HStack {
                        Label("Choose Apps & Websites", systemImage: "apps.iphone")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(focusManager.selectedItemsCount > 0 ? "\(focusManager.selectedItemsCount) selected" : "All Activity")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    IOSHaptics.shared.tap()
                    Task { _ = await focusManager.requestScreenTimeAuthorization() }
                } label: {
                    Label("Allow Apple Screen Time", systemImage: "hourglass.badge.plus")
                        .fontWeight(.semibold)
                }

                if let err = focusManager.lastAuthorizationError, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Apple Screen Time", info: .screentime)
        }
    }

    private var focusNudgesSection: some View {
        Section {
            Toggle("Adaptive Task Nudges", isOn: Binding(
                get: { store.focusBehavior.isEnabled },
                set: { val in
                    IOSHaptics.shared.toggle()
                    store.toggleFocusEnabled(val)
                    if val {
                        focusManager.startScreenTimeMonitoring()
                    } else {
                        focusManager.stopScreenTimeMonitoring()
                    }
                }
            ))

            Button {
                IOSHaptics.shared.tap()
                Task {
                    await focusManager.sendPreviewBanner(for: store)
                    withAnimation { bannerSent = true }
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { bannerSent = false }
                }
            } label: {
                HStack {
                    Label("Test Banner Nudge", systemImage: "bell.badge")
                    Spacer()
                    if bannerSent {
                        Text("Sent")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("Focus Nudges", info: .nudges)
        }
    }

    private var circadianHistorySection: some View {
        Section {
            if focusManager.isScreenTimeAuthorized {
                DeviceActivityReport(.roweCircadianHistory, filter: sevenDayFilter)
                    .frame(minHeight: 150)
            } else {
                Text("Allow Screen Time above to load your past 7 days immediately.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Circadian Rhythm · 7 Days", info: .circadian)
        }
    }

    private var learnedWindowsSection: some View {
        Section {
            if silencedSlots.isEmpty && learnedActiveSlots.isEmpty {
                Text("No learned windows yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(silencedSlots, id: \.key) { item in
                    HStack {
                        Label(item.label, systemImage: "bell.slash")
                            .lineLimit(1)
                        Spacer()
                        Button("Unmute") {
                            IOSHaptics.shared.tap()
                            store.unmuteFocusSlot(storageKey: item.key)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                ForEach(learnedActiveSlots.prefix(5), id: \.key) { item in
                    HStack {
                        Text(item.label)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((item.rec.score * 100).rounded()))%")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("Learned Windows", info: .learned)
        }
    }

    private var allowlistSection: some View {
        Section {
            Button {
                IOSHaptics.shared.tap()
                showSiteSelector = true
            } label: {
                Label("Select Work & Study Sites", systemImage: "plus.circle")
            }

            ForEach(store.focusBehavior.allowlistedDomains, id: \.self) { domain in
                HStack(spacing: 10) {
                    Image(systemName: RoweAllowlistPreset.icon(for: domain))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(RoweAllowlistPreset.displayName(for: domain))
                    Spacer()
                    if RoweAllowlistPreset.displayName(for: domain) != domain {
                        Text(domain)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        IOSHaptics.shared.tap()
                        store.removeFocusAllowlistedDomain(domain)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { offsets in
                let domains = store.focusBehavior.allowlistedDomains
                for idx in offsets {
                    store.removeFocusAllowlistedDomain(domains[idx])
                }
            }
        } header: {
            sectionHeader("Work & Study Allowlist", info: .allowlist)
        }
    }

    private func sectionHeader(_ title: String, info: FocusInfoTopic) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                IOSHaptics.shared.tap()
                activeInfo = info
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func humanLabel(forStorageKey key: String) -> String {
        let parts = key.split(separator: "|").map(String.init)
        guard parts.count == 3, let slotIdx = Int(parts[2]) else { return key }
        let app = CanonicalTargetRegistry.displayName(for: parts[0])
        let day = parts[1].capitalized
        let slot = FocusSlotKey(canonicalTarget: parts[0], dayType: DayType(rawValue: parts[1]) ?? .weekday, twoHourSlot: slotIdx)
        return "\(app) · \(day) \(slot.humanTimeWindow)"
    }
}

// MARK: - Native iOS Visual Site Selector Sheet

private struct IOSAllowlistSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore

    @State private var searchText: String = ""
    @State private var customDomain: String = ""

    private var categories: [String] {
        var seen: [String] = []
        for p in RoweAllowlistPreset.all where !seen.contains(p.category) {
            seen.append(p.category)
        }
        return seen
    }

    private var filteredPresets: [RoweAllowlistPreset] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return RoweAllowlistPreset.all }
        return RoweAllowlistPreset.all.filter {
            $0.name.lowercased().contains(q) || $0.domain.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(categories, id: \.self) { category in
                    let items = filteredPresets.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category) {
                            ForEach(items) { preset in
                                let isSelected = store.focusBehavior.allowlistedDomains.contains(preset.domain)
                                Button {
                                    IOSHaptics.shared.tap()
                                    if isSelected {
                                        store.removeFocusAllowlistedDomain(preset.domain)
                                    } else {
                                        store.addFocusAllowlistedDomain(preset.domain)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: preset.icon)
                                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name)
                                                .foregroundStyle(.primary)
                                            Text(preset.domain)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Other Website") {
                    HStack {
                        TextField("e.g. university.edu", text: $customDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { addCustom() }

                        if !customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Add") { addCustom() }
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Select Sites")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Filter sites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addCustom() {
        let trimmed = customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        IOSHaptics.shared.tap()
        store.addFocusAllowlistedDomain(trimmed)
        customDomain = ""
    }
}

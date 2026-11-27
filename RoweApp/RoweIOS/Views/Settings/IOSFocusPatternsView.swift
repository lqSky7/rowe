import SwiftUI
import UserNotifications
import RoweCore

/// Native iOS Settings Form for Rowe's Adaptive Focus system.
/// Reuses onboarding GlassGlow artwork, uses standard iOS `Form` / `Section` controls,
/// gates explanatory text behind `i` buttons, and uses a visual Site Selector sheet.
struct IOSFocusPatternsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var bannerSent: Bool = false
    @State private var activeInfo: FocusInfoTopic?
    @State private var showSiteSelector: Bool = false

    private enum FocusInfoTopic: String, Identifiable {
        case nudges
        case circadian
        case observed
        case learned
        case shortcuts
        case allowlist

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nudges: "Adaptive Task Nudges"
            case .circadian: "Circadian Rhythm"
            case .observed: "Observed Apps & Sites"
            case .learned: "Learned Windows"
            case .shortcuts: "Instant 0-Second iPhone Nudges"
            case .allowlist: "Work & Study Allowlist"
            }
        }

        var message: String {
            switch self {
            case .nudges:
                "Rowe observes your scroll rhythm across Mac and iPhone and suggests a quick (≤ 25 min) unlocked task before long sessions. It never blocks apps, never reads PIN-locked notes, and stays silent if you have no quick tasks."
            case .circadian:
                "Shows your deduplicated 7-day scroll minutes across Mac and iPhone grouped into 2-hour windows. Overlapping sessions on both devices are merged so time is never double-counted."
            case .observed:
                "Rowe observes silently for the first 3 sessions per app to calibrate your typical session length before offering suggestions."
            case .learned:
                "As you accept or dismiss nudges, Rowe learns which time windows welcome a quick task and automatically mutes hours where you prefer to unwind, gently re-checking once every ~3 weeks."
            case .shortcuts:
                "To trigger instant non-blocking banners when you open Instagram, YouTube, or Reddit:\n\n1. Open Apple Shortcuts → Automation → + → App.\n2. Pick the app (Is Opened + Run Immediately) and add Rowe's \"Log App Opened for Focus Nudge\".\n3. Optional: add an Is Closed automation with \"Log App Closed\" for exact session length."
            case .allowlist:
                "Browsers are never tracked as a whole — only distraction domains. Pick work or study sites so they are always ignored. Only aggregate rhythm syncs across devices."
            }
        }
    }

    private var accent: Color { Color(hex: store.settings.accentColor.hex) }

    private var circadianSlots: [Double] {
        store.circadianFocusMinutes(daysBack: 7)
    }

    private var totalMinutes7d: Int {
        Int(circadianSlots.reduce(0, +).rounded())
    }

    private var observedTargets: [(slug: String, name: String, icon: String, sessions: Int, medianMins: Int)] {
        let engine = FocusNudgeEngine()
        let slugs = Array(Set(store.focusBehavior.intervals.map(\.canonicalTarget)))
        var rows: [(slug: String, name: String, icon: String, sessions: Int, medianMins: Int)] = []
        for slug in slugs {
            let sessions = engine.mergedSessions(for: slug, from: store.focusBehavior.intervals)
            guard !sessions.isEmpty else { continue }
            let sortedMins = sessions.map(\.durationMinutes).sorted()
            let med = sortedMins[sortedMins.count / 2]
            rows.append((
                slug: slug,
                name: CanonicalTargetRegistry.displayName(for: slug),
                icon: CanonicalTargetRegistry.iconName(for: slug),
                sessions: sessions.count,
                medianMins: max(1, Int(med.rounded()))
            ))
        }
        return rows.sorted { $0.medianMins > $1.medianMins }
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
            // Reused Onboarding GlassGlow Focus Artwork Header
            Section {
                HStack(spacing: 16) {
                    RoweGlassGlowArtworkView(kind: .focusPermissions, size: 54, speed: 0.72, glow: 1.05)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Adaptive Focus")
                            .font(.headline)
                        Text("Calm, non-blocking task nudges.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // 1. Master Toggle & Preview
            Section {
                Toggle("Adaptive Task Nudges", isOn: Binding(
                    get: { store.focusBehavior.isEnabled },
                    set: { val in
                        IOSHaptics.shared.toggle()
                        store.toggleFocusEnabled(val)
                    }
                ))

                Button {
                    IOSHaptics.shared.tap()
                    Task {
                        await IOSFocusManager.shared.sendPreviewBanner(for: store)
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

            // 2. Circadian Rhythm
            Section {
                circadianChartRow
            } header: {
                sectionHeader("Circadian Rhythm · 7 Days", info: .circadian)
            }

            // 3. Observed Apps & Sites
            Section {
                if observedTargets.isEmpty {
                    Text("Observing silently")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(observedTargets, id: \.slug) { row in
                        HStack(spacing: 12) {
                            Image(systemName: row.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            Text(row.name)
                            Spacer()
                            Text("~\(formatMinutes(row.medianMins)) · \(row.sessions)×")
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                sectionHeader("Observed Apps & Sites", info: .observed)
            }

            // 4. Learned Windows & Muted Slots
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

            // 5. iPhone 0-Second Shortcuts Automation (gated behind i button)
            Section {
                Button {
                    IOSHaptics.shared.tap()
                    activeInfo = .shortcuts
                } label: {
                    HStack {
                        Label("Shortcuts 0s Setup Guide", systemImage: "bolt.horizontal")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                sectionHeader("iPhone Automation", info: .shortcuts)
            }

            // 6. Visual Work & Study Allowlist Selector
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
        .navigationTitle("Focus Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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
            await IOSFocusManager.shared.refreshNotificationStatus()
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

    private var circadianChartRow: some View {
        let slots = circadianSlots
        let maxVal = max(30.0, slots.max() ?? 30.0)
        let peakIndex = slots.enumerated().max(by: { $0.element < $1.element })?.offset

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(totalMinutes7d > 0 ? formatMinutes(totalMinutes7d) : "Calibrating")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let peak = peakIndex, slots[peak] > 0 {
                    Text("Peak \(slotRangeShort(peak))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { idx in
                    let val = slots[idx]
                    let frac = max(0.08, min(1.0, val / maxVal))
                    let isPeak = (idx == peakIndex && val > 0)
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            val > 0
                                ? (isPeak ? accent : Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                                : Color.primary.opacity(0.08)
                        )
                        .frame(height: max(5, CGFloat(frac) * 56))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60, alignment: .bottom)

            HStack {
                Text("12a")
                Spacer()
                Text("4a")
                Spacer()
                Text("8a")
                Spacer()
                Text("12p")
                Spacer()
                Text("4p")
                Spacer()
                Text("8p")
                Spacer()
                Text("12a")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatMinutes(_ mins: Int) -> String {
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(mins)m"
    }

    private func slotRangeShort(_ idx: Int) -> String {
        let start = idx * 2
        let end = (start + 2) % 24
        func f(_ h: Int) -> String {
            if h == 0 { return "12a" }
            if h == 12 { return "12p" }
            return h < 12 ? "\(h)a" : "\(h - 12)p"
        }
        return "\(f(start))–\(f(end))"
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

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoweCore

/// Non-AI-slop, Apple-native editorial Settings view for Rowe's Adaptive Focus & Behavioral Nudge system.
/// Reuses onboarding GlassGlow Focus artwork, uses a visual Site & App Selector (no raw typing),
/// and opens System Settings directly for macOS Accessibility permission.
struct FocusPatternsSettingsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAllowlistSelector = false
    private let tracker = MacFocusTracker.shared

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
        VStack(alignment: .leading, spacing: 22) {
            headerSection
            circadianRhythmCard
            observedTargetsCard
            receptivityCard
            allowlistCard
            permissionsAndPrivacyFooter
        }
        .onAppear {
            tracker.refreshScreenTimeStatus(importIfAvailable: true)
        }
        .sheet(isPresented: $showAllowlistSelector) {
            MacAllowlistSelectorSheet(store: store)
        }
    }

    // MARK: - 1. Header with Reused Onboarding GlassGlow Artwork & Master Toggle

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            surfaceCard {
                HStack(spacing: 16) {
                    RoweGlassGlowArtworkView(kind: .focusPermissions, size: 62, speed: 0.72, glow: 1.05)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus Patterns")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Observes your scroll rhythm across Mac and iPhone, suggesting a quick task before long sessions — never blocking apps.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Button {
                        let preview = store.makePreviewFocusSuggestion()
                        FocusNudgeHUDController.shared.show(suggestion: preview, store: store, isPreview: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                            Text("Preview Nudge")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.07))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            surfaceCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adaptive Task Nudges")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Silent when you have no quick (≤ 25 min) tasks or during auto-muted hours.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.focusBehavior.isEnabled },
                        set: { store.toggleFocusEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - 2. 24-Hour Circadian Rhythm Card

    private var circadianRhythmCard: some View {
        let slots = circadianSlots
        let maxVal = max(30.0, slots.max() ?? 30.0)
        let peakIndex = slots.enumerated().max(by: { $0.element < $1.element })?.offset

        return surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CIRCADIAN RHYTHM · LAST 7 DAYS")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(totalMinutes7d > 0 ? formatMinutes(totalMinutes7d) + " deduplicated across devices" : "Observing silently — calibrating your baseline")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if let peak = peakIndex, slots[peak] > 0 {
                        Text("Peak \(slotRangeShort(peak))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(0..<12, id: \.self) { idx in
                        let val = slots[idx]
                        let frac = max(0.06, min(1.0, val / maxVal))
                        let isPeak = (idx == peakIndex && val > 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                val > 0
                                    ? (isPeak ? accent : Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                                    : Color.primary.opacity(0.06)
                            )
                            .frame(height: max(5, CGFloat(frac) * 76))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 82, alignment: .bottom)

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
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 3. Observed Targets & Typical Duration

    private var observedTargetsCard: some View {
        let rows = observedTargets
        let maxMed = max(30, rows.map(\.medianMins).max() ?? 30)

        return surfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("OBSERVED APPS & SITES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                if rows.isEmpty {
                    Text("No scroll sessions recorded yet. Rowe observes silently for the first 3 sessions per app before suggesting tasks.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows, id: \.slug) { row in
                            HStack(spacing: 12) {
                                Image(systemName: row.icon)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(row.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("~\(formatMinutes(row.medianMins)) typical · \(row.sessions) \(row.sessions == 1 ? "session" : "sessions")")
                                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.06))
                                            Capsule()
                                                .fill(accent.opacity(0.75))
                                                .frame(width: max(8, geo.size.width * CGFloat(row.medianMins) / CGFloat(maxMed)))
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Learned Receptivity & Auto-Muted Slots

    private var receptivityCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LEARNED WINDOWS & MUTED SLOTS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto-checks every ~3 weeks")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if silencedSlots.isEmpty && learnedActiveSlots.isEmpty {
                    Text("As you tap ✓ or × on nudges, Rowe learns which time windows welcome a quick task and automatically silences windows where you prefer to unwind.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(silencedSlots, id: \.key) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.label)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text("Auto-muted · \(item.rec.dismissedCount) dismissed")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Unmute") {
                                    store.unmuteFocusSlot(storageKey: item.key)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                        }

                        ForEach(learnedActiveSlots.prefix(5), id: \.key) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int((item.rec.score * 100).rounded()))% receptive")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Visual Work & Study Allowlist Selector

    private var allowlistCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WORK & STUDY ALLOWLIST")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("Choose websites or Mac apps that Rowe should always treat as productive.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showAllowlistSelector = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12.5))
                            Text("Choose Sites & Apps…")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if store.focusBehavior.allowlistedDomains.isEmpty {
                    Text("No custom exceptions added — browsers are only observed on distraction domains.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    FlowChipStack(items: store.focusBehavior.allowlistedDomains) { domain in
                        store.removeFocusAllowlistedDomain(domain)
                    }
                }
            }
        }
    }

    // MARK: - 6. Permissions & Zero-Knowledge Footer

    private var permissionsAndPrivacyFooter: some View {
        surfaceCard {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Screen Time Data")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(tracker.hasScreenTimeAccess
                         ? "Reading 30-day Apple Screen Time history locally (0% polling). PIN-locked notes are never read."
                         : "Grant Full Disk Access so Rowe can read your existing Apple Screen Time history immediately.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if tracker.hasScreenTimeAccess {
                    HStack(spacing: 8) {
                        Button("Refresh History") {
                            tracker.importScreenTimeHistory(daysBack: 30)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))

                        Label("Screen Time Active", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
                } else {
                    Button {
                        tracker.requestScreenTimeAccess()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                            Text("Grant Screen Time Access")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func surfaceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07), lineWidth: 0.75)
                    )
            )
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

// MARK: - Visual Allowlist Selector Sheet (Sites + Installed Mac Apps + Browse)

private struct InstalledMacAppItem: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bundleId: String
}

private struct MacAllowlistSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore

    @State private var tab: Int = 0 // 0 = Websites, 1 = Mac Apps
    @State private var searchText: String = ""
    @State private var customDomain: String = ""
    @State private var installedApps: [InstalledMacAppItem] = []

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

    private var filteredApps: [InstalledMacAppItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return installedApps }
        return installedApps.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Work & Study Allowlist")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Picker("", selection: $tab) {
                Text("Popular Sites").tag(0)
                Text("Installed Apps").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12.5))
                TextField(tab == 0 ? "Filter websites…" : "Filter installed apps…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Divider().opacity(0.25)

            if tab == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(categories, id: \.self) { category in
                            let items = filteredPresets.filter { $0.category == category }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(category.uppercased())
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(.secondary)

                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(items) { preset in
                                            let isSelected = store.focusBehavior.allowlistedDomains.contains(preset.domain)
                                            Button {
                                                if isSelected {
                                                    store.removeFocusAllowlistedDomain(preset.domain)
                                                } else {
                                                    store.addFocusAllowlistedDomain(preset.domain)
                                                }
                                            } label: {
                                                HStack(spacing: 9) {
                                                    Image(systemName: preset.icon)
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                                        .frame(width: 20)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(preset.name)
                                                            .font(.system(size: 12.5, weight: .medium))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        Text(preset.domain)
                                                            .font(.system(size: 10.5, design: .monospaced))
                                                            .foregroundStyle(.tertiary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer(minLength: 4)
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.75)
                                                        )
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                }

                Divider().opacity(0.25)

                HStack(spacing: 8) {
                    TextField("Other website (e.g. university.edu)", text: $customDomain)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .onSubmit { addCustom() }

                    Button("Add") { addCustom() }
                        .disabled(customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredApps) { app in
                            let key = app.name.lowercased()
                            let isSelected = store.focusBehavior.allowlistedDomains.contains(key)
                            Button {
                                if isSelected {
                                    store.removeFocusAllowlistedDomain(key)
                                } else {
                                    store.addFocusAllowlistedDomain(key)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }

                Divider().opacity(0.25)

                HStack {
                    Text("Missing an app?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Browse Applications…") {
                        browseAppBundle()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 480, height: 500)
        .onAppear { loadInstalledApps() }
    }

    private func addCustom() {
        let trimmed = customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addFocusAllowlistedDomain(trimmed)
        customDomain = ""
    }

    private func loadInstalledApps() {
        guard installedApps.isEmpty else { return }
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var found: [InstalledMacAppItem] = []
        var seenNames = Set<String>()
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension.lowercased() == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                guard !seenNames.contains(name) else { continue }
                seenNames.insert(name)
                let bundleId = Bundle(url: url)?.bundleIdentifier ?? name
                found.append(InstalledMacAppItem(name: name, path: url.path, bundleId: bundleId))
            }
        }
        installedApps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func browseAppBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        store.addFocusAllowlistedDomain(name.lowercased())
    }
}

private struct FlowChipStack: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: RoweAllowlistPreset.icon(for: item))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text(RoweAllowlistPreset.displayName(for: item))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                }
            }
        }
    }
}

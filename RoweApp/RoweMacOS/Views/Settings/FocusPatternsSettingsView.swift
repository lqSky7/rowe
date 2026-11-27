import SwiftUI
import RoweCore

/// Non-AI-slop, Apple-native editorial Settings view for Rowe's Adaptive Focus & Behavioral Nudge system.
/// Monochrome surfaces + user's single pastel accent, crisp tabular figures, zero blocking, zero guilt UI.
struct FocusPatternsSettingsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var newAllowDomain: String = ""
    @State private var newCustomTarget: String = ""

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
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            circadianRhythmCard
            observedTargetsCard
            receptivityCard
            allowlistCard
            permissionsAndPrivacyFooter
        }
    }

    // MARK: - 1. Header & Master Toggle

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Focus Patterns")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Observes your scroll rhythm across Mac and iPhone, suggesting a quick task before long sessions — never blocking apps.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

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

                // 12 crisp 2-hour vertical bars
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(0..<12, id: \.self) { idx in
                        let val = slots[idx]
                        let frac = max(0.06, min(1.0, val / maxVal))
                        let isPeak = (idx == peakIndex && val > 0)
                        VStack(spacing: 6) {
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
                }
                .frame(height: 82, alignment: .bottom)

                // Clean axis ticks
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

    // MARK: - 5. Productive Domain Allowlist & Custom Targets

    private var allowlistCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORK & STUDY ALLOWLIST")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("Browsers are never tracked as a whole — only distraction domains. Add domains you always want ignored.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("e.g. docs.swift.org or leetcode.com", text: $newAllowDomain)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75))
                        )
                        .onSubmit {
                            store.addFocusAllowlistedDomain(newAllowDomain)
                            newAllowDomain = ""
                        }

                    Button("Add") {
                        store.addFocusAllowlistedDomain(newAllowDomain)
                        newAllowDomain = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
                }

                if !store.focusBehavior.allowlistedDomains.isEmpty {
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
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zero-Knowledge Private by Design")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("PIN-locked notes are never read or suggested. Browser tab URLs are classified locally and never stored.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !MacFocusTracker.shared.hasAccessibilityPermission {
                    Button("Grant Access") {
                        MacFocusTracker.shared.requestAccessibilityPermission()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
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

private struct FlowChipStack: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 5) {
                        Text(item)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9)
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

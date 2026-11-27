import SwiftUI
import UserNotifications
import RoweCore

/// Non-AI-slop, Apple-native editorial Settings view for Rowe's Adaptive Focus system on iOS.
/// Monochrome translucent surfaces + user's single pastel accent, crisp tabular figures, zero blocking.
struct IOSFocusPatternsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var newAllowDomain: String = ""
    @State private var bannerFeedback: String?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                masterCard
                circadianRhythmCard
                observedTargetsCard
                receptivityCard
                shortcutsSetupCard
                allowlistCard
                privacyFooterCard
            }
            .padding(18)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Focus Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await IOSFocusManager.shared.refreshNotificationStatus()
        }
    }

    // MARK: - 1. Master Toggle & Live Banner Test

    private var masterCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { store.focusBehavior.isEnabled },
                    set: { val in
                        IOSHaptics.shared.toggle()
                        store.toggleFocusEnabled(val)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adaptive Task Nudges")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Suggests a quick (≤ 25m) task before long scroll sessions. Never blocks apps.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.22)

                HStack(spacing: 10) {
                    Button {
                        IOSHaptics.shared.tap()
                        Task {
                            await IOSFocusManager.shared.sendPreviewBanner(for: store)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                bannerFeedback = "Preview banner sent"
                            }
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation { bannerFeedback = nil }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 13, weight: .medium))
                            Text("Test Banner Nudge")
                                .font(.system(size: 13.5, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(RowePressScaleStyle())

                    Spacer()

                    if let msg = bannerFeedback {
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
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
                        Text("CIRCADIAN RHYTHM · 7 DAYS")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(totalMinutes7d > 0 ? "\(formatMinutes(totalMinutes7d)) across Mac & iPhone" : "Observing silently to calibrate baseline")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if let peak = peakIndex, slots[peak] > 0 {
                        Text(slotRangeShort(peak))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<12, id: \.self) { idx in
                        let val = slots[idx]
                        let frac = max(0.06, min(1.0, val / maxVal))
                        let isPeak = (idx == peakIndex && val > 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                val > 0
                                    ? (isPeak ? accent : Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                                    : Color.primary.opacity(0.07)
                            )
                            .frame(height: max(5, CGFloat(frac) * 74))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80, alignment: .bottom)

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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 3. Observed Targets

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
                    Text("No sessions logged yet. Rowe observes silently for 3 sessions per app before nudging.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows, id: \.slug) { row in
                            HStack(spacing: 12) {
                                Image(systemName: row.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(row.name)
                                            .font(.system(size: 14.5, weight: .medium))
                                        Spacer()
                                        Text("~\(formatMinutes(row.medianMins)) · \(row.sessions)×")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.07))
                                            Capsule()
                                                .fill(accent.opacity(0.8))
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

    // MARK: - 4. Learned Receptivity & Muted Slots

    private var receptivityCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LEARNED WINDOWS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto-checks ~3w")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }

                if silencedSlots.isEmpty && learnedActiveSlots.isEmpty {
                    Text("Dismissing nudges during a specific time window automatically teaches Rowe to leave you alone during those hours.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(silencedSlots, id: \.key) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Auto-muted · \(item.rec.dismissedCount) dismissed")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Unmute") {
                                    IOSHaptics.shared.tap()
                                    store.unmuteFocusSlot(storageKey: item.key)
                                }
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.09)))
                            }
                        }

                        ForEach(learnedActiveSlots.prefix(5), id: \.key) { item in
                            HStack(spacing: 10) {
                                Circle().fill(accent).frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 13.5))
                                Spacer()
                                Text("\(Int((item.rec.score * 100).rounded()))%")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Instant 0-Second iOS Shortcuts Automation Guide

    private var shortcutsSetupCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("INSTANT 0-SECOND IPHONE NUDGES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text("For instant non-blocking banners the moment you open Instagram, YouTube, or Reddit on iPhone:")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    stepRow("1", "Open Apple Shortcuts → Automation → + → App.")
                    stepRow("2", "Pick Instagram (Is Opened + Run Immediately) → add Rowe's \"Log App Opened for Focus Nudge\".")
                    stepRow("3", "Optional: add a matching Is Closed automation with \"Log App Closed\" for exact session length.")
                }
                .padding(.top, 2)
            }
        }
    }

    private func stepRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.07)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 6. Work & Study Allowlist

    private var allowlistCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("WORK & STUDY ALLOWLIST")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Add domain (e.g. github.com)", text: $newAllowDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .onSubmit {
                            store.addFocusAllowlistedDomain(newAllowDomain)
                            newAllowDomain = ""
                        }

                    Button("Add") {
                        IOSHaptics.shared.tap()
                        store.addFocusAllowlistedDomain(newAllowDomain)
                        newAllowDomain = ""
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.09)))
                }

                if !store.focusBehavior.allowlistedDomains.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.focusBehavior.allowlistedDomains, id: \.self) { domain in
                                HStack(spacing: 6) {
                                    Text(domain)
                                        .font(.system(size: 12.5, design: .monospaced))
                                    Button {
                                        IOSHaptics.shared.tap()
                                        store.removeFocusAllowlistedDomain(domain)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 7. Privacy Footer

    private var privacyFooterCard: some View {
        surfaceCard {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zero-Knowledge Private")
                        .font(.system(size: 14, weight: .semibold))
                    Text("PIN-locked notes are never read or suggested. Only aggregate app rhythm syncs between your devices.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 0.75)
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

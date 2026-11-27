import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let roweCircadianHistory = Self("com.rowe.focus.circadianHistory")
}

struct ScreenTimeAppRow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let minutes: Int
}

struct ScreenTimeHistorySummary: Sendable {
    let totalMinutes: Int
    let slotMinutes: [Double] // 12 x 2-hour circadian buckets
    let topApps: [ScreenTimeAppRow]
}

@main
@MainActor
struct RoweDeviceActivityReportExtension: @preconcurrency DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RoweCircadianHistoryScene { summary in
            RoweCircadianHistoryReportView(summary: summary)
        }
    }
}

/// Reads existing historical Apple Screen Time data directly from `DeviceActivityResults`
/// so Rowe's 7-day circadian rhythm & top apps are immediately populated on Day 1.
@MainActor
struct RoweCircadianHistoryScene: @preconcurrency DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .roweCircadianHistory
    let content: (ScreenTimeHistorySummary) -> RoweCircadianHistoryReportView

    nonisolated func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTimeHistorySummary {
        var totalSeconds: TimeInterval = 0
        var slots = Array(repeating: 0.0, count: 12)
        var appSeconds: [String: TimeInterval] = [:]
        let cal = Calendar.current

        for await activityData in data {
            for await segment in activityData.activitySegments {
                let segDuration = segment.totalActivityDuration
                totalSeconds += segDuration
                let hour = cal.component(.hour, from: segment.dateInterval.start)
                let slotIdx = max(0, min(11, hour / 2))
                slots[slotIdx] += segDuration / 60.0

                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? "App"
                        appSeconds[name, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }

        let topApps = appSeconds
            .map { ScreenTimeAppRow(id: $0.key, name: $0.key, minutes: max(1, Int(($0.value / 60.0).rounded()))) }
            .sorted { $0.minutes > $1.minutes }
            .prefix(6)

        return ScreenTimeHistorySummary(
            totalMinutes: Int((totalSeconds / 60.0).rounded()),
            slotMinutes: slots,
            topApps: Array(topApps)
        )
    }
}

struct RoweCircadianHistoryReportView: View {
    let summary: ScreenTimeHistorySummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let maxVal = max(30.0, summary.slotMinutes.max() ?? 30.0)
        let peakIdx = summary.slotMinutes.enumerated().max(by: { $0.element < $1.element })?.offset

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(summary.totalMinutes > 0 ? formatMinutes(summary.totalMinutes) + " · 7-day Screen Time" : "No Screen Time data yet")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let peak = peakIdx, summary.slotMinutes[peak] > 0 {
                    Text("Peak \(slotRangeShort(peak))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { idx in
                    let val = summary.slotMinutes[idx]
                    let frac = max(0.08, min(1.0, val / maxVal))
                    let isPeak = (idx == peakIdx && val > 0)
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            val > 0
                                ? (isPeak ? Color.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                                : Color.primary.opacity(0.08)
                        )
                        .frame(height: max(5, CGFloat(frac) * 56))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60, alignment: .bottom)

            HStack {
                Text("12a"); Spacer(); Text("4a"); Spacer(); Text("8a"); Spacer()
                Text("12p"); Spacer(); Text("4p"); Spacer(); Text("8p"); Spacer(); Text("12a")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)

            if !summary.topApps.isEmpty {
                Divider().opacity(0.25)
                VStack(spacing: 8) {
                    ForEach(summary.topApps) { app in
                        HStack {
                            Text(app.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMinutes(app.minutes))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
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
}

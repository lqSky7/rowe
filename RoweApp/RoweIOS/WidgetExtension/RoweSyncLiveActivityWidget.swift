import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RoweWidgetBundle: WidgetBundle {
    var body: some Widget {
        RoweSyncLiveActivityWidget()
    }
}

/// Custom bespoke vector artwork for Rowe's Sync Live Activity (Lock Screen & Dynamic Island):
/// twin orbital sync arcs, precision constellation nodes, and a minimalist Rowe ribbon core.
struct RoweLiveActivityOrbitArt: View {
    let phase: RoweSyncActivityAttributes.SyncPhase
    var size: CGFloat = 38

    private var accentColor: Color {
        switch phase {
        case .syncing: Color(red: 0.54, green: 0.72, blue: 0.98)
        case .synced: Color(red: 0.36, green: 0.84, blue: 0.56)
        case .offline: Color(red: 0.95, green: 0.68, blue: 0.36)
        }
    }

    var body: some View {
        let accent = accentColor
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height) / 100.0
            let ox = (sz.width - 100 * s) * 0.5
            let oy = (sz.height - 100 * s) * 0.5
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
            }

            // Soft circular ceramic badge fill
            let bg = Path(ellipseIn: rect(4, 4, 92, 92))
            ctx.fill(bg, with: .color(accent.opacity(0.16)))
            ctx.stroke(bg, with: .color(accent.opacity(0.32)), lineWidth: 1.5 * s)

            // Twin precision orbital arcs
            var topArc = Path()
            topArc.addArc(center: pt(50, 50), radius: 34 * s, startAngle: .degrees(200), endAngle: .degrees(345), clockwise: false)
            ctx.stroke(topArc, with: .color(accent), style: StrokeStyle(lineWidth: 3.4 * s, lineCap: .round))

            var botArc = Path()
            botArc.addArc(center: pt(50, 50), radius: 34 * s, startAngle: .degrees(20), endAngle: .degrees(165), clockwise: false)
            ctx.stroke(botArc, with: .color(accent.opacity(0.65)), style: StrokeStyle(lineWidth: 3.4 * s, lineCap: .round))

            // Satellite beacon dots
            ctx.fill(Path(ellipseIn: rect(78, 34, 9, 9)), with: .color(accent))
            ctx.fill(Path(ellipseIn: rect(13, 57, 9, 9)), with: .color(accent.opacity(0.75)))

            // Center emblem: checkmark when synced, minimalist Rowe ribbon wave while syncing
            switch phase {
            case .synced:
                var check = Path()
                check.move(to: pt(35, 51))
                check.addLine(to: pt(46, 62))
                check.addLine(to: pt(66, 39))
                ctx.stroke(check, with: .color(accent), style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round, lineJoin: .round))
            case .syncing:
                var ribbon = Path()
                ribbon.move(to: pt(28, 53))
                ribbon.addCurve(to: pt(50, 42), control1: pt(35, 38), control2: pt(44, 38))
                ribbon.addCurve(to: pt(72, 53), control1: pt(56, 46), control2: pt(64, 62))
                ctx.stroke(ribbon, with: .color(.white), style: StrokeStyle(lineWidth: 4.8 * s, lineCap: .round))
            case .offline:
                var slash = Path()
                slash.move(to: pt(37, 37)); slash.addLine(to: pt(63, 63))
                slash.move(to: pt(63, 37)); slash.addLine(to: pt(37, 63))
                ctx.stroke(slash, with: .color(accent), style: StrokeStyle(lineWidth: 4.8 * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

struct RoweSyncLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoweSyncActivityAttributes.self) { context in
            // Lock Screen / Notification Banner Live Activity
            HStack(spacing: 14) {
                RoweLiveActivityOrbitArt(phase: context.state.phase, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(statusHeadline(context.state.phase))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("· \(context.attributes.spaceName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text(context.state.taskTitle)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                statusBadge(context.state.phase)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Color.black.opacity(0.78))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RoweLiveActivityOrbitArt(phase: context.state.phase, size: 34)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusBadge(context.state.phase)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusHeadline(context.state.phase))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.taskTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                RoweLiveActivityOrbitArt(phase: context.state.phase, size: 22)
            } compactTrailing: {
                Image(systemName: compactSymbol(context.state.phase))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(compactTint(context.state.phase))
            } minimal: {
                RoweLiveActivityOrbitArt(phase: context.state.phase, size: 22)
            }
        }
    }

    private func statusHeadline(_ phase: RoweSyncActivityAttributes.SyncPhase) -> String {
        switch phase {
        case .syncing: "Syncing to Mac"
        case .synced: "Synced across devices"
        case .offline: "Saved locally"
        }
    }

    private func compactSymbol(_ phase: RoweSyncActivityAttributes.SyncPhase) -> String {
        switch phase {
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .offline: "icloud.slash"
        }
    }

    private func compactTint(_ phase: RoweSyncActivityAttributes.SyncPhase) -> Color {
        switch phase {
        case .syncing: Color(red: 0.54, green: 0.72, blue: 0.98)
        case .synced: Color(red: 0.36, green: 0.84, blue: 0.56)
        case .offline: Color(red: 0.95, green: 0.68, blue: 0.36)
        }
    }

    private func statusBadge(_ phase: RoweSyncActivityAttributes.SyncPhase) -> some View {
        HStack(spacing: 4) {
            Image(systemName: compactSymbol(phase))
                .font(.system(size: 11, weight: .semibold))
            Text(phase == .syncing ? "Sync" : (phase == .synced ? "Done" : "Queued"))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(compactTint(phase))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(compactTint(phase).opacity(0.18)))
    }
}

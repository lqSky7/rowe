import Observation
import SwiftUI
import UIKit
import RoweCore

struct TaskBubbleFlightPayload: Identifiable {
    let id: UUID = UUID()
    let blockId: String
    let title: String
    let scheduleDate: Date
    let hasRepeat: Bool
    let imageCount: Int
    let isInbox: Bool
    let accentColor: Color
    let isDarkMode: Bool
    let textOriginFrame: CGRect
    let composerCardFrame: CGRect
    let measuredTextSize: CGSize
    let startTime: Date
    let backdropSnapshot: UIImage?
}

/// Coordinates the forward Liquid Glass Bubble flight on iOS:
/// From `t = 0`, the glass bubble travels continuously along a smooth arc directly toward the
/// 19×19 checkbox (never pausing or hovering around the text), shrinking smoothly into the checkbox
/// while refracting whatever lies along its path. Meanwhile, the task text glides independently
/// into its destination row slot.
@MainActor
@Observable
final class IOSTaskFlightCoordinator {
    var rowFrames: [String: CGRect] = [:]
    var daySectionFrames: [Date: CGRect] = [:]
    var hiddenLandingBlockId: String? = nil
    var activeEditingBlockId: String? = nil
    var activeFlight: TaskBubbleFlightPayload? = nil

    @ObservationIgnored weak var snapshotSourceView: UIView?
    @ObservationIgnored private var completionTask: Task<Void, Never>?

    nonisolated static let forwardTotalDuration: TimeInterval = 0.50

    func shouldHideRow(_ blockId: String) -> Bool {
        hiddenLandingBlockId == blockId || activeEditingBlockId == blockId
    }

    func reportRowFrame(_ frame: CGRect, for blockId: String) {
        guard frame.width > 10, frame.height > 10 else { return }
        if rowFrames[blockId] != frame {
            rowFrames[blockId] = frame
        }
    }

    func reportDaySectionFrame(_ frame: CGRect, for day: Date) {
        let key = Calendar.current.startOfDay(for: day)
        guard frame.width > 10 else { return }
        if daySectionFrames[key] != frame {
            daySectionFrames[key] = frame
        }
    }

    static func measureTaskText(_ text: String, maxWidth: CGFloat) -> CGSize {
        let safeText = text.isEmpty ? "Task" : text
        let font = UIFont.systemFont(ofSize: 16, weight: .medium)
        let rect = (safeText as NSString).boundingRect(
            with: CGSize(width: max(60, maxWidth), height: 64),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(
            width: min(max(ceil(rect.width), 16), maxWidth),
            height: min(max(ceil(rect.height), 20), 48)
        )
    }

    private func captureBackdropSnapshot() -> UIImage? {
        guard let view = snapshotSourceView, view.bounds.width > 10, view.bounds.height > 10 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, 2.0)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }

    /// Launches the direct Composer -> Checkbox Liquid Glass Bubble flight (zero hover/wait).
    func launchSettleToRow(
        blockId: String,
        title: String,
        scheduleDate: Date,
        hasRepeat: Bool,
        imageCount: Int,
        isInbox: Bool,
        accentColor: Color,
        isDarkMode: Bool,
        textFieldFrame: CGRect,
        composerCardFrame: CGRect
    ) {
        completionTask?.cancel()
        hiddenLandingBlockId = blockId
        let snapshot = captureBackdropSnapshot()
        let maxTextW = textFieldFrame.width > 40 ? textFieldFrame.width : max(200, composerCardFrame.width - 36)
        let measured = Self.measureTaskText(title, maxWidth: maxTextW)

        let payload = TaskBubbleFlightPayload(
            blockId: blockId,
            title: title,
            scheduleDate: Calendar.current.startOfDay(for: scheduleDate),
            hasRepeat: hasRepeat,
            imageCount: imageCount,
            isInbox: isInbox,
            accentColor: accentColor,
            isDarkMode: isDarkMode,
            textOriginFrame: textFieldFrame,
            composerCardFrame: composerCardFrame,
            measuredTextSize: measured,
            startTime: Date(),
            backdropSnapshot: snapshot
        )
        activeFlight = payload
        IOSHaptics.shared.playBubbleSettleHaptic()

        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.forwardTotalDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeFlight?.id == payload.id else { return }
            self.activeFlight = nil
            self.hiddenLandingBlockId = nil
        }
    }

    func destinationFrame(for payload: TaskBubbleFlightPayload, in screenSize: CGSize) -> CGRect {
        if let exact = rowFrames[payload.blockId], exact.width > 20, exact.height > 10 {
            return exact
        }
        if let dayRect = daySectionFrames[payload.scheduleDate], dayRect.width > 20 {
            return CGRect(
                x: 0,
                y: min(dayRect.maxY + 20, screenSize.height - 140),
                width: screenSize.width,
                height: 40
            )
        }
        return CGRect(x: 0, y: 178, width: screenSize.width, height: 40)
    }
}

/// Per-frame optical & geometric state evaluated at 120fps:
/// The bubble moves continuously toward `checkboxCenter` from t=0 without ever hovering around the text.
private struct TaskBubbleFrameMetrics {
    let center: CGPoint
    let textCenter: CGPoint
    let halfSize: CGSize
    let cornerRadius: CGFloat
    let power: Double
    let dispersion: Double
    let wobblePhase: Double
    let wobbleAmp: Double
    let bubbleOpacity: Double
    let flyingTextOpacity: Double
    let settlingRowOpacity: Double
    let rowFrame: CGRect

    static let checkboxSize: CGFloat = 19
    static let checkboxCorner: CGFloat = 5.5
    static let textLeadingOffsetInRow: CGFloat = 18 + 19 + 12

    static func evaluate(
        elapsed t: TimeInterval,
        payload: TaskBubbleFlightPayload,
        rowFrame: CGRect,
        screenSize: CGSize
    ) -> TaskBubbleFrameMetrics {
        let total = IOSTaskFlightCoordinator.forwardTotalDuration
        let u = clamp(t / total)

        let cardRect = payload.composerCardFrame.width > 40
            ? payload.composerCardFrame
            : CGRect(x: 14, y: screenSize.height * 0.42, width: screenSize.width - 28, height: 152)

        let textW = payload.measuredTextSize.width
        let textH = payload.measuredTextSize.height
        let dropletW = min(max(textW * 0.55 + 32, 54), 110)
        let dropletH = min(max(textH + 22, 46), 68)

        let checkboxCenter = CGPoint(x: rowFrame.minX + 18 + checkboxSize * 0.5, y: rowFrame.midY)
        let clampedRowTextW = min(textW, max(40, rowFrame.width - textLeadingOffsetInRow - 48))
        let rowTextCenter = CGPoint(
            x: rowFrame.minX + textLeadingOffsetInRow + clampedRowTextW * 0.5,
            y: rowFrame.midY
        )

        let tfOriginX = payload.textOriginFrame.width > 20 ? payload.textOriginFrame.minX : (cardRect.minX + 18)
        let tfMidY = payload.textOriginFrame.height > 10 ? payload.textOriginFrame.midY : (cardRect.minY + 66)
        let textStartCenter = CGPoint(
            x: min(max(tfOriginX + textW * 0.5, 24), screenSize.width - 24),
            y: tfMidY
        )
        let bubbleStartCenter = CGPoint(x: cardRect.midX, y: cardRect.midY)

        // Bubble continuously curves straight from composer to checkboxCenter (quadratic Bezier, zero hover!)
        let bubbleProgress = easeInOutCubic(u)
        let controlPoint = CGPoint(
            x: lerp(bubbleStartCenter.x, checkboxCenter.x, 0.35) - 24,
            y: min(bubbleStartCenter.y, checkboxCenter.y) - 18
        )
        let currentCenter = quadBezier(bubbleStartCenter, controlPoint, checkboxCenter, t: bubbleProgress)

        // Size smoothly contracts: composer card -> liquid droplet -> exact 19×19 checkbox
        let condense = smoothstep(clamp(u / 0.28))
        let shrinkToCheckbox = smoothstep(clamp((u - 0.14) / 0.86))
        let arcStretch = sin(u * .pi) * 0.08 * (1.0 - shrinkToCheckbox)
        let midW = lerp(cardRect.width, dropletW * (1.0 - CGFloat(arcStretch * 0.3)), condense)
        let midH = lerp(cardRect.height, dropletH * (1.0 + CGFloat(arcStretch)), condense)
        let currentW = lerp(midW, checkboxSize, shrinkToCheckbox)
        let currentH = lerp(midH, checkboxSize, shrinkToCheckbox)

        let dropletCorner = min(dropletW, dropletH) * 0.5
        let midCorner = lerp(24.0, dropletCorner, condense)
        let cornerRadius = lerp(midCorner, checkboxCorner, shrinkToCheckbox)

        // Task text independently glides straight from composer text slot to row text slot
        let textProgress = easeOutCubic(clamp(u / 0.78))
        let textCenter = CGPoint(
            x: lerp(textStartCenter.x, rowTextCenter.x, textProgress),
            y: lerp(textStartCenter.y, rowTextCenter.y, textProgress) - 8.0 * CGFloat(sin(textProgress * .pi))
        )

        let opticalEnv = (0.35 + 0.65 * condense) * (1.0 - smoothstep(clamp((u - 0.76) / 0.24)) * 0.78)
        let power = 0.88 * opticalEnv
        let dispersion = 0.72 * opticalEnv
        let wobbleAmp = 0.90 * condense * (1.0 - shrinkToCheckbox)
        let wobblePhase = t * 8.2

        let bubbleOpacity = 1.0 - smoothstep(clamp((u - 0.90) / 0.10))
        let textHandoff = smoothstep(clamp((u - 0.72) / 0.18))
        let flyingTextOpacity = 1.0 - textHandoff
        let settlingRowOpacity = textHandoff

        return TaskBubbleFrameMetrics(
            center: currentCenter,
            textCenter: textCenter,
            halfSize: CGSize(width: currentW * 0.5, height: currentH * 0.5),
            cornerRadius: cornerRadius,
            power: power,
            dispersion: dispersion,
            wobblePhase: wobblePhase,
            wobbleAmp: wobbleAmp,
            bubbleOpacity: bubbleOpacity,
            flyingTextOpacity: flyingTextOpacity,
            settlingRowOpacity: settlingRowOpacity,
            rowFrame: rowFrame
        )
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func easeOutCubic(_ t: Double) -> Double { 1.0 - pow(1.0 - t, 3.0) }
    private static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    private static func quadBezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: Double) -> CGPoint {
        let mt = 1.0 - t
        let a = CGFloat(mt * mt)
        let b = CGFloat(2.0 * mt * t)
        let c = CGFloat(t * t)
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x, y: a * p0.y + b * p1.y + c * p2.y)
    }
}

/// Pure SwiftUI overlay rendering the continuous Liquid Glass Bubble flight straight to the checkbox,
/// refracting BOTH the underlying calendar backdrop AND the flying task text beneath the glass lens.
struct IOSTaskBubbleFlightOverlay: View {
    @Bindable var coordinator: IOSTaskFlightCoordinator
    var targetComposerBottomInset: CGFloat = 324
    var liveComposerFrame: CGRect = .zero

    var body: some View {
        if let payload = coordinator.activeFlight {
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    let elapsed = max(0, timeline.date.timeIntervalSince(payload.startTime))
                    let rowFrame = coordinator.destinationFrame(for: payload, in: geo.size)
                    let m = TaskBubbleFrameMetrics.evaluate(
                        elapsed: elapsed,
                        payload: payload,
                        rowFrame: rowFrame,
                        screenSize: geo.size
                    )

                    ZStack {
                        // Layer 1: Flying / settling task text (rendered beneath the glass bubble)
                        if m.settlingRowOpacity > 0.01 {
                            rowTextWithoutCheckbox(payload: payload)
                                .frame(width: rowFrame.width, height: rowFrame.height)
                                .position(x: rowFrame.midX, y: rowFrame.midY)
                                .opacity(m.settlingRowOpacity)
                                .allowsHitTesting(false)
                        }

                        if m.flyingTextOpacity > 0.01 {
                            Text(payload.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(width: payload.measuredTextSize.width + 6, alignment: .leading)
                                .position(m.textCenter)
                                .opacity(m.flyingTextOpacity)
                                .allowsHitTesting(false)
                        }

                        // Layer 2: Refracting Liquid Glass Bubble passing OVER backdrop + flying text straight to checkbox
                        if m.bubbleOpacity > 0.01 {
                            ZStack {
                                if let snap = payload.backdropSnapshot {
                                    Image(uiImage: snap)
                                        .resizable()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                } else {
                                    Color(payload.isDarkMode ? .black : .white)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                }

                                if m.flyingTextOpacity > 0.01 {
                                    Text(payload.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: payload.measuredTextSize.width + 6, alignment: .leading)
                                        .position(m.textCenter)
                                        .opacity(m.flyingTextOpacity)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .compositingGroup()
                            .layerEffect(
                                ShaderLibrary.taskBubbleLens(
                                    .float2(m.center.x, m.center.y),
                                    .float2(m.halfSize.width, m.halfSize.height),
                                    .float(m.cornerRadius),
                                    .float(m.power),
                                    .float(m.dispersion),
                                    .float(m.wobblePhase),
                                    .float(m.wobbleAmp),
                                    .float(m.bubbleOpacity),
                                    .float(0)
                                ),
                                maxSampleOffset: CGSize(width: 140, height: 140)
                            )
                            .allowsHitTesting(false)

                            RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.76),
                                            .white.opacity(0.10),
                                            .white.opacity(0.36)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: m.halfSize.width < 14 ? 1.4 : 0.9
                                )
                                .frame(width: m.halfSize.width * 2, height: m.halfSize.height * 2)
                                .position(m.center)
                                .opacity(m.bubbleOpacity * (0.48 + 0.52 * m.power))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private func rowTextWithoutCheckbox(payload: TaskBubbleFlightPayload) -> some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: TaskBubbleFrameMetrics.checkboxSize, height: TaskBubbleFrameMetrics.checkboxSize)

            HStack(spacing: 8) {
                Text(payload.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                if payload.imageCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "photo")
                            .font(.system(size: 10.5))
                        Text("\(payload.imageCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }

                if payload.hasRepeat {
                    Image(systemName: "repeat")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }

                if payload.isInbox {
                    Text("Inbox")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

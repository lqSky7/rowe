import Observation
import SwiftUI
import UIKit
import RoweCore

enum TaskBubbleFlightDirection: Equatable {
    /// Text inside Composer -> bubble blooms right around text -> glides to exact row text slot -> bubble collapses into 19×19 checkbox
    case settleToRow
    /// Task Row -> 19×19 checkbox un-bubbles & scoops text -> glides straight to Composer text slot -> Composer unfolds around it
    case openForEdit
}

struct TaskBubbleFlightPayload: Identifiable {
    let id: UUID = UUID()
    let direction: TaskBubbleFlightDirection
    let blockId: String
    let title: String
    let scheduleDate: Date
    let hasRepeat: Bool
    let imageCount: Int
    let isInbox: Bool
    let accentColor: Color
    let isDarkMode: Bool
    /// Exact global frame of the composer's TextField (forward) or tapped row (reverse)
    let textOriginFrame: CGRect
    /// Full composer card frame (used to gently fade out the surrounding card chrome)
    let composerCardFrame: CGRect
    let measuredTextSize: CGSize
    let startTime: Date
    let backdropSnapshot: UIImage?
}

/// Coordinates both directions of the text-anchored Liquid Glass Bubble choreography on iOS:
/// - Forward (`.settleToRow`): Bubble blooms tightly around the actual task text (e.g. just "hi" or "do homework")
///   while the surrounding composer card fades away, flies straight to the task's destination text slot, and collapses
///   pixel-for-pixel into the 19×19 checkbox (no shimmer).
/// - Reverse (`.openForEdit`): 19×19 checkbox un-bubbles into a text-sized bubble, scoops up the task text,
///   and flies directly to the leading text slot inside the above-keyboard Task Composer.
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

    static let forwardTotalDuration: TimeInterval = 0.62
    static let reverseTotalDuration: TimeInterval = 0.42

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

    /// Launches the forward Text-Anchored Bubble -> Destination Row -> Exact 19×19 Checkbox flight.
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
            direction: .settleToRow,
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

    /// Launches the reverse Row -> Checkbox Un-Bubbles & Scoops Text -> Above-Keyboard Composer Text Slot flight.
    func launchOpenForEdit(
        item: ResolvedTaskItem,
        accentColor: Color,
        isDarkMode: Bool,
        onReadyForComposer: @escaping () -> Void
    ) {
        let rowFrame = rowFrames[item.block.id] ?? CGRect(x: 0, y: 220, width: UIScreen.main.bounds.width, height: 40)
        completionTask?.cancel()
        hiddenLandingBlockId = item.block.id
        let snapshot = captureBackdropSnapshot()
        let title = item.block.content.isEmpty ? "Untitled Task" : item.block.content
        let maxTextW = max(160, rowFrame.width - 96)
        let measured = Self.measureTaskText(title, maxWidth: maxTextW)

        let payload = TaskBubbleFlightPayload(
            direction: .openForEdit,
            blockId: item.block.id,
            title: title,
            scheduleDate: Calendar.current.startOfDay(for: item.block.task?.scheduleDate ?? Date()),
            hasRepeat: item.block.task?.repeatRule != nil,
            imageCount: item.block.task?.attachedImagesBase64.count ?? 0,
            isInbox: item.isInbox,
            accentColor: accentColor,
            isDarkMode: isDarkMode,
            textOriginFrame: rowFrame,
            composerCardFrame: .zero,
            measuredTextSize: measured,
            startTime: Date(),
            backdropSnapshot: snapshot
        )
        activeFlight = payload
        IOSHaptics.shared.playBubbleOpenForEditHaptic()

        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.reverseTotalDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeFlight?.id == payload.id else { return }
            onReadyForComposer()
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

/// Per-frame optical & geometric state evaluated at 120fps for text-anchored forward and reverse flights.
private struct TaskBubbleFrameMetrics {
    let center: CGPoint
    let textCenter: CGPoint
    let textPower: Double
    let halfSize: CGSize
    let cornerRadius: CGFloat
    let power: Double
    let dispersion: Double
    let wobblePhase: Double
    let wobbleAmp: Double
    let bubbleOpacity: Double
    let fadingComposerRect: CGRect
    let fadingComposerOpacity: Double
    let refractedTextOpacity: Double
    let settlingTextOpacity: Double
    let rowFrame: CGRect

    static let checkboxSize: CGFloat = 19
    static let checkboxCorner: CGFloat = 5.5
    static let textLeadingOffsetInRow: CGFloat = 18 + 19 + 12

    static func evaluate(
        elapsed t: TimeInterval,
        payload: TaskBubbleFlightPayload,
        rowFrame: CGRect,
        screenSize: CGSize,
        targetComposerBottomInset: CGFloat,
        liveComposerFrame: CGRect
    ) -> TaskBubbleFrameMetrics {
        let textW = payload.measuredTextSize.width
        let textH = payload.measuredTextSize.height
        let bubbleW = min(max(textW + 44, 68), min(230, screenSize.width - 48))
        let bubbleH = min(max(textH + 30, 50), 82)

        let checkboxCenter = CGPoint(x: rowFrame.minX + 18 + checkboxSize * 0.5, y: rowFrame.midY)
        let clampedRowTextW = min(textW, max(40, rowFrame.width - textLeadingOffsetInRow - 48))
        let rowTextCenter = CGPoint(
            x: rowFrame.minX + textLeadingOffsetInRow + clampedRowTextW * 0.5,
            y: rowFrame.midY
        )

        switch payload.direction {
        case .settleToRow:
            return evaluateForward(
                t: t,
                payload: payload,
                rowFrame: rowFrame,
                checkboxCenter: checkboxCenter,
                rowTextCenter: rowTextCenter,
                bubbleW: bubbleW,
                bubbleH: bubbleH,
                screenSize: screenSize
            )
        case .openForEdit:
            return evaluateReverse(
                t: t,
                payload: payload,
                rowFrame: rowFrame,
                checkboxCenter: checkboxCenter,
                rowTextCenter: rowTextCenter,
                bubbleW: bubbleW,
                bubbleH: bubbleH,
                screenSize: screenSize,
                targetComposerBottomInset: targetComposerBottomInset,
                liveComposerFrame: liveComposerFrame
            )
        }
    }

    private static func evaluateForward(
        t: TimeInterval,
        payload: TaskBubbleFlightPayload,
        rowFrame: CGRect,
        checkboxCenter: CGPoint,
        rowTextCenter: CGPoint,
        bubbleW: CGFloat,
        bubbleH: CGFloat,
        screenSize: CGSize
    ) -> TaskBubbleFrameMetrics {
        let cardRect = payload.composerCardFrame.width > 40
            ? payload.composerCardFrame
            : CGRect(x: 14, y: screenSize.height * 0.42, width: screenSize.width - 28, height: 152)

        let tfOriginX = payload.textOriginFrame.width > 20 ? payload.textOriginFrame.minX : (cardRect.minX + 18)
        let tfMidY = payload.textOriginFrame.height > 10 ? payload.textOriginFrame.midY : (cardRect.minY + 66)
        let rawTextCenterX = tfOriginX + payload.measuredTextSize.width * 0.5
        let clampedStartX = min(max(rawTextCenterX, bubbleW * 0.5 + 8), screenSize.width - bubbleW * 0.5 - 8)
        let textStartCenter = CGPoint(x: clampedStartX, y: tfMidY)

        // Composer itself turns into the bubble and rapidly wraps around the text WHILE already traveling
        let wrapU = clamp(t / 0.20)
        let wrap = smoothstep(wrapU)

        let flightU = clamp(t / 0.44)
        let flight = springEase(flightU)

        // Late path divergence right before arrival: bubble curves into checkbox, text glides into row slot
        let divergeU = clamp((t - 0.34) / 0.24)
        let diverge = smoothstep(divergeU)

        let flightArc = sin(flightU * .pi)
        let stretch = CGFloat(flightArc * 0.07 * wrap * (1.0 - diverge))
        let tightW = bubbleW * (1.0 - stretch * 0.35)
        let tightH = bubbleH * (1.0 + stretch)
        let wrappedW = lerp(cardRect.width, tightW, wrap)
        let wrappedH = lerp(cardRect.height, tightH, wrap)
        let currentW = lerp(wrappedW, checkboxSize, diverge)
        let currentH = lerp(wrappedH, checkboxSize, diverge)

        let bubbleCorner = min(tightW, tightH) * 0.5
        let wrappedCorner = lerp(24.0, bubbleCorner, wrap)
        let cornerRadius = lerp(wrappedCorner, checkboxCorner, diverge)

        let approachTarget = CGPoint(
            x: lerp(rowTextCenter.x, checkboxCenter.x, 0.32),
            y: rowTextCenter.y
        )
        let liftY = -12.0 * CGFloat(flightArc)
        let textTravelPos = CGPoint(
            x: lerp(textStartCenter.x, approachTarget.x, flight),
            y: lerp(textStartCenter.y, approachTarget.y, flight) + liftY
        )
        let cardCenter = CGPoint(x: cardRect.midX, y: cardRect.midY)
        let cardFlightCenter = CGPoint(
            x: lerp(cardCenter.x, textTravelPos.x, wrap),
            y: lerp(cardCenter.y, textTravelPos.y, wrap)
        )

        let bubbleBranchArc = -6.0 * CGFloat(sin(divergeU * .pi))
        let currentCenter = CGPoint(
            x: lerp(cardFlightCenter.x, checkboxCenter.x, diverge),
            y: lerp(cardFlightCenter.y, checkboxCenter.y, diverge) + bubbleBranchArc
        )
        let textCenter = CGPoint(
            x: lerp(textTravelPos.x, rowTextCenter.x, diverge),
            y: lerp(textTravelPos.y, rowTextCenter.y, diverge)
        )

        let wobbleFade = 1.0 - smoothstep(clamp(divergeU / 0.85))
        let opticalRamp = 0.25 + 0.75 * wrap
        let opticalEnv = opticalRamp * (1.0 - diverge * 0.85)
        let power = 0.84 * opticalEnv
        let dispersion = 0.92 * opticalEnv
        let wobbleAmp = 0.95 * wrap * wobbleFade
        let wobblePhase = t * 7.6

        let bubbleOpacity = 1.0 - smoothstep(clamp((t - 0.58) / 0.04))

        let textPower = power * wrap * (1.0 - smoothstep(clamp(divergeU / 0.72)))
        let textHandoff = smoothstep(clamp((t - 0.50) / 0.09))
        let refractedTextOpacity = (1.0 - textHandoff) * (1.0 - smoothstep(clamp((t - 0.58) / 0.04)))
        let settlingTextOpacity = t < 0.62 ? textHandoff : 0.0

        return TaskBubbleFrameMetrics(
            center: currentCenter,
            textCenter: textCenter,
            textPower: textPower,
            halfSize: CGSize(width: currentW * 0.5, height: currentH * 0.5),
            cornerRadius: cornerRadius,
            power: power,
            dispersion: dispersion,
            wobblePhase: wobblePhase,
            wobbleAmp: wobbleAmp,
            bubbleOpacity: bubbleOpacity,
            fadingComposerRect: .zero,
            fadingComposerOpacity: 0.0,
            refractedTextOpacity: refractedTextOpacity,
            settlingTextOpacity: settlingTextOpacity,
            rowFrame: rowFrame
        )
    }

    private static func evaluateReverse(
        t: TimeInterval,
        payload: TaskBubbleFlightPayload,
        rowFrame: CGRect,
        checkboxCenter: CGPoint,
        rowTextCenter: CGPoint,
        bubbleW: CGFloat,
        bubbleH: CGFloat,
        screenSize: CGSize,
        targetComposerBottomInset: CGFloat,
        liveComposerFrame: CGRect
    ) -> TaskBubbleFrameMetrics {
        let composerRect: CGRect = {
            if liveComposerFrame.width > 120 && liveComposerFrame.height > 60 {
                return liveComposerFrame
            }
            let composerW = max(260, screenSize.width - 28)
            let composerH: CGFloat = 152
            return CGRect(
                x: (screenSize.width - composerW) * 0.5,
                y: screenSize.height - targetComposerBottomInset - composerH,
                width: composerW,
                height: composerH
            )
        }()
        let destTextOriginX = composerRect.minX + 18
        let destTextMidY = composerRect.minY + 66
        let rawDestX = destTextOriginX + payload.measuredTextSize.width * 0.5
        let destTextCenter = CGPoint(
            x: min(max(rawDestX, bubbleW * 0.5 + 8), screenSize.width - bubbleW * 0.5 - 8),
            y: destTextMidY
        )

        let convergeU = clamp(t / 0.16)
        let converge = smoothstep(convergeU)
        let flightU = clamp((t - 0.04) / 0.30)
        let flight = springEase(flightU)
        let unwrapU = clamp((t - 0.24) / 0.18)
        let unwrap = smoothstep(unwrapU)

        let midW = lerp(checkboxSize, bubbleW, converge)
        let midH = lerp(checkboxSize, bubbleH, converge)
        let currentW = lerp(midW, composerRect.width, unwrap)
        let currentH = lerp(midH, composerRect.height, unwrap)
        let bubbleCorner = min(bubbleW, bubbleH) * 0.5
        let midCorner = lerp(checkboxCorner, bubbleCorner, converge)
        let cornerRadius = lerp(midCorner, 24.0, unwrap)

        let approachOrigin = CGPoint(
            x: lerp(rowTextCenter.x, checkboxCenter.x, 0.32),
            y: rowTextCenter.y
        )
        let flightArc = sin(flightU * .pi)
        let sharedPos = CGPoint(
            x: lerp(approachOrigin.x, destTextCenter.x, flight),
            y: lerp(approachOrigin.y, destTextCenter.y, flight) - 12.0 * CGFloat(flightArc)
        )

        let bubbleMergeArc = -6.0 * CGFloat(sin(convergeU * .pi))
        let mergedBubblePos = CGPoint(
            x: lerp(checkboxCenter.x, sharedPos.x, converge),
            y: lerp(checkboxCenter.y, sharedPos.y, converge) + bubbleMergeArc
        )
        let composerCenter = CGPoint(x: composerRect.midX, y: composerRect.midY)
        let currentCenter = CGPoint(
            x: lerp(mergedBubblePos.x, composerCenter.x, unwrap),
            y: lerp(mergedBubblePos.y, composerCenter.y, unwrap)
        )
        let textCenter = CGPoint(
            x: lerp(rowTextCenter.x, sharedPos.x, converge),
            y: lerp(rowTextCenter.y, sharedPos.y, converge)
        )

        let opticalEnv = converge * (1.0 - unwrap * 0.72)
        let power = 0.84 * opticalEnv
        let dispersion = 0.90 * opticalEnv
        let wobbleAmp = 0.95 * converge * (1.0 - unwrap)
        let wobblePhase = -t * 7.6

        let textPower = power * smoothstep(clamp(convergeU / 0.85)) * (1.0 - unwrap)
        let textPickup = smoothstep(clamp(t / 0.06))
        let settlingTextOpacity = 1.0 - textPickup
        let refractedTextOpacity = textPickup * (1.0 - smoothstep(clamp((t - 0.36) / 0.06)))

        return TaskBubbleFrameMetrics(
            center: currentCenter,
            textCenter: textCenter,
            textPower: textPower,
            halfSize: CGSize(width: currentW * 0.5, height: currentH * 0.5),
            cornerRadius: cornerRadius,
            power: power,
            dispersion: dispersion,
            wobblePhase: wobblePhase,
            wobbleAmp: wobbleAmp,
            bubbleOpacity: 1.0 - smoothstep(clamp((t - 0.37) / 0.05)),
            fadingComposerRect: .zero,
            fadingComposerOpacity: 0.0,
            refractedTextOpacity: refractedTextOpacity,
            settlingTextOpacity: settlingTextOpacity,
            rowFrame: rowFrame
        )
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    private static func springEase(_ u: Double) -> Double {
        guard u > 0 else { return 0 }
        guard u < 1 else { return 1 }
        let raw = 1.0 - exp(-6.4 * u) * cos(4.6 * u)
        let end = 1.0 - exp(-6.4) * cos(4.6)
        return raw / end
    }
}

/// Pure SwiftUI overlay mounted above `CompactTabBarContainer` (zero UIKit `.layerEffect` conflicts),
/// rendering text-anchored Forward (Composer Text -> Bubble -> 19×19 Checkbox) and Reverse (Row -> Un-Bubble -> Composer Text) flights.
struct IOSTaskBubbleFlightOverlay: View {
    @Bindable var coordinator: IOSTaskFlightCoordinator
    var targetComposerBottomInset: CGFloat = 324
    var liveComposerFrame: CGRect = .zero

    var body: some View {
        if let payload = coordinator.activeFlight {
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    let elapsed = max(0, timeline.date.timeIntervalSince(payload.startTime))
                    let rowFrame = payload.direction == .openForEdit
                        ? payload.textOriginFrame
                        : coordinator.destinationFrame(for: payload, in: geo.size)
                    let m = TaskBubbleFrameMetrics.evaluate(
                        elapsed: elapsed,
                        payload: payload,
                        rowFrame: rowFrame,
                        screenSize: geo.size,
                        targetComposerBottomInset: targetComposerBottomInset,
                        liveComposerFrame: liveComposerFrame
                    )

                    ZStack {
                        if m.fadingComposerOpacity > 0.01 && m.fadingComposerRect.width > 40 {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: m.fadingComposerRect.width, height: m.fadingComposerRect.height)
                                .position(x: m.fadingComposerRect.midX, y: m.fadingComposerRect.midY)
                                .scaleEffect(0.96 + 0.04 * m.fadingComposerOpacity)
                                .opacity(m.fadingComposerOpacity * 0.88)
                                .allowsHitTesting(false)
                        }

                        if m.settlingTextOpacity > 0.01 {
                            rowTextWithoutCheckbox(payload: payload)
                                .frame(width: rowFrame.width, height: rowFrame.height)
                                .position(x: rowFrame.midX, y: rowFrame.midY)
                                .opacity(m.settlingTextOpacity)
                                .allowsHitTesting(false)
                        }

                        if m.bubbleOpacity > 0.01 {
                            Group {
                                if let snap = payload.backdropSnapshot {
                                    Image(uiImage: snap)
                                        .resizable()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                } else {
                                    Color(payload.isDarkMode ? .black : .white)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                }
                            }
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
                        }

                        if m.refractedTextOpacity > 0.01 {
                            let textMaxW = max(payload.measuredTextSize.width + 16, 48)
                            if m.textPower > 0.04 && m.halfSize.width > 18 {
                                let pad: CGFloat = 140
                                let sampleW = max(m.halfSize.width * 2, textMaxW) + pad * 2
                                let sampleH = max(m.halfSize.height * 2, payload.measuredTextSize.height + 24) + pad * 2

                                Text(payload.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: payload.measuredTextSize.width + 6, alignment: .leading)
                                    .frame(width: sampleW, height: sampleH)
                                    .compositingGroup()
                                    .layerEffect(
                                        ShaderLibrary.taskBubbleLens(
                                            .float2(sampleW * 0.5, sampleH * 0.5),
                                            .float2(m.halfSize.width, m.halfSize.height),
                                            .float(m.cornerRadius),
                                            .float(m.textPower * 0.68),
                                            .float(m.dispersion * 0.85),
                                            .float(m.wobblePhase),
                                            .float(m.wobbleAmp),
                                            .float(1.0),
                                            .float(1.0)
                                        ),
                                        maxSampleOffset: CGSize(width: 140, height: 140)
                                    )
                                    .position(m.textCenter)
                                    .opacity(m.refractedTextOpacity)
                                    .allowsHitTesting(false)
                            } else {
                                Text(payload.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: payload.measuredTextSize.width + 6, alignment: .leading)
                                    .position(m.textCenter)
                                    .opacity(m.refractedTextOpacity)
                                    .allowsHitTesting(false)
                            }
                        }

                        if m.bubbleOpacity > 0.01 {
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

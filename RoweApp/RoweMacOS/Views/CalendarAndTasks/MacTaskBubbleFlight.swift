import AppKit
import Metal
import MetalKit
import Observation
import SwiftUI
import RoweCore

enum MacTaskBubbleFlightDirection: Equatable {
    /// Text inside Composer -> bubble blooms right around text -> glides to exact row text slot -> collapses into 16×16 checkbox
    case settleToRow
    /// Task Row -> 16×16 checkbox un-bubbles & scoops text -> glides straight to Composer text slot -> Composer unfolds around it
    case openForEdit
}

struct MacTaskBubbleFlightPayload: Identifiable {
    let id: UUID = UUID()
    let direction: MacTaskBubbleFlightDirection
    let blockId: String
    let title: String
    let scheduleDate: Date
    let hasRepeat: Bool
    let imageCount: Int
    let isInbox: Bool
    let documentTitle: String
    let accentColor: Color
    let isDarkMode: Bool
    /// Exact window-space frame of the composer's text input (forward) or tapped row (reverse)
    let textOriginFrame: CGRect
    /// Full composer card frame (for fading out the surrounding card smoothly)
    let composerCardFrame: CGRect
    let measuredTextSize: CGSize
    let startTime: Date
    let backdropCGImage: CGImage?
}

/// Coordinates macOS text-anchored Liquid Glass Bubble flights (exact parity with iOS, no shimmer):
/// - Forward (`.settleToRow`): Bubble blooms tightly around the actual task text inside the composer
///   while the surrounding card dissolves, glides straight to the row's text slot, and collapses into the 16×16 checkbox.
/// - Reverse (`.openForEdit`): 16×16 checkbox un-bubbles into a text-sized bubble, scoops up the task text,
///   and glides straight to the leading text slot inside TaskEditorPopover.
/// - Background hide: keeps `activeEditingBlockId` hidden in the Calendar list while open in the composer.
@MainActor
@Observable
final class MacTaskFlightCoordinator {
    var rowFrames: [String: CGRect] = [:]
    var daySectionFrames: [Date: CGRect] = [:]
    var hiddenLandingBlockId: String? = nil
    var activeEditingBlockId: String? = nil
    var activeFlight: MacTaskBubbleFlightPayload? = nil

    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var hapticTask: Task<Void, Never>?

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
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let rect = (safeText as NSString).boundingRect(
            with: CGSize(width: max(60, maxWidth), height: 60),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return CGSize(
            width: min(max(ceil(rect.width), 16), maxWidth),
            height: min(max(ceil(rect.height), 18), 44)
        )
    }

    /// Ultra-fast 0.45x downscaled CALayer snapshot (~3-5ms instead of 250ms full-Retina cacheDisplay).
    private func captureWindowSnapshot() -> CGImage? {
        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView,
              let layer = view.layer,
              view.bounds.width > 20, view.bounds.height > 20 else {
            return nil
        }
        let scale: CGFloat = 0.45
        let w = max(1, Int(view.bounds.width * scale))
        let h = max(1, Int(view.bounds.height * scale))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    func launchSettleToRow(
        item: ResolvedTaskItem,
        accentColor: Color,
        isDarkMode: Bool,
        textFieldFrame: CGRect,
        composerCardFrame: CGRect
    ) {
        cancelTasks()
        hiddenLandingBlockId = item.block.id
        activeEditingBlockId = nil
        let snapshot = captureWindowSnapshot()
        let title = item.block.content.isEmpty ? "Image Task" : item.block.content
        let maxTextW = textFieldFrame.width > 40 ? textFieldFrame.width : 500
        let measured = Self.measureTaskText(title, maxWidth: maxTextW)

        let payload = MacTaskBubbleFlightPayload(
            direction: .settleToRow,
            blockId: item.block.id,
            title: title,
            scheduleDate: Calendar.current.startOfDay(for: item.block.task?.scheduleDate ?? Date()),
            hasRepeat: item.block.task?.repeatRule != nil,
            imageCount: item.block.task?.attachedImagesBase64.count ?? 0,
            isInbox: item.isInbox,
            documentTitle: item.documentTitle,
            accentColor: accentColor,
            isDarkMode: isDarkMode,
            textOriginFrame: textFieldFrame,
            composerCardFrame: composerCardFrame,
            measuredTextSize: measured,
            startTime: Date(),
            backdropCGImage: snapshot
        )
        activeFlight = payload
        HapticsManager.shared.tap()

        hapticTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard !Task.isCancelled, self?.activeFlight?.id == payload.id else { return }
            HapticsManager.shared.boundarySnap()
        }

        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.forwardTotalDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeFlight?.id == payload.id else { return }
            HapticsManager.shared.taskComplete()
            self.activeFlight = nil
            self.hiddenLandingBlockId = nil
        }
    }

    func launchOpenForEdit(
        item: ResolvedTaskItem,
        accentColor: Color,
        isDarkMode: Bool,
        onReadyForComposer: @escaping () -> Void
    ) {
        guard let rowFrame = rowFrames[item.block.id], rowFrame.width > 20 else {
            activeEditingBlockId = item.block.id
            onReadyForComposer()
            return
        }
        cancelTasks()
        hiddenLandingBlockId = item.block.id
        activeEditingBlockId = item.block.id
        let snapshot = captureWindowSnapshot()
        let title = item.block.content.isEmpty ? "Untitled Task" : item.block.content
        let maxTextW = max(160, rowFrame.width - 80)
        let measured = Self.measureTaskText(title, maxWidth: maxTextW)

        let payload = MacTaskBubbleFlightPayload(
            direction: .openForEdit,
            blockId: item.block.id,
            title: title,
            scheduleDate: Calendar.current.startOfDay(for: item.block.task?.scheduleDate ?? Date()),
            hasRepeat: item.block.task?.repeatRule != nil,
            imageCount: item.block.task?.attachedImagesBase64.count ?? 0,
            isInbox: item.isInbox,
            documentTitle: item.documentTitle,
            accentColor: accentColor,
            isDarkMode: isDarkMode,
            textOriginFrame: rowFrame,
            composerCardFrame: .zero,
            measuredTextSize: measured,
            startTime: Date(),
            backdropCGImage: snapshot
        )
        activeFlight = payload
        HapticsManager.shared.boundarySnap()

        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.reverseTotalDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeFlight?.id == payload.id else { return }
            onReadyForComposer()
            self.activeFlight = nil
            self.hiddenLandingBlockId = nil
        }
    }

    func clearEditingState() {
        activeEditingBlockId = nil
    }

    private func cancelTasks() {
        completionTask?.cancel()
        hapticTask?.cancel()
    }

    func destinationFrame(for payload: MacTaskBubbleFlightPayload, in windowSize: CGSize) -> CGRect {
        if let exact = rowFrames[payload.blockId], exact.width > 20, exact.height > 8 {
            return exact
        }
        if let dayRect = daySectionFrames[payload.scheduleDate], dayRect.width > 20 {
            return CGRect(
                x: dayRect.minX + 130,
                y: min(dayRect.minY + 24, windowSize.height - 120),
                width: max(300, dayRect.width - 150),
                height: 26
            )
        }
        return CGRect(x: windowSize.width * 0.36, y: 190, width: 480, height: 26)
    }
}

// MARK: - 120fps Optical & Geometric State (Text-Anchored, Non-Constant Bubble Sizes, No Shimmer)

private struct MacBubbleUniforms {
    var resolution: SIMD2<Float>
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var cornerRadius: Float
    var power: Float
    var dispersion: Float
    var wobblePhase: Float
    var wobbleAmp: Float
    var opacity: Float
}

private struct MacTaskBubbleFrameMetrics {
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

    static let checkboxSize: CGFloat = 16
    static let checkboxCorner: CGFloat = 4.5
    static let textLeadingOffsetInRow: CGFloat = 16 + 8

    static func evaluate(
        elapsed t: TimeInterval,
        payload: MacTaskBubbleFlightPayload,
        rowFrame: CGRect,
        windowSize: CGSize
    ) -> MacTaskBubbleFrameMetrics {
        let textW = payload.measuredTextSize.width
        let textH = payload.measuredTextSize.height
        let bubbleW = min(max(textW + 44, 66), min(240, windowSize.width - 80))
        let bubbleH = min(max(textH + 28, 48), 78)

        let checkboxCenter = CGPoint(x: rowFrame.minX + checkboxSize * 0.5, y: rowFrame.midY)
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
                windowSize: windowSize
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
                windowSize: windowSize
            )
        }
    }

    private static func evaluateForward(
        t: TimeInterval,
        payload: MacTaskBubbleFlightPayload,
        rowFrame: CGRect,
        checkboxCenter: CGPoint,
        rowTextCenter: CGPoint,
        bubbleW: CGFloat,
        bubbleH: CGFloat,
        windowSize: CGSize
    ) -> MacTaskBubbleFrameMetrics {
        let cardRect = payload.composerCardFrame.width > 40
            ? payload.composerCardFrame
            : CGRect(
                x: windowSize.width * 0.5 - 300 + 44,
                y: windowSize.height * 0.5 - 76 - 56,
                width: 600,
                height: 152
            )

        let tfOriginX = payload.textOriginFrame.width > 20 ? payload.textOriginFrame.minX : (cardRect.minX + 48)
        let tfMidY = payload.textOriginFrame.height > 10 ? payload.textOriginFrame.midY : (cardRect.minY + 66)
        let rawTextCenterX = tfOriginX + payload.measuredTextSize.width * 0.5
        let clampedStartX = min(max(rawTextCenterX, bubbleW * 0.5 + 8), windowSize.width - bubbleW * 0.5 - 8)
        let textStartCenter = CGPoint(x: clampedStartX, y: tfMidY)

        // Composer itself turns into the bubble and rapidly wraps around the text WHILE already traveling
        let wrapU = clamp(t / 0.20)
        let wrap = smoothstep(wrapU)

        let flightU = clamp(t / 0.44)
        let flight = springEase(flightU)

        // Late path divergence right before arrival: bubble curves into 16x16 checkbox, text glides into row slot
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
        let wrappedCorner = lerp(20.0, bubbleCorner, wrap)
        let cornerRadius = lerp(wrappedCorner, checkboxCorner, diverge)

        let approachTarget = CGPoint(
            x: lerp(rowTextCenter.x, checkboxCenter.x, 0.32),
            y: rowTextCenter.y
        )
        let liftY = -14.0 * CGFloat(flightArc)
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

        return MacTaskBubbleFrameMetrics(
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
        payload: MacTaskBubbleFlightPayload,
        rowFrame: CGRect,
        checkboxCenter: CGPoint,
        rowTextCenter: CGPoint,
        bubbleW: CGFloat,
        bubbleH: CGFloat,
        windowSize: CGSize
    ) -> MacTaskBubbleFrameMetrics {
        let composerW: CGFloat = 600
        let composerH: CGFloat = 152
        let composerRect = CGRect(
            x: windowSize.width * 0.5 - composerW * 0.5 + 44,
            y: windowSize.height * 0.5 - composerH * 0.5 - 56,
            width: composerW,
            height: composerH
        )
        // Exact leading text slot inside TaskEditorPopover (padding 20 + checkbox 16 + spacing 12 = 48)
        let destTextOriginX = composerRect.minX + 48
        let destTextMidY = composerRect.minY + 66
        let rawDestX = destTextOriginX + payload.measuredTextSize.width * 0.5
        let destTextCenter = CGPoint(
            x: min(max(rawDestX, bubbleW * 0.5 + 8), windowSize.width - bubbleW * 0.5 - 8),
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
        let cornerRadius = lerp(midCorner, 20.0, unwrap)

        let approachOrigin = CGPoint(
            x: lerp(rowTextCenter.x, checkboxCenter.x, 0.32),
            y: rowTextCenter.y
        )
        let flightArc = sin(flightU * .pi)
        let sharedPos = CGPoint(
            x: lerp(approachOrigin.x, destTextCenter.x, flight),
            y: lerp(approachOrigin.y, destTextCenter.y, flight) - 14.0 * CGFloat(flightArc)
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

        return MacTaskBubbleFrameMetrics(
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

// MARK: - Prewarmed Metal Pipeline Cache (Zero First-Frame Compilation Lag on Enter)

@MainActor
final class MacBubbleMetalCache {
    static let shared = MacBubbleMetalCache()

    let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private(set) var commandQueue: MTLCommandQueue?
    private(set) var pipelineState: MTLRenderPipelineState?
    private var didStartPrewarm = false

    static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float2 center;
        float2 halfSize;
        float cornerRadius;
        float power;
        float dispersion;
        float wobblePhase;
        float wobbleAmp;
        float opacity;
    };

    struct VSOut {
        float4 pos [[position]];
        float2 uv;
    };

    vertex VSOut bubble_vs(uint vid [[vertex_id]]) {
        const float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VSOut out;
        out.pos = float4(verts[vid], 0.0, 1.0);
        out.uv = float2(verts[vid].x * 0.5 + 0.5, 0.5 - verts[vid].y * 0.5);
        return out;
    }

    static float sdRoundedBox(float2 p, float2 halfSize, float radius) {
        float2 q = abs(p) - halfSize + float2(radius);
        return min(max(q.x, q.y), 0.0f) + length(max(q, float2(0.0f))) - radius;
    }

    fragment float4 bubble_fs(
        VSOut in [[stage_in]],
        texture2d<float> backdrop [[texture(0)]],
        constant Uniforms& u [[buffer(0)]]
    ) {
        if (u.opacity <= 0.001f) {
            return float4(0.0f);
        }

        float2 position = in.uv * u.resolution;
        float2 safeHalf = max(u.halfSize, float2(1.0f));
        float2 delta = position - u.center;
        float2 n = delta / safeHalf;
        float rRaw = length(n);
        float angle = atan2(n.y, n.x);

        float wobble = u.wobbleAmp * (
            0.048f * sin(2.0f * angle + u.wobblePhase) +
            0.030f * cos(3.0f * angle - u.wobblePhase * 1.35f) +
            0.016f * sin(4.0f * angle + u.wobblePhase * 0.75f)
        );
        float2 wobbledHalf = safeHalf * (1.0f + wobble);
        float effRadius = min(u.cornerRadius, min(wobbledHalf.x, wobbledHalf.y));

        float sdf = sdRoundedBox(delta, wobbledHalf, effRadius);
        float minDim = max(min(wobbledHalf.x, wobbledHalf.y), 1.0f);
        float mask = 1.0f - smoothstep(-1.25f, 1.25f, sdf);
        if (mask <= 0.001f) {
            return float4(0.0f);
        }

        float edgeProx = clamp(1.0f + sdf / minDim, 0.0f, 1.0f);
        float r = clamp(mix(rRaw, edgeProx, 0.55f), 0.0f, 1.0f);

        float2 direction = rRaw > 0.0001f ? n / rRaw : float2(0.0f);
        float2 tangent = float2(-direction.y, direction.x);

        float zoom = mix(1.0f, 0.48f + pow(r, 3.0f) * 0.80f, u.power);
        float split = pow(r, 2.4f) * min(minDim * 0.34f, 24.0f) * u.dispersion;

        float2 base = delta * (zoom - 1.0f);
        float2 redOffset   = clamp(base - direction * split * 1.18f + tangent * split * 0.24f, -140.0f, 140.0f);
        float2 greenOffset = clamp(base, -140.0f, 140.0f);
        float2 blueOffset  = clamp(base + direction * split * 1.26f - tangent * split * 0.24f, -140.0f, 140.0f);

        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 invRes = 1.0f / max(u.resolution, float2(1.0f));
        float4 red   = backdrop.sample(s, clamp((position + redOffset) * invRes, 0.0f, 1.0f));
        float4 green = backdrop.sample(s, clamp((position + greenOffset) * invRes, 0.0f, 1.0f));
        float4 blue  = backdrop.sample(s, clamp((position + blueOffset) * invRes, 0.0f, 1.0f));

        float3 color = float3(red.r, green.g, blue.b);

        float z = sqrt(max(1.0f - min(r * r, 1.0f), 0.0f));
        float frost = mix(0.14f, 0.03f, u.power) * (0.42f + 0.58f * (1.0f - z));
        color = mix(color, float3(0.14f), frost * u.power);

        float topLight = pow(max(dot(n, normalize(float2(-0.32f, -0.88f))), 0.0f), 3.4f);
        float bottomBounce = pow(max(dot(n, normalize(float2(0.25f, 0.92f))), 0.0f), 3.8f);
        float specular = topLight * smoothstep(0.58f, 0.98f, r) * 0.44f * u.power;
        float bounce = bottomBounce * smoothstep(0.72f, 0.985f, r) * 0.16f * u.power;

        float rim = smoothstep(-2.4f, -0.35f, sdf) * (1.0f - smoothstep(-0.15f, 1.1f, sdf));
        float innerShade = smoothstep(0.76f, 0.96f, r) * (1.0f - rim) * 0.045f * u.power;

        float3 rimTint = float3(
            1.0f + 0.22f * u.dispersion * sin(angle * 2.0f + u.wobblePhase),
            1.0f,
            1.0f + 0.22f * u.dispersion * cos(angle * 2.0f - u.wobblePhase)
        );

        color += float3(specular + bounce - innerShade) + rimTint * (rim * 0.38f * (0.32f + 0.68f * u.power));
        float outAlpha = mask * u.opacity;
        return float4(clamp(color, 0.0f, 1.0f) * outAlpha, outAlpha);
    }
    """

    /// Precompiles the Metal shader asynchronously on app launch so pressing Enter has 0ms shader lag.
    func prewarm() {
        guard !didStartPrewarm, let device else { return }
        didStartPrewarm = true
        commandQueue = device.makeCommandQueue()
        let src = Self.metalSource
        device.makeLibrary(source: src, options: nil) { library, _ in
            guard let library,
                  let vs = library.makeFunction(name: "bubble_vs"),
                  let fs = library.makeFunction(name: "bubble_fs") else { return }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vs
            desc.fragmentFunction = fs
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            let state = try? device.makeRenderPipelineState(descriptor: desc)
            Task { @MainActor in
                self.pipelineState = state
            }
        }
    }
}

// MARK: - Runtime-Compiled Metal Optical Liquid Glass Bubble View

private struct MacTaskBubbleMetalView: NSViewRepresentable {
    let backdropImage: CGImage?
    let uniforms: MacBubbleUniforms

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtk = MTKView()
        mtk.device = MacBubbleMetalCache.shared.device
        mtk.delegate = context.coordinator
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtk.layer?.isOpaque = false
        mtk.isPaused = true
        mtk.enableSetNeedsDisplay = true
        MacBubbleMetalCache.shared.prewarm()
        return mtk
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateBackdropIfNeeded(image: backdropImage, device: nsView.device)
        context.coordinator.uniforms = uniforms
        nsView.setNeedsDisplay(nsView.bounds)
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        private var backdropTexture: MTLTexture?
        private var lastBackdropId: ObjectIdentifier?
        var uniforms = MacBubbleUniforms(
            resolution: .init(1, 1),
            center: .zero,
            halfSize: .init(1, 1),
            cornerRadius: 20,
            power: 0,
            dispersion: 0,
            wobblePhase: 0,
            wobbleAmp: 0,
            opacity: 0
        )

        func updateBackdropIfNeeded(image: CGImage?, device: MTLDevice?) {
            guard let image, let device else { return }
            let id = ObjectIdentifier(image)
            guard id != lastBackdropId else { return }
            lastBackdropId = id
            let loader = MTKTextureLoader(device: device)
            backdropTexture = try? loader.newTexture(cgImage: image, options: [
                .SRGB: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
            ])
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipelineState = MacBubbleMetalCache.shared.pipelineState,
                  let commandQueue = MacBubbleMetalCache.shared.commandQueue,
                  let texture = backdropTexture,
                  let passDesc = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let cmd = commandQueue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc) else { return }

            var u = uniforms
            enc.setRenderPipelineState(pipelineState)
            enc.setFragmentTexture(texture, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<MacBubbleUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}

// MARK: - macOS Flight Overlay

struct MacTaskBubbleFlightOverlay: View {
    @Bindable var coordinator: MacTaskFlightCoordinator

    var body: some View {
        if let payload = coordinator.activeFlight {
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    let elapsed = max(0, timeline.date.timeIntervalSince(payload.startTime))
                    let rowFrame = payload.direction == .openForEdit
                        ? payload.textOriginFrame
                        : coordinator.destinationFrame(for: payload, in: geo.size)
                    let m = MacTaskBubbleFrameMetrics.evaluate(
                        elapsed: elapsed,
                        payload: payload,
                        rowFrame: rowFrame,
                        windowSize: geo.size
                    )

                    ZStack {
                        if m.fadingComposerOpacity > 0.01 && m.fadingComposerRect.width > 40 {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: m.fadingComposerRect.width, height: m.fadingComposerRect.height)
                                .position(x: m.fadingComposerRect.midX, y: m.fadingComposerRect.midY)
                                .scaleEffect(0.96 + 0.04 * m.fadingComposerOpacity)
                                .opacity(m.fadingComposerOpacity * 0.85)
                                .allowsHitTesting(false)
                        }

                        if m.settlingTextOpacity > 0.01 {
                            rowTextWithoutCheckbox(payload: payload)
                                .frame(width: rowFrame.width, height: rowFrame.height, alignment: .leading)
                                .position(x: rowFrame.midX, y: rowFrame.midY)
                                .opacity(m.settlingTextOpacity)
                                .allowsHitTesting(false)
                        }

                        if m.bubbleOpacity > 0.01 {
                            MacTaskBubbleMetalView(
                                backdropImage: payload.backdropCGImage,
                                uniforms: MacBubbleUniforms(
                                    resolution: SIMD2(Float(max(geo.size.width, 1)), Float(max(geo.size.height, 1))),
                                    center: SIMD2(Float(m.center.x), Float(m.center.y)),
                                    halfSize: SIMD2(Float(m.halfSize.width), Float(m.halfSize.height)),
                                    cornerRadius: Float(m.cornerRadius),
                                    power: Float(m.power),
                                    dispersion: Float(m.dispersion),
                                    wobblePhase: Float(m.wobblePhase),
                                    wobbleAmp: Float(m.wobbleAmp),
                                    opacity: Float(m.bubbleOpacity)
                                )
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                        }

                        if m.refractedTextOpacity > 0.01 {
                            Text(payload.title)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(width: payload.measuredTextSize.width + 6, alignment: .leading)
                                .scaleEffect(1.0 + CGFloat(m.textPower * 0.07))
                                .position(m.textCenter)
                                .opacity(m.refractedTextOpacity)
                                .allowsHitTesting(false)
                        }

                        if m.bubbleOpacity > 0.01 {
                            RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.74),
                                            .white.opacity(0.10),
                                            .white.opacity(0.34)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: m.halfSize.width < 14 ? 1.35 : 0.9
                                )
                                .frame(width: m.halfSize.width * 2, height: m.halfSize.height * 2)
                                .position(m.center)
                                .opacity(m.bubbleOpacity * (0.48 + 0.52 * m.power))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func rowTextWithoutCheckbox(payload: MacTaskBubbleFlightPayload) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: MacTaskBubbleFrameMetrics.checkboxSize, height: MacTaskBubbleFrameMetrics.checkboxSize)

            Text(payload.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(payload.isInbox ? "Inbox" : payload.documentTitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.05)))

            if payload.hasRepeat {
                Image(systemName: "repeat")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

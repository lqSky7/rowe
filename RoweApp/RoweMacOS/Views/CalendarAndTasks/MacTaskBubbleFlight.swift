import AppKit
import Metal
import MetalKit
import Observation
import SwiftUI
import RoweCore

struct MacTaskBubbleFlightPayload: Identifiable {
    let id: UUID = UUID()
    let blockId: String
    let title: String
    let scheduleDate: Date
    let hasRepeat: Bool
    let imageCount: Int
    let isInbox: Bool
    let documentTitle: String
    let accentColor: Color
    let isDarkMode: Bool
    let textOriginFrame: CGRect
    let composerCardFrame: CGRect
    let measuredTextSize: CGSize
    let startTime: Date
    let backdropCGImage: CGImage?
    let taskTextCGImage: CGImage?
}

/// Coordinates the macOS Liquid Glass Bubble flight:
/// - Captures a clean 1.0x backdrop of the underlying window AFTER the composer closes so the lens
///   refracts the real Calendar rows (never the old modal).
/// - Renders the task text into an alpha texture passed directly into the Metal lens shader so the
///   glass bubble genuinely refracts BOTH the underlying Calendar rows AND the flying task text.
/// - Travels continuously straight from the composer to the 16×16 checkbox without ever hovering.
@MainActor
@Observable
final class MacTaskFlightCoordinator {
    var rowFrames: [String: CGRect] = [:]
    var daySectionFrames: [Date: CGRect] = [:]
    var hiddenLandingBlockId: String? = nil
    var activeEditingBlockId: String? = nil
    var activeFlight: MacTaskBubbleFlightPayload? = nil

    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var hapticTask: Task<Void, Never>?

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
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let rect = (safeText as NSString).boundingRect(
            with: CGSize(width: max(60, maxWidth), height: 60),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return CGSize(
            width: min(max(ceil(rect.width) + 6, 20), maxWidth),
            height: min(max(ceil(rect.height) + 4, 20), 44)
        )
    }

    /// Renders the flying task title into a crisp 2x RGBA CGImage so the Metal lens refracts it directly.
    private static func renderTaskTextCGImage(title: String, size: CGSize, isDarkMode: Bool) -> CGImage? {
        let scale: CGFloat = 2.0
        let w = max(2, Int(ceil(size.width * scale)))
        let h = max(2, Int(ceil(size.height * scale)))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: isDarkMode ? NSColor.white : NSColor.black,
            .paragraphStyle: paragraph
        ]
        (title as NSString).draw(
            in: CGRect(x: 0, y: 1, width: size.width, height: size.height),
            withAttributes: attrs
        )
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func captureWindowSnapshot() -> CGImage? {
        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView,
              let layer = view.layer,
              view.bounds.width > 20, view.bounds.height > 20 else {
            return nil
        }
        let scale: CGFloat = 1.0
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
        let title = item.block.content.isEmpty ? "Image Task" : item.block.content
        let maxTextW = textFieldFrame.width > 40 ? textFieldFrame.width : 500
        let measured = Self.measureTaskText(title, maxWidth: maxTextW)
        let textImg = Self.renderTaskTextCGImage(title: title, size: measured, isDarkMode: isDarkMode)

        // Wait 1 display tick so SwiftUI removes the composer modal BEFORE capturing the clean window backdrop
        launchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.captureWindowSnapshot()
            let payload = MacTaskBubbleFlightPayload(
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
                backdropCGImage: snapshot,
                taskTextCGImage: textImg
            )
            self.activeFlight = payload
            HapticsManager.shared.tap()

            self.hapticTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, self?.activeFlight?.id == payload.id else { return }
                HapticsManager.shared.boundarySnap()
            }

            self.completionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.forwardTotalDuration * 1_000_000_000))
                guard !Task.isCancelled, let self, self.activeFlight?.id == payload.id else { return }
                HapticsManager.shared.taskComplete()
                self.activeFlight = nil
                self.hiddenLandingBlockId = nil
            }
        }
    }

    func clearEditingState() {
        activeEditingBlockId = nil
    }

    private func cancelTasks() {
        launchTask?.cancel()
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

// MARK: - 120fps Optical & Geometric State (Direct-to-Checkbox Trajectory, Zero Hover)

private struct MacBubbleUniforms {
    var resolution: SIMD2<Float>
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var textCenter: SIMD2<Float>
    var textHalfSize: SIMD2<Float>
    var textOpacity: Float
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

    static let checkboxSize: CGFloat = 16
    static let checkboxCorner: CGFloat = 4.5
    static let textLeadingOffsetInRow: CGFloat = 16 + 8

    static func evaluate(
        elapsed t: TimeInterval,
        payload: MacTaskBubbleFlightPayload,
        rowFrame: CGRect,
        windowSize: CGSize
    ) -> MacTaskBubbleFrameMetrics {
        let total = MacTaskFlightCoordinator.forwardTotalDuration
        let u = clamp(t / total)

        let cardRect = payload.composerCardFrame.width > 40
            ? payload.composerCardFrame
            : CGRect(
                x: windowSize.width * 0.5 - 300 + 44,
                y: windowSize.height * 0.5 - 76 - 56,
                width: 600,
                height: 152
            )

        let textW = payload.measuredTextSize.width
        let textH = payload.measuredTextSize.height
        let dropletW = min(max(textW * 0.55 + 32, 54), 112)
        let dropletH = min(max(textH + 22, 44), 66)

        let checkboxCenter = CGPoint(x: rowFrame.minX + checkboxSize * 0.5, y: rowFrame.midY)
        let clampedRowTextW = min(textW, max(40, rowFrame.width - textLeadingOffsetInRow - 48))
        let rowTextCenter = CGPoint(
            x: rowFrame.minX + textLeadingOffsetInRow + clampedRowTextW * 0.5,
            y: rowFrame.midY
        )

        let tfOriginX = payload.textOriginFrame.width > 20 ? payload.textOriginFrame.minX : (cardRect.minX + 48)
        let tfMidY = payload.textOriginFrame.height > 10 ? payload.textOriginFrame.midY : (cardRect.minY + 66)
        let textStartCenter = CGPoint(
            x: min(max(tfOriginX + textW * 0.5, 24), windowSize.width - 24),
            y: tfMidY
        )
        let bubbleStartCenter = CGPoint(x: cardRect.midX, y: cardRect.midY)

        // Bubble moves continuously on a smooth curve directly to checkboxCenter from t=0 (zero hover!)
        let bubbleProgress = easeInOutCubic(u)
        let controlPoint = CGPoint(
            x: lerp(bubbleStartCenter.x, checkboxCenter.x, 0.35) - 28,
            y: min(bubbleStartCenter.y, checkboxCenter.y) - 20
        )
        let currentCenter = quadBezier(bubbleStartCenter, controlPoint, checkboxCenter, t: bubbleProgress)

        let condense = smoothstep(clamp(u / 0.28))
        let shrinkToCheckbox = smoothstep(clamp((u - 0.14) / 0.86))
        let arcStretch = sin(u * .pi) * 0.08 * (1.0 - shrinkToCheckbox)
        let midW = lerp(cardRect.width, dropletW * (1.0 - CGFloat(arcStretch * 0.3)), condense)
        let midH = lerp(cardRect.height, dropletH * (1.0 + CGFloat(arcStretch)), condense)
        let currentW = lerp(midW, checkboxSize, shrinkToCheckbox)
        let currentH = lerp(midH, checkboxSize, shrinkToCheckbox)

        let dropletCorner = min(dropletW, dropletH) * 0.5
        let midCorner = lerp(20.0, dropletCorner, condense)
        let cornerRadius = lerp(midCorner, checkboxCorner, shrinkToCheckbox)

        // Task text independently glides straight into rowTextCenter
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

        return MacTaskBubbleFrameMetrics(
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

// MARK: - Prewarmed Metal Pipeline Cache (Refracts Backdrop + Moving Task Text Together)

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
        float2 textCenter;
        float2 textHalfSize;
        float textOpacity;
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

    static float3 sampleSceneAt(
        float2 posPx,
        texture2d<float> backdrop,
        texture2d<float> taskText,
        sampler s,
        constant Uniforms& u
    ) {
        float2 invRes = 1.0f / max(u.resolution, float2(1.0f));
        float3 bg = backdrop.sample(s, clamp(posPx * invRes, 0.0f, 1.0f)).rgb;
        if (u.textOpacity > 0.005f && u.textHalfSize.x > 1.0f && u.textHalfSize.y > 1.0f) {
            float2 tuv = (posPx - (u.textCenter - u.textHalfSize)) / (u.textHalfSize * 2.0f);
            if (tuv.x >= 0.0f && tuv.x <= 1.0f && tuv.y >= 0.0f && tuv.y <= 1.0f) {
                float4 txt = taskText.sample(s, tuv);
                float a = clamp(txt.a * u.textOpacity, 0.0f, 1.0f);
                bg = mix(bg, txt.rgb / max(txt.a, 0.001f), a);
            }
        }
        return bg;
    }

    fragment float4 bubble_fs(
        VSOut in [[stage_in]],
        texture2d<float> backdrop [[texture(0)]],
        texture2d<float> taskText [[texture(1)]],
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
        float split = pow(r, 2.4f) * min(minDim * 0.28f, 18.0f) * u.dispersion;

        float2 base = delta * (zoom - 1.0f);
        float2 redOffset   = clamp(base - direction * split * 1.12f + tangent * split * 0.20f, -140.0f, 140.0f);
        float2 greenOffset = clamp(base, -140.0f, 140.0f);
        float2 blueOffset  = clamp(base + direction * split * 1.18f - tangent * split * 0.20f, -140.0f, 140.0f);

        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float3 sR = sampleSceneAt(position + redOffset, backdrop, taskText, s, u);
        float3 sG = sampleSceneAt(position + greenOffset, backdrop, taskText, s, u);
        float3 sB = sampleSceneAt(position + blueOffset, backdrop, taskText, s, u);

        float3 color = float3(sR.r, sG.g, sB.b);

        float z = sqrt(max(1.0f - min(r * r, 1.0f), 0.0f));
        float frost = mix(0.12f, 0.025f, u.power) * (0.42f + 0.58f * (1.0f - z));
        color = mix(color, float3(0.14f), frost * u.power);

        float topLight = pow(max(dot(n, normalize(float2(-0.32f, -0.88f))), 0.0f), 3.4f);
        float bottomBounce = pow(max(dot(n, normalize(float2(0.25f, 0.92f))), 0.0f), 3.8f);
        float specular = topLight * smoothstep(0.58f, 0.98f, r) * 0.44f * u.power;
        float bounce = bottomBounce * smoothstep(0.72f, 0.985f, r) * 0.16f * u.power;

        float rim = smoothstep(-2.4f, -0.35f, sdf) * (1.0f - smoothstep(-0.15f, 1.1f, sdf));
        float innerShade = smoothstep(0.76f, 0.96f, r) * (1.0f - rim) * 0.045f * u.power;

        color += float3(specular + bounce - innerShade) + float3(1.0f) * (rim * 0.36f * (0.32f + 0.68f * u.power));
        float outAlpha = mask * u.opacity;
        return float4(clamp(color, 0.0f, 1.0f) * outAlpha, outAlpha);
    }
    """

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

private struct MacTaskBubbleMetalView: NSViewRepresentable {
    let backdropImage: CGImage?
    let taskTextImage: CGImage?
    let uniforms: MacBubbleUniforms

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let mtk = MTKView()
        mtk.device = MacBubbleMetalCache.shared.device
        mtk.delegate = context.coordinator
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtk.layer?.isOpaque = false
        mtk.framebufferOnly = true
        if let metalLayer = mtk.layer as? CAMetalLayer {
            metalLayer.presentsWithTransaction = true
        }
        mtk.isPaused = true
        mtk.enableSetNeedsDisplay = true
        MacBubbleMetalCache.shared.prewarm()
        return mtk
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateTexturesIfNeeded(
            backdrop: backdropImage,
            taskText: taskTextImage,
            device: nsView.device
        )
        context.coordinator.uniforms = uniforms
        nsView.setNeedsDisplay(nsView.bounds)
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        private var backdropTexture: MTLTexture?
        private var textTexture: MTLTexture?
        private var lastBackdropId: ObjectIdentifier?
        private var lastTextId: ObjectIdentifier?
        var uniforms = MacBubbleUniforms(
            resolution: .init(1, 1),
            center: .zero,
            halfSize: .init(1, 1),
            textCenter: .zero,
            textHalfSize: .init(1, 1),
            textOpacity: 0,
            cornerRadius: 20,
            power: 0,
            dispersion: 0,
            wobblePhase: 0,
            wobbleAmp: 0,
            opacity: 0
        )

        func updateTexturesIfNeeded(backdrop: CGImage?, taskText: CGImage?, device: MTLDevice?) {
            guard let device else { return }
            let loader = MTKTextureLoader(device: device)
            let opts: [MTKTextureLoader.Option: Any] = [
                .SRGB: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
            ]
            if let backdrop {
                let id = ObjectIdentifier(backdrop)
                if id != lastBackdropId {
                    lastBackdropId = id
                    backdropTexture = try? loader.newTexture(cgImage: backdrop, options: opts)
                }
            }
            if let taskText {
                let id = ObjectIdentifier(taskText)
                if id != lastTextId {
                    lastTextId = id
                    textTexture = try? loader.newTexture(cgImage: taskText, options: opts)
                }
            }
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
            enc.setFragmentTexture(textTexture ?? texture, index: 1)
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
                    let rowFrame = coordinator.destinationFrame(for: payload, in: geo.size)
                    let m = MacTaskBubbleFrameMetrics.evaluate(
                        elapsed: elapsed,
                        payload: payload,
                        rowFrame: rowFrame,
                        windowSize: geo.size
                    )

                    ZStack {
                        // Layer 1: Flying & settling task text (rendered UNDER the refracting glass bubble!)
                        if m.settlingRowOpacity > 0.01 {
                            rowTextWithoutCheckbox(payload: payload)
                                .frame(width: rowFrame.width, height: rowFrame.height, alignment: .leading)
                                .position(x: rowFrame.midX, y: rowFrame.midY)
                                .opacity(m.settlingRowOpacity)
                                .allowsHitTesting(false)
                        }

                        if m.flyingTextOpacity > 0.01 {
                            Text(payload.title)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(width: payload.measuredTextSize.width, alignment: .leading)
                                .position(m.textCenter)
                                .opacity(m.flyingTextOpacity)
                                .allowsHitTesting(false)
                        }

                        // Layer 2: True refracting Metal glass bubble passing OVER backdrop + flying text
                        if m.bubbleOpacity > 0.01 {
                            MacTaskBubbleMetalView(
                                backdropImage: payload.backdropCGImage,
                                taskTextImage: payload.taskTextCGImage,
                                uniforms: MacBubbleUniforms(
                                    resolution: SIMD2(Float(max(geo.size.width, 1)), Float(max(geo.size.height, 1))),
                                    center: SIMD2(Float(m.center.x), Float(m.center.y)),
                                    halfSize: SIMD2(Float(m.halfSize.width), Float(m.halfSize.height)),
                                    textCenter: SIMD2(Float(m.textCenter.x), Float(m.textCenter.y)),
                                    textHalfSize: SIMD2(Float(payload.measuredTextSize.width * 0.5), Float(payload.measuredTextSize.height * 0.5)),
                                    textOpacity: Float(m.flyingTextOpacity),
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

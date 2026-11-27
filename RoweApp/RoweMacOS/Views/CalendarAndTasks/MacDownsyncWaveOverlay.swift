import AppKit
import Metal
import MetalKit
import Observation
import SwiftUI
import RoweCore

enum MacDownsyncWavePhase {
    /// Phase 1: Rainbow + upward distortion + progressive blur converging toward the top edge while reaching backend
    case converging(id: UUID, startTime: Date, fadeOutStartTime: Date?, isDarkMode: Bool, backdropCGImage: CGImage?)
    /// Phase 2: Luminous soft-white wave with rainbow halo + progressive blur expanding downward to midway
    case expanding(id: UUID, taskIds: Set<String>, startTime: Date, isDarkMode: Bool, backdropCGImage: CGImage?)
}

/// Coordinates the full ~2.05s 2-phase optical sync animation on macOS (exact parity with iOS):
/// 1. **Phase 1 (~0.56s — Converging Rainbow + Top Stretch + Progressive Blur)**: Newly downsynced tasks
///    stay hidden (`opacity 0`) while the rainbow arc & upward distortion converge toward the top edge.
/// 2. **Phase 2 (~1.52s — Expanding Soft-White Wave with Rainbow Halo + Reveal + Dim Fade)**:
///    Soft-white wave with rainbow halo & wide progressive blur expands organically from top toward midway,
///    tasks smoothly fade in (NO scale-up) with a single thin bright shimmer, and the dim fades smoothly out.
@MainActor
@Observable
final class MacDownsyncWaveCoordinator {
    var activePhase: MacDownsyncWavePhase? = nil
    var pendingRevealTaskIds: Set<String> = []
    var highlightedTaskIds: Set<String> = []
    var shimmerTriggerId: UUID = UUID()

    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var lastConvergeTriggerAt: Date = .distantPast
    @ObservationIgnored private var lastExpandTriggerAt: Date = .distantPast

    static let convergeCooldown: TimeInterval = 12.0
    static let expandCooldown: TimeInterval = 6.0
    static let convergeDuration: TimeInterval = 0.56
    static let convergeFadeOutDuration: TimeInterval = 0.34
    static let waveDuration: TimeInterval = 1.05
    static let dimFadeOutStart: TimeInterval = 0.88
    static let dimFadeOutDuration: TimeInterval = 0.62
    static let expandTotalDuration: TimeInterval = 1.52

    func shouldHidePendingReveal(_ blockId: String) -> Bool {
        pendingRevealTaskIds.contains(blockId)
    }

    func beginConverging(isDarkMode: Bool) {
        if case .expanding = activePhase { return }
        if !pendingRevealTaskIds.isEmpty { return }
        let now = Date()
        guard now.timeIntervalSince(lastConvergeTriggerAt) >= Self.convergeCooldown,
              now.timeIntervalSince(lastExpandTriggerAt) >= Self.convergeCooldown else { return }
        lastConvergeTriggerAt = now

        cleanupTask?.cancel()
        let snap = Self.captureWindowSnapshot()
        let id = UUID()
        activePhase = .converging(
            id: id,
            startTime: now,
            fadeOutStartTime: nil,
            isDarkMode: isDarkMode,
            backdropCGImage: snap
        )

        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.finishConvergingIfIdle()
        }
    }

    func finishConvergingIfIdle() {
        guard pendingRevealTaskIds.isEmpty else { return }
        guard case .converging(let id, let startTime, let existingFade, let isDarkMode, let snap) = activePhase,
              existingFade == nil else { return }
        cleanupTask?.cancel()
        let fadeStart = Date()
        activePhase = .converging(
            id: id,
            startTime: startTime,
            fadeOutStartTime: fadeStart,
            isDarkMode: isDarkMode,
            backdropCGImage: snap
        )
        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.convergeFadeOutDuration + 0.04) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if case .converging(let curId, _, _, _, _) = self.activePhase, curId == id {
                self.activePhase = nil
            }
        }
    }

    func trigger(taskIds: Set<String>, isDarkMode: Bool) {
        guard !taskIds.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastExpandTriggerAt) >= Self.expandCooldown else { return }
        lastExpandTriggerAt = now
        lastConvergeTriggerAt = now
        launchTask?.cancel()
        revealTask?.cancel()
        cleanupTask?.cancel()

        // Immediately hide newly downsynced tasks so they NEVER appear before the wave
        pendingRevealTaskIds = taskIds
        highlightedTaskIds = []

        // Guarantee full Phase 1 converging rainbow (~0.56s) even when backend responded quickly
        let remainingConverge: TimeInterval
        if case .converging(_, let startTime, nil, _, _) = activePhase {
            let elapsed = Date().timeIntervalSince(startTime)
            remainingConverge = max(0.05, Self.convergeDuration - elapsed)
        } else {
            let snap = Self.captureWindowSnapshot()
            activePhase = .converging(
                id: UUID(),
                startTime: Date(),
                fadeOutStartTime: nil,
                isDarkMode: isDarkMode,
                backdropCGImage: snap
            )
            remainingConverge = Self.convergeDuration
        }

        launchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingConverge * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            let snap = Self.captureWindowSnapshot()
            let id = UUID()
            self.highlightedTaskIds = taskIds
            self.shimmerTriggerId = id
            self.activePhase = .expanding(
                id: id,
                taskIds: taskIds,
                startTime: Date(),
                isDarkMode: isDarkMode,
                backdropCGImage: snap
            )
            HapticsManager.shared.boundarySnap()

            self.revealTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    self.pendingRevealTaskIds.subtract(taskIds)
                }
            }

            self.cleanupTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.expandTotalDuration * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if case .expanding(let curId, _, _, _, _) = self.activePhase, curId == id {
                    self.activePhase = nil
                    self.highlightedTaskIds = []
                    self.pendingRevealTaskIds = []
                }
            }
        }
    }

    private static func captureWindowSnapshot() -> CGImage? {
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
}

// MARK: - Prewarmed Runtime-Compiled Metal Pipeline for 2-Phase macOS Sync Wave

private struct MacDownsyncUniforms {
    var resolution: SIMD2<Float>
    var progress: Float
    var intensity: Float
    var isDarkMode: Float
    var phaseMode: Float
}

@MainActor
final class MacDownsyncMetalCache {
    static let shared = MacDownsyncMetalCache()

    let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private(set) var commandQueue: MTLCommandQueue?
    private(set) var pipelineState: MTLRenderPipelineState?
    private var didStartPrewarm = false

    static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float progress;
        float intensity;
        float isDarkMode;
        float phaseMode;
    };

    struct VSOut {
        float4 pos [[position]];
        float2 uv;
    };

    vertex VSOut downsync_vs(uint vid [[vertex_id]]) {
        const float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VSOut out;
        out.pos = float4(verts[vid], 0.0, 1.0);
        out.uv = float2(verts[vid].x * 0.5 + 0.5, 0.5 - verts[vid].y * 0.5);
        return out;
    }

    static float3 prismRainbow(float x) {
        float t = clamp(x, 0.0f, 1.0f);
        float3 c0 = float3(1.00f, 0.62f, 0.42f);
        float3 c1 = float3(0.98f, 0.44f, 0.78f);
        float3 c2 = float3(0.58f, 0.56f, 1.00f);
        float3 c3 = float3(0.32f, 0.86f, 1.00f);
        float3 c4 = float3(0.48f, 0.96f, 0.76f);

        if (t < 0.25f) return mix(c0, c1, t / 0.25f);
        if (t < 0.50f) return mix(c1, c2, (t - 0.25f) / 0.25f);
        if (t < 0.75f) return mix(c2, c3, (t - 0.50f) / 0.25f);
        return mix(c3, c4, (t - 0.75f) / 0.25f);
    }

    fragment float4 downsync_fs(
        VSOut in [[stage_in]],
        texture2d<float> backdrop [[texture(0)]],
        constant Uniforms& u [[buffer(0)]]
    ) {
        float env = clamp(u.intensity, 0.0f, 1.0f);
        if (env <= 0.001f || u.resolution.x < 1.0f || u.resolution.y < 1.0f) {
            return float4(0.0f);
        }

        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0f);

        float2 origin = float2(0.5f, -0.07f);
        float2 delta = uv - origin;
        float2 scaledDelta = float2(delta.x * aspect * 0.38f, delta.y);
        float radialDist = length(scaledDelta);
        float2 dir = radialDist > 1e-4f ? (delta / max(length(delta), 1e-4f)) : float2(0.0f, 1.0f);

        float verticalFade = 1.0f - smoothstep(0.40f, 0.86f, uv.y);
        bool isExpanding = (u.phaseMode >= 0.5f);

        float crestRadius;
        float leadWidth;
        float trailWidth;
        if (!isExpanding) {
            crestRadius = mix(0.66f, 0.04f, u.progress);
            leadWidth = mix(0.28f, 0.14f, u.progress);
            trailWidth = mix(0.34f, 0.18f, u.progress);
        } else {
            crestRadius = mix(-0.02f, 0.76f, u.progress);
            leadWidth = mix(0.15f, 0.34f, u.progress);
            trailWidth = mix(0.26f, 0.54f, u.progress);
        }

        float signedDist = radialDist - crestRadius;
        float width = signedDist > 0.0f ? leadWidth : trailWidth;
        float normD = signedDist / max(width, 0.02f);
        float waveBell = exp(-normD * normD);

        // 1. True smooth liquid-lens magnification stretch (zero pixelation)
        float stretchEnv = waveBell * env * verticalFade;
        float lensScale = isExpanding ? (1.0f - 0.16f * stretchEnv) : (1.0f + 0.13f * stretchEnv);

        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 pR = clamp(origin + delta * mix(1.0f, lensScale, 1.14f), 0.001f, 0.999f);
        float2 pG = clamp(origin + delta * lensScale, 0.001f, 0.999f);
        float2 pB = clamp(origin + delta * mix(1.0f, lensScale, 0.86f), 0.001f, 0.999f);

        // 2. Smooth 16-tap golden-angle Vogel spiral progressive blur (silky frosted glass)
        float blurWidth = max(width * 1.80f, 0.22f);
        float blurBell = exp(-pow(signedDist / blurWidth, 2.0f));
        float topBlur = exp(-max(uv.y, 0.0f) * 2.8f) * (isExpanding ? exp(-u.progress * 2.4f) : smoothstep(0.1f, 0.9f, u.progress));
        float progBlurAmt = clamp(max(blurBell, topBlur * 0.85f) * env * verticalFade, 0.0f, 1.0f);
        float2 blurRadiusUV = float2(progBlurAmt * (isExpanding ? 0.012f : 0.010f) / max(aspect, 0.5f),
                                     progBlurAmt * (isExpanding ? 0.012f : 0.010f));

        float rAcc = 0.0f;
        float gAcc = 0.0f;
        float bAcc = 0.0f;
        float wSum = 0.0f;
        const float goldenAngle = 2.39996323f;
        for (int i = 0; i < 16; i++) {
            float fi = float(i) + 0.5f;
            float rNorm = sqrt(fi / 16.0f);
            float theta = fi * goldenAngle;
            float2 off = float2(cos(theta), sin(theta)) * blurRadiusUV * rNorm;
            float w = exp(-1.8f * rNorm * rNorm);
            rAcc += backdrop.sample(s, clamp(pR + off, 0.001f, 0.999f)).r * w;
            gAcc += backdrop.sample(s, clamp(pG + off, 0.001f, 0.999f)).g * w;
            bAcc += backdrop.sample(s, clamp(pB + off, 0.001f, 0.999f)).b * w;
            wSum += w;
        }

        float3 refracted = float3(rAcc, gAcc, bAcc) / max(wSum, 1e-4f);

        float radialHue = clamp((signedDist / max(width * 1.35f, 0.08f)) * 0.5f + 0.5f, 0.0f, 1.0f);
        float lateralShift = 0.14f * sin(uv.x * 4.2f + u.progress * 2.4f);
        float3 rainbowColor = prismRainbow(fract(radialHue + lateralShift));

        float3 glowRGB;
        float blendAmt;
        float alpha;
        if (!isExpanding) {
            float topGather = exp(-max(uv.y, 0.0f) * 4.2f) * smoothstep(0.25f, 1.0f, u.progress) * env;
            float rainbowBand = waveBell * env * verticalFade;
            float gain = mix(0.26f, 0.38f, u.isDarkMode);
            glowRGB = rainbowColor * (rainbowBand * gain + topGather * 0.24f)
                    + float3(1.0f, 0.98f, 0.96f) * (topGather * 0.18f);
            blendAmt = clamp(rainbowBand * 1.05f + topGather * 0.85f, 0.0f, 0.82f);
            alpha = clamp(max(max(blurBell * 1.15f, waveBell * 1.20f), topGather) * env * verticalFade, 0.0f, 1.0f);
        } else {
            float coreWidth = mix(0.095f, 0.23f, u.progress);
            float haloWidth = mix(0.22f, 0.44f, u.progress);
            float coreArc = exp(-pow(signedDist / coreWidth, 2.0f)) * env * verticalFade;
            float outerHalo = exp(-pow((signedDist - coreWidth * 0.85f) / (haloWidth * 0.65f), 2.0f)) * env * verticalFade;
            float innerHalo = exp(-pow((signedDist + coreWidth * 0.75f) / (haloWidth * 0.75f), 2.0f)) * env * verticalFade;
            float rainbowHalo = clamp(outerHalo * 0.95f + innerHalo * 0.75f, 0.0f, 1.0f);
            float topLaunch = exp(-u.progress * 3.8f) * exp(-max(uv.y, 0.0f) * 4.5f) * env;

            float coreGain = mix(0.24f, 0.34f, u.isDarkMode);
            float haloGain = mix(0.28f, 0.42f, u.isDarkMode);
            glowRGB = float3(1.0f, 0.99f, 0.98f) * (coreArc * coreGain + topLaunch * 0.22f)
                    + rainbowColor * (rainbowHalo * haloGain + topLaunch * 0.26f);
            blendAmt = clamp(coreArc + rainbowHalo * 1.05f + topLaunch, 0.0f, 0.88f);
            alpha = clamp(max(max(blurBell * 1.18f, rainbowHalo), topLaunch) * env * verticalFade, 0.0f, 1.0f);
        }

        float3 screened = 1.0f - (1.0f - clamp(refracted, 0.0f, 1.0f)) * (1.0f - clamp(glowRGB, 0.0f, 0.68f));
        float3 outRGB = mix(refracted, screened, blendAmt);

        return float4(clamp(outRGB, 0.0f, 1.0f) * alpha, alpha);
    }
    """

    func prewarm() {
        guard !didStartPrewarm, let device else { return }
        didStartPrewarm = true
        commandQueue = device.makeCommandQueue()
        let src = Self.metalSource
        device.makeLibrary(source: src, options: nil) { library, _ in
            guard let library,
                  let vs = library.makeFunction(name: "downsync_vs"),
                  let fs = library.makeFunction(name: "downsync_fs") else { return }
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

private struct MacDownsyncWaveMetalView: NSViewRepresentable {
    let backdropImage: CGImage?
    let uniforms: MacDownsyncUniforms

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let mtk = MTKView()
        mtk.device = MacDownsyncMetalCache.shared.device
        mtk.delegate = context.coordinator
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtk.layer?.isOpaque = false
        mtk.isPaused = true
        mtk.enableSetNeedsDisplay = true
        MacDownsyncMetalCache.shared.prewarm()
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
        var uniforms = MacDownsyncUniforms(resolution: .init(1, 1), progress: 0, intensity: 0, isDarkMode: 1, phaseMode: 1)

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
            guard let pipelineState = MacDownsyncMetalCache.shared.pipelineState,
                  let commandQueue = MacDownsyncMetalCache.shared.commandQueue,
                  let texture = backdropTexture,
                  let passDesc = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let cmd = commandQueue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc) else { return }

            var u = uniforms
            enc.setRenderPipelineState(pipelineState)
            enc.setFragmentTexture(texture, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<MacDownsyncUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}

/// Full-window macOS overlay rendering both Phase 1 (converging rainbow + top distortion + progressive blur)
/// and Phase 2 (expanding soft-white wave with rainbow halo + progressive blur + gradual dim).
struct MacDownsyncWaveOverlay: View {
    @Bindable var waveCoordinator: MacDownsyncWaveCoordinator
    @Bindable var flightCoordinator: MacTaskFlightCoordinator

    var body: some View {
        if let phase = waveCoordinator.activePhase {
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    switch phase {
                    case .converging(_, let startTime, let fadeOutStart, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / MacDownsyncWaveCoordinator.convergeDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.1)
                        let fadeIn = smoothstep(min(max(elapsed / 0.14, 0), 1))
                        let fadeOut: Double = {
                            guard let fStart = fadeOutStart else { return 1.0 }
                            let fe = max(0, timeline.date.timeIntervalSince(fStart))
                            return 1.0 - smoothstep(min(max(fe / MacDownsyncWaveCoordinator.convergeFadeOutDuration, 0), 1))
                        }()
                        let pulse = 0.88 + 0.12 * sin(elapsed * 5.2)
                        let intensity = fadeIn * fadeOut * pulse

                        if intensity > 0.002, let snap {
                            MacDownsyncWaveMetalView(
                                backdropImage: snap,
                                uniforms: MacDownsyncUniforms(
                                    resolution: SIMD2(Float(max(geo.size.width, 1)), Float(max(geo.size.height, 1))),
                                    progress: Float(easedProgress),
                                    intensity: Float(intensity),
                                    isDarkMode: isDarkMode ? 1.0 : 0.0,
                                    phaseMode: 0.0
                                )
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                        }

                    case .expanding(_, let taskIds, let startTime, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / MacDownsyncWaveCoordinator.waveDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.15)

                        let waveIn = smoothstep(min(max(elapsed / 0.10, 0), 1))
                        let waveOut = 1.0 - smoothstep(min(max((elapsed - 0.40) / 0.65, 0), 1))
                        let waveIntensity = waveIn * waveOut

                        let dimIn = smoothstep(min(max(elapsed / 0.18, 0), 1))
                        let dimOut = 1.0 - smoothstep(min(max((elapsed - MacDownsyncWaveCoordinator.dimFadeOutStart) / MacDownsyncWaveCoordinator.dimFadeOutDuration, 0), 1))
                        let maxDim = isDarkMode ? 0.34 : 0.18
                        let dimAlpha = maxDim * dimIn * dimOut

                        let cutoutRects: [CGRect] = taskIds.compactMap { id in
                            guard let rect = flightCoordinator.rowFrames[id], rect.width > 12, rect.height > 8 else {
                                return nil
                            }
                            return rect
                        }

                        ZStack {
                            if dimAlpha > 0.002 {
                                ZStack {
                                    Color.black.opacity(dimAlpha)
                                    ForEach(Array(cutoutRects.enumerated()), id: \.offset) { _, rect in
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black)
                                            .frame(width: rect.width + 18, height: rect.height + 10)
                                            .position(x: rect.midX, y: rect.midY)
                                            .blur(radius: 5)
                                            .blendMode(.destinationOut)
                                    }
                                }
                                .compositingGroup()
                                .allowsHitTesting(false)
                            }

                            if waveIntensity > 0.002, let snap {
                                MacDownsyncWaveMetalView(
                                    backdropImage: snap,
                                    uniforms: MacDownsyncUniforms(
                                        resolution: SIMD2(Float(max(geo.size.width, 1)), Float(max(geo.size.height, 1))),
                                        progress: Float(easedProgress),
                                        intensity: Float(waveIntensity),
                                        isDarkMode: isDarkMode ? 1.0 : 0.0,
                                        phaseMode: 1.0
                                    )
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private func smoothstep(_ t: Double) -> Double {
        t * t * (3.0 - 2.0 * t)
    }
}

/// Very thin single bright shimmer for newly downsynced tasks on macOS (NO scale-up).
struct MacDownsyncTaskShimmerModifier: ViewModifier {
    let isHighlighted: Bool
    let triggerId: UUID
    let isDarkMode: Bool

    @State private var sweepProgress: CGFloat = -0.35
    @State private var shimmerOpacity: Double = 0.0
    @State private var animTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                if shimmerOpacity > 0.005 {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        let bandCenter = sweepProgress * w
                        let hairlineHighlight = LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(isDarkMode ? 0.90 : 0.84), location: 0.46),
                                .init(color: Color(hex: "#C7E9FF").opacity(isDarkMode ? 0.94 : 0.72), location: 0.50),
                                .init(color: .white.opacity(isDarkMode ? 0.90 : 0.84), location: 0.54),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(hairlineHighlight, lineWidth: 1.05)
                                .padding(.horizontal, -6)
                                .padding(.vertical, -2)
                                .mask(
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, .white, .clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(60, w * 0.26))
                                        .position(x: bandCenter, y: geo.size.height * 0.5)
                                )

                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(isDarkMode ? 0.14 : 0.22),
                                            .white.opacity(isDarkMode ? 0.26 : 0.34),
                                            .white.opacity(isDarkMode ? 0.14 : 0.22),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(48, w * 0.18))
                                .position(x: bandCenter, y: geo.size.height * 0.5)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(.horizontal, -6)
                                .padding(.vertical, -2)
                        }
                        .opacity(shimmerOpacity)
                        .allowsHitTesting(false)
                    }
                }
            }
            .onChange(of: triggerId) { _, _ in
                if isHighlighted { playSingleShimmer() }
            }
            .onAppear {
                if isHighlighted { playSingleShimmer() }
            }
    }

    private func playSingleShimmer() {
        animTask?.cancel()
        sweepProgress = -0.25
        shimmerOpacity = 0.0
        animTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                shimmerOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.66)) {
                sweepProgress = 1.25
            }
            try? await Task.sleep(nanoseconds: 480_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.26)) {
                shimmerOpacity = 0.0
            }
        }
    }
}

extension View {
    func macDownsyncTaskShimmer(isHighlighted: Bool, triggerId: UUID, isDarkMode: Bool) -> some View {
        modifier(MacDownsyncTaskShimmerModifier(isHighlighted: isHighlighted, triggerId: triggerId, isDarkMode: isDarkMode))
    }
}

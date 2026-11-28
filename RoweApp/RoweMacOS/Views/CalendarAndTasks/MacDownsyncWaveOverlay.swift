import AppKit
import Metal
import MetalKit
import Observation
import SwiftUI
import RoweCore

enum MacDownsyncWavePhase {
    /// Phase 1: Full-spectrum rainbow converging toward the top edge on manual sync (⌘R)
    case converging(id: UUID, startTime: Date, fadeOutStartTime: Date?, isDarkMode: Bool, backdropCGImage: CGImage?)
    /// Phase 2: Full-spectrum rainbow wave expanding downward when tasks are added/updated/reordered/deleted
    case expanding(id: UUID, taskIds: Set<String>, startTime: Date, isDarkMode: Bool, backdropCGImage: CGImage?)
}

/// Coordinates the 2-phase optical sync animation on macOS (Calendar page only):
/// - Phase 1 (manual sync ⌘R): Full-spectrum rainbow arc converging toward the top edge.
/// - Phase 2 (task downsync): Full-spectrum rainbow wave expanding smoothly with zero ghosting;
///   newly synced tasks fade in cleanly without excess border glow, shimmering, or dim cutouts.
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

    static let convergeDuration: TimeInterval = 0.56
    static let convergeFadeOutDuration: TimeInterval = 0.34
    static let waveDuration: TimeInterval = 0.96
    static let expandTotalDuration: TimeInterval = 1.04

    func shouldHidePendingReveal(_ blockId: String) -> Bool {
        pendingRevealTaskIds.contains(blockId)
    }

    func reset() {
        launchTask?.cancel()
        revealTask?.cancel()
        cleanupTask?.cancel()
        activePhase = nil
        pendingRevealTaskIds = []
        highlightedTaskIds = []
    }

    /// Phase 1: Manual-sync-only (⌘R) converging rainbow wave.
    func beginConverging(isDarkMode: Bool) {
        if case .expanding = activePhase { return }
        cleanupTask?.cancel()
        let now = Date()
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

    /// Phase 2: Expanding rainbow wave when tasks are added, updated, reordered, or deleted.
    func trigger(taskIds: Set<String>, isDarkMode: Bool) {
        launchTask?.cancel()
        revealTask?.cancel()
        cleanupTask?.cancel()

        pendingRevealTaskIds = taskIds
        highlightedTaskIds = []

        launchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 32_000_000)
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
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.easeOut(duration: 0.24)) {
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
        float t = fract(x) * 7.0f;
        float3 c0 = float3(1.00f, 0.24f, 0.32f); // vivid red
        float3 c1 = float3(1.00f, 0.56f, 0.16f); // warm orange
        float3 c2 = float3(1.00f, 0.88f, 0.20f); // sunlit yellow
        float3 c3 = float3(0.22f, 0.90f, 0.46f); // emerald green
        float3 c4 = float3(0.16f, 0.84f, 1.00f); // electric cyan
        float3 c5 = float3(0.30f, 0.46f, 1.00f); // royal blue
        float3 c6 = float3(0.76f, 0.32f, 1.00f); // vivid violet

        if (t < 1.0f) return mix(c0, c1, smoothstep(0.0f, 1.0f, t));
        if (t < 2.0f) return mix(c1, c2, smoothstep(0.0f, 1.0f, t - 1.0f));
        if (t < 3.0f) return mix(c2, c3, smoothstep(0.0f, 1.0f, t - 2.0f));
        if (t < 4.0f) return mix(c3, c4, smoothstep(0.0f, 1.0f, t - 3.0f));
        if (t < 5.0f) return mix(c4, c5, smoothstep(0.0f, 1.0f, t - 4.0f));
        if (t < 6.0f) return mix(c5, c6, smoothstep(0.0f, 1.0f, t - 5.0f));
        return mix(c6, c0, smoothstep(0.0f, 1.0f, t - 6.0f));
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

        float verticalFade = 1.0f - smoothstep(0.40f, 0.84f, uv.y);
        bool isExpanding = (u.phaseMode >= 0.5f);

        float crestRadius;
        float leadWidth;
        float trailWidth;
        if (!isExpanding) {
            crestRadius = mix(0.66f, 0.04f, u.progress);
            leadWidth = mix(0.26f, 0.14f, u.progress);
            trailWidth = mix(0.32f, 0.18f, u.progress);
        } else {
            crestRadius = mix(-0.02f, 0.74f, u.progress);
            leadWidth = mix(0.15f, 0.32f, u.progress);
            trailWidth = mix(0.26f, 0.48f, u.progress);
        }

        float signedDist = radialDist - crestRadius;
        float width = signedDist > 0.0f ? leadWidth : trailWidth;
        float normD = signedDist / max(width, 0.02f);
        float waveBell = exp(-normD * normD);

        // Zero-ghosting envelope: lens displacement & blur settle back to 0 well before alpha fades out
        float warpEnv = smoothstep(0.28f, 0.92f, env);
        float stretchEnv = waveBell * warpEnv * verticalFade;
        float lensScale = isExpanding ? (1.0f - 0.075f * stretchEnv) : (1.0f + 0.065f * stretchEnv);

        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 p = clamp(origin + delta * lensScale, 0.001f, 0.999f);

        float blurWidth = max(width * 1.55f, 0.18f);
        float blurBell = exp(-pow(signedDist / blurWidth, 2.0f));
        float topBlur = exp(-max(uv.y, 0.0f) * 3.0f) * (isExpanding ? exp(-u.progress * 2.8f) : smoothstep(0.12f, 0.88f, u.progress));
        float progBlurAmt = clamp(max(blurBell, topBlur * 0.78f) * warpEnv * verticalFade, 0.0f, 1.0f);
        float2 blurRadiusUV = float2(progBlurAmt * (isExpanding ? 0.0085f : 0.007f) / max(aspect, 0.5f),
                                     progBlurAmt * (isExpanding ? 0.0085f : 0.007f));

        float3 acc = float3(0.0f);
        float wSum = 0.0f;
        const float goldenAngle = 2.39996323f;
        for (int i = 0; i < 16; i++) {
            float fi = float(i) + 0.5f;
            float rNorm = sqrt(fi / 16.0f);
            float theta = fi * goldenAngle;
            float2 off = float2(cos(theta), sin(theta)) * blurRadiusUV * rNorm;
            float w = exp(-1.8f * rNorm * rNorm);
            acc += backdrop.sample(s, clamp(p + off, 0.001f, 0.999f)).rgb * w;
            wSum += w;
        }

        float3 refracted = acc / max(wSum, 1e-4f);

        float horizontalSpectrum = uv.x * 1.20f;
        float radialSpectrum = (signedDist / max(width * 1.7f, 0.12f)) * 0.28f;
        float timeDrift = isExpanding ? (u.progress * 0.38f) : (-u.progress * 0.48f);
        float3 rainbowColor = prismRainbow(horizontalSpectrum + radialSpectrum + timeDrift);

        float3 glowRGB;
        float blendAmt;
        float alpha;
        if (!isExpanding) {
            float topGather = exp(-max(uv.y, 0.0f) * 4.2f) * smoothstep(0.22f, 1.0f, u.progress) * env;
            float rainbowBand = waveBell * env * verticalFade;
            float gain = mix(0.32f, 0.46f, u.isDarkMode);
            glowRGB = rainbowColor * (rainbowBand * gain + topGather * 0.28f)
                    + float3(1.0f, 0.99f, 0.98f) * (topGather * 0.12f);
            blendAmt = clamp(rainbowBand * 1.05f + topGather * 0.85f, 0.0f, 0.84f);
            alpha = clamp(max(max(blurBell * warpEnv, waveBell * env), topGather) * verticalFade, 0.0f, 1.0f);
        } else {
            float coreWidth = mix(0.09f, 0.22f, u.progress);
            float haloWidth = mix(0.20f, 0.40f, u.progress);
            float coreArc = exp(-pow(signedDist / coreWidth, 2.0f)) * env * verticalFade;
            float outerHalo = exp(-pow((signedDist - coreWidth * 0.82f) / (haloWidth * 0.65f), 2.0f)) * env * verticalFade;
            float innerHalo = exp(-pow((signedDist + coreWidth * 0.72f) / (haloWidth * 0.75f), 2.0f)) * env * verticalFade;
            float rainbowHalo = clamp(outerHalo * 0.98f + innerHalo * 0.82f, 0.0f, 1.0f);
            float topLaunch = exp(-u.progress * 4.0f) * exp(-max(uv.y, 0.0f) * 4.5f) * env;

            float coreGain = mix(0.18f, 0.28f, u.isDarkMode);
            float haloGain = mix(0.34f, 0.50f, u.isDarkMode);
            glowRGB = float3(1.0f, 0.99f, 0.98f) * (coreArc * coreGain + topLaunch * 0.16f)
                    + rainbowColor * (rainbowHalo * haloGain + topLaunch * 0.32f);
            blendAmt = clamp(coreArc + rainbowHalo * 1.05f + topLaunch, 0.0f, 0.86f);
            alpha = clamp(max(max(blurBell * warpEnv, max(coreArc, rainbowHalo)), topLaunch) * verticalFade, 0.0f, 1.0f);
        }

        float3 screened = 1.0f - (1.0f - clamp(refracted, 0.0f, 1.0f)) * (1.0f - clamp(glowRGB, 0.0f, 0.72f));
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

/// Calendar-page-only macOS overlay rendering the full-spectrum rainbow sync wave with zero ghosting.
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
                        let pulse = 0.90 + 0.10 * sin(elapsed * 5.0)
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

                    case .expanding(_, _, let startTime, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / MacDownsyncWaveCoordinator.waveDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.15)

                        let waveIn = smoothstep(min(max(elapsed / 0.09, 0), 1))
                        let waveOut = 1.0 - smoothstep(min(max((elapsed - 0.36) / 0.60, 0), 1))
                        let waveIntensity = waveIn * waveOut

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

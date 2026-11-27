import Observation
import SwiftUI
import UIKit
import RoweCore

enum IOSDownsyncWavePhase {
    /// Phase 1: Rainbow + upward distortion converging toward the top edge while reaching backend
    case converging(id: UUID, startTime: Date, fadeOutStartTime: Date?, isDarkMode: Bool, backdropSnapshot: UIImage?)
    /// Phase 2: Luminous soft-white wave with rainbow halo expanding downward to midway when new tasks arrive
    case expanding(id: UUID, taskIds: Set<String>, startTime: Date, isDarkMode: Bool, backdropSnapshot: UIImage?)
}

/// Coordinates the full ~2.0s 2-phase optical sync choreography on iOS:
/// 1. **Phase 1 (~0.56s — Converging Rainbow + Top Stretch)**: Newly synced tasks stay hidden (`opacity 0`)
///    while the rainbow arc + strong upward distortion converges toward the top edge.
/// 2. **Phase 2 (~1.48s — Expanding Soft-White Wave with Rainbow Halo + Reveal + Dim Fade)**:
///    Soft-white wave with rainbow prism halo expands organically from top toward midway and fades out;
///    newly synced tasks smoothly fade in (NO scale-up) with a single thin bright shimmer right as the
///    wave arrives, while the rest of the screen dims softly and fades back cleanly.
@MainActor
@Observable
final class IOSDownsyncWaveCoordinator {
    var activePhase: IOSDownsyncWavePhase? = nil
    var pendingRevealTaskIds: Set<String> = []
    var highlightedTaskIds: Set<String> = []
    var shimmerTriggerId: UUID = UUID()

    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var lastConvergeTriggerAt: Date = .distantPast

    static let convergeDuration: TimeInterval = 0.56
    static let convergeFadeOutDuration: TimeInterval = 0.34
    static let waveDuration: TimeInterval = 1.05
    static let dimFadeOutStart: TimeInterval = 0.88
    static let dimFadeOutDuration: TimeInterval = 0.62
    static let expandTotalDuration: TimeInterval = 1.52

    func shouldHidePendingReveal(_ blockId: String) -> Bool {
        pendingRevealTaskIds.contains(blockId)
    }

    /// Phase 1: Starts the top-converging rainbow + upward distortion when syncing starts.
    func beginConverging(isDarkMode: Bool, sourceView: UIView?) {
        if case .expanding = activePhase { return }
        if !pendingRevealTaskIds.isEmpty { return }
        let now = Date()
        guard now.timeIntervalSince(lastConvergeTriggerAt) > 1.2 else { return }
        lastConvergeTriggerAt = now

        cleanupTask?.cancel()
        let snap = Self.captureSnapshot(from: sourceView)
        let id = UUID()
        activePhase = .converging(
            id: id,
            startTime: now,
            fadeOutStartTime: nil,
            isDarkMode: isDarkMode,
            backdropSnapshot: snap
        )

        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.finishConvergingIfIdle()
        }
    }

    /// Gracefully fades out Phase 1 when sync finishes without new downsynced tasks.
    func finishConvergingIfIdle() {
        // Never cancel Phase 1 if we are actively staging a downsync reveal!
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
            backdropSnapshot: snap
        )
        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.convergeFadeOutDuration + 0.04) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if case .converging(let curId, _, _, _, _) = self.activePhase, curId == id {
                self.activePhase = nil
            }
        }
    }

    /// Full ~2.05s Downsync Reveal:
    /// Immediately hides newly arrived tasks, guarantees the full Phase 1 converging rainbow plays,
    /// then launches Phase 2 expanding white-rainbow wave and smoothly reveals the tasks right as it sweeps in.
    func trigger(
        taskIds: Set<String>,
        isDarkMode: Bool,
        sourceView: UIView?
    ) {
        guard !taskIds.isEmpty else { return }
        launchTask?.cancel()
        revealTask?.cancel()
        cleanupTask?.cancel()

        // Immediately hide newly downsynced tasks so they NEVER pop in before the wave!
        pendingRevealTaskIds = taskIds
        highlightedTaskIds = []

        // Guarantee full Phase 1 converging rainbow (~0.56s) even when backend responded in 40ms
        let remainingConverge: TimeInterval
        if case .converging(_, let startTime, nil, _, _) = activePhase {
            let elapsed = Date().timeIntervalSince(startTime)
            remainingConverge = max(0.05, Self.convergeDuration - elapsed)
        } else {
            let snap = Self.captureSnapshot(from: sourceView)
            activePhase = .converging(
                id: UUID(),
                startTime: Date(),
                fadeOutStartTime: nil,
                isDarkMode: isDarkMode,
                backdropSnapshot: snap
            )
            remainingConverge = Self.convergeDuration
        }

        launchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingConverge * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            let snap = Self.captureSnapshot(from: sourceView)
            let id = UUID()
            self.highlightedTaskIds = taskIds
            self.shimmerTriggerId = id
            self.activePhase = .expanding(
                id: id,
                taskIds: taskIds,
                startTime: Date(),
                isDarkMode: isDarkMode,
                backdropSnapshot: snap
            )
            IOSHaptics.shared.playDownsyncWaveHaptic()

            // Smoothly fade the newly synced tasks into view right as the expanding wave sweeps over them
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

    private static func captureSnapshot(from view: UIView?) -> UIImage? {
        guard let view, view.bounds.width > 10, view.bounds.height > 10 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, 2.0)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }
}

/// Full-screen iOS overlay rendering both Phase 1 (converging rainbow + top distortion) and
/// Phase 2 (expanding soft-white wave with rainbow halo + gradual dim with un-dimmed task cutouts).
struct IOSDownsyncWaveOverlay: View {
    @Bindable var waveCoordinator: IOSDownsyncWaveCoordinator
    @Bindable var flightCoordinator: IOSTaskFlightCoordinator

    var body: some View {
        if let phase = waveCoordinator.activePhase {
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    switch phase {
                    case .converging(_, let startTime, let fadeOutStart, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / IOSDownsyncWaveCoordinator.convergeDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.1)
                        let fadeIn = smoothstep(min(max(elapsed / 0.14, 0), 1))
                        let fadeOut: Double = {
                            guard let fStart = fadeOutStart else { return 1.0 }
                            let fe = max(0, timeline.date.timeIntervalSince(fStart))
                            return 1.0 - smoothstep(min(max(fe / IOSDownsyncWaveCoordinator.convergeFadeOutDuration, 0), 1))
                        }()
                        let pulse = 0.88 + 0.12 * sin(elapsed * 5.2)
                        let intensity = fadeIn * fadeOut * pulse

                        if intensity > 0.002, let snap {
                            Image(uiImage: snap)
                                .resizable()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .compositingGroup()
                                .layerEffect(
                                    ShaderLibrary.downsyncWaveShader(
                                        .float2(geo.size.width, geo.size.height),
                                        .float(easedProgress),
                                        .float(intensity),
                                        .float(isDarkMode ? 1.0 : 0.0),
                                        .float(0.0)
                                    ),
                                    maxSampleOffset: CGSize(width: 120, height: 180)
                                )
                                .opacity(min(1.0, intensity * 1.35))
                                .allowsHitTesting(false)
                        }

                    case .expanding(_, let taskIds, let startTime, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / IOSDownsyncWaveCoordinator.waveDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.15)

                        let waveIn = smoothstep(min(max(elapsed / 0.10, 0), 1))
                        let waveOut = 1.0 - smoothstep(min(max((elapsed - 0.40) / 0.65, 0), 1))
                        let waveIntensity = waveIn * waveOut

                        let dimIn = smoothstep(min(max(elapsed / 0.18, 0), 1))
                        let dimOut = 1.0 - smoothstep(min(max((elapsed - IOSDownsyncWaveCoordinator.dimFadeOutStart) / IOSDownsyncWaveCoordinator.dimFadeOutDuration, 0), 1))
                        let maxDim = isDarkMode ? 0.36 : 0.19
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
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.black)
                                            .frame(width: rect.width - 12, height: rect.height + 6)
                                            .position(x: rect.midX, y: rect.midY)
                                            .blur(radius: 5)
                                            .blendMode(.destinationOut)
                                    }
                                }
                                .compositingGroup()
                                .allowsHitTesting(false)
                            }

                            if waveIntensity > 0.002, let snap {
                                Image(uiImage: snap)
                                    .resizable()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .compositingGroup()
                                    .layerEffect(
                                        ShaderLibrary.downsyncWaveShader(
                                            .float2(geo.size.width, geo.size.height),
                                            .float(easedProgress),
                                            .float(waveIntensity),
                                            .float(isDarkMode ? 1.0 : 0.0),
                                            .float(1.0)
                                        ),
                                        maxSampleOffset: CGSize(width: 120, height: 180)
                                    )
                                    .opacity(min(1.0, waveIntensity * 1.40))
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

/// Very thin single bright shimmer for newly downsynced tasks on iOS (NO scale-up).
struct IOSDownsyncTaskShimmerModifier: ViewModifier {
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
                                .init(color: .white.opacity(isDarkMode ? 0.92 : 0.85), location: 0.46),
                                .init(color: Color(hex: "#C7E9FF").opacity(isDarkMode ? 0.95 : 0.72), location: 0.50),
                                .init(color: .white.opacity(isDarkMode ? 0.92 : 0.85), location: 0.54),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(hairlineHighlight, lineWidth: 1.15)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                                .mask(
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, .white, .clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(58, w * 0.28))
                                        .position(x: bandCenter, y: geo.size.height * 0.5)
                                )

                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(isDarkMode ? 0.16 : 0.24),
                                            .white.opacity(isDarkMode ? 0.28 : 0.36),
                                            .white.opacity(isDarkMode ? 0.16 : 0.24),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(46, w * 0.20))
                                .position(x: bandCenter, y: geo.size.height * 0.5)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
                                .padding(.horizontal, 10)
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
            // Timed right as the tasks fade into view inside the expanding wave (~0.24s into Phase 2)
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
    func iosDownsyncTaskShimmer(isHighlighted: Bool, triggerId: UUID, isDarkMode: Bool) -> some View {
        modifier(IOSDownsyncTaskShimmerModifier(isHighlighted: isHighlighted, triggerId: triggerId, isDarkMode: isDarkMode))
    }
}

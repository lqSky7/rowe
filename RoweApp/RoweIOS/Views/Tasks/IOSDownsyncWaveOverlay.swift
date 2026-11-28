import Observation
import SwiftUI
import UIKit
import RoweCore

enum IOSDownsyncWavePhase {
    /// Phase 1: Full-spectrum rainbow converging toward the top edge on manual sync
    case converging(id: UUID, startTime: Date, fadeOutStartTime: Date?, isDarkMode: Bool, backdropSnapshot: UIImage?)
    /// Phase 2: Full-spectrum rainbow wave expanding downward when tasks are added/updated/reordered/deleted
    case expanding(id: UUID, taskIds: Set<String>, startTime: Date, isDarkMode: Bool, backdropSnapshot: UIImage?)
}

/// Coordinates the 2-phase optical sync choreography on iOS (Calendar page only):
/// - Phase 1 (manual sync): Full-spectrum rainbow arc converging toward the top edge.
/// - Phase 2 (task downsync): Full-spectrum rainbow wave expanding smoothly with zero ghosting;
///   newly synced tasks fade in cleanly without excess border glow, shimmering, or dim cutouts.
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

    /// Phase 1: Manual-sync-only converging rainbow wave.
    func beginConverging(isDarkMode: Bool, sourceView: UIView?) {
        if case .expanding = activePhase { return }
        cleanupTask?.cancel()
        let now = Date()
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

    /// Gracefully fades out Phase 1 when manual sync finishes without task changes.
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

    /// Phase 2: Expanding rainbow wave when tasks are added, updated, reordered, or deleted.
    func trigger(
        taskIds: Set<String>,
        isDarkMode: Bool,
        sourceView: UIView?
    ) {
        launchTask?.cancel()
        revealTask?.cancel()
        cleanupTask?.cancel()

        pendingRevealTaskIds = taskIds
        highlightedTaskIds = []

        launchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 32_000_000)
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

/// Calendar-page-only iOS overlay rendering the full-spectrum rainbow sync wave with zero ghosting.
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
                        let pulse = 0.90 + 0.10 * sin(elapsed * 5.0)
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
                                    maxSampleOffset: CGSize(width: 96, height: 140)
                                )
                                .allowsHitTesting(false)
                        }

                    case .expanding(_, _, let startTime, let isDarkMode, let snap):
                        let elapsed = max(0, timeline.date.timeIntervalSince(startTime))
                        let rawP = min(max(elapsed / IOSDownsyncWaveCoordinator.waveDuration, 0), 1)
                        let easedProgress = 1.0 - pow(1.0 - rawP, 2.15)

                        let waveIn = smoothstep(min(max(elapsed / 0.09, 0), 1))
                        let waveOut = 1.0 - smoothstep(min(max((elapsed - 0.36) / 0.60, 0), 1))
                        let waveIntensity = waveIn * waveOut

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
                                    maxSampleOffset: CGSize(width: 96, height: 140)
                                )
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

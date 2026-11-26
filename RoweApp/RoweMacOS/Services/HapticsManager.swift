import AppKit
import Foundation

/// Centralized Force Touch trackpad haptics engine for Rowe on macOS.
/// Rapid pulse bursts (~18-22ms spacing) fuse on Apple's Taptic Engine into a tactile buzz.
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()
    var isEnabled: Bool = true
    private var activeBuzzTask: Task<Void, Never>?

    private init() {}

    func tap() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func toggle() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func boundarySnap() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func taskComplete() {
        guard isEnabled else { return }
        activeBuzzTask?.cancel()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        activeBuzzTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 34_000_000)
            guard !Task.isCancelled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Buzz-like vibration triggered when double-clicking a task to cross/cancel it.
    func taskCrossOutBuzz() {
        guard isEnabled else { return }
        activeBuzzTask?.cancel()
        activeBuzzTask = Task { @MainActor in
            let pattern: [NSHapticFeedbackManager.FeedbackPattern] = [
                .generic, .levelChange, .generic, .levelChange, .generic
            ]
            for (index, step) in pattern.enumerated() {
                guard !Task.isCancelled else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(step, performanceTime: .now)
                if index + 1 < pattern.count {
                    try? await Task.sleep(nanoseconds: 19_000_000)
                }
            }
        }
    }

    func destructive() {
        guard isEnabled else { return }
        activeBuzzTask?.cancel()
        activeBuzzTask = Task { @MainActor in
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 28_000_000)
            guard !Task.isCancelled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

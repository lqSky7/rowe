import SwiftUI
import RoweCore

/// Craft-style task checkbox supporting zero-latency single-click completion (with accent glow)
/// and instant double-click cross-out (`canceled`) with red glow + trackpad buzz vibration.
struct TaskCheckboxControl: View {
    let state: TaskCompletionState
    let onChange: (TaskCompletionState) -> Void

    @State private var lastClickTimestamp: TimeInterval = 0
    @State private var popScale: CGFloat = 1.0
    @State private var isFlashingRed: Bool = false
    @State private var isFlashingAccent: Bool = false

    var body: some View {
        Button {
            let now = ProcessInfo.processInfo.systemUptime
            let isRapidDoubleClick = (now - lastClickTimestamp) < 0.34
            lastClickTimestamp = now

            triggerPop()

            if isRapidDoubleClick {
                HapticsManager.shared.taskCrossOutBuzz()
                SoundManager.shared.playSubtlePop()
                triggerRedFlash()
                onChange(.canceled)
            } else {
                switch state {
                case .pending:
                    HapticsManager.shared.taskComplete()
                    SoundManager.shared.playComplete()
                    triggerAccentFlash()
                    onChange(.completed)
                case .completed, .canceled:
                    HapticsManager.shared.tap()
                    onChange(.pending)
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(isFlashingRed ? Color.red : fillColor)
                    .frame(width: 16, height: 16)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(glowColor)
                            .frame(width: 24, height: 24)
                            .blur(radius: 3.5)
                            .allowsHitTesting(false)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: state == .pending && !isFlashingRed ? 1.25 : 0)
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: state)
                    .animation(.easeOut(duration: 0.16), value: isFlashingRed)
                    .animation(.easeOut(duration: 0.16), value: isFlashingAccent)

                if state == .completed && !isFlashingRed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                } else if state == .canceled || isFlashingRed {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                }
            }
            .scaleEffect(popScale)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to complete · Double-click to cross out")
    }

    private var glowColor: Color {
        if isFlashingRed { return Color.red.opacity(0.45) }
        if isFlashingAccent { return Color.accentColor.opacity(0.45) }
        if state == .canceled { return Color.red.opacity(0.22) }
        if state == .completed { return Color.accentColor.opacity(0.22) }
        return .clear
    }

    private func triggerPop() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
            popScale = 1.2
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                popScale = 1.0
            }
        }
    }

    private func triggerRedFlash() {
        withAnimation(.easeOut(duration: 0.08)) {
            isFlashingRed = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            withAnimation(.easeInOut(duration: 0.26)) {
                isFlashingRed = false
            }
        }
    }

    private func triggerAccentFlash() {
        withAnimation(.easeOut(duration: 0.08)) {
            isFlashingAccent = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            withAnimation(.easeInOut(duration: 0.26)) {
                isFlashingAccent = false
            }
        }
    }

    private var fillColor: Color {
        switch state {
        case .pending: .clear
        case .completed: Color.accentColor
        case .canceled: Color.red.opacity(0.76)
        }
    }

    private var borderColor: Color {
        Color.primary.opacity(0.32)
    }
}

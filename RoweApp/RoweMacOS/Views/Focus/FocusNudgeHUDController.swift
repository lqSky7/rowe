import AppKit
import SwiftUI
import RoweCore

/// Non-activating Liquid Glass floating HUD for macOS.
/// Never steals keyboard focus or blocks the active application; gently appears in the top-right corner
/// and auto-fades after 9 seconds (pausing while hovered).
@MainActor
public final class FocusNudgeHUDController {
    public static let shared = FocusNudgeHUDController()

    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?
    private var currentSuggestion: FocusSuggestion?
    private weak var currentStore: WorkspaceStore?
    private var isHovered: Bool = false

    private init() {}

    public func show(suggestion: FocusSuggestion, store: WorkspaceStore, isPreview: Bool = false) {
        dismiss(recordIgnored: false)

        self.currentSuggestion = suggestion
        self.currentStore = store
        self.isHovered = false

        let hudView = FocusNudgeHUDView(
            suggestion: suggestion,
            accentColor: Color(hex: store.settings.accentColor.hex),
            isPreview: isPreview,
            onAccept: { [weak self] in
                self?.handleAction(.accepted, isPreview: isPreview)
            },
            onDismiss: { [weak self] in
                self?.handleAction(.dismissed, isPreview: isPreview)
            },
            onMarkWork: { [weak self] in
                self?.handleAction(.markedProductive, isPreview: isPreview)
            },
            onHoverChanged: { [weak self] hovering in
                self?.isHovered = hovering
                if !hovering {
                    self?.scheduleAutoDismiss(isPreview: isPreview)
                } else {
                    self?.autoDismissTask?.cancel()
                }
            }
        )

        let hosting = NSHostingView(rootView: hudView)
        let size = NSSize(width: 364, height: 146)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.maxX - size.width - 18, y: vf.maxY - size.height - 16)
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        scheduleAutoDismiss(isPreview: isPreview)
    }

    private func scheduleAutoDismiss(isPreview: Bool) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled, let self, !self.isHovered else { return }
            self.dismiss(recordIgnored: !isPreview)
        }
    }

    private func handleAction(_ outcome: NudgeOutcome, isPreview: Bool) {
        autoDismissTask?.cancel()
        if let suggestion = currentSuggestion, let store = currentStore {
            if !isPreview {
                store.recordFocusOutcome(outcome, for: suggestion)
            }
            if outcome == .accepted {
                NSApp.activate(ignoringOtherApps: true)
                store.navigate(to: .document(suggestion.task.documentId))
            }
        }
        dismiss(recordIgnored: false)
    }

    public func dismiss(recordIgnored: Bool = false) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        if recordIgnored, let suggestion = currentSuggestion, let store = currentStore {
            store.recordFocusOutcome(.ignored, for: suggestion)
        }
        currentSuggestion = nil

        guard let existing = panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            existing.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                existing.orderOut(nil)
            }
        })
    }
}

private struct FocusNudgeHUDView: View {
    let suggestion: FocusSuggestion
    let accentColor: Color
    let isPreview: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onMarkWork: () -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Calm editorial header row
            HStack(spacing: 8) {
                Image(systemName: suggestion.iconName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.07)))

                Text(suggestion.headline)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            // Proposed quick task
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(suggestion.task.title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                Text("~\(suggestion.estimatedMinutes)m")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? accentColor : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(colorScheme == .dark ? 0.20 : 0.24))
                    )
            }

            // Tactile actions row — zero guilt, zero blocking
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Do this first")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary))
                }
                .buttonStyle(.plain)

                Button(action: onMarkWork) {
                    Text("Work / Study")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Text(isPreview ? "Preview" : "Scroll freely")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 356)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.14), radius: 22, y: 10)
        }
        .scaleEffect(appeared ? 1.0 : 0.96)
        .blur(radius: appeared ? 0 : 4)
        .opacity(appeared ? 1 : 0)
        .onHover { onHoverChanged($0) }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }
}

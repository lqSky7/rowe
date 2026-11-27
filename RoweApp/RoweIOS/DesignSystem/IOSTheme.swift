import CoreHaptics
import SwiftUI
import UIKit
import RoweCore

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (128, 128, 128, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum IOSTheme {
    static func craftSpring(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.80)
    }

    static func microSpring(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .linear(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.78)
    }

    static func font(for style: BlockTextStyle, family: FontFamily, isBold: Bool = false) -> Font {
        let size: CGFloat = {
            switch style {
            case .title: 27
            case .subtitle: 21
            case .heading: 18
            case .strong: 16
            case .body, .pageRegular, .pageCard: 15.5
            case .caption: 13
            }
        }()
        let weight: Font.Weight = {
            if isBold { return .bold }
            switch style {
            case .title: return .bold
            case .subtitle, .heading, .strong: return .semibold
            default: return .regular
            }
        }()

        switch family {
        case .system: return .system(size: size, weight: weight, design: .default)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .baskerville: return .custom(weight == .bold || weight == .semibold ? "Baskerville-SemiBold" : "Baskerville", size: size)
        case .georgia: return .custom(weight == .bold || weight == .semibold ? "Georgia-Bold" : "Georgia", size: size)
        case .avenir: return .custom(weight == .bold || weight == .semibold ? "AvenirNext-DemiBold" : "AvenirNext-Regular", size: size)
        case .palatino: return .custom(weight == .bold || weight == .semibold ? "Palatino-Bold" : "Palatino-Roman", size: size)
        }
    }

    static func uiFont(for style: BlockTextStyle, family: FontFamily, isBold: Bool = false, isItalic: Bool = false) -> UIFont {
        let size: CGFloat = {
            switch style {
            case .title: 27
            case .subtitle: 21
            case .heading: 18
            case .strong: 16
            case .body, .pageRegular, .pageCard: 15.5
            case .caption: 13
            }
        }()
        let weight: UIFont.Weight = {
            if isBold { return .bold }
            switch style {
            case .title: return .bold
            case .subtitle, .heading, .strong: return .semibold
            default: return .regular
            }
        }()

        var font: UIFont = {
            switch family {
            case .system:
                return .systemFont(ofSize: size, weight: weight)
            case .serif:
                let base = UIFont.systemFont(ofSize: size, weight: weight)
                if let desc = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: desc, size: size) }
                return base
            case .mono:
                return .monospacedSystemFont(ofSize: size, weight: weight)
            case .rounded:
                let base = UIFont.systemFont(ofSize: size, weight: weight)
                if let desc = base.fontDescriptor.withDesign(.rounded) { return UIFont(descriptor: desc, size: size) }
                return base
            case .baskerville:
                return UIFont(name: weight == .bold || weight == .semibold ? "Baskerville-SemiBold" : "Baskerville", size: size) ?? .systemFont(ofSize: size, weight: weight)
            case .georgia:
                return UIFont(name: weight == .bold || weight == .semibold ? "Georgia-Bold" : "Georgia", size: size) ?? .systemFont(ofSize: size, weight: weight)
            case .avenir:
                return UIFont(name: weight == .bold || weight == .semibold ? "AvenirNext-DemiBold" : "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size, weight: weight)
            case .palatino:
                return UIFont(name: weight == .bold || weight == .semibold ? "Palatino-Bold" : "Palatino-Roman", size: size) ?? .systemFont(ofSize: size, weight: weight)
            }
        }()

        if isItalic, let italicDesc = font.fontDescriptor.withSymbolicTraits([font.fontDescriptor.symbolicTraits, .traitItalic]) {
            font = UIFont(descriptor: italicDesc, size: size)
        }
        return font
    }
}

struct RowePressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct RoweUnblurModifier: ViewModifier {
    let active: Bool
    let scale: CGFloat
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? scale : 1)
            .blur(radius: active ? blurRadius : 0)
    }
}

extension AnyTransition {
    static var roweUnblur: AnyTransition {
        .modifier(
            active: RoweUnblurModifier(active: true, scale: 0.96, blurRadius: 5),
            identity: RoweUnblurModifier(active: false, scale: 1, blurRadius: 0)
        )
    }

    static var roweConvergeUnblur: AnyTransition {
        .modifier(
            active: RoweUnblurModifier(active: true, scale: 0.94, blurRadius: 10),
            identity: RoweUnblurModifier(active: false, scale: 1, blurRadius: 0)
        )
    }
}

extension Date {
    var craftRelativeString: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let secs = Int(Date().timeIntervalSince(self))
            if secs < 60 { return "Just Now" }
            if secs < 3600 { return "\(secs / 60)m ago" }
            return "\(secs / 3600)h ago"
        }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: self)
    }
}

/// Reliably dismisses the iOS software keyboard from any SwiftUI screen.
@MainActor
enum IOSKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Centralized UIKit + CoreHaptics feedback engine respecting `store.settings.enableHaptics`.
@MainActor
final class IOSHaptics {
    static let shared = IOSHaptics()
    var isEnabled: Bool = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notif = UINotificationFeedbackGenerator()

    private var hapticEngine: CHHapticEngine?
    private var activePlayer: CHHapticPatternPlayer?

    private func ensureEngine() -> CHHapticEngine? {
        guard isEnabled, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if let engine = hapticEngine {
            try? engine.start()
            return engine
        }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.activePlayer = nil
                }
            }
            try engine.start()
            self.hapticEngine = engine
            return engine
        } catch {
            return nil
        }
    }

    private func playPattern(events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let engine = ensureEngine() else { return }
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            activePlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently ignore transient audio/haptic session interruptions
        }
    }

    func stopContinuousHaptics() {
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil
    }

    func tap() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    func toggle() {
        guard isEnabled else { return }
        selectionGen.selectionChanged()
    }

    func snap() {
        guard isEnabled else { return }
        medium.impactOccurred(intensity: 0.85)
    }

    func taskComplete() {
        guard isEnabled else { return }
        notif.notificationOccurred(.success)
    }

    func errorBuzz() {
        guard isEnabled else { return }
        notif.notificationOccurred(.error)
    }

    func destructive() {
        guard isEnabled else { return }
        rigid.impactOccurred(intensity: 0.9)
    }

    /// Custom CoreHaptics choreography for Forward flight (Composer -> Liquid Glass Bubble -> 19x19 Checkbox + 0.5s Shimmer):
    /// 0.00s soft gather -> 0.14s elastic detach -> 0.14-0.66s ultra-dim silky glide hum ->
    /// 0.72s crisp spring-snap into checkbox (+ 0.78s micro-rebound) -> 0.80-1.18s faint glassy shimmer tail.
    func playBubbleSettleHaptic() {
        guard isEnabled else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            snap()
            return
        }
        let events: [CHHapticEvent] = [
            // 1. Composer begins condensing
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.30),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.26)
                ],
                relativeTime: 0.0
            ),
            // 2. Bubble finishes condensing & detaches
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.42),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.36)
                ],
                relativeTime: 0.14
            ),
            // 3. Continuous very-dim silky hum while the bubble glides through the air
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.16)
                ],
                relativeTime: 0.11,
                duration: 0.43
            ),
            // 4. Crisp spring-snap right as the bubble condenses into the 19x19 checkbox
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.78),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.70)
                ],
                relativeTime: 0.56
            ),
            // 5. Subtle spring-settle rebound micro-tick
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.26),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.54)
                ],
                relativeTime: 0.61
            )
        ]
        let curves: [CHHapticParameterCurve] = [
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.11, value: 0.65),
                    .init(relativeTime: 0.30, value: 1.0),
                    .init(relativeTime: 0.53, value: 0.45)
                ],
                relativeTime: 0.0
            )
        ]
        playPattern(events: events, curves: curves)
    }

    /// Custom CoreHaptics choreography for Reverse edit flight (Row -> Checkbox Un-Bubbles & Scoops Text -> Composer):
    /// 0.00s glassy release pop -> 0.05-0.41s ultra-dim glide hum -> 0.46s warm cushioned composer landing.
    func playBubbleOpenForEditHaptic() {
        guard isEnabled else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            tap()
            return
        }
        let events: [CHHapticEvent] = [
            // 1. Checkbox un-bubbles & scoops the task
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.54),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.64)
                ],
                relativeTime: 0.0
            ),
            // 2. Ultra-dim continuous liquid glide as the bubble travels outward
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.20)
                ],
                relativeTime: 0.05,
                duration: 0.36
            ),
            // 3. Soft cushioned open as the bubble flattens into the Task Composer card
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.44),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.24)
                ],
                relativeTime: 0.46
            )
        ]
        let curves: [CHHapticParameterCurve] = [
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.05, value: 0.65),
                    .init(relativeTime: 0.24, value: 1.0),
                    .init(relativeTime: 0.41, value: 0.40)
                ],
                relativeTime: 0.0
            )
        ]
        playPattern(events: events, curves: curves)
    }

    /// Subtle liquid bloom / tuck haptic for the '+' button <-> Task Composer morph.
    func playComposerMorphHaptic(expanding: Bool) {
        guard isEnabled else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            tap()
            return
        }
        let events: [CHHapticEvent] = expanding
            ? [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.13),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22)
                    ],
                    relativeTime: 0.0,
                    duration: 0.18
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.34),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
                    ],
                    relativeTime: 0.18
                )
            ]
            : [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.28),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.38)
                    ],
                    relativeTime: 0.0
                )
            ]
        playPattern(events: events)
    }

    /// Spatial top-to-bottom downsync wave haptic: soft luminous swell tapering smoothly as the wave sweeps down,
    /// followed by a delicate glassy tick as newly synced tasks shimmer into place.
    func playDownsyncWaveHaptic() {
        guard isEnabled else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            snap()
            return
        }
        let events: [CHHapticEvent] = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.36),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.28)
                ],
                relativeTime: 0.0
            ),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.34),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22)
                ],
                relativeTime: 0.02,
                duration: 0.88
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.42),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.62)
                ],
                relativeTime: 0.34
            )
        ]
        let curves: [CHHapticParameterCurve] = [
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.02, value: 0.45),
                    .init(relativeTime: 0.22, value: 1.0),
                    .init(relativeTime: 0.62, value: 0.55),
                    .init(relativeTime: 0.90, value: 0.05)
                ],
                relativeTime: 0.0
            )
        ]
        playPattern(events: events, curves: curves)
    }
}

/// Sweeping strikethrough animation matching macOS Rowe.
struct AnimatedStrikethroughText: View {
    let text: String
    let isStruck: Bool
    let strikeColor: Color
    let font: Font
    let lineLimit: Int?
    let reduceMotion: Bool

    @State private var strikeProgress: Double = 0
    @State private var sweepTask: Task<Void, Never>?

    init(
        _ text: String,
        isStruck: Bool,
        strikeColor: Color = .secondary,
        font: Font = .system(size: 16),
        lineLimit: Int? = 1,
        reduceMotion: Bool = false
    ) {
        self.text = text
        self.isStruck = isStruck
        self.strikeColor = strikeColor
        self.font = font
        self.lineLimit = lineLimit
        self.reduceMotion = reduceMotion
        _strikeProgress = State(initialValue: isStruck ? 1.0 : 0.0)
    }

    private var renderedAttributed: AttributedString {
        var attributed = AttributedString(text)
        let total = text.count
        guard total > 0, strikeProgress > 0 else { return attributed }
        let struckChars = min(total, max(0, Int((Double(total) * strikeProgress).rounded())))
        guard struckChars > 0 else { return attributed }
        let start = attributed.startIndex
        let end = attributed.index(start, offsetByCharacters: struckChars)
        attributed[start..<end].strikethroughStyle = .single
        attributed[start..<end].strikethroughColor = UIColor(strikeColor)
        return attributed
    }

    var body: some View {
        Text(renderedAttributed)
            .font(font)
            .foregroundStyle(isStruck ? .secondary : .primary)
            .opacity(isStruck ? 0.58 : 1.0)
            .lineLimit(lineLimit)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.1) : .easeOut(duration: 0.22),
                value: isStruck
            )
            .onChange(of: isStruck) { _, newValue in
                runSweep(to: newValue ? 1.0 : 0.0)
            }
            .onDisappear {
                sweepTask?.cancel()
            }
    }

    private func runSweep(to target: Double) {
        sweepTask?.cancel()
        if reduceMotion || text.isEmpty {
            strikeProgress = target
            return
        }
        let start = strikeProgress
        let steps = 14
        let stepNs: UInt64 = 15_000_000
        sweepTask = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepNs)
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let eased = 1.0 - pow(1.0 - t, 3.0)
                strikeProgress = start + (target - start) * eased
            }
            strikeProgress = target
        }
    }
}

/// Re-enables UIKit's edge-swipe-back gesture on `NavigationStack` even when `.toolbar(.hidden, for: .navigationBar)` is used.
struct IOSSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackController {
        SwipeBackController()
    }

    func updateUIViewController(_ uiViewController: SwipeBackController, context: Context) {
        uiViewController.enableInteractivePop()
    }

    final class SwipeBackController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableInteractivePop()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableInteractivePop()
        }

        func enableInteractivePop() {
            DispatchQueue.main.async { [weak self] in
                guard let nav = self?.navigationController else { return }
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = nil
            }
        }
    }
}

/// Makes floating iOS sheets/cards dismissable by dragging down without swallowing taps on nested Menu buttons.
struct IOSDragToDismissModifier: ViewModifier {
    var onDismiss: () -> Void
    @State private var dragOffsetY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: max(0, dragOffsetY))
            .opacity(dragOffsetY > 0 ? max(0.35, 1.0 - Double(dragOffsetY) / 260.0) : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 28, coordinateSpace: .local)
                    .onChanged { value in
                        guard value.translation.height > 12,
                              abs(value.translation.height) > abs(value.translation.width) * 1.4 else { return }
                        dragOffsetY = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 85 || value.predictedEndTranslation.height > 165 {
                            IOSHaptics.shared.tap()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                dragOffsetY = 260
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                onDismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                dragOffsetY = 0
                            }
                        }
                    }
            )
    }
}

extension View {
    func iosDragToDismiss(onDismiss: @escaping () -> Void) -> some View {
        modifier(IOSDragToDismissModifier(onDismiss: onDismiss))
    }
}

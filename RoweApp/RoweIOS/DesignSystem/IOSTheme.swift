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

/// Centralized UIKit haptic feedback engine respecting `store.settings.enableHaptics`.
@MainActor
final class IOSHaptics {
    static let shared = IOSHaptics()
    var isEnabled: Bool = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notif = UINotificationFeedbackGenerator()

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
        attributed[start..<end].strikethroughColor = strikeColor
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

/// Makes any custom floating iOS sheet/card dismissable by dragging down anywhere on it.
struct IOSDragToDismissModifier: ViewModifier {
    var onDismiss: () -> Void
    @State private var dragOffsetY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: max(0, dragOffsetY))
            .opacity(dragOffsetY > 0 ? max(0.35, 1.0 - Double(dragOffsetY) / 260.0) : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard value.translation.height > 0,
                              abs(value.translation.height) > abs(value.translation.width) * 1.1 else { return }
                        dragOffsetY = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 75 || value.predictedEndTranslation.height > 145 {
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

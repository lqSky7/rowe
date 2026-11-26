import SwiftUI
import RoweCore

enum CraftTheme {
    // Recovered PageStyles/default.css metrics (Spec 06)
    static let bodyFontSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 3.75
    static let paragraphBottomPadding: CGFloat = 10
    static let titleFontSize: CGFloat = 24
    static let subtitleFontSize: CGFloat = 22
    static let headingFontSize: CGFloat = 20
    static let strongFontSize: CGFloat = 16
    static let captionFontSize: CGFloat = 13

    // Canvas widths (Spec 06 §1)
    static let normalPageWidth: CGFloat = 724
    static let widePageWidth: CGFloat = 1120

    static let lightPageBackground = Color(hex: "#FFFFFF")
    static let darkPageBackground = Color(hex: "#222222")
    static let lightPageText = Color(hex: "#1F2225")
    static let darkPageText = Color(hex: "#F4F4F4")

    // Recovered BounceAnimation: duration 0.3, dampingRatio 0.8
    static func craftSpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.2)
    }

    static func microSpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.78)
    }

    static func hoverEase(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.05) : .easeOut(duration: 0.14)
    }
}

private struct BlurFadeModifier: ViewModifier {
    let blurRadius: CGFloat
    let opacity: Double
    let scale: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
    }
}

extension AnyTransition {
    /// Subtle spring + unblur transition for expanding sidebar groups, disappearing tasks, and floating panels.
    static var roweUnblur: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blurRadius: 6, opacity: 0, scale: 0.97, yOffset: -4),
            identity: BlurFadeModifier(blurRadius: 0, opacity: 1, scale: 1.0, yOffset: 0)
        )
    }

    /// Crisp unblur popover transition anchored from top.
    static var rowePopoverUnblur: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blurRadius: 5, opacity: 0, scale: 0.95, yOffset: -6),
            identity: BlurFadeModifier(blurRadius: 0, opacity: 1, scale: 1.0, yOffset: 0)
        )
    }

    /// Minimal converge + unblur animation for the Cmd+K global search palette.
    static var roweConvergeUnblur: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blurRadius: 8, opacity: 0, scale: 1.045, yOffset: -6),
            identity: BlurFadeModifier(blurRadius: 0, opacity: 1, scale: 1.0, yOffset: 0)
        )
    }
}

/// Subtle tactile spring press feedback for glass buttons & interactive pills.
struct RowePressScaleButtonStyle: ButtonStyle {
    let pressedScale: CGFloat

    init(pressedScale: CGFloat = 0.93) {
        self.pressedScale = pressedScale
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Text with a typographically exact sweeping strikethrough animation across 1 or multiple lines.
struct AnimatedStrikethroughText: View {
    let text: String
    let isStruck: Bool
    let font: Font
    let lineLimit: Int?
    let reduceMotion: Bool

    @State private var strikeProgress: Double = 0
    @State private var sweepTask: Task<Void, Never>?

    init(
        _ text: String,
        isStruck: Bool,
        font: Font = .system(size: 13.5),
        lineLimit: Int? = 1,
        reduceMotion: Bool = false
    ) {
        self.text = text
        self.isStruck = isStruck
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
        return attributed
    }

    var body: some View {
        Text(renderedAttributed)
            .font(font)
            .foregroundStyle(isStruck ? .secondary : .primary)
            .opacity(isStruck ? 0.56 : 1.0)
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
        let stepNs: UInt64 = 15_000_000 // ~210ms total smooth ease-out sweep
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

extension CraftTheme {
    static func font(for style: BlockTextStyle, family: FontFamily, isBold: Bool = false) -> Font {
        let size: CGFloat = switch style {
        case .title: titleFontSize
        case .subtitle: subtitleFontSize
        case .heading: headingFontSize
        case .strong: strongFontSize
        case .body: bodyFontSize
        case .caption: captionFontSize
        case .pageRegular, .pageCard: 15.5
        }
        let weight: Font.Weight = switch style {
        case .title, .subtitle: .bold
        case .heading, .strong, .pageRegular, .pageCard: .semibold
        case .body: isBold ? .semibold : .regular
        case .caption: .light
        }
        switch family {
        case .system: return .system(size: size, weight: weight, design: .default)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .baskerville: return .custom("Baskerville", size: size).weight(weight)
        case .georgia: return .custom("Georgia", size: size).weight(weight)
        case .avenir: return .custom("Avenir Next", size: size).weight(weight)
        case .palatino: return .custom("Palatino", size: size).weight(weight)
        }
    }

    static func nsFont(for style: BlockTextStyle, family: FontFamily, isBold: Bool = false, isItalic: Bool = false, isCode: Bool = false) -> NSFont {
        let size: CGFloat = switch style {
        case .title: titleFontSize
        case .subtitle: subtitleFontSize
        case .heading: headingFontSize
        case .strong: strongFontSize
        case .body: isCode ? 13.5 : bodyFontSize
        case .caption: captionFontSize
        case .pageRegular, .pageCard: 15.5
        }
        let baseWeight: NSFont.Weight = switch style {
        case .title, .subtitle: .bold
        case .heading, .strong, .pageRegular, .pageCard: .semibold
        case .body: isBold ? .bold : .regular
        case .caption: .light
        }
        let effectiveWeight: NSFont.Weight = isBold ? .bold : baseWeight
        let wantsBold = effectiveWeight == .bold || effectiveWeight == .semibold

        let base: NSFont
        if isCode || family == .mono {
            base = NSFont.monospacedSystemFont(ofSize: size, weight: effectiveWeight)
        } else {
            switch family {
            case .system:
                base = NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .serif:
                let desc = NSFont.systemFont(ofSize: size, weight: effectiveWeight).fontDescriptor.withDesign(.serif)
                base = desc.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .rounded:
                let desc = NSFont.systemFont(ofSize: size, weight: effectiveWeight).fontDescriptor.withDesign(.rounded)
                base = desc.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .baskerville:
                base = NSFont(name: wantsBold ? "Baskerville-SemiBold" : "Baskerville", size: size) ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .georgia:
                base = NSFont(name: wantsBold ? "Georgia-Bold" : "Georgia", size: size) ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .avenir:
                base = NSFont(name: wantsBold ? "AvenirNext-DemiBold" : "AvenirNext-Regular", size: size) ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .palatino:
                base = NSFont(name: wantsBold ? "Palatino-Bold" : "Palatino-Roman", size: size) ?? NSFont.systemFont(ofSize: size, weight: effectiveWeight)
            case .mono:
                base = NSFont.monospacedSystemFont(ofSize: size, weight: effectiveWeight)
            }
        }

        if isItalic {
            let italicDesc = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.italic))
            return NSFont(descriptor: italicDesc, size: size) ?? base
        }
        return base
    }
}

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
            (r, g, b, a) = (31, 34, 37, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Date {
    var craftRelativeString: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 { return "Just Now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(seconds / 86400)
        if days < 7 { return days == 1 ? "1 day ago" : "\(days) days ago" }
        let weeks = days / 7
        if weeks < 4 { return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago" }
        let months = max(1, days / 30)
        return months == 1 ? "1 month ago" : "\(months) months ago"
    }
}

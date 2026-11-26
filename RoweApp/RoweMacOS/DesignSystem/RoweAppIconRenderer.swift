import AppKit
import SwiftUI
import RoweCore

enum RoweIconVariant: Int, CaseIterable, Identifiable {
    case light = 0
    case dark = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Smoothed vector geometry of the Rowe ribbon-loop mark (normalized from 1000x750 viewBox).
struct RoweLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 1000.0, rect.height / 750.0)
        let dx = rect.midX - 500.0 * scale
        let dy = rect.midY - 375.0 * scale

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        var path = Path()

        // Primary flowing ribbon curve (smoothed C1 cubic Beziers)
        path.move(to: pt(18, 292))
        path.addCurve(to: pt(62, 278), control1: pt(34, 282), control2: pt(48, 278))
        path.addCurve(to: pt(198, 382), control1: pt(114, 278), control2: pt(134, 382))
        path.addCurve(to: pt(446, 300), control1: pt(268, 382), control2: pt(356, 336))
        path.addCurve(to: pt(690, 232), control1: pt(536, 264), control2: pt(628, 232))
        path.addCurve(to: pt(780, 318), control1: pt(744, 232), control2: pt(780, 268))
        path.addCurve(to: pt(650, 460), control1: pt(780, 376), control2: pt(728, 424))
        path.addCurve(to: pt(286, 558), control1: pt(534, 514), control2: pt(392, 558))
        path.addCurve(to: pt(236, 510), control1: pt(252, 558), control2: pt(236, 538))
        path.addCurve(to: pt(478, 408), control1: pt(236, 456), control2: pt(354, 408))
        path.addCurve(to: pt(882, 490), control1: pt(628, 408), control2: pt(764, 490))
        path.addCurve(to: pt(984, 458), control1: pt(928, 490), control2: pt(960, 472))

        // Inner organic loop
        path.move(to: pt(400, 180))
        path.addCurve(to: pt(600, 342), control1: pt(454, 184), control2: pt(594, 246))
        path.addCurve(to: pt(484, 445), control1: pt(605, 402), control2: pt(548, 442))
        path.addCurve(to: pt(296, 276), control1: pt(414, 448), control2: pt(302, 374))
        path.addCurve(to: pt(400, 180), control1: pt(291, 212), control2: pt(344, 176))
        path.closeSubpath()

        return path
    }
}

struct RoweAppIconPreview: View {
    let variant: RoweIconVariant
    let accentHex: String
    let size: CGFloat

    var body: some View {
        let radius = size * 0.225
        let strokeWidth = max(1.6, size * 0.032)

        ZStack {
            backgroundSurface(radius: radius)

            RoweLogoShape()
                .stroke(
                    strokeStyle,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.11)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(rimColor, lineWidth: max(0.75, size * 0.014))
        )
    }

    @ViewBuilder
    private func backgroundSurface(radius: CGFloat) -> some View {
        switch variant {
        case .light:
            LinearGradient(
                colors: [Color(hex: "#FCFBF8"), Color(hex: "#E8E3D8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [Color(hex: "#282C34"), Color(hex: "#121418")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var strokeStyle: Color {
        switch variant {
        case .light: Color(hex: "#1A1B1E")
        case .dark: Color(hex: "#F2F4F8")
        }
    }

    private var rimColor: Color {
        switch variant {
        case .light: Color.black.opacity(0.09)
        case .dark: Color.white.opacity(0.16)
        }
    }
}

@MainActor
enum RoweAppIconRenderer {
    static func applyDockIcon(variantIndex: Int, accentHex: String) {
        let variant = RoweIconVariant(rawValue: variantIndex) ?? .light
        let view = RoweAppIconPreview(variant: variant, accentHex: accentHex, size: 512)
            .padding(44)
            .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        if let nsImage = renderer.nsImage {
            NSApplication.shared.applicationIconImage = nsImage
        }
    }
}

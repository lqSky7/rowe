import AppKit
import SwiftUI

struct WashiTapePreset: Identifiable, Hashable {
    let id: String
    let name: String

    static let all: [WashiTapePreset] = [
        WashiTapePreset(id: "peachy_peach", name: "Peachy Peach"),
        WashiTapePreset(id: "groovy_water", name: "Groovy Water"),
        WashiTapePreset(id: "childhood_clouds", name: "Childhood"),
        WashiTapePreset(id: "botanical_ink", name: "Botanical Ink"),
        WashiTapePreset(id: "sage_linen", name: "Sage Linen")
    ]
}

/// Torn zigzag edge shape mimicking Craft's washi tape separators.
struct WashiTapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 5
        let toothW: CGFloat = 5.5
        let stepY = rect.height / CGFloat(teeth)

        path.move(to: CGPoint(x: toothW, y: 0))
        path.addLine(to: CGPoint(x: rect.width - toothW, y: 0))

        // Right torn edge
        for i in 0..<teeth {
            let midY = (CGFloat(i) + 0.5) * stepY
            let endY = CGFloat(i + 1) * stepY
            path.addLine(to: CGPoint(x: rect.width, y: midY))
            path.addLine(to: CGPoint(x: rect.width - toothW, y: endY))
        }

        path.addLine(to: CGPoint(x: toothW, y: rect.height))

        // Left torn edge
        for i in (0..<teeth).reversed() {
            let midY = (CGFloat(i) + 0.5) * stepY
            let startY = CGFloat(i) * stepY
            path.addLine(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: toothW, y: startY))
        }
        path.closeSubpath()
        return path
    }
}

/// Renders either a built-in procedural Washi Tape pattern or a user-uploaded custom washi image.
struct WashiTapeSeparatorView: View {
    let patternId: String
    let customImageBase64: String?
    let height: CGFloat

    init(patternId: String = "peachy_peach", customImageBase64: String? = nil, height: CGFloat = 24) {
        self.patternId = patternId
        self.customImageBase64 = customImageBase64
        self.height = height
    }

    var body: some View {
        Group {
            if patternId == "custom",
               let b64 = customImageBase64,
               let data = Data(base64Encoded: b64),
               let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Canvas { ctx, size in
                    drawPattern(patternId, in: &ctx, size: size)
                }
            }
        }
        .frame(height: height)
        .clipShape(WashiTapeShape())
    }

    private func drawPattern(_ id: String, in ctx: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        switch id {
        case "peachy_peach":
            ctx.fill(Path(rect), with: .color(Color(hex: "#F5ECE5")))
            var x: CGFloat = 10
            var idx = 0
            while x < size.width + 20 {
                let y = idx.isMultiple(of: 2) ? size.height * 0.54 : size.height * 0.36
                let r = size.height * 0.34
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y - r, width: r * 2.1, height: r * 1.9)), with: .color(Color(hex: "#F2B69E")))
                ctx.fill(Path(ellipseIn: CGRect(x: x + r * 1.6, y: y - r * 1.1, width: r * 1.0, height: r * 0.5)), with: .color(Color(hex: "#4B6B4D")))
                x += size.height * 1.85
                idx += 1
            }

        case "groovy_water":
            ctx.fill(Path(rect), with: .color(Color(hex: "#2C73D2")))
            var x: CGFloat = -6
            while x < size.width + 16 {
                var wave = Path()
                wave.move(to: CGPoint(x: x, y: 0))
                wave.addCurve(
                    to: CGPoint(x: x + 12, y: size.height),
                    control1: CGPoint(x: x + 16, y: size.height * 0.33),
                    control2: CGPoint(x: x - 4, y: size.height * 0.66)
                )
                ctx.stroke(wave, with: .color(Color(hex: "#F7F3E8")), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                x += 18
            }

        case "childhood_clouds":
            ctx.fill(Path(rect), with: .color(Color(hex: "#C5A8C9")))
            var x: CGFloat = 12
            var idx = 0
            while x < size.width + 16 {
                let y = idx.isMultiple(of: 2) ? size.height * 0.35 : size.height * 0.62
                let w = size.height * 1.05
                let h = size.height * 0.42
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y - h / 2, width: w, height: h), cornerRadius: h / 2), with: .color(Color(hex: "#E6CC53")))
                x += size.height * 1.75
                idx += 1
            }

        case "botanical_ink":
            ctx.fill(Path(rect), with: .color(Color(hex: "#FAF9F6")))
            var x: CGFloat = 14
            while x < size.width + 12 {
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: size.height * 0.88))
                stem.addCurve(
                    to: CGPoint(x: x + 14, y: size.height * 0.14),
                    control1: CGPoint(x: x + 2, y: size.height * 0.45),
                    control2: CGPoint(x: x + 12, y: size.height * 0.55)
                )
                ctx.stroke(stem, with: .color(Color(hex: "#222222").opacity(0.75)), lineWidth: 1.0)
                ctx.fill(Path(ellipseIn: CGRect(x: x + 8, y: size.height * 0.22, width: 6, height: 4.5)), with: .color(Color(hex: "#E03A2D")))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: size.height * 0.52, width: 5.5, height: 4)), with: .color(Color(hex: "#E03A2D")))
                x += 28
            }

        default: // sage_linen
            ctx.fill(Path(rect), with: .color(Color(hex: "#D4DFD5")))
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 8, height: size.height)), with: .color(Color(hex: "#7F9B86").opacity(0.24)))
                x += 16
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height * 0.42, width: size.width, height: 3)), with: .color(Color(hex: "#5D7A65").opacity(0.25)))
        }
    }
}

/// Hand-drawn organic squiggle separator ("Doodle" style from Craft).
struct DoodleSeparatorView: View {
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let midY = size.height / 2
            let step: CGFloat = 14
            path.move(to: CGPoint(x: 2, y: midY))
            var x: CGFloat = 2
            var up = true
            while x + step <= size.width - 2 {
                let nextX = x + step
                let ctrlY = up ? midY - 4.5 : midY + 4.5
                path.addQuadCurve(to: CGPoint(x: nextX, y: midY), control: CGPoint(x: (x + nextX) / 2, y: ctrlY))
                x = nextX
                up.toggle()
            }
            ctx.stroke(path, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 14)
    }
}

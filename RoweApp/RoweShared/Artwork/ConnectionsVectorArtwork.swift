import SwiftUI
import RoweCore

/// Custom-crafted Swiss-editorial vector artwork for the Connections hub (macOS & iOS).
/// Pure vector SwiftUI paths — zero shader glow, crisp at every Retina scale.
public struct ConnectionsHeroArtwork: View {
    public var accentColor: Color
    @Environment(\.colorScheme) private var colorScheme

    public init(accentColor: Color) {
        self.accentColor = accentColor
    }

    private var strokeInk: Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.75)
    }

    private var faintInk: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    public var body: some View {
        let ink = strokeInk
        let faint = faintInk
        let dark = colorScheme == .dark
        let accent = accentColor

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(dark ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
                )

            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let center = CGPoint(x: w * 0.5, y: h * 0.5)

                // Subtle architectural dot grid
                let step: CGFloat = 14
                var x = step * 0.8
                while x < w - 6 {
                    var y = step * 0.8
                    while y < h - 6 {
                        let dot = Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        ctx.fill(dot, with: .color(faint))
                        y += step
                    }
                    x += step
                }

                // Concentric dashed orbit ring
                let orbitR = min(w, h) * 0.34
                let orbitRect = CGRect(x: center.x - orbitR, y: center.y - orbitR, width: orbitR * 2, height: orbitR * 2)
                ctx.stroke(
                    Path(ellipseIn: orbitRect),
                    with: .color(faint.opacity(1.8)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3.5])
                )

                // Three satellite endpoint nodes
                let leftNode = CGPoint(x: w * 0.19, y: h * 0.30)
                let rightNode = CGPoint(x: w * 0.82, y: h * 0.28)
                let bottomNode = CGPoint(x: w * 0.76, y: h * 0.76)

                // Precision bezier data bridges
                func drawBridge(from a: CGPoint, to b: CGPoint, control: CGPoint, highlight: Bool) {
                    var p = Path()
                    p.move(to: a)
                    p.addQuadCurve(to: b, control: control)
                    ctx.stroke(
                        p,
                        with: .color(highlight ? accent.opacity(0.95) : ink.opacity(0.45)),
                        style: StrokeStyle(lineWidth: highlight ? 1.8 : 1.25, lineCap: .round)
                    )
                }

                drawBridge(from: leftNode, to: center, control: CGPoint(x: w * 0.34, y: h * 0.22), highlight: true)
                drawBridge(from: rightNode, to: center, control: CGPoint(x: w * 0.72, y: h * 0.50), highlight: false)
                drawBridge(from: bottomNode, to: center, control: CGPoint(x: w * 0.56, y: h * 0.76), highlight: true)

                // Draw satellite nodes
                for (pt, filled) in [(leftNode, true), (rightNode, false), (bottomNode, true)] {
                    let r: CGFloat = 5.5
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(filled ? accent : (dark ? Color(white: 0.16) : .white)))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3))
                }

                // Central Rowe hub hexagon/square badge
                let hubSize: CGFloat = 24
                let hubRect = CGRect(x: center.x - hubSize / 2, y: center.y - hubSize / 2, width: hubSize, height: hubSize)
                let hubPath = Path(roundedRect: hubRect, cornerRadius: 7)
                ctx.fill(hubPath, with: .color(dark ? Color(white: 0.14) : .white))
                ctx.stroke(hubPath, with: .color(ink), style: StrokeStyle(lineWidth: 1.5))

                // Inner precision diamond inside hub
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - 5.5))
                diamond.addLine(to: CGPoint(x: center.x + 5.5, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + 5.5))
                diamond.addLine(to: CGPoint(x: center.x - 5.5, y: center.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(accent))
            }
        }
    }
}

/// Custom vector icon badge for MCP vs API connections (zero shader effects).
public struct ConnectionKindVectorBadge: View {
    public let kind: ConnectionKind
    public var accentColor: Color
    public var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(kind: ConnectionKind, accentColor: Color, size: CGFloat = 42) {
        self.kind = kind
        self.accentColor = accentColor
        self.size = size
    }

    private var strokeInk: Color {
        colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.80)
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                )

            Canvas { ctx, sz in
                let w = sz.width
                let h = sz.height
                let cx = w * 0.5
                let cy = h * 0.5

                if kind == .mcp {
                    // Bespoke vector MCP protocol chip: central die + 8 pins + accent core
                    let core = CGRect(x: cx - w * 0.20, y: cy - h * 0.20, width: w * 0.40, height: h * 0.40)
                    ctx.stroke(Path(roundedRect: core, cornerRadius: 3.5), with: .color(strokeInk), style: StrokeStyle(lineWidth: 1.5))

                    let inner = core.insetBy(dx: w * 0.08, dy: h * 0.08)
                    ctx.fill(Path(roundedRect: inner, cornerRadius: 1.8), with: .color(accentColor))

                    // Pins on 4 sides
                    let pinLen = w * 0.10
                    let offsets: [CGFloat] = [-w * 0.08, w * 0.08]
                    var pins = Path()
                    for off in offsets {
                        // Top
                        pins.move(to: CGPoint(x: cx + off, y: core.minY))
                        pins.addLine(to: CGPoint(x: cx + off, y: core.minY - pinLen))
                        // Bottom
                        pins.move(to: CGPoint(x: cx + off, y: core.maxY))
                        pins.addLine(to: CGPoint(x: cx + off, y: core.maxY + pinLen))
                        // Left
                        pins.move(to: CGPoint(x: core.minX, y: cy + off))
                        pins.addLine(to: CGPoint(x: core.minX - pinLen, y: cy + off))
                        // Right
                        pins.move(to: CGPoint(x: core.maxX, y: cy + off))
                        pins.addLine(to: CGPoint(x: core.maxX + pinLen, y: cy + off))
                    }
                    ctx.stroke(pins, with: .color(strokeInk.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                } else {
                    // Bespoke vector REST API bridge: two opposing chevrons + accent signal dot
                    var leftBracket = Path()
                    leftBracket.move(to: CGPoint(x: w * 0.36, y: h * 0.30))
                    leftBracket.addLine(to: CGPoint(x: w * 0.21, y: cy))
                    leftBracket.addLine(to: CGPoint(x: w * 0.36, y: h * 0.70))

                    var rightBracket = Path()
                    rightBracket.move(to: CGPoint(x: w * 0.64, y: h * 0.30))
                    rightBracket.addLine(to: CGPoint(x: w * 0.79, y: cy))
                    rightBracket.addLine(to: CGPoint(x: w * 0.64, y: h * 0.70))

                    let style = StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                    ctx.stroke(leftBracket, with: .color(strokeInk), style: style)
                    ctx.stroke(rightBracket, with: .color(strokeInk), style: style)

                    // Diagonal slash / signal line
                    var slash = Path()
                    slash.move(to: CGPoint(x: w * 0.45, y: h * 0.66))
                    slash.addLine(to: CGPoint(x: w * 0.55, y: h * 0.34))
                    ctx.stroke(slash, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

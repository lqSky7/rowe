import AppKit
import SwiftUI
import RoweCore

/// In-memory cache for bundled JPEG wallpapers so cards & editors scroll at 60fps without re-decoding.
@MainActor
private enum RoweWallpaperCache {
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 24
        return c
    }()

    static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Wallpapers"),
              let img = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

/// Resolution-independent Craft-style editorial cover & backdrop artworks + bundled photography wallpapers.
/// Supports document backdrops, Style Gallery cards, and AllDocs Gallery/Grid cover banners.
struct CraftCoverArtwork: View {
    let artworkName: String

    var body: some View {
        if let wallpaper = RoweWallpaperCache.image(named: artworkName) {
            GeometryReader { geo in
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            switch artworkName {
            case "ivory_folds":
                ivoryFoldsCanvas
            case "sage_wash":
                sageWashCanvas
            case "obsidian_silk":
                obsidianSilkCanvas
            case "terracotta_arch":
                terracottaArchCanvas
            case "nordic_mist":
                nordicMistCanvas
            default:
                ivoryFoldsCanvas
            }
        }
    }

    // 1. Warm Ivory & Champagne Sculpted Paper Folds
    private var ivoryFoldsCanvas: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#FBF8F1"), Color(hex: "#EDE3D2"), Color(hex: "#DFCEB4")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            // Sweeping sculpted paper ribbon 1
            var wave1 = Path()
            wave1.move(to: CGPoint(x: -size.width * 0.05, y: size.height * 0.42))
            wave1.addCurve(
                to: CGPoint(x: size.width * 1.05, y: size.height * 0.25),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.85),
                control2: CGPoint(x: size.width * 0.65, y: -size.height * 0.08)
            )
            wave1.addLine(to: CGPoint(x: size.width * 1.05, y: size.height * 1.1))
            wave1.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height * 1.1))
            wave1.closeSubpath()
            ctx.fill(
                wave1,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#F6EFE2").opacity(0.95), Color(hex: "#D9C3A3").opacity(0.85)]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.2),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            // Upper curved fold shadow + highlight
            var wave2 = Path()
            wave2.move(to: CGPoint(x: size.width * 0.12, y: 0))
            wave2.addCurve(
                to: CGPoint(x: size.width * 0.78, y: 0),
                control1: CGPoint(x: size.width * 0.34, y: size.height * 0.72),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.62)
            )
            wave2.closeSubpath()
            ctx.fill(
                wave2,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#FFFDF9"), Color(hex: "#E8DAC3").opacity(0.9)]),
                    startPoint: CGPoint(x: size.width * 0.2, y: 0),
                    endPoint: CGPoint(x: size.width * 0.6, y: size.height * 0.6)
                )
            )

            var foldLine = Path()
            foldLine.move(to: CGPoint(x: 0, y: size.height * 0.68))
            foldLine.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.56),
                control1: CGPoint(x: size.width * 0.32, y: size.height * 0.35),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.92)
            )
            ctx.stroke(foldLine, with: .color(Color(hex: "#9B8260").opacity(0.22)), lineWidth: 1.5)
        }
    }

    // 2. Muted Sage & Eucalyptus Watercolor Wash
    private var sageWashCanvas: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#F6F7F2"), Color(hex: "#EAEFE7")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            let blobs: [(CGPoint, CGSize, Color)] = [
                (CGPoint(x: size.width * 0.25, y: size.height * 0.52), CGSize(width: size.width * 0.78, height: size.height * 0.76), Color(hex: "#7C9B8A").opacity(0.28)),
                (CGPoint(x: size.width * 0.72, y: size.height * 0.62), CGSize(width: size.width * 0.68, height: size.height * 0.72), Color(hex: "#5F7E6F").opacity(0.26)),
                (CGPoint(x: size.width * 0.48, y: size.height * 0.35), CGSize(width: size.width * 0.62, height: size.height * 0.54), Color(hex: "#A5BEB0").opacity(0.25))
            ]
            for (center, dims, color) in blobs {
                let ellipseRect = CGRect(
                    x: center.x - dims.width / 2,
                    y: center.y - dims.height / 2,
                    width: dims.width,
                    height: dims.height
                )
                ctx.fill(Path(ellipseIn: ellipseRect), with: .color(color))
            }
        }
    }

    // 3. Deep Obsidian, Slate Indigo & Silver Mist Silk Waves
    private var obsidianSilkCanvas: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#121318"), Color(hex: "#1B1E28"), Color(hex: "#101116")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            var silk = Path()
            silk.move(to: CGPoint(x: -size.width * 0.1, y: size.height * 0.72))
            silk.addCurve(
                to: CGPoint(x: size.width * 1.1, y: size.height * 0.12),
                control1: CGPoint(x: size.width * 0.36, y: size.height * 0.85),
                control2: CGPoint(x: size.width * 0.64, y: size.height * 0.05)
            )
            silk.addLine(to: CGPoint(x: size.width * 1.1, y: size.height * 0.48))
            silk.addCurve(
                to: CGPoint(x: -size.width * 0.1, y: size.height * 0.96),
                control1: CGPoint(x: size.width * 0.68, y: size.height * 0.45),
                control2: CGPoint(x: size.width * 0.32, y: size.height * 1.05)
            )
            silk.closeSubpath()

            ctx.fill(
                silk,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hex: "#2D3548").opacity(0.65),
                        Color(hex: "#8F9BB3").opacity(0.55),
                        Color(hex: "#394156").opacity(0.5)
                    ]),
                    startPoint: CGPoint(x: 0, y: size.height),
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            )

            var sheen = Path()
            sheen.move(to: CGPoint(x: 0, y: size.height * 0.78))
            sheen.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.22),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.78),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.26)
            )
            ctx.stroke(sheen, with: .color(Color.white.opacity(0.28)), lineWidth: 2.0)
        }
    }

    // 4. Terracotta Clay & Warm Linen Architectural Geometry
    private var terracottaArchCanvas: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#F4E9DD"), Color(hex: "#E8D4C1")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            // Warm terracotta left block
            ctx.fill(
                Path(CGRect(x: 0, y: 0, width: size.width * 0.42, height: size.height * 0.56)),
                with: .color(Color(hex: "#B5623E").opacity(0.82))
            )

            // Cream architectural arch
            let archRect = CGRect(
                x: size.width * 0.11,
                y: size.height * 0.12,
                width: size.width * 0.32,
                height: size.height * 0.96
            )
            ctx.fill(
                Path(roundedRect: archRect, cornerRadius: archRect.width / 2),
                with: .color(Color(hex: "#FAF6F0"))
            )

            // Peach vertical strip
            ctx.fill(
                Path(CGRect(x: size.width * 0.50, y: 0, width: size.width * 0.18, height: size.height)),
                with: .color(Color(hex: "#E5B79B").opacity(0.72))
            )

            // Accent clay circle
            let circleD = min(size.width, size.height) * 0.26
            ctx.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.61, y: size.height * 0.62, width: circleD, height: circleD)),
                with: .color(Color(hex: "#B8603C").opacity(0.88))
            )
        }
    }

    // 5. Cool Nordic Coastal Mist
    private var nordicMistCanvas: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#DCE8F2"), Color(hex: "#B8CFE0"), Color(hex: "#EDF3F7")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            let horizon = CGRect(x: -size.width * 0.1, y: size.height * 0.52, width: size.width * 1.2, height: size.height * 0.65)
            ctx.fill(
                Path(ellipseIn: horizon),
                with: .color(Color(hex: "#6D8DA6").opacity(0.24))
            )
        }
    }
}

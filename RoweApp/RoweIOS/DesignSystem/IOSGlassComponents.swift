import SwiftUI
import UIKit
import RoweCore

/// Applies native iOS 26 Liquid Glass when available, falling back cleanly to frosted material on iOS 18.
struct IOSLiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        }
    }
}

extension View {
    func roweIOSGlass<S: InsettableShape>(in shape: S, interactive: Bool = true) -> some View {
        modifier(IOSLiquidGlassModifier(shape: shape, interactive: interactive))
    }

    func roweIOSGlassCapsule(interactive: Bool = true) -> some View {
        roweIOSGlass(in: Capsule(), interactive: interactive)
    }

    func roweIOSGlassRoundedRect(radius: CGFloat = 16, interactive: Bool = true) -> some View {
        roweIOSGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }
}

struct IOSGlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 16
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(RowePressScaleStyle())
        .roweIOSGlass(in: Circle(), interactive: true)
    }
}

struct IOSGlassPillButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(RowePressScaleStyle())
        .roweIOSGlassCapsule(interactive: true)
    }
}

/// Space avatar supporting custom base64 photo or clean initials badge.
struct IOSSpaceAvatar: View {
    let space: Space
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let b64 = space.avatarImageBase64,
               let data = Data(base64Encoded: b64),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "#2D323E"), Color(hex: "#191C24")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(space.name.prefix(2)).uppercased())
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        )
    }
}

/// In-memory cache for bundled JPEG wallpapers so iOS carousels and grids scroll at 120fps ProMotion.
@MainActor
private enum IOSWallpaperCache {
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 20
        return c
    }()

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Wallpapers")
                ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

struct IOSCoverArtwork: View {
    let artworkName: String

    var body: some View {
        if let wallpaper = IOSWallpaperCache.image(named: artworkName) {
            GeometryReader { geo in
                Image(uiImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            LinearGradient(
                colors: fallbackColors(for: artworkName),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func fallbackColors(for name: String) -> [Color] {
        switch name {
        case "sage_wash": [Color(hex: "#EEF3EC"), Color(hex: "#B8CFC0")]
        case "obsidian_silk": [Color(hex: "#121318"), Color(hex: "#2B3245")]
        case "terracotta_arch": [Color(hex: "#F4E9DD"), Color(hex: "#C97A53")]
        case "nordic_mist": [Color(hex: "#DCE8F2"), Color(hex: "#9BB8CE")]
        default: [Color(hex: "#FBF8F1"), Color(hex: "#DFCEB4")]
        }
    }
}

/// Torn-edge Washi Tape & Ink-Aware Doodle Separators (zero contrast bugs on light cards in Dark Mode).
struct IOSWashiTapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 5
        let toothW: CGFloat = 5
        let stepY = rect.height / CGFloat(teeth)
        path.move(to: CGPoint(x: toothW, y: 0))
        path.addLine(to: CGPoint(x: rect.width - toothW, y: 0))
        for i in 0..<teeth {
            path.addLine(to: CGPoint(x: rect.width, y: (CGFloat(i) + 0.5) * stepY))
            path.addLine(to: CGPoint(x: rect.width - toothW, y: CGFloat(i + 1) * stepY))
        }
        path.addLine(to: CGPoint(x: toothW, y: rect.height))
        for i in (0..<teeth).reversed() {
            path.addLine(to: CGPoint(x: 0, y: (CGFloat(i) + 0.5) * stepY))
            path.addLine(to: CGPoint(x: toothW, y: CGFloat(i) * stepY))
        }
        path.closeSubpath()
        return path
    }
}

struct IOSWashiSeparatorView: View {
    let patternId: String
    let height: CGFloat

    init(patternId: String = "peachy_peach", height: CGFloat = 22) {
        self.patternId = patternId
        self.height = height
    }

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            switch patternId {
            case "groovy_water":
                ctx.fill(Path(rect), with: .color(Color(hex: "#2C73D2")))
                var x: CGFloat = -6
                while x < size.width + 16 {
                    var w = Path()
                    w.move(to: CGPoint(x: x, y: 0))
                    w.addCurve(to: CGPoint(x: x + 12, y: size.height),
                               control1: CGPoint(x: x + 16, y: size.height * 0.33),
                               control2: CGPoint(x: x - 4, y: size.height * 0.66))
                    ctx.stroke(w, with: .color(Color(hex: "#F7F3E8")), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    x += 18
                }
            case "childhood_clouds":
                ctx.fill(Path(rect), with: .color(Color(hex: "#C5A8C9")))
                var x: CGFloat = 10
                while x < size.width + 16 {
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: size.height * 0.28, width: 22, height: 9), cornerRadius: 4.5), with: .color(Color(hex: "#E6CC53")))
                    x += 34
                }
            case "botanical_ink":
                ctx.fill(Path(rect), with: .color(Color(hex: "#FAF9F6")))
                var x: CGFloat = 12
                while x < size.width + 12 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x + 6, y: size.height * 0.22, width: 6, height: 4.5)), with: .color(Color(hex: "#E03A2D")))
                    x += 26
                }
            case "sage_linen":
                ctx.fill(Path(rect), with: .color(Color(hex: "#D4DFD5")))
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.42, width: size.width, height: 3)), with: .color(Color(hex: "#5D7A65").opacity(0.28)))
            default: // peachy_peach
                ctx.fill(Path(rect), with: .color(Color(hex: "#F5ECE5")))
                var x: CGFloat = 10
                while x < size.width + 16 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: size.height * 0.22, width: 14, height: 12)), with: .color(Color(hex: "#F2B69E")))
                    x += 32
                }
            }
        }
        .frame(height: height)
        .clipShape(IOSWashiTapeShape())
    }
}

struct IOSDoodleSeparatorView: View {
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

/// Replaces SwiftUI's native spinning `.refreshable` loader with a clean magnifying-glass
/// pull-down indicator that triggers Global Search prematurely (~48pt overscroll) without ever spinning.
struct IOSPullDownToSearchModifier: ViewModifier {
    @Binding var isPresented: Bool
    let reduceMotion: Bool

    @State private var pullDistance: CGFloat = 0
    @State private var hasTriggered = false

    private let triggerThreshold: CGFloat = 48

    func body(content: Content) -> some View {
        let progress = min(1.0, max(0.0, pullDistance / triggerThreshold))
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, adjustedOffset in
                let pulled = max(0, -adjustedOffset)
                pullDistance = pulled
                if pulled >= triggerThreshold && !hasTriggered && !isPresented {
                    hasTriggered = true
                    IOSHaptics.shared.snap()
                    IOSKeyboard.dismiss()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                        isPresented = true
                    }
                } else if pulled < 8 && hasTriggered {
                    hasTriggered = false
                }
            }
            .overlay(alignment: .top) {
                if progress > 0.12 && !isPresented {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(progress >= 0.85 ? Color.accentColor : .primary)
                        if progress > 0.55 {
                            Text("Search")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, progress > 0.55 ? 14 : 10)
                    .frame(height: 34)
                    .roweIOSGlassCapsule(interactive: false)
                    .scaleEffect(0.68 + 0.32 * progress)
                    .opacity(Double(min(1.0, progress * 1.4)))
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.85), value: progress > 0.55)
                }
            }
    }
}

extension View {
    func iosPullDownToSearch(isPresented: Binding<Bool>, reduceMotion: Bool = false) -> some View {
        modifier(IOSPullDownToSearchModifier(isPresented: isPresented, reduceMotion: reduceMotion))
    }
}

import SwiftUI

// MARK: - Bespoke GlassGlow Vector Shapes (Shared between Onboarding & Settings)

/// Layered editorial document cards with a floating star accent — represents "Documents That Feel Alive".
public struct RoweDocumentsMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100.0
        let ox = rect.midX - 50.0 * s
        let oy = rect.midY - 50.0 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Back tilted card outline
        p.addRoundedRect(
            in: CGRect(x: ox + 26 * s, y: oy + 12 * s, width: 52 * s, height: 64 * s),
            cornerSize: CGSize(width: 10 * s, height: 10 * s)
        )
        // Front primary page card
        p.addRoundedRect(
            in: CGRect(x: ox + 16 * s, y: oy + 22 * s, width: 54 * s, height: 66 * s),
            cornerSize: CGSize(width: 11 * s, height: 11 * s)
        )
        // Editorial headline & ruled lines inside front card
        p.move(to: pt(26, 40))
        p.addLine(to: pt(52, 40))
        p.move(to: pt(26, 52))
        p.addLine(to: pt(58, 52))
        p.move(to: pt(26, 63))
        p.addLine(to: pt(48, 63))
        // Four-point editorial sparkle at top-right
        p.move(to: pt(80, 14))
        p.addQuadCurve(to: pt(90, 24), control: pt(81, 23))
        p.addQuadCurve(to: pt(80, 34), control: pt(81, 25))
        p.addQuadCurve(to: pt(70, 24), control: pt(79, 25))
        p.addQuadCurve(to: pt(80, 14), control: pt(79, 23))
        p.closeSubpath()
        return p
    }
}

/// Zero-knowledge cryptographic shield with clean keyhole — represents "Zero-Knowledge Locked Notes".
public struct RoweVaultLockMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100.0
        let ox = rect.midX - 50.0 * s
        let oy = rect.midY - 50.0 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Sculpted shield silhouette
        p.move(to: pt(50, 10))
        p.addCurve(to: pt(84, 24), control1: pt(64, 10), control2: pt(76, 18))
        p.addLine(to: pt(84, 48))
        p.addCurve(to: pt(50, 90), control1: pt(84, 70), control2: pt(68, 84))
        p.addCurve(to: pt(16, 48), control1: pt(32, 84), control2: pt(16, 70))
        p.addLine(to: pt(16, 24))
        p.addCurve(to: pt(50, 10), control1: pt(24, 18), control2: pt(36, 10))
        p.closeSubpath()

        // Inner padlock shackle & keyhole
        p.addArc(
            center: pt(50, 44),
            radius: 10 * s,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addRoundedRect(
            in: CGRect(x: ox + 36 * s, y: oy + 44 * s, width: 28 * s, height: 22 * s),
            cornerSize: CGSize(width: 6 * s, height: 6 * s)
        )
        p.addEllipse(in: CGRect(x: ox + 46.5 * s, y: oy + 50.5 * s, width: 7 * s, height: 7 * s))
        p.move(to: pt(50, 57.5))
        p.addLine(to: pt(50, 62))
        return p
    }
}

/// Concentric calm focus radar rings + rhythmic pulse arc — represents "Permissions & Adaptive Focus".
public struct RoweFocusPermissionsMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100.0
        let ox = rect.midX - 50.0 * s
        let oy = rect.midY - 50.0 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Outer open circadian halo
        p.addArc(
            center: pt(50, 50),
            radius: 38 * s,
            startAngle: .degrees(-65),
            endAngle: .degrees(215),
            clockwise: false
        )
        // Secondary calm rhythm arc
        p.move(to: pt(50 + 26 * cos(-20 * .pi / 180), 50 + 26 * sin(-20 * .pi / 180)))
        p.addArc(
            center: pt(50, 50),
            radius: 26 * s,
            startAngle: .degrees(-20),
            endAngle: .degrees(260),
            clockwise: false
        )
        // Inner focus core ring
        p.addEllipse(in: CGRect(x: ox + 39 * s, y: oy + 39 * s, width: 22 * s, height: 22 * s))
        // Subtle chime/beacon dot on outer orbit
        p.addEllipse(in: CGRect(x: ox + 66 * s, y: oy + 14 * s, width: 10 * s, height: 10 * s))
        // Gentle checkmark inside core
        p.move(to: pt(45, 50.5))
        p.addLine(to: pt(49, 54.5))
        p.addLine(to: pt(56, 46.5))
        return p
    }
}

/// Twin orbiting sync arcs around a central node — represents "Your Space, Everywhere" & Account Sync.
public struct RoweSyncOrbitMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100.0
        let ox = rect.midX - 50.0 * s
        let oy = rect.midY - 50.0 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Upper sweeping sync arc
        p.addArc(
            center: pt(50, 50),
            radius: 34 * s,
            startAngle: .degrees(195),
            endAngle: .degrees(345),
            clockwise: false
        )
        // Arrowhead on upper arc
        p.move(to: pt(77, 36))
        p.addLine(to: pt(84, 42))
        p.addLine(to: pt(88, 33))

        // Lower sweeping sync arc
        p.move(to: pt(50 + 34 * cos(15 * .pi / 180), 50 + 34 * sin(15 * .pi / 180)))
        p.addArc(
            center: pt(50, 50),
            radius: 34 * s,
            startAngle: .degrees(15),
            endAngle: .degrees(165),
            clockwise: false
        )
        // Arrowhead on lower arc
        p.move(to: pt(23, 64))
        p.addLine(to: pt(16, 58))
        p.addLine(to: pt(12, 67))

        // Paired device nodes inside
        p.addRoundedRect(
            in: CGRect(x: ox + 30 * s, y: oy + 40 * s, width: 22 * s, height: 16 * s),
            cornerSize: CGSize(width: 4 * s, height: 4 * s)
        )
        p.addRoundedRect(
            in: CGRect(x: ox + 57 * s, y: oy + 37 * s, width: 13 * s, height: 22 * s),
            cornerSize: CGSize(width: 3.5 * s, height: 3.5 * s)
        )
        return p
    }
}

// MARK: - Unified GlassGlow Artwork Component (Onboarding & Settings)

public enum RoweArtworkKind: Hashable, Sendable {
    case welcome
    case documents
    case vaultLock
    case focusPermissions
    case syncOrbit

    @MainActor
    public var palette: GlassGlowPalette {
        switch self {
        case .welcome:
            return RoweOnboardingView.monochromePalette
        case .documents:
            return RoweOnboardingView.paleGreyPeachPalette
        case .vaultLock:
            return RoweOnboardingView.paleGreySkyBluePalette
        case .focusPermissions:
            return GlassGlowPalette(
                Color(red: 0.78, green: 0.84, blue: 0.96),
                Color(red: 0.80, green: 0.90, blue: 0.86),
                Color(red: 0.86, green: 0.80, blue: 0.94)
            )
        case .syncOrbit:
            return RoweOnboardingView.paleSageMistPalette
        }
    }
}

/// Renders any bespoke Rowe onboarding artwork through the GlassGlow Metal shader,
/// scalable from large onboarding hero illustrations to compact Settings section headers.
public struct RoweGlassGlowArtworkView: View {
    public let kind: RoweArtworkKind
    public var size: CGFloat
    public var speed: Double
    public var glow: Double

    public init(
        kind: RoweArtworkKind,
        size: CGFloat = 128,
        speed: Double = 0.72,
        glow: Double = 1.15
    ) {
        self.kind = kind
        self.size = size
        self.speed = speed
        self.glow = glow
    }

    private var strokeWidth: CGFloat {
        max(2.6, size * 0.042)
    }

    public var body: some View {
        Group {
            switch kind {
            case .welcome:
                RoweRibbonMark()
                    .stroke(style: StrokeStyle(lineWidth: max(3.5, size * 0.075), lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: size * 1.18, height: size * 0.90)
                    .glassGlow(kind.palette, speed: speed, glow: glow)
            case .documents:
                RoweDocumentsMark()
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassGlow(kind.palette, speed: speed, glow: glow)
            case .vaultLock:
                RoweVaultLockMark()
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassGlow(kind.palette, speed: speed, glow: glow)
            case .focusPermissions:
                RoweFocusPermissionsMark()
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassGlow(kind.palette, speed: speed, glow: glow)
            case .syncOrbit:
                RoweSyncOrbitMark()
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassGlow(kind.palette, speed: speed, glow: glow)
            }
        }
    }
}

// MARK: - Curated Work & Study Allowlist Presets (Visual Selector)

public struct RoweAllowlistPreset: Identifiable, Hashable, Sendable {
    public var id: String { domain }
    public let name: String
    public let domain: String
    public let icon: String
    public let category: String

    public init(name: String, domain: String, icon: String, category: String) {
        self.name = name
        self.domain = domain
        self.icon = icon
        self.category = category
    }

    public static let all: [RoweAllowlistPreset] = [
        // Engineering & Docs
        RoweAllowlistPreset(name: "GitHub", domain: "github.com", icon: "chevron.left.forwardslash.chevron.right", category: "Engineering"),
        RoweAllowlistPreset(name: "Stack Overflow", domain: "stackoverflow.com", icon: "square.stack.3d.up", category: "Engineering"),
        RoweAllowlistPreset(name: "Swift Docs", domain: "docs.swift.org", icon: "swift", category: "Engineering"),
        RoweAllowlistPreset(name: "Apple Developer", domain: "developer.apple.com", icon: "hammer", category: "Engineering"),
        RoweAllowlistPreset(name: "MDN Web Docs", domain: "developer.mozilla.org", icon: "globe", category: "Engineering"),
        RoweAllowlistPreset(name: "LeetCode", domain: "leetcode.com", icon: "terminal", category: "Engineering"),

        // Study & Research
        RoweAllowlistPreset(name: "arXiv", domain: "arxiv.org", icon: "doc.text.magnifyingglass", category: "Study & Research"),
        RoweAllowlistPreset(name: "Google Scholar", domain: "scholar.google.com", icon: "graduationcap", category: "Study & Research"),
        RoweAllowlistPreset(name: "Overleaf", domain: "overleaf.com", icon: "doc.richtext", category: "Study & Research"),
        RoweAllowlistPreset(name: "Wikipedia", domain: "wikipedia.org", icon: "book.closed", category: "Study & Research"),
        RoweAllowlistPreset(name: "Coursera", domain: "coursera.org", icon: "play.square.stack", category: "Study & Research"),
        RoweAllowlistPreset(name: "Khan Academy", domain: "khanacademy.org", icon: "lightbulb", category: "Study & Research"),

        // Workspace & AI
        RoweAllowlistPreset(name: "Google Docs", domain: "docs.google.com", icon: "doc.text", category: "Workspace & AI"),
        RoweAllowlistPreset(name: "Notion", domain: "notion.so", icon: "square.grid.2x2", category: "Workspace & AI"),
        RoweAllowlistPreset(name: "Figma", domain: "figma.com", icon: "paintbrush", category: "Workspace & AI"),
        RoweAllowlistPreset(name: "Linear", domain: "linear.app", icon: "checklist", category: "Workspace & AI"),
        RoweAllowlistPreset(name: "ChatGPT", domain: "chatgpt.com", icon: "sparkles", category: "Workspace & AI"),
        RoweAllowlistPreset(name: "Claude", domain: "claude.ai", icon: "brain.head.profile", category: "Workspace & AI"),

        // Video (if user wants to always allowlist)
        RoweAllowlistPreset(name: "YouTube (Always Allow)", domain: "youtube.com", icon: "play.rectangle", category: "Media Exceptions"),

        // Popular iOS & Mac Apps
        RoweAllowlistPreset(name: "Discord", domain: "discord", icon: "bubble.left.and.bubble.right", category: "Apps"),
        RoweAllowlistPreset(name: "Slack", domain: "slack", icon: "number", category: "Apps"),
        RoweAllowlistPreset(name: "GoodNotes", domain: "goodnotes", icon: "pencil.and.outline", category: "Apps"),
        RoweAllowlistPreset(name: "Obsidian", domain: "obsidian", icon: "diamond", category: "Apps"),
        RoweAllowlistPreset(name: "Xcode", domain: "xcode", icon: "hammer.fill", category: "Apps"),
        RoweAllowlistPreset(name: "Cursor", domain: "cursor", icon: "chevron.left.forwardslash.chevron.right", category: "Apps")
    ]

    public static func displayName(for domain: String) -> String {
        all.first(where: { $0.domain.caseInsensitiveCompare(domain) == .orderedSame })?.name ?? domain
    }

    public static func icon(for domain: String) -> String {
        all.first(where: { $0.domain.caseInsensitiveCompare(domain) == .orderedSame })?.icon ?? "globe"
    }
}

// MARK: - Editorial Vector Empty-State Illustrations (Bespoke SVG-Style Line Art)

public enum RoweEmptyArtworkKind: Hashable, Sendable {
    case documents
    case tasksClear
    case trashEmpty
    case sharedSpace
}

/// Crisp, editorial vector line-art illustrations used across empty states in macOS & iOS
/// (replacing generic SF Symbol placeholders with bespoke architectural vector geometry).
public struct RoweEmptyStateArtwork: View {
    public let kind: RoweEmptyArtworkKind
    public var accent: Color
    public var size: CGFloat

    public init(kind: RoweEmptyArtworkKind, accent: Color = .accentColor, size: CGFloat = 92) {
        self.kind = kind
        self.accent = accent
        self.size = size
    }

    public var body: some View {
        let primaryStroke = Color.primary.opacity(0.62)
        let secondaryStroke = Color.primary.opacity(0.22)
        let accentFill = accent.opacity(0.16)
        let accentStroke = accent.opacity(0.85)

        Canvas { ctx, sz in
            let s = min(sz.width, sz.height) / 100.0
            let ox = (sz.width - 100 * s) * 0.5
            let oy = (sz.height - 100 * s) * 0.5
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
            }

            let halo = Path(ellipseIn: rect(12, 12, 76, 76))
            ctx.fill(halo, with: .color(accentFill.opacity(0.55)))
            ctx.stroke(halo, with: .color(secondaryStroke), style: StrokeStyle(lineWidth: 1.0 * s, dash: [3 * s, 3 * s]))

            switch kind {
            case .documents:
                let back = Path(roundedRect: rect(34, 18, 42, 54), cornerRadius: 7 * s)
                ctx.stroke(back, with: .color(secondaryStroke), lineWidth: 1.5 * s)
                let front = Path(roundedRect: rect(22, 26, 44, 56), cornerRadius: 8 * s)
                ctx.fill(front, with: .color(accentFill))
                ctx.stroke(front, with: .color(primaryStroke), lineWidth: 1.8 * s)
                var lines = Path()
                lines.move(to: pt(31, 41)); lines.addLine(to: pt(52, 41))
                lines.move(to: pt(31, 51)); lines.addLine(to: pt(57, 51))
                lines.move(to: pt(31, 61)); lines.addLine(to: pt(47, 61))
                ctx.stroke(lines, with: .color(primaryStroke), style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
                var star = Path()
                star.move(to: pt(76, 18))
                star.addQuadCurve(to: pt(84, 26), control: pt(77, 25))
                star.addQuadCurve(to: pt(76, 34), control: pt(77, 27))
                star.addQuadCurve(to: pt(68, 26), control: pt(75, 27))
                star.addQuadCurve(to: pt(76, 18), control: pt(75, 25))
                ctx.fill(star, with: .color(accentStroke))

            case .tasksClear:
                let card = Path(roundedRect: rect(22, 20, 56, 60), cornerRadius: 12 * s)
                ctx.fill(card, with: .color(accentFill))
                ctx.stroke(card, with: .color(primaryStroke), lineWidth: 1.8 * s)
                var check = Path()
                check.move(to: pt(36, 51))
                check.addLine(to: pt(46, 61))
                check.addLine(to: pt(65, 39))
                ctx.stroke(check, with: .color(accentStroke), style: StrokeStyle(lineWidth: 3.0 * s, lineCap: .round, lineJoin: .round))

            case .trashEmpty:
                var lid = Path()
                lid.move(to: pt(26, 31)); lid.addLine(to: pt(74, 31))
                ctx.stroke(lid, with: .color(primaryStroke), style: StrokeStyle(lineWidth: 2.0 * s, lineCap: .round))
                let handle = Path(roundedRect: rect(42, 23, 16, 8), cornerRadius: 3 * s)
                ctx.stroke(handle, with: .color(primaryStroke), lineWidth: 1.6 * s)
                var body = Path()
                body.move(to: pt(31, 35))
                body.addLine(to: pt(35, 76))
                body.addQuadCurve(to: pt(41, 81), control: pt(35.5, 81))
                body.addLine(to: pt(59, 81))
                body.addQuadCurve(to: pt(65, 76), control: pt(64.5, 81))
                body.addLine(to: pt(69, 35))
                ctx.fill(body, with: .color(accentFill))
                ctx.stroke(body, with: .color(primaryStroke), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                var sp = Path()
                sp.move(to: pt(50, 48)); sp.addLine(to: pt(50, 66))
                sp.move(to: pt(41, 57)); sp.addLine(to: pt(59, 57))
                ctx.stroke(sp, with: .color(accentStroke), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))

            case .sharedSpace:
                let left = Path(ellipseIn: rect(20, 32, 36, 36))
                let right = Path(ellipseIn: rect(44, 32, 36, 36))
                ctx.fill(left, with: .color(accentFill))
                ctx.fill(right, with: .color(accentFill))
                ctx.stroke(left, with: .color(primaryStroke), lineWidth: 1.8 * s)
                ctx.stroke(right, with: .color(accentStroke), lineWidth: 1.8 * s)
                let centerDot = Path(ellipseIn: rect(46, 46, 8, 8))
                ctx.fill(centerDot, with: .color(accentStroke))
            }
        }
        .frame(width: size, height: size)
    }
}

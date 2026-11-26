import SwiftUI
import RoweCore

/// Smoothed Rowe ribbon mark rendered as a SwiftUI Shape — ideal for GlassGlow Metal shader surfaces.
public struct RoweRibbonMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 1000.0, rect.height / 750.0)
        let dx = rect.midX - 500.0 * scale
        let dy = rect.midY - 375.0 * scale
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        var p = Path()
        p.move(to: pt(18, 292))
        p.addCurve(to: pt(62, 278), control1: pt(34, 282), control2: pt(48, 278))
        p.addCurve(to: pt(198, 382), control1: pt(114, 278), control2: pt(134, 382))
        p.addCurve(to: pt(446, 300), control1: pt(268, 382), control2: pt(356, 336))
        p.addCurve(to: pt(690, 232), control1: pt(536, 264), control2: pt(628, 232))
        p.addCurve(to: pt(780, 318), control1: pt(744, 232), control2: pt(780, 268))
        p.addCurve(to: pt(650, 460), control1: pt(780, 376), control2: pt(728, 424))
        p.addCurve(to: pt(286, 558), control1: pt(534, 514), control2: pt(392, 558))
        p.addCurve(to: pt(236, 510), control1: pt(252, 558), control2: pt(236, 538))
        p.addCurve(to: pt(478, 408), control1: pt(236, 456), control2: pt(354, 408))
        p.addCurve(to: pt(882, 490), control1: pt(628, 408), control2: pt(764, 490))
        p.addCurve(to: pt(984, 458), control1: pt(928, 490), control2: pt(960, 472))

        p.move(to: pt(400, 180))
        p.addCurve(to: pt(600, 342), control1: pt(454, 184), control2: pt(594, 246))
        p.addCurve(to: pt(484, 445), control1: pt(605, 402), control2: pt(548, 442))
        p.addCurve(to: pt(296, 276), control1: pt(414, 448), control2: pt(302, 374))
        p.addCurve(to: pt(400, 180), control1: pt(291, 212), control2: pt(344, 176))
        p.closeSubpath()
        return p
    }
}

private struct OnboardingSlide: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String? // nil uses RoweRibbonMark
    let palette: GlassGlowPalette
}

/// Consistent, Metal-powered GlassGlow onboarding experience shared across iOS and macOS.
public struct RoweOnboardingView: View {
    @Bindable var store: WorkspaceStore
    var onSignInRequested: () -> Void
    var onFinish: () -> Void

    @State private var step: Int = 0
    @State private var appeared = false

    private static let monochromePalette = GlassGlowPalette(
        Color(white: 0.96),
        Color(white: 0.56),
        Color(white: 0.22)
    )
    private static let paleGreyPeachPalette = GlassGlowPalette(
        Color(red: 0.95, green: 0.84, blue: 0.78),
        Color(red: 0.85, green: 0.82, blue: 0.81),
        Color(red: 0.97, green: 0.89, blue: 0.84)
    )
    private static let paleGreySkyBluePalette = GlassGlowPalette(
        Color(red: 0.76, green: 0.86, blue: 0.96),
        Color(red: 0.82, green: 0.85, blue: 0.89),
        Color(red: 0.70, green: 0.82, blue: 0.94)
    )
    private static let paleSageMistPalette = GlassGlowPalette(
        Color(red: 0.82, green: 0.90, blue: 0.86),
        Color(red: 0.85, green: 0.85, blue: 0.90),
        Color(red: 0.88, green: 0.91, blue: 0.94)
    )

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            id: 0,
            eyebrow: "STEP 1 OF 4",
            title: "Welcome to Rowe",
            subtitle: "A calm, tactile workspace for crafted documents, daily planning, and effortless speed — built native for Apple devices.",
            symbol: nil,
            palette: RoweOnboardingView.monochromePalette
        ),
        OnboardingSlide(
            id: 1,
            eyebrow: "STEP 2 OF 4",
            title: "Documents That Feel Alive",
            subtitle: "Pair custom wallpapers, editorial typography, multi-card page breaks, and washi or doodle separators in seconds.",
            symbol: "sparkles.rectangle.stack.fill",
            palette: RoweOnboardingView.paleGreyPeachPalette
        ),
        OnboardingSlide(
            id: 2,
            eyebrow: "STEP 3 OF 4",
            title: "Zero-Knowledge Locked Notes",
            subtitle: "Lock private notes with a 4- or 6-digit PIN. Encrypted on-device with AES-256-GCM so nobody — not even the database — can read them.",
            symbol: "lock.shield.fill",
            palette: RoweOnboardingView.paleGreySkyBluePalette
        ),
        OnboardingSlide(
            id: 3,
            eyebrow: "STEP 4 OF 4",
            title: "Your Space, Everywhere",
            subtitle: "Sign in to sync your documents and PIN-locked vault across Mac and iPhone, or start completely offline right now.",
            symbol: "icloud.and.arrow.up.fill",
            palette: RoweOnboardingView.paleSageMistPalette
        )
    ]

    public init(
        store: WorkspaceStore,
        onSignInRequested: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.store = store
        self.onSignInRequested = onSignInRequested
        self.onFinish = onFinish
    }

    private var currentSlide: OnboardingSlide { slides[step] }

    public var body: some View {
        ZStack {
            // Deep subtle atmospheric backdrop so the Metal GlassGlow halo shines crisply
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.055, blue: 0.075),
                    Color(red: 0.08, green: 0.085, blue: 0.115),
                    Color(red: 0.04, green: 0.045, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: step counter + Skip
                HStack {
                    Text(currentSlide.eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())

                    Spacer()

                    if step < slides.count - 1 {
                        Button("Skip") {
                            completeOnboarding(openLogin: false)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)

                Spacer(minLength: 16)

                // Hero GlassGlow Metal artwork
                ZStack {
                    if let symbol = currentSlide.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 92, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 140, height: 140)
                            .glassGlow(currentSlide.palette, speed: 0.8, glow: 1.15)
                            .id("sym-\(step)")
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        RoweRibbonMark()
                            .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(.white)
                            .frame(width: 156, height: 118)
                            .glassGlow(currentSlide.palette, speed: 0.75, glow: 1.2)
                            .id("mark-\(step)")
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .frame(height: 190)
                .animation(.spring(response: 0.44, dampingFraction: 0.78), value: step)

                // Title & subtitle with numericText smooth morphing
                VStack(spacing: 12) {
                    Text(currentSlide.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())

                    Text(currentSlide.subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 380)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 28)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: step)

                Spacer(minLength: 24)

                // Page progress dots
                HStack(spacing: 8) {
                    ForEach(slides) { s in
                        Capsule()
                            .fill(step == s.id ? Color.white : Color.white.opacity(0.25))
                            .frame(width: step == s.id ? 24 : 7, height: 7)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    step = s.id
                                }
                            }
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: step)
                .padding(.bottom, 24)

                // Bottom action buttons
                if step < slides.count - 1 {
                    HStack(spacing: 12) {
                        if step > 0 {
                            Button {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                    step -= 1
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                step += 1
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Continue")
                                    .font(.system(size: 15.5, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 10) {
                        Button {
                            completeOnboarding(openLogin: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.system(size: 14))
                                Text("Sign In or Create Account")
                                    .font(.system(size: 15.5, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)

                        Button {
                            completeOnboarding(openLogin: false)
                        } label: {
                            Text("Start Writing Locally")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(Color.white.opacity(0.11)))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
            .blur(radius: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                    appeared = true
                }
            }
        }
    }

    private func completeOnboarding(openLogin: Bool) {
        store.updateSettings { $0.hasCompletedOnboarding = true }
        onFinish()
        if openLogin {
            onSignInRequested()
        }
    }
}

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

/// Consistent, Metal-powered GlassGlow onboarding experience shared across iOS and macOS,
/// matching the app's native surface theme with an integrated Sign In / Create Account step.
public struct RoweOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    var onSignInRequested: () -> Void
    var onFinish: () -> Void

    @State private var step: Int = 0
    @State private var appeared = false
    @State private var isRegisterMode = false
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @Namespace private var modePillNS

    public static let monochromePalette = GlassGlowPalette(
        Color(white: 0.96),
        Color(white: 0.56),
        Color(white: 0.22)
    )
    public static let paleGreyPeachPalette = GlassGlowPalette(
        Color(red: 0.95, green: 0.84, blue: 0.78),
        Color(red: 0.85, green: 0.82, blue: 0.81),
        Color(red: 0.97, green: 0.89, blue: 0.84)
    )
    public static let paleGreySkyBluePalette = GlassGlowPalette(
        Color(red: 0.76, green: 0.86, blue: 0.96),
        Color(red: 0.82, green: 0.85, blue: 0.89),
        Color(red: 0.70, green: 0.82, blue: 0.94)
    )
    public static let paleSageMistPalette = GlassGlowPalette(
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
            subtitle: "Sync documents, profile, and your PIN-locked vault across Mac and iPhone.",
            symbol: nil,
            palette: RoweOnboardingView.paleSageMistPalette
        )
    ]

    public init(
        store: WorkspaceStore,
        onSignInRequested: @escaping () -> Void = {},
        onFinish: @escaping () -> Void
    ) {
        self.store = store
        self.onSignInRequested = onSignInRequested
        self.onFinish = onFinish
    }

    private var currentSlide: OnboardingSlide { slides[step] }
    private var isAuthStep: Bool { step == slides.count - 1 }

    @ViewBuilder
    private var appNativeBackground: some View {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
            .ignoresSafeArea()
        #else
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
        #endif
    }

    public var body: some View {
        ZStack {
            appNativeBackground

            VStack(spacing: 0) {
                // Top bar: back button, step counter, and Skip
                HStack {
                    if step > 0 {
                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                step -= 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(currentSlide.eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())

                    Spacer()

                    Button(isAuthStep ? "Offline" : "Skip") {
                        finishOnboarding()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)

                Spacer(minLength: 10)

                if isAuthStep {
                    integratedAuthSlide
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    introSlideContent
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Spacer(minLength: 14)

                // Page progress dots
                HStack(spacing: 8) {
                    ForEach(slides) { s in
                        Capsule()
                            .fill(step == s.id ? Color.primary : Color.primary.opacity(0.22))
                            .frame(width: step == s.id ? 24 : 7, height: 7)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    step = s.id
                                }
                            }
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: step)
                .padding(.bottom, 22)

                if !isAuthStep {
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            step += 1
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Continue")
                                .font(.system(size: 15.5, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(Color.primary))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: step)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
            .blur(radius: appeared ? 0 : 8)
            .onAppear {
                if displayName.isEmpty && store.space.authorName != "Owner" {
                    displayName = store.space.authorName
                }
                if email.isEmpty { email = store.space.email }
                store.authErrorMessage = nil
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Intro Slides (Steps 1–3)

    private var introSlideContent: some View {
        VStack(spacing: 22) {
            ZStack {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.085, blue: 0.105))
                        .frame(width: 174, height: 174)
                        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                }

                if let symbol = currentSlide.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 92, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 140)
                        .glassGlow(currentSlide.palette, speed: 0.78, glow: 1.15)
                        .id("sym-\(step)")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    RoweRibbonMark()
                        .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.white)
                        .frame(width: 156, height: 118)
                        .glassGlow(currentSlide.palette, speed: 0.72, glow: 1.2)
                        .id("mark-\(step)")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .frame(height: 185)

            VStack(spacing: 12) {
                Text(currentSlide.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())

                Text(currentSlide.subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 380)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Integrated Flagship Sign In / Create Account Step (Step 4)

    private var integratedAuthSlide: some View {
        VStack(spacing: 18) {
            ZStack {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.085, blue: 0.105))
                        .frame(width: 118, height: 90)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                }
                RoweRibbonMark()
                    .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 72)
                    .glassGlow(Self.paleSageMistPalette, speed: 0.72, glow: 1.05)
            }

            VStack(spacing: 6) {
                Text(isRegisterMode ? "Create your Rowe account" : "Sign in to Rowe")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text("Sync documents and zero-knowledge locked notes across your devices.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // Adaptive Mode Pill
            HStack(spacing: 4) {
                authModeTab("Sign In", active: !isRegisterMode) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isRegisterMode = false
                        store.authErrorMessage = nil
                    }
                }
                authModeTab("Create Account", active: isRegisterMode) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isRegisterMode = true
                        store.authErrorMessage = nil
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
            )
            .frame(maxWidth: 340)

            // Inputs
            VStack(spacing: 10) {
                if isRegisterMode {
                    authFieldRow(icon: "person", placeholder: "Your name") {
                        TextField("", text: $displayName, prompt: Text("Your name").foregroundStyle(.secondary))
                            .textFieldStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                authFieldRow(icon: "envelope", placeholder: "Email address") {
                    #if os(iOS)
                    TextField("", text: $email, prompt: Text("Email address").foregroundStyle(.secondary))
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    #else
                    TextField("", text: $email, prompt: Text("Email address").foregroundStyle(.secondary))
                        .textFieldStyle(.plain)
                    #endif
                }

                authFieldRow(icon: "lock", placeholder: isRegisterMode ? "Create password (8+ chars)" : "Password") {
                    SecureField(
                        "",
                        text: $password,
                        prompt: Text(isRegisterMode ? "Create password (8+ chars)" : "Password").foregroundStyle(.secondary)
                    )
                    .textFieldStyle(.plain)
                    .onSubmit { submitAuth() }
                }
            }
            .frame(maxWidth: 340)
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isRegisterMode)

            if let err = store.authErrorMessage, !err.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: 340, alignment: .leading)
                .transition(.opacity)
            }

            VStack(spacing: 10) {
                Button {
                    submitAuth()
                } label: {
                    HStack(spacing: 8) {
                        if store.isAuthBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(colorScheme == .dark ? .black : .white)
                        }
                        Text(isRegisterMode ? "Create Account & Start" : "Sign In & Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.primary.opacity(canSubmitAuth ? 1.0 : 0.45)))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitAuth || store.isAuthBusy)

                Button {
                    finishOnboarding()
                } label: {
                    Text("Continue Offline — Start Writing Locally")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 340)
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
    }

    private var canSubmitAuth: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.count >= 8
    }

    private func authModeTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                            .matchedGeometryEffect(id: "onboardingAuthPill", in: modePillNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func authFieldRow<Content: View>(icon: String, placeholder: String, @ViewBuilder field: () -> Content) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            field()
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
        )
    }

    private func submitAuth() {
        guard canSubmitAuth, !store.isAuthBusy else { return }
        Task {
            if isRegisterMode {
                await store.registerAccount(
                    serverURL: store.serverURL,
                    email: email,
                    password: password,
                    displayName: displayName
                )
            } else {
                await store.signIn(
                    serverURL: store.serverURL,
                    email: email,
                    password: password
                )
            }
            if store.isSignedIn {
                finishOnboarding()
            }
        }
    }

    private func finishOnboarding() {
        store.updateSettings { $0.hasCompletedOnboarding = true }
        onFinish()
    }
}

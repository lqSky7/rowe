import SwiftUI
import RoweCore

/// Flagship Liquid Glass + GlassGlow Sign In modal for macOS (invoked from Settings or Sidebar).
/// Matches the integrated onboarding auth step with zero Server URL clutter.
struct LoginModalView: View {
    @Bindable var store: WorkspaceStore
    var onClose: () -> Void

    @State private var isRegisterMode = false
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @Namespace private var modePillNS

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.count >= 8
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 18) {
                RoweRibbonMark()
                    .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 66)
                    .glassGlow(RoweOnboardingView.monochromePalette, speed: 0.72, glow: 1.0)
                    .padding(.top, 6)

                VStack(spacing: 5) {
                    Text(isRegisterMode ? "Create your Rowe account" : "Sign in to Rowe")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("Sync documents, profile, and zero-knowledge locked notes.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }

                // Frosted Glass Mode Switch
                HStack(spacing: 4) {
                    modeTab("Sign In", active: !isRegisterMode) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            isRegisterMode = false
                            store.authErrorMessage = nil
                        }
                    }
                    modeTab("Create Account", active: isRegisterMode) {
                        withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            isRegisterMode = true
                            store.authErrorMessage = nil
                        }
                    }
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
                )

                // Frosted Glass Fields
                VStack(spacing: 10) {
                    if isRegisterMode {
                        fieldRow(icon: "person") {
                            TextField("", text: $displayName, prompt: Text("Your name").foregroundStyle(.white.opacity(0.38)))
                                .textFieldStyle(.plain)
                        }
                        .transition(.roweUnblur)
                    }

                    fieldRow(icon: "envelope") {
                        TextField("", text: $email, prompt: Text("Email address").foregroundStyle(.white.opacity(0.38)))
                            .textFieldStyle(.plain)
                    }

                    fieldRow(icon: "lock") {
                        SecureField(
                            "",
                            text: $password,
                            prompt: Text(isRegisterMode ? "Create password (8+ chars)" : "Password").foregroundStyle(.white.opacity(0.38))
                        )
                        .textFieldStyle(.plain)
                        .onSubmit { submit() }
                    }
                }
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: isRegisterMode)

                if let err = store.authErrorMessage, !err.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.54))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.roweUnblur)
                }

                VStack(spacing: 10) {
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if store.isAuthBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            }
                            Text(isRegisterMode ? "Create Account" : "Sign In")
                                .font(.system(size: 14.5, weight: .semibold))
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.white.opacity(canSubmit ? 1.0 : 0.42)))
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                    .disabled(!canSubmit || store.isAuthBusy)

                    Button("Continue Offline") {
                        HapticsManager.shared.tap()
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)

            Button {
                HapticsManager.shared.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(RowePressScaleButtonStyle())
            .padding(16)
        }
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.085, blue: 0.11).opacity(0.96),
                            Color(red: 0.05, green: 0.055, blue: 0.075).opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.9)
        )
        .shadow(color: .black.opacity(0.42), radius: 32, y: 16)
        .onAppear {
            if displayName.isEmpty && store.space.authorName != "Owner" {
                displayName = store.space.authorName
            }
            if email.isEmpty { email = store.space.email }
            store.authErrorMessage = nil
        }
    }

    private func modeTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.52))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
                            .matchedGeometryEffect(id: "loginModalPill", in: modePillNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18)
            content()
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                )
        )
    }

    private func submit() {
        guard canSubmit, !store.isAuthBusy else { return }
        HapticsManager.shared.tap()
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
                onClose()
            }
        }
    }
}

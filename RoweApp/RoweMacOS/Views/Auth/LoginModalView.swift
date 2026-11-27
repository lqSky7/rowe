import SwiftUI
import RoweCore

/// Native Liquid Glass + GlassGlow Sign In modal for macOS matching the rest of Rowe's surfaces.
struct LoginModalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    var onClose: () -> Void

    private enum LoginField: Hashable {
        case displayName, email, password
    }

    @State private var isRegisterMode = false
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: LoginField?
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
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("Sync documents, profile, and zero-knowledge locked notes.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

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
                        .fill(Color.primary.opacity(0.07))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
                )

                VStack(spacing: 10) {
                    if isRegisterMode {
                        fieldRow(icon: "person") {
                            TextField("Your name", text: $displayName)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .displayName)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                        }
                        .transition(.roweUnblur)
                    }

                    fieldRow(icon: "envelope") {
                        TextField("Email address", text: $email)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }

                    fieldRow(icon: "lock") {
                        SecureField(isRegisterMode ? "Create password (8+ chars)" : "Password", text: $password)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
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
                    .foregroundStyle(.red)
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
                            }
                            Text(isRegisterMode ? "Create Account" : "Sign In")
                                .font(.system(size: 14.5, weight: .semibold))
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.primary.opacity(canSubmit ? 1.0 : 0.42)))
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                    .disabled(!canSubmit || store.isAuthBusy)

                    Button("Continue Offline") {
                        HapticsManager.shared.tap()
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)

            GlassCircleButton(systemImage: "xmark", helpText: "Close", size: 28, iconSize: 10.5) {
                onClose()
            }
            .padding(16)
        }
        .frame(width: 400)
        .background(RoweNativeGlassBackdrop(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.9)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
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
                .foregroundStyle(active ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.primary.opacity(0.13))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
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
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
                .font(.system(size: 13.5))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
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

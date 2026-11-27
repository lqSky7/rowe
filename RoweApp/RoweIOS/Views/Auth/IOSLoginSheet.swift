import SwiftUI
import RoweCore

/// Native adaptive Liquid Glass + GlassGlow Sign In sheet for iOS (matches app background, zero Server URL clutter).
struct IOSLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore

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
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Button("Offline") {
                            IOSKeyboard.dismiss()
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    RoweRibbonMark()
                        .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 72)
                        .glassGlow(RoweOnboardingView.monochromePalette, speed: 0.72, glow: 1.0)
                        .padding(.top, 4)

                    VStack(spacing: 6) {
                        Text(isRegisterMode ? "Create your Rowe account" : "Sign in to Rowe")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("Sync documents, profile, and zero-knowledge locked notes.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 4) {
                        modeTab("Sign In", active: !isRegisterMode) {
                            withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                                isRegisterMode = false
                                store.authErrorMessage = nil
                            }
                        }
                        modeTab("Create Account", active: isRegisterMode) {
                            withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
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

                    VStack(spacing: 12) {
                        if isRegisterMode {
                            fieldRow(icon: "person") {
                                TextField("Your name", text: $displayName)
                                    .focused($focusedField, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                            }
                        }

                        fieldRow(icon: "envelope") {
                            TextField("Email address", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }

                        fieldRow(icon: "lock") {
                            SecureField(isRegisterMode ? "Create password (8+ chars)" : "Password", text: $password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { submit() }
                        }
                    }

                    if let err = store.authErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if store.isAuthBusy { ProgressView() }
                            Text(isRegisterMode ? "Create Account" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.primary.opacity(canSubmit ? 1.0 : 0.42)))
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .disabled(!canSubmit || store.isAuthBusy)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { IOSKeyboard.dismiss() }
            .onAppear {
                if displayName.isEmpty && store.space.authorName != "Owner" {
                    displayName = store.space.authorName
                }
                if email.isEmpty { email = store.space.email }
                store.authErrorMessage = nil
            }
        }
    }

    private func modeTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.primary.opacity(0.13))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                            .matchedGeometryEffect(id: "iosLoginPill", in: modePillNS)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
                .font(.system(size: 15))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                )
        )
    }

    private func submit() {
        IOSKeyboard.dismiss()
        IOSHaptics.shared.tap()
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
            if store.isSignedIn { dismiss() }
        }
    }
}

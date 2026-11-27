import SwiftUI
import RoweCore

/// Sleek, keyboard-aware Sign In / Create Account sheet for iOS:
/// - Compact adaptive header that gracefully tucks when the keyboard is active
/// - Crisp elevated segmented switcher & focus-ringed inputs (zero muddy gray borders)
/// - Primary Sign In / Create Account button pinned via `.safeAreaInset(edge: .bottom)` so it
///   always floats cleanly above the keyboard alongside the password field.
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
    @State private var showPassword = false
    @FocusState private var focusedField: LoginField?
    @Namespace private var modePillNS

    private var isDark: Bool { colorScheme == .dark }

    private var resolvedAccent: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: isDark))
    }

    private var isKeyboardActive: Bool {
        focusedField != nil
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.count >= 8
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: isKeyboardActive ? 16 : 22) {
                        // Adaptive hero header — stays spacious at rest and compacts smoothly while typing
                        VStack(spacing: isKeyboardActive ? 6 : 12) {
                            if !isKeyboardActive {
                                RoweRibbonMark()
                                    .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(.white)
                                    .frame(width: 82, height: 62)
                                    .glassGlow(RoweOnboardingView.monochromePalette, speed: 0.72, glow: 1.0)
                                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                            }

                            VStack(spacing: 4) {
                                Text(isRegisterMode ? "Create your account" : "Welcome back")
                                    .font(.system(size: isKeyboardActive ? 22 : 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .contentTransition(.numericText())

                                Text("Sync tasks, docs, and locked notes across devices.")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, isKeyboardActive ? 4 : 10)
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isKeyboardActive)

                        // Clean elevated pill switcher
                        HStack(spacing: 3) {
                            modeTab("Sign In", active: !isRegisterMode) {
                                IOSHaptics.shared.toggle()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    isRegisterMode = false
                                    store.authErrorMessage = nil
                                }
                            }
                            modeTab("Create Account", active: isRegisterMode) {
                                IOSHaptics.shared.toggle()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    isRegisterMode = true
                                    store.authErrorMessage = nil
                                }
                            }
                        }
                        .padding(3.5)
                        .background(
                            Capsule()
                                .fill(isDark ? Color(white: 0.13) : Color(uiColor: .secondarySystemFill))
                        )

                        // Crisp modern form inputs with active focus ring
                        VStack(spacing: 11) {
                            if isRegisterMode {
                                fieldRow(
                                    icon: "person",
                                    isFocused: focusedField == .displayName
                                ) {
                                    TextField("Your name", text: $displayName)
                                        .textContentType(.name)
                                        .focused($focusedField, equals: .displayName)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .email }
                                }
                                .id(LoginField.displayName)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            fieldRow(
                                icon: "envelope",
                                isFocused: focusedField == .email
                            ) {
                                TextField("Email address", text: $email)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .id(LoginField.email)

                            fieldRow(
                                icon: "lock",
                                isFocused: focusedField == .password
                            ) {
                                HStack(spacing: 8) {
                                    Group {
                                        if showPassword {
                                            TextField(isRegisterMode ? "Create password (8+ chars)" : "Password", text: $password)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                        } else {
                                            SecureField(isRegisterMode ? "Create password (8+ chars)" : "Password", text: $password)
                                        }
                                    }
                                    .textContentType(isRegisterMode ? .newPassword : .password)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { if canSubmit { submit() } }

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .id(LoginField.password)
                        }

                        if let err = store.authErrorMessage, !err.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 14))
                                Text(err)
                                    .font(.system(size: 13, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(isDark ? 0.14 : 0.08))
                            )
                            .id("authError")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if store.isAuthBusy {
                                ProgressView()
                                    .tint(isDark ? .black : .white)
                            }
                            Text(isRegisterMode ? "Create Account" : "Continue")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(isDark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(canSubmit ? 1.0 : 0.28))
                        )
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .disabled(!canSubmit || store.isAuthBusy)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: Color(uiColor: .systemBackground).opacity(0.0), location: 0.0),
                            .init(color: Color(uiColor: .systemBackground).opacity(0.92), location: 0.28),
                            .init(color: Color(uiColor: .systemBackground), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Offline") {
                        IOSKeyboard.dismiss()
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
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
                .padding(.vertical, 9)
                .background {
                    if active {
                        Capsule()
                            .fill(isDark ? Color(white: 0.22) : Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(isDark ? 0.28 : 0.08), radius: 5, y: 2)
                            .matchedGeometryEffect(id: "iosLoginPill", in: modePillNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(
        icon: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(isFocused ? resolvedAccent : .secondary)
                .frame(width: 20)
            content()
                .font(.system(size: 15.5))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isDark ? Color(white: 0.115) : Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? resolvedAccent.opacity(0.85)
                                : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                            lineWidth: isFocused ? 1.4 : 0.75
                        )
                )
        )
        .animation(.easeOut(duration: 0.16), value: isFocused)
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

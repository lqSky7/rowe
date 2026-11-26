import SwiftUI
import RoweCore

enum AuthSheetMode: String, CaseIterable {
    case signIn = "Sign In"
    case register = "Create Account"
}

/// Simple, clean Liquid Glass Sign In / Create Account sheet connecting Rowe to RoweServer.
struct LoginModalView: View {
    @Bindable var store: WorkspaceStore
    var onClose: () -> Void

    @State private var mode: AuthSheetMode = .signIn
    @State private var serverURL: String = ""
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode == .signIn ? "Sign in to Rowe" : "Create your Rowe account")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Sync documents and zero-knowledge locked notes across all your devices.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassCircleButton(systemImage: "xmark", helpText: "Close", size: 28, iconSize: 11) {
                    onClose()
                }
            }

            LiquidGlassSegmentedControl(
                items: AuthSheetMode.allCases,
                selection: $mode,
                height: 32
            ) { item, isSelected in
                Text(item.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldGroup("Server URL") {
                    TextField("https://rowe.traverses.dpdns.org", text: $serverURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }

                if mode == .register {
                    fieldGroup("Display Name") {
                        TextField("Your name", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                }

                fieldGroup("Email") {
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }

                fieldGroup("Password") {
                    SecureField(mode == .register ? "At least 8 characters" : "Password", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { submit() }
                }
            }

            if let err = store.authErrorMessage, !err.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                    Text(err)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.10)))
            }

            HStack(spacing: 10) {
                Button("Continue Offline") {
                    HapticsManager.shared.tap()
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    submit()
                } label: {
                    HStack(spacing: 6) {
                        if store.isAuthBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .buttonStyle(RowePressScaleButtonStyle())
                .roweGlassCapsule(interactive: true)
                .disabled(store.isAuthBusy || email.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 8)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 400)
        .background(RoweNativeGlassBackdrop(cornerRadius: 20))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .onAppear {
            serverURL = store.serverURL
            if displayName.isEmpty { displayName = store.space.authorName }
            if email.isEmpty { email = store.space.email }
            store.authErrorMessage = nil
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            content()
                .roweGlassInput(cornerRadius: 10)
        }
    }

    private func submit() {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedEmail.isEmpty, password.count >= 8 else { return }
        HapticsManager.shared.tap()
        Task {
            if mode == .signIn {
                await store.signIn(serverURL: trimmedURL, email: trimmedEmail, password: password)
            } else {
                await store.registerAccount(
                    serverURL: trimmedURL,
                    email: trimmedEmail,
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
    }
}

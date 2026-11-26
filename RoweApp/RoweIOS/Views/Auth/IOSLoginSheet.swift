import SwiftUI
import RoweCore

struct IOSLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore

    @State private var isRegisterMode = false
    @State private var serverURL: String = ""
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RoweRibbonMark()
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 72)
                        .glassGlow(
                            GlassGlowPalette(
                                primary: Color(white: 0.96),
                                secondary: Color(white: 0.56),
                                accent: Color(white: 0.22)
                            ),
                            speed: 0.75,
                            glow: 0.95
                        )
                        .padding(.top, 10)

                    VStack(spacing: 4) {
                        Text(isRegisterMode ? "Create Rowe Account" : "Sign In to Rowe")
                            .font(.system(size: 22, weight: .bold))
                            .contentTransition(.numericText())
                        Text("Sync documents & zero-knowledge locked notes.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                    }

                    Picker("Mode", selection: $isRegisterMode) {
                        Text("Sign In").tag(false)
                        Text("Create Account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        inputBox("Server URL") {
                            TextField("https://rowe.traverses.dpdns.org", text: $serverURL)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                        }

                        if isRegisterMode {
                            inputBox("Display Name") {
                                TextField("Your name", text: $displayName)
                            }
                        }

                        inputBox("Email") {
                            TextField("you@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                        }

                        inputBox("Password") {
                            SecureField(isRegisterMode ? "At least 8 characters" : "Password", text: $password)
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
                            if store.isAuthBusy { ProgressView().tint(.black) }
                            Text(isRegisterMode ? "Create Account" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .disabled(store.isAuthBusy || email.isEmpty || password.count < 8)
                }
                .padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { IOSKeyboard.dismiss() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Offline") { dismiss() }
                }
            }
            .onAppear {
                serverURL = store.serverURL
                if displayName.isEmpty { displayName = store.space.authorName }
                if email.isEmpty { email = store.space.email }
                store.authErrorMessage = nil
            }
        }
    }

    private func inputBox<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
    }

    private func submit() {
        IOSKeyboard.dismiss()
        IOSHaptics.shared.tap()
        Task {
            if isRegisterMode {
                await store.registerAccount(serverURL: serverURL, email: email, password: password, displayName: displayName)
            } else {
                await store.signIn(serverURL: serverURL, email: email, password: password)
            }
            if store.isSignedIn { dismiss() }
        }
    }
}

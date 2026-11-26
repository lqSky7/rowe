import SwiftUI
import RoweCore

struct IOSPinLockSheet: View {
    @Bindable var store: WorkspaceStore
    let request: PinPromptRequest
    var onDismiss: () -> Void

    @State private var pinLength: Int = 6
    @State private var enteredPin: String = ""
    @State private var firstSetupPin: String? = nil
    @State private var verifiedCurrentPin: String? = nil
    @State private var errorMessage: String? = nil
    @State private var shakePhase: CGFloat = 0
    @State private var showErrorFlash = false
    @State private var isUnlockedSuccess = false
    @State private var isProcessing = false

    private var titleText: String {
        switch request {
        case .setupPin: return firstSetupPin == nil ? "Create Lock PIN" : "Confirm Lock PIN"
        case .unlockDocument(let docId):
            let locked = store.documents.first(where: { $0.id == docId })?.isLocked ?? true
            return locked ? "Unlock Note" : "Enter PIN to Lock"
        case .changePin:
            if verifiedCurrentPin == nil { return "Current PIN" }
            return firstSetupPin == nil ? "New PIN" : "Confirm New PIN"
        }
    }

    private var canToggleLength: Bool {
        if case .setupPin = request { return firstSetupPin == nil }
        if case .changePin = request { return verifiedCurrentPin != nil && firstSetupPin == nil }
        return false
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Image(systemName: isUnlockedSuccess ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(showErrorFlash ? .red : (isUnlockedSuccess ? .green : .primary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 62, height: 62)
                .background(Circle().fill(showErrorFlash ? Color.red.opacity(0.15) : Color.primary.opacity(0.08)))

            Text(titleText)
                .font(.system(size: 20, weight: .bold))
                .contentTransition(.numericText())

            if canToggleLength {
                Picker("PIN Length", selection: $pinLength) {
                    Text("4-Digit").tag(4)
                    Text("6-Digit").tag(6)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .onChange(of: pinLength) { _, _ in enteredPin = "" }
            }

            HStack(spacing: 16) {
                ForEach(0..<pinLength, id: \.self) { idx in
                    let filled = idx < enteredPin.count
                    Circle()
                        .fill(showErrorFlash ? Color.red : (isUnlockedSuccess ? Color.green : (filled ? Color.primary : Color.clear)))
                        .frame(width: 15, height: 15)
                        .overlay(
                            Circle().strokeBorder(showErrorFlash ? Color.red : Color.primary.opacity(0.35), lineWidth: 1.6)
                        )
                        .scaleEffect(filled ? 1.18 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: filled)
                }
            }
            .padding(.vertical, 6)
            .modifier(IOSPinShake(animatableData: shakePhase))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                padRow(["1", "2", "3"])
                padRow(["4", "5", "6"])
                padRow(["7", "8", "9"])
                HStack(spacing: 22) {
                    Color.clear.frame(width: 72, height: 56)
                    padKey("0")
                    Button {
                        guard !enteredPin.isEmpty else { return }
                        IOSHaptics.shared.tap()
                        enteredPin.removeLast()
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, height: 56)
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .onAppear {
            if let len = store.vaultEnvelope?.pinLength, len == 4 || len == 6 {
                pinLength = len
            }
        }
    }

    private func padRow(_ digits: [String]) -> some View {
        HStack(spacing: 22) {
            ForEach(digits, id: \.self) { padKey($0) }
        }
    }

    private func padKey(_ digit: String) -> some View {
        Button {
            guard !isProcessing, enteredPin.count < pinLength else { return }
            IOSHaptics.shared.tap()
            errorMessage = nil
            enteredPin.append(digit)
            if enteredPin.count == pinLength {
                handleComplete(enteredPin)
            }
        } label: {
            Text(digit)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 56)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(RowePressScaleStyle())
        .disabled(isProcessing)
    }

    private func handleComplete(_ pin: String) {
        switch request {
        case .setupPin(let docId):
            if let first = firstSetupPin {
                if first == pin {
                    isProcessing = true
                    Task {
                        do {
                            try await store.setupVaultPin(pin, pinLength: pinLength, thenLockDocId: docId)
                            await MainActor.run { succeedAndClose() }
                        } catch {
                            await MainActor.run { isProcessing = false; fail("Could not save PIN") }
                        }
                    }
                } else {
                    firstSetupPin = nil
                    fail("PINs didn't match")
                }
            } else {
                withAnimation(IOSTheme.craftSpring()) { firstSetupPin = pin; enteredPin = "" }
            }

        case .unlockDocument(let docId):
            do {
                try store.verifyPinAndUnlock(docId: docId, pin: pin)
                succeedAndClose()
            } catch {
                fail("Incorrect PIN")
            }

        case .changePin:
            if verifiedCurrentPin == nil {
                if let env = store.vaultEnvelope,
                   (try? NoteCryptoService.unwrapVaultKey(pin: pin, envelope: env)) != nil {
                    withAnimation(IOSTheme.craftSpring()) { verifiedCurrentPin = pin; enteredPin = "" }
                } else {
                    fail("Incorrect current PIN")
                }
            } else if let first = firstSetupPin {
                if first == pin, let cur = verifiedCurrentPin {
                    isProcessing = true
                    Task {
                        do {
                            try await store.changeVaultPin(currentPin: cur, newPin: pin, pinLength: pinLength)
                            await MainActor.run { succeedAndClose() }
                        } catch {
                            await MainActor.run { isProcessing = false; fail("Update failed") }
                        }
                    }
                } else {
                    firstSetupPin = nil
                    fail("New PINs didn't match")
                }
            } else {
                withAnimation(IOSTheme.craftSpring()) { firstSetupPin = pin; enteredPin = "" }
            }
        }
    }

    private func fail(_ msg: String) {
        IOSHaptics.shared.errorBuzz()
        errorMessage = msg
        showErrorFlash = true
        withAnimation(.default) { shakePhase += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            enteredPin = ""
            showErrorFlash = false
        }
    }

    private func succeedAndClose() {
        IOSHaptics.shared.taskComplete()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { isUnlockedSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { onDismiss() }
    }
}

private struct IOSPinShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 4) * 10, y: 0))
    }
}

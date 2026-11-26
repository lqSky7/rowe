import AppKit
import SwiftUI
import RoweCore

/// Tactile 4- or 6-digit PIN Lock / Unlock sheet with animated dots, keyboard + keypad input,
/// horizontal shake + red flash + haptic buzz on wrong PIN, and smooth lock/unlock symbol transitions.
struct PinLockSheet: View {
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
    @State private var keyMonitor: Any?

    private var titleText: String {
        switch request {
        case .setupPin:
            return firstSetupPin == nil ? "Create Lock PIN" : "Confirm Lock PIN"
        case .unlockDocument(let docId):
            let isLocked = store.documents.first(where: { $0.id == docId })?.isLocked ?? true
            return isLocked ? "Unlock Note" : "Enter PIN to Lock"
        case .changePin:
            if verifiedCurrentPin == nil { return "Enter Current PIN" }
            return firstSetupPin == nil ? "Enter New PIN" : "Confirm New PIN"
        }
    }

    private var subtitleText: String {
        switch request {
        case .setupPin:
            return firstSetupPin == nil
                ? "Encrypted end-to-end on your device. Works across all your signed-in devices."
                : "Re-enter your \(pinLength)-digit PIN to confirm."
        case .unlockDocument:
            return "Enter your \(pinLength)-digit PIN."
        case .changePin:
            if verifiedCurrentPin == nil { return "Verify your current \(pinLength)-digit PIN first." }
            return firstSetupPin == nil ? "Choose a new \(pinLength)-digit PIN." : "Re-enter your new PIN to confirm."
        }
    }

    private var canTogglePinLength: Bool {
        if case .setupPin = request { return firstSetupPin == nil }
        if case .changePin = request { return verifiedCurrentPin != nil && firstSetupPin == nil }
        return false
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                GlassCircleButton(systemImage: "xmark", helpText: "Cancel (Esc)", size: 28, iconSize: 11) {
                    onDismiss()
                }
            }
            .padding(.bottom, -10)

            // Animated Lock Icon
            ZStack {
                Circle()
                    .fill(
                        showErrorFlash
                            ? Color.red.opacity(0.16)
                            : (isUnlockedSuccess ? Color.green.opacity(0.16) : Color.primary.opacity(0.08))
                    )
                    .frame(width: 58, height: 58)
                    .scaleEffect(isUnlockedSuccess ? 1.08 : 1.0)

                Image(systemName: isUnlockedSuccess ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(showErrorFlash ? .red : (isUnlockedSuccess ? .green : .primary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isUnlockedSuccess)
            .animation(.easeOut(duration: 0.18), value: showErrorFlash)

            VStack(spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)

            if canTogglePinLength {
                LiquidGlassSegmentedControl(
                    items: [4, 6],
                    selection: $pinLength,
                    height: 28,
                    title: { "\($0)-Digit PIN" }
                )
                .frame(width: 190)
                .onChange(of: pinLength) { _, _ in
                    enteredPin = ""
                    errorMessage = nil
                }
            }

            // Animated PIN Dots
            HStack(spacing: 14) {
                ForEach(0..<pinLength, id: \.self) { idx in
                    let filled = idx < enteredPin.count
                    Circle()
                        .fill(
                            showErrorFlash
                                ? Color.red
                                : (isUnlockedSuccess ? Color.green : (filled ? Color.primary : Color.clear))
                        )
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    showErrorFlash
                                        ? Color.red
                                        : (isUnlockedSuccess ? Color.green : Color.primary.opacity(filled ? 0.9 : 0.32)),
                                    lineWidth: 1.5
                                )
                        )
                        .scaleEffect(filled ? 1.15 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: filled)
                }
            }
            .padding(.vertical, 6)
            .modifier(PinShakeEffect(animatableData: shakePhase))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            } else {
                Text("Type on keyboard or click keypad")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Tactile Numeric Keypad
            VStack(spacing: 10) {
                keypadRow(["1", "2", "3"])
                keypadRow(["4", "5", "6"])
                keypadRow(["7", "8", "9"])
                HStack(spacing: 14) {
                    Color.clear.frame(width: 56, height: 42)
                    keypadButton("0")
                    Button {
                        deleteDigit()
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, height: 42)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                    .disabled(enteredPin.isEmpty || isProcessing)
                }
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 310)
        .background(RoweNativeGlassBackdrop(cornerRadius: 22))
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        .onAppear {
            if let existingLen = store.vaultEnvelope?.pinLength, existingLen == 4 || existingLen == 6 {
                pinLength = existingLen
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func keypadRow(_ digits: [String]) -> some View {
        HStack(spacing: 14) {
            ForEach(digits, id: \.self) { digit in
                keypadButton(digit)
            }
        }
    }

    private func keypadButton(_ digit: String) -> some View {
        Button {
            appendDigit(digit)
        } label: {
            Text(digit)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(RowePressScaleButtonStyle())
        .disabled(isProcessing)
    }

    private func appendDigit(_ digit: String) {
        guard !isProcessing, enteredPin.count < pinLength else { return }
        HapticsManager.shared.tap()
        errorMessage = nil
        enteredPin.append(digit)
        if enteredPin.count == pinLength {
            handleCompletedPin(enteredPin)
        }
    }

    private func deleteDigit() {
        guard !isProcessing, !enteredPin.isEmpty else { return }
        HapticsManager.shared.tap()
        enteredPin.removeLast()
    }

    private func handleCompletedPin(_ pin: String) {
        switch request {
        case .setupPin(let targetDocId):
            if let first = firstSetupPin {
                if first == pin {
                    isProcessing = true
                    Task {
                        do {
                            try await store.setupVaultPin(pin, pinLength: pinLength, thenLockDocId: targetDocId)
                            await MainActor.run { celebrateAndClose() }
                        } catch {
                            await MainActor.run {
                                isProcessing = false
                                triggerError("Could not set up PIN")
                            }
                        }
                    }
                } else {
                    firstSetupPin = nil
                    triggerError("PINs didn't match — try again")
                }
            } else {
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    firstSetupPin = pin
                    enteredPin = ""
                }
            }

        case .unlockDocument(let docId):
            do {
                try store.verifyPinAndUnlock(docId: docId, pin: pin)
                celebrateAndClose()
            } catch {
                if let until = store.pinLockoutUntil, until > Date() {
                    let secs = max(1, Int(ceil(until.timeIntervalSinceNow)))
                    triggerError("Too many attempts · wait \(secs)s")
                } else {
                    triggerError("Incorrect PIN")
                }
            }

        case .changePin:
            if verifiedCurrentPin == nil {
                if let env = store.vaultEnvelope,
                   (try? NoteCryptoService.unwrapVaultKey(pin: pin, envelope: env)) != nil {
                    withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        verifiedCurrentPin = pin
                        enteredPin = ""
                    }
                } else {
                    triggerError("Incorrect current PIN")
                }
            } else if let first = firstSetupPin {
                if first == pin, let current = verifiedCurrentPin {
                    isProcessing = true
                    Task {
                        do {
                            try await store.changeVaultPin(currentPin: current, newPin: pin, pinLength: pinLength)
                            await MainActor.run { celebrateAndClose() }
                        } catch {
                            await MainActor.run {
                                isProcessing = false
                                triggerError("Could not update PIN")
                            }
                        }
                    }
                } else {
                    firstSetupPin = nil
                    triggerError("New PINs didn't match")
                }
            } else {
                withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    firstSetupPin = pin
                    enteredPin = ""
                }
            }
        }
    }

    private func triggerError(_ message: String) {
        HapticsManager.shared.taskCrossOutBuzz()
        errorMessage = message
        showErrorFlash = true
        withAnimation(.default) {
            shakePhase += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            enteredPin = ""
            showErrorFlash = false
        }
    }

    private func celebrateAndClose() {
        HapticsManager.shared.taskComplete()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
            isUnlockedSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            onDismiss()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onDismiss()
                return nil
            }
            if event.keyCode == 51 { // Backspace
                deleteDigit()
                return nil
            }
            if let chars = event.charactersIgnoringModifiers, chars.count == 1, let ch = chars.first, ch.isNumber {
                appendDigit(String(ch))
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

/// Smooth damped horizontal shake geometry effect for wrong PIN entry.
private struct PinShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 4) * 9
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

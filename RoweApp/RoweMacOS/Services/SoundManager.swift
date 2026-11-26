import AppKit

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    var isEnabled: Bool = false

    private init() {}

    func playSubtlePop() {
        guard isEnabled else { return }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    func playComplete() {
        guard isEnabled else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
}

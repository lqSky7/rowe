import CommonCrypto
import CryptoKit
import Foundation

public enum NoteCryptoError: Error, LocalizedError, Sendable {
    case invalidPin
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case missingVaultKey

    public var errorDescription: String? {
        switch self {
        case .invalidPin: "Incorrect PIN"
        case .keyDerivationFailed: "Could not derive encryption key"
        case .encryptionFailed: "Could not encrypt note"
        case .decryptionFailed: "Could not decrypt note"
        case .missingVaultKey: "Vault key not unlocked"
        }
    }
}

/// Client-side PIN-wrapped 256-bit Note Vault Key envelope.
/// Synced to RoweServer `/api/v1/vault` so all of the user's devices can unlock locked notes
/// with the same PIN without the server ever learning the PIN or plaintext note contents.
public struct VaultKeyEnvelope: Codable, Hashable, Sendable {
    public var wrappedKey: String
    public var salt: String
    public var nonce: String
    public var kdfIterations: Int
    public var pinLength: Int
    public var version: Int

    public init(
        wrappedKey: String,
        salt: String,
        nonce: String = "",
        kdfIterations: Int = 210_000,
        pinLength: Int = 6,
        version: Int = 1
    ) {
        self.wrappedKey = wrappedKey
        self.salt = salt
        self.nonce = nonce
        self.kdfIterations = kdfIterations
        self.pinLength = pinLength
        self.version = version
    }
}

/// Zero-knowledge AES-256-GCM + PBKDF2-HMAC-SHA256 client-side encryption engine for locked notes.
public enum NoteCryptoService {
    public static let defaultIterations = 210_000

    /// Generates a fresh 256-bit Note Vault Key (NVK) and wraps it with a key derived from `pin`.
    public static func createVault(pin: String, pinLength: Int = 6) throws -> (vaultKey: Data, envelope: VaultKeyEnvelope) {
        var vaultKeyBytes = Data(count: 32)
        let rc = vaultKeyBytes.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        guard rc == errSecSuccess else { throw NoteCryptoError.encryptionFailed }
        let envelope = try wrapVaultKey(vaultKeyBytes, withPin: pin, pinLength: pinLength)
        return (vaultKeyBytes, envelope)
    }

    /// Wraps an existing 256-bit NVK with a new PIN (instant PIN change without re-encrypting every note).
    public static func wrapVaultKey(_ vaultKey: Data, withPin pin: String, pinLength: Int = 6) throws -> VaultKeyEnvelope {
        var salt = Data(count: 16)
        let rc = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 16, ptr.baseAddress!)
        }
        guard rc == errSecSuccess else { throw NoteCryptoError.encryptionFailed }

        let kek = try deriveKEK(pin: pin, salt: salt, iterations: defaultIterations)
        let nonce = AES.GCM.Nonce()
        guard let sealed = try? AES.GCM.seal(vaultKey, using: kek, nonce: nonce),
              let combined = sealed.combined else {
            throw NoteCryptoError.encryptionFailed
        }

        return VaultKeyEnvelope(
            wrappedKey: combined.base64EncodedString(),
            salt: salt.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            kdfIterations: defaultIterations,
            pinLength: pinLength,
            version: 1
        )
    }

    /// Derives KEK from `pin` + envelope salt and unwraps the 256-bit NVK. Throws `.invalidPin` on mismatch.
    public static func unwrapVaultKey(pin: String, envelope: VaultKeyEnvelope) throws -> Data {
        guard let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.wrappedKey) else {
            throw NoteCryptoError.decryptionFailed
        }
        let kek = try deriveKEK(pin: pin, salt: salt, iterations: max(100_000, envelope.kdfIterations))
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: kek)
        } catch {
            throw NoteCryptoError.invalidPin
        }
    }

    /// Encrypts a document's blocks to an opaque Base64 AES-256-GCM payload.
    public static func encryptBlocks(_ blocks: [Block], with vaultKey: Data) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(blocks)
        let key = SymmetricKey(data: vaultKey)
        guard let sealed = try? AES.GCM.seal(plaintext, using: key),
              let combined = sealed.combined else {
            throw NoteCryptoError.encryptionFailed
        }
        return combined.base64EncodedString()
    }

    /// Decrypts an opaque Base64 AES-256-GCM payload back into `[Block]`.
    public static func decryptBlocks(from base64Ciphertext: String, with vaultKey: Data) throws -> [Block] {
        guard let combined = Data(base64Encoded: base64Ciphertext) else {
            throw NoteCryptoError.decryptionFailed
        }
        let key = SymmetricKey(data: vaultKey)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Block].self, from: plaintext)
        } catch {
            throw NoteCryptoError.decryptionFailed
        }
    }

    /// RFC 2898 PBKDF2-HMAC-SHA256 using Apple CommonCrypto.
    private static func deriveKEK(pin: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pinData = Data(pin.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                pinData.withUnsafeBytes { pinPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinPtr.bindMemory(to: Int8.self).baseAddress,
                        pinData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw NoteCryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}

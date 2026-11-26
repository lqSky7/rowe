import Foundation

public struct AuthUser: Codable, Hashable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String
    public let avatarBase64: String?
    public let avatarMime: String?

    public init(id: String, email: String, displayName: String, avatarBase64: String? = nil, avatarMime: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarBase64 = avatarBase64
        self.avatarMime = avatarMime
    }
}

public struct AuthSession: Codable, Hashable, Sendable {
    public var serverURL: String
    public var accessToken: String
    public var refreshToken: String
    public var user: AuthUser

    public init(serverURL: String, accessToken: String, refreshToken: String, user: AuthUser) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

public struct AuthAPIResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int64
    public let user: AuthUser
    public let vault: VaultKeyEnvelope?
}

public struct SyncDocumentDTO: Codable, Sendable {
    public var id: String
    public var spaceId: String
    public var folderId: String?
    public var title: String
    public var isLocked: Bool
    public var payloadJson: String?
    public var encryptedPayload: String?
    public var isStarred: Bool
    public var isTrashed: Bool
    public var version: Int64
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(
        id: String,
        spaceId: String,
        folderId: String? = nil,
        title: String,
        isLocked: Bool,
        payloadJson: String? = nil,
        encryptedPayload: String? = nil,
        isStarred: Bool = false,
        isTrashed: Bool = false,
        version: Int64 = 1,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.folderId = folderId
        self.title = title
        self.isLocked = isLocked
        self.payloadJson = payloadJson
        self.encryptedPayload = encryptedPayload
        self.isStarred = isStarred
        self.isTrashed = isTrashed
        self.version = version
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct SyncBatchResponse: Codable, Sendable {
    public let serverTime: Int64
    public let documents: [SyncDocumentDTO]
}

public enum BackendError: Error, LocalizedError, Sendable {
    case invalidURL
    case serverError(String)
    case unauthorized
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .serverError(let msg): msg
        case .unauthorized: "Session expired — please sign in again"
        case .decodingFailed: "Unexpected response from server"
        }
    }
}

/// Async HTTP client for RoweServer (Auth, Zero-Knowledge Vault Envelope, and Delta Sync).
public actor RoweBackendClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    private var platformDeviceName: String {
        #if os(iOS)
        return "Rowe iOS"
        #else
        return "Rowe macOS"
        #endif
    }

    public func register(serverURL: String, email: String, password: String, displayName: String) async throws -> AuthAPIResponse {
        struct Body: Encodable {
            let email: String
            let password: String
            let displayName: String
            let device: String
        }
        return try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/register",
            method: "POST",
            bearer: nil,
            body: Body(email: email, password: password, displayName: displayName, device: platformDeviceName)
        )
    }

    public func login(serverURL: String, email: String, password: String) async throws -> AuthAPIResponse {
        struct Body: Encodable {
            let email: String
            let password: String
            let device: String
        }
        return try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/login",
            method: "POST",
            bearer: nil,
            body: Body(email: email, password: password, device: platformDeviceName)
        )
    }

    public func refresh(serverURL: String, refreshToken: String) async throws -> AuthAPIResponse {
        struct Body: Encodable {
            let refreshToken: String
            let device: String
        }
        return try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/refresh",
            method: "POST",
            bearer: nil,
            body: Body(refreshToken: refreshToken, device: platformDeviceName)
        )
    }

    public func me(serverURL: String, accessToken: String) async throws -> (user: AuthUser, vault: VaultKeyEnvelope?) {
        struct Resp: Decodable {
            let user: AuthUser
            let vault: VaultKeyEnvelope?
        }
        let resp: Resp = try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/me",
            method: "GET",
            bearer: accessToken,
            body: Optional<String>.none
        )
        return (resp.user, resp.vault)
    }

    public func updateAvatar(serverURL: String, accessToken: String, avatarBase64: String) async throws -> AuthUser {
        struct Body: Encodable { let avatarBase64: String }
        struct Resp: Decodable { let user: AuthUser }
        let resp: Resp = try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/avatar",
            method: "PUT",
            bearer: accessToken,
            body: Body(avatarBase64: avatarBase64)
        )
        return resp.user
    }

    public func deleteAvatar(serverURL: String, accessToken: String) async throws -> AuthUser {
        struct Resp: Decodable { let user: AuthUser }
        let resp: Resp = try await request(
            serverURL: serverURL,
            path: "/api/v1/auth/avatar",
            method: "DELETE",
            bearer: accessToken,
            body: Optional<String>.none
        )
        return resp.user
    }

    public func logout(serverURL: String, refreshToken: String) async {
        struct Body: Encodable { let refreshToken: String }
        struct Ack: Decodable { let ok: Bool }
        let _: Ack? = try? await request(
            serverURL: serverURL,
            path: "/api/v1/auth/logout",
            method: "POST",
            bearer: nil,
            body: Body(refreshToken: refreshToken)
        )
    }

    public func putVault(serverURL: String, accessToken: String, envelope: VaultKeyEnvelope) async throws -> VaultKeyEnvelope? {
        struct Resp: Decodable { let vault: VaultKeyEnvelope? }
        let resp: Resp = try await request(
            serverURL: serverURL,
            path: "/api/v1/vault",
            method: "PUT",
            bearer: accessToken,
            body: envelope
        )
        return resp.vault
    }

    public func getVault(serverURL: String, accessToken: String) async throws -> VaultKeyEnvelope? {
        struct Resp: Decodable { let vault: VaultKeyEnvelope? }
        let resp: Resp = try await request(
            serverURL: serverURL,
            path: "/api/v1/vault",
            method: "GET",
            bearer: accessToken,
            body: Optional<String>.none
        )
        return resp.vault
    }

    public func syncPush(serverURL: String, accessToken: String, documents: [SyncDocumentDTO]) async throws -> SyncBatchResponse {
        struct Body: Encodable { let documents: [SyncDocumentDTO] }
        return try await request(
            serverURL: serverURL,
            path: "/api/v1/sync/push",
            method: "POST",
            bearer: accessToken,
            body: Body(documents: documents)
        )
    }

    public func syncPull(serverURL: String, accessToken: String, sinceMs: Int64 = 0) async throws -> SyncBatchResponse {
        return try await request(
            serverURL: serverURL,
            path: "/api/v1/sync/pull?since=\(sinceMs)",
            method: "GET",
            bearer: accessToken,
            body: Optional<String>.none
        )
    }

    public func deleteDocument(serverURL: String, accessToken: String, id: String) async throws {
        struct Ack: Decodable { let ok: Bool }
        guard let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw BackendError.invalidURL
        }
        let _: Ack = try await request(
            serverURL: serverURL,
            path: "/api/v1/documents/\(encodedId)",
            method: "DELETE",
            bearer: accessToken,
            body: Optional<String>.none
        )
    }

    public static func normalizeServerURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.isEmpty && !trimmed.contains("://") {
            let isLocal = trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1")
            trimmed = (isLocal ? "http://" : "https://") + trimmed
        }
        return trimmed
    }

    // MARK: - Transport

    private func request<Body: Encodable, Resp: Decodable>(
        serverURL: String,
        path: String,
        method: String,
        bearer: String?,
        body: Body?
    ) async throws -> Resp {
        let base = Self.normalizeServerURL(serverURL)
        guard !base.isEmpty, let url = URL(string: base + path) else { throw BackendError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.serverError("No HTTP response")
        }

        if http.statusCode == 401 {
            throw BackendError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            if let errObj = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = errObj["error"] {
                throw BackendError.serverError(msg)
            }
            throw BackendError.serverError("Server returned status \(http.statusCode)")
        }

        do {
            return try decoder.decode(Resp.self, from: data)
        } catch {
            throw BackendError.decodingFailed
        }
    }
}

import Foundation

public enum ConnectionKind: String, Codable, CaseIterable, Sendable {
    case mcp = "MCP"
    case api = "API"
}

public enum ConnectionPermission: String, Codable, CaseIterable, Sendable {
    case readOnly = "Read Only"
    case readAndWrite = "Read and Write"
}

public enum ConnectionAccessMode: String, Codable, CaseIterable, Sendable {
    case publicAccess = "Public"
    case tokenRequired = "Token Required"
    case localOnly = "Local Only"
}

public enum ConnectionDocumentScope: String, Codable, CaseIterable, Sendable {
    case allDocuments = "All Documents"
    case dailyNotesAndTasks = "Tasks Only"
    case selectedFolders = "Selected Folders"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "All Daily Notes and Tasks" {
            self = .dailyNotesAndTasks
        } else if let scope = Self(rawValue: rawValue) {
            self = scope
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown connection document scope: \(rawValue)")
        }
    }
}

public struct ConnectionItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: ConnectionKind
    public var name: String
    public var endpointURL: String
    public var documentScope: ConnectionDocumentScope
    public var permission: ConnectionPermission
    public var accessMode: ConnectionAccessMode
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: ConnectionKind,
        name: String,
        endpointURL: String,
        documentScope: ConnectionDocumentScope = .allDocuments,
        permission: ConnectionPermission = .readAndWrite,
        accessMode: ConnectionAccessMode = .publicAccess,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.endpointURL = endpointURL
        self.documentScope = documentScope
        self.permission = permission
        self.accessMode = accessMode
        self.createdAt = createdAt
    }
}

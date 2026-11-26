import Foundation

public struct Space: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var authorName: String
    public var email: String
    public var bio: String
    public var avatarSymbol: String
    public var avatarImageBase64: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        authorName: String = "Owner",
        email: String = "",
        bio: String = "",
        avatarSymbol: String = "sparkles",
        avatarImageBase64: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.authorName = authorName
        self.email = email
        self.bio = bio
        self.avatarSymbol = avatarSymbol
        self.avatarImageBase64 = avatarImageBase64
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Space"
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? "Owner"
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        avatarSymbol = try c.decodeIfPresent(String.self, forKey: .avatarSymbol) ?? "sparkles"
        avatarImageBase64 = try c.decodeIfPresent(String.self, forKey: .avatarImageBase64)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct Folder: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var iconName: String
    public var parentId: String?
    public var sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        spaceId: String,
        name: String,
        iconName: String = "folder",
        parentId: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.spaceId = spaceId
        self.name = name
        self.iconName = iconName
        self.parentId = parentId
        self.sortOrder = sortOrder
    }
}

public struct TagItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var isPinned: Bool
    public var colorHex: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        isPinned: Bool = false,
        colorHex: String = "#6E7681"
    ) {
        self.id = id
        self.name = name
        self.isPinned = isPinned
        self.colorHex = colorHex
    }
}

public enum SidebarSectionType: String, Codable, CaseIterable, Sendable {
    case starred
    case folders
    case tags
}

public struct SidebarSectionState: Codable, Hashable, Sendable {
    public var type: SidebarSectionType
    public var isVisible: Bool
    public var isCollapsed: Bool

    public init(type: SidebarSectionType, isVisible: Bool = true, isCollapsed: Bool = false) {
        self.type = type
        self.isVisible = isVisible
        self.isCollapsed = isCollapsed
    }
}

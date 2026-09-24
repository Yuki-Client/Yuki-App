import Foundation

public struct Server: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var owner: String
    public var name: String
    public var description: String?
    public var channels: [String]
    public var categories: [ServerCategory]?
    public var systemMessages: SystemMessageChannels?
    public var roles: [String: Role]
    public var defaultPermissions: Int64
    public var icon: Attachment?
    public var banner: Attachment?
    public var flags: Int
    public var nsfw: Bool
    public var discoverable: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case owner
        case name
        case description
        case channels
        case categories
        case systemMessages = "system_messages"
        case roles
        case defaultPermissions = "default_permissions"
        case icon
        case banner
        case flags
        case nsfw
        case discoverable
    }

    public init(
        id: String,
        owner: String,
        name: String,
        description: String? = nil,
        channels: [String] = [],
        categories: [ServerCategory]? = nil,
        systemMessages: SystemMessageChannels? = nil,
        roles: [String: Role] = [:],
        defaultPermissions: Int64 = 0,
        icon: Attachment? = nil,
        banner: Attachment? = nil,
        flags: Int = 0,
        nsfw: Bool = false,
        discoverable: Bool = false
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.description = description
        self.channels = channels
        self.categories = categories
        self.systemMessages = systemMessages
        self.roles = roles
        self.defaultPermissions = defaultPermissions
        self.icon = icon
        self.banner = banner
        self.flags = flags
        self.nsfw = nsfw
        self.discoverable = discoverable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        owner = try c.decode(String.self, forKey: .owner)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        channels = try c.decodeIfPresent([String].self, forKey: .channels) ?? []
        categories = try c.decodeIfPresent([ServerCategory].self, forKey: .categories)
        systemMessages = try c.decodeIfPresent(SystemMessageChannels.self, forKey: .systemMessages)
        roles = try c.decodeIfPresent([String: Role].self, forKey: .roles) ?? [:]
        defaultPermissions = try c.decodeIfPresent(Int64.self, forKey: .defaultPermissions) ?? 0
        icon = try c.decodeIfPresent(Attachment.self, forKey: .icon)
        banner = try c.decodeIfPresent(Attachment.self, forKey: .banner)
        flags = try c.decodeIfPresent(Int.self, forKey: .flags) ?? 0
        nsfw = try c.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false
        discoverable = try c.decodeIfPresent(Bool.self, forKey: .discoverable) ?? false
    }

    public var initials: String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words.prefix(2).compactMap { $0.first }).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    public var isVerified: Bool { flags & 1 != 0 }
    public var isOfficial: Bool { flags & 2 != 0 }
}

public struct ServerCategory: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var channels: [String]

    public init(id: String, title: String, channels: [String]) {
        self.id = id
        self.title = title
        self.channels = channels
    }
}

public struct SystemMessageChannels: Codable, Sendable, Hashable {
    public var userJoined: String?
    public var userLeft: String?
    public var userKicked: String?
    public var userBanned: String?

    enum CodingKeys: String, CodingKey {
        case userJoined = "user_joined"
        case userLeft = "user_left"
        case userKicked = "user_kicked"
        case userBanned = "user_banned"
    }

    public init(userJoined: String? = nil, userLeft: String? = nil, userKicked: String? = nil, userBanned: String? = nil) {
        self.userJoined = userJoined
        self.userLeft = userLeft
        self.userKicked = userKicked
        self.userBanned = userBanned
    }

    public var isEmpty: Bool {
        userJoined == nil && userLeft == nil && userKicked == nil && userBanned == nil
    }
}

public struct Role: Codable, Sendable, Hashable {
    public var name: String
    public var permissions: RolePermissions
    public var colour: String?
    public var hoist: Bool
    public var rank: Int64
    public var icon: Attachment?

    enum CodingKeys: String, CodingKey {
        case name, permissions, colour, hoist, rank, icon
    }

    public init(
        name: String,
        permissions: RolePermissions = RolePermissions(),
        colour: String? = nil,
        hoist: Bool = false,
        rank: Int64 = 0,
        icon: Attachment? = nil
    ) {
        self.name = name
        self.permissions = permissions
        self.colour = colour
        self.hoist = hoist
        self.rank = rank
        self.icon = icon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        permissions = try c.decodeIfPresent(RolePermissions.self, forKey: .permissions) ?? RolePermissions()
        colour = try c.decodeIfPresent(String.self, forKey: .colour)
        hoist = try c.decodeIfPresent(Bool.self, forKey: .hoist) ?? false
        rank = try c.decodeIfPresent(Int64.self, forKey: .rank) ?? 0
        icon = try c.decodeIfPresent(Attachment.self, forKey: .icon)
    }
}

public struct RolePermissions: Codable, Sendable, Hashable {
    public var a: Int64
    public var d: Int64

    public init(a: Int64 = 0, d: Int64 = 0) {
        self.a = a
        self.d = d
    }
}

public struct ServerMemberId: Codable, Sendable, Hashable {
    public let server: String
    public let user: String

    public init(server: String, user: String) {
        self.server = server
        self.user = user
    }
}

public struct ServerMember: Codable, Identifiable, Sendable, Hashable {
    public var id: String { "\(key.server):\(key.user)" }
    public let key: ServerMemberId
    public var joinedAt: String?
    public var nickname: String?
    public var pronouns: String?
    public var avatar: Attachment?
    public var roles: [String]
    public var timeout: String?
    public var canPublish: Bool
    public var canReceive: Bool

    enum CodingKeys: String, CodingKey {
        case key = "_id"
        case joinedAt = "joined_at"
        case nickname
        case pronouns
        case avatar
        case roles
        case timeout
        case canPublish = "can_publish"
        case canReceive = "can_receive"
    }

    public init(
        key: ServerMemberId,
        joinedAt: String? = nil,
        nickname: String? = nil,
        pronouns: String? = nil,
        avatar: Attachment? = nil,
        roles: [String] = [],
        timeout: String? = nil,
        canPublish: Bool = true,
        canReceive: Bool = true
    ) {
        self.key = key
        self.joinedAt = joinedAt
        self.nickname = nickname
        self.pronouns = pronouns
        self.avatar = avatar
        self.roles = roles
        self.timeout = timeout
        self.canPublish = canPublish
        self.canReceive = canReceive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(ServerMemberId.self, forKey: .key)
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        pronouns = try c.decodeIfPresent(String.self, forKey: .pronouns)
        avatar = try c.decodeIfPresent(Attachment.self, forKey: .avatar)
        roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? []
        timeout = try c.decodeIfPresent(String.self, forKey: .timeout)
        canPublish = try c.decodeIfPresent(Bool.self, forKey: .canPublish) ?? true
        canReceive = try c.decodeIfPresent(Bool.self, forKey: .canReceive) ?? true
    }

    public var activeTimeout: Date? {
        guard let timeout, let date = StoatDate.parse(timeout), date > Date() else { return nil }
        return date
    }
}

public struct ServerBan: Decodable, Sendable, Hashable, Identifiable {
    public var id: String { key.user }
    public let key: ServerMemberId
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case key = "_id"
        case reason
    }
}

public struct ServerBansResponse: Decodable, Sendable {
    public let users: [BannedUser]
    public let bans: [ServerBan]
}

public struct BannedUser: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let username: String
    public let discriminator: String?
    public let avatar: Attachment?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username, discriminator, avatar
    }
}

/// ISO 8601 timestamps as sent by the API (with or without fractional seconds).
public enum StoatDate {
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

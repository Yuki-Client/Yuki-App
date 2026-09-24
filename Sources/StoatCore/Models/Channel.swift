import Foundation

public enum ChannelType: String, Codable, Sendable, Hashable {
    case textChannel = "TextChannel"
    case voiceChannel = "VoiceChannel"
    case directMessage = "DirectMessage"
    case group = "Group"
    case savedMessages = "SavedMessages"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ChannelType(rawValue: value) ?? .unknown
    }
}

public struct Channel: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let channelType: ChannelType
    public let server: String?
    /// Owner of a saved messages channel.
    public let user: String?
    public var name: String?
    public var owner: String?
    public var description: String?
    public var icon: Attachment?
    public var lastMessageId: String?
    public var recipients: [String]?
    public var active: Bool?
    public var nsfw: Bool
    /// Group-wide permission value (groups only).
    public var permissions: Int64?
    public var defaultPermissions: RolePermissions?
    public var rolePermissions: [String: RolePermissions]
    public var voice: VoiceInformation?
    public var slowmode: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case channelType = "channel_type"
        case server
        case user
        case name
        case owner
        case description
        case icon
        case lastMessageId = "last_message_id"
        case recipients
        case active
        case nsfw
        case permissions
        case defaultPermissions = "default_permissions"
        case rolePermissions = "role_permissions"
        case voice
        case slowmode
    }

    public init(
        id: String,
        channelType: ChannelType,
        server: String? = nil,
        user: String? = nil,
        name: String? = nil,
        owner: String? = nil,
        description: String? = nil,
        icon: Attachment? = nil,
        lastMessageId: String? = nil,
        recipients: [String]? = nil,
        active: Bool? = nil,
        nsfw: Bool = false,
        permissions: Int64? = nil,
        defaultPermissions: RolePermissions? = nil,
        rolePermissions: [String: RolePermissions] = [:],
        voice: VoiceInformation? = nil,
        slowmode: Int? = nil
    ) {
        self.id = id
        self.channelType = channelType
        self.server = server
        self.user = user
        self.name = name
        self.owner = owner
        self.description = description
        self.icon = icon
        self.lastMessageId = lastMessageId
        self.recipients = recipients
        self.active = active
        self.nsfw = nsfw
        self.permissions = permissions
        self.defaultPermissions = defaultPermissions
        self.rolePermissions = rolePermissions
        self.voice = voice
        self.slowmode = slowmode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        channelType = try c.decode(ChannelType.self, forKey: .channelType)
        server = try c.decodeIfPresent(String.self, forKey: .server)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(Attachment.self, forKey: .icon)
        lastMessageId = try c.decodeIfPresent(String.self, forKey: .lastMessageId)
        recipients = try c.decodeIfPresent([String].self, forKey: .recipients)
        active = try c.decodeIfPresent(Bool.self, forKey: .active)
        nsfw = try c.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false
        permissions = try c.decodeIfPresent(Int64.self, forKey: .permissions)
        defaultPermissions = try c.decodeIfPresent(RolePermissions.self, forKey: .defaultPermissions)
        rolePermissions = try c.decodeIfPresent([String: RolePermissions].self, forKey: .rolePermissions) ?? [:]
        voice = try c.decodeIfPresent(VoiceInformation.self, forKey: .voice)
        slowmode = try c.decodeIfPresent(Int.self, forKey: .slowmode)
    }

    public var isTextBased: Bool {
        channelType != .voiceChannel && channelType != .unknown
    }

    /// Whether this server channel hosts voice (legacy voice channels, or text channels with voice enabled).
    public var supportsVoice: Bool {
        channelType == .voiceChannel || voice != nil
    }

    public var isPrivate: Bool {
        channelType == .directMessage || channelType == .group || channelType == .savedMessages
    }

    public func otherRecipient(currentUserId: String?) -> String? {
        recipients?.first(where: { $0 != currentUserId }) ?? recipients?.first
    }

    public func displayName(withUsers users: [String: User] = [:], currentUserId: String? = nil) -> String {
        switch channelType {
        case .savedMessages:
            return "Saved Notes"
        case .directMessage:
            if let otherId = otherRecipient(currentUserId: currentUserId) {
                return users[otherId]?.visibleName ?? "Direct Message"
            }
            return "Direct Message"
        case .group:
            if let name, !name.isEmpty { return name }
            let memberNames = (recipients ?? [])
                .filter { $0 != currentUserId }
                .compactMap { users[$0]?.visibleName }
            return memberNames.isEmpty ? "Group" : memberNames.joined(separator: ", ")
        default:
            if let name, !name.isEmpty { return name }
            return "Channel"
        }
    }
}

public struct VoiceInformation: Codable, Sendable, Hashable {
    public let maxUsers: Int?

    enum CodingKeys: String, CodingKey {
        case maxUsers = "max_users"
    }

    public init(maxUsers: Int? = nil) {
        self.maxUsers = maxUsers
    }
}

/// Read state for a channel, as returned by `/sync/unreads`.
public struct ChannelUnread: Codable, Sendable, Hashable {
    public struct Key: Codable, Sendable, Hashable {
        public let channel: String
        public let user: String
    }

    public let id: Key
    public var lastId: String?
    public var mentions: [String]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case lastId = "last_id"
        case mentions
    }

    public init(channel: String, user: String, lastId: String? = nil, mentions: [String] = []) {
        self.id = Key(channel: channel, user: user)
        self.lastId = lastId
        self.mentions = mentions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Key.self, forKey: .id)
        lastId = try c.decodeIfPresent(String.self, forKey: .lastId)
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions) ?? []
    }
}

public struct UserVoiceState: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var isReceiving: Bool
    public var isPublishing: Bool
    public var screensharing: Bool
    public var camera: Bool
    /// When they joined the call (ISO 8601), if Stoat said.
    public var joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case joinedAt = "joined_at"
        case isReceiving = "is_receiving"
        case isPublishing = "is_publishing"
        case screensharing
        case camera
    }

    public init(id: String, isReceiving: Bool = true, isPublishing: Bool = false, screensharing: Bool = false, camera: Bool = false) {
        self.id = id
        self.isReceiving = isReceiving
        self.isPublishing = isPublishing
        self.screensharing = screensharing
        self.camera = camera
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        isReceiving = try c.decodeIfPresent(Bool.self, forKey: .isReceiving) ?? true
        isPublishing = try c.decodeIfPresent(Bool.self, forKey: .isPublishing) ?? false
        screensharing = try c.decodeIfPresent(Bool.self, forKey: .screensharing) ?? false
        camera = try c.decodeIfPresent(Bool.self, forKey: .camera) ?? false
        joinedAt = try? c.decodeIfPresent(String.self, forKey: .joinedAt)
    }
}

public struct ChannelVoiceState: Codable, Sendable, Hashable {
    public let id: String
    public let participants: [UserVoiceState]
}

/// Public preview of an invite, from `GET /invites/:code`.
public struct InvitePreview: Decodable, Sendable, Hashable {
    public let type: String
    public let code: String
    public let serverId: String?
    public let serverName: String?
    public let serverIcon: Attachment?
    public let serverBanner: Attachment?
    public let channelId: String
    public let channelName: String
    public let channelDescription: String?
    public let userName: String
    public let userAvatar: Attachment?
    public let memberCount: Int?

    enum CodingKeys: String, CodingKey {
        case type, code
        case serverId = "server_id"
        case serverName = "server_name"
        case serverIcon = "server_icon"
        case serverBanner = "server_banner"
        case channelId = "channel_id"
        case channelName = "channel_name"
        case channelDescription = "channel_description"
        case userName = "user_name"
        case userAvatar = "user_avatar"
        case memberCount = "member_count"
    }
}

/// An invite as stored by the server (`POST /channels/:id/invites`, `GET /servers/:id/invites`).
public struct Invite: Decodable, Identifiable, Sendable, Hashable {
    public var id: String { code }
    public let type: String
    public let code: String
    public let server: String?
    public let creator: String
    public let channel: String

    enum CodingKeys: String, CodingKey {
        case type
        case code = "_id"
        case server, creator, channel
    }
}

extension Channel {
    public static func slowmodeLabel(_ seconds: Int) -> String {
        if seconds <= 0 { return "Off" }
        if seconds < 60 { return seconds == 1 ? "1 second" : "\(seconds) seconds" }
        if seconds < 3600 { return seconds < 120 ? "1 minute" : "\(seconds / 60) minutes" }
        return seconds < 7200 ? "1 hour" : "\(seconds / 3600) hours"
    }
}

public struct ChannelSlowmode: Decodable, Sendable, Hashable {
    public let channelId: String
    public let duration: Int
    public let retryAfter: Int

    enum CodingKeys: String, CodingKey {
        case duration
        case channelId = "channel_id"
        case retryAfter = "retry_after"
    }
}

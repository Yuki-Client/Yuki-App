import Foundation

/// Shapes follow `EventV1` in stoatchat/crates/core/database/src/events/client.rs.
public enum GatewayEvent: Sendable {
    case authenticated
    case logout
    case error(String)
    case pong(data: Int?)
    case bulk([GatewayEvent])
    case ready(ReadyPayload)

    case message(Message)
    case messageUpdate(id: String, channel: String, data: PartialMessage, clear: [String])
    case messageAppend(id: String, channel: String, embeds: [Embed])
    case messageDelete(id: String, channel: String)
    case messageReact(id: String, channel: String, userId: String, emoji: String)
    case messageUnreact(id: String, channel: String, userId: String, emoji: String)
    case messageRemoveReaction(id: String, channel: String, emoji: String)
    case bulkMessageDelete(channel: String, ids: [String])

    case serverCreate(server: Server, channels: [Channel], emojis: [Emoji])
    case serverUpdate(id: String, data: PartialServer, clear: [String])
    case serverDelete(id: String)
    case serverMemberUpdate(id: ServerMemberId, data: PartialMember, clear: [String])
    case serverMemberJoin(serverId: String, userId: String, member: ServerMember?)
    case serverMemberLeave(serverId: String, userId: String)
    case serverRoleUpdate(serverId: String, roleId: String, data: PartialRole, clear: [String])
    case serverRoleDelete(serverId: String, roleId: String)
    case serverRoleRanksUpdate(serverId: String, ranks: [String])

    case userUpdate(id: String, data: PartialUser, clear: [String])
    case userRelationship(user: User)
    case userSettingsUpdate(update: [String: SyncedSetting])
    case userPlatformWipe(userId: String, flags: Int)

    case emojiCreate(Emoji)
    case emojiUpdate(id: String, name: String?)
    case emojiDelete(id: String)

    case channelCreate(Channel)
    case channelUpdate(id: String, data: PartialChannel, clear: [String])
    case channelDelete(channelId: String)
    case channelGroupJoin(channelId: String, userId: String)
    case channelGroupLeave(channelId: String, userId: String)
    case channelStartTyping(channelId: String, userId: String)
    case channelStopTyping(channelId: String, userId: String)
    case channelAck(channelId: String, userId: String, messageId: String)

    case voiceChannelJoin(channelId: String, state: UserVoiceState)
    case voiceChannelLeave(channelId: String, userId: String)
    case voiceChannelMove(userId: String, from: String, to: String, state: UserVoiceState)
    case userVoiceStateUpdate(userId: String, channelId: String, data: PartialUserVoiceState)
    /// A call in a DM or group started (ringing the people in it) or ended.
    case voiceCallUpdate(initiatorId: String, channelId: String, ended: Bool)
    case userSlowmodes([ChannelSlowmode])

    case unknown(type: String)
}

public struct ReadyPayload: Decodable, Sendable {
    public let users: [User]
    public let servers: [Server]
    public let channels: [Channel]
    public let members: [ServerMember]
    public let emojis: [Emoji]
    public let voiceStates: [ChannelVoiceState]
    public let policyChanges: [PolicyChange]

    enum CodingKeys: String, CodingKey {
        case users, servers, channels, members, emojis
        case voiceStates = "voice_states"
        case policyChanges = "policy_changes"
    }

    public init(
        users: [User] = [],
        servers: [Server] = [],
        channels: [Channel] = [],
        members: [ServerMember] = [],
        emojis: [Emoji] = [],
        voiceStates: [ChannelVoiceState] = [],
        policyChanges: [PolicyChange] = []
    ) {
        self.users = users
        self.servers = servers
        self.channels = channels
        self.members = members
        self.emojis = emojis
        self.voiceStates = voiceStates
        self.policyChanges = policyChanges
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users = try c.decodeLossyArray(User.self, forKey: .users) ?? []
        servers = try c.decodeLossyArray(Server.self, forKey: .servers) ?? []
        channels = try c.decodeLossyArray(Channel.self, forKey: .channels) ?? []
        members = try c.decodeLossyArray(ServerMember.self, forKey: .members) ?? []
        emojis = try c.decodeLossyArray(Emoji.self, forKey: .emojis) ?? []
        voiceStates = try c.decodeLossyArray(ChannelVoiceState.self, forKey: .voiceStates) ?? []
        policyChanges = try c.decodeLossyArray(PolicyChange.self, forKey: .policyChanges) ?? []
    }
}

public struct PolicyChange: Codable, Sendable, Hashable {
    public let createdTime: String?
    public let effectiveTime: String?
    public let description: String
    public let url: String

    enum CodingKeys: String, CodingKey {
        case createdTime = "created_time"
        case effectiveTime = "effective_time"
        case description, url
    }
}

// MARK: - Partial objects

public struct PartialMessage: Decodable, Sendable {
    public let content: String?
    public let edited: String?
    public let pinned: Bool?
    public let embeds: [Embed]?
    public let reactions: [String: [String]]?

    public init(content: String? = nil, edited: String? = nil, pinned: Bool? = nil, embeds: [Embed]? = nil, reactions: [String: [String]]? = nil) {
        self.content = content
        self.edited = edited
        self.pinned = pinned
        self.embeds = embeds
        self.reactions = reactions
    }

    enum CodingKeys: String, CodingKey {
        case content, edited, pinned, embeds, reactions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        edited = try c.decodeIfPresent(String.self, forKey: .edited)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned)
        embeds = try c.decodeLossyArray(Embed.self, forKey: .embeds)
        reactions = try? c.decodeIfPresent([String: [String]].self, forKey: .reactions)
    }
}

public struct PartialChannel: Decodable, Sendable {
    public let name: String?
    public let owner: String?
    public let description: String?
    public let icon: Attachment?
    public let nsfw: Bool?
    public let active: Bool?
    public let permissions: Int64?
    public let rolePermissions: [String: RolePermissions]?
    public let defaultPermissions: RolePermissions?
    public let lastMessageId: String?
    public let voice: VoiceInformation?
    public let slowmode: Int?

    enum CodingKeys: String, CodingKey {
        case name, owner, description, icon, nsfw, active, permissions, voice, slowmode
        case rolePermissions = "role_permissions"
        case defaultPermissions = "default_permissions"
        case lastMessageId = "last_message_id"
    }
}

public struct PartialServer: Decodable, Sendable {
    public let owner: String?
    public let name: String?
    public let description: String?
    public let channels: [String]?
    public let categories: [ServerCategory]?
    public let systemMessages: SystemMessageChannels?
    public let roles: [String: Role]?
    public let defaultPermissions: Int64?
    public let icon: Attachment?
    public let banner: Attachment?
    public let flags: Int?
    public let nsfw: Bool?
    public let discoverable: Bool?

    enum CodingKeys: String, CodingKey {
        case owner, name, description, channels, categories, roles, icon, banner, flags, nsfw, discoverable
        case systemMessages = "system_messages"
        case defaultPermissions = "default_permissions"
    }
}

public struct PartialMember: Decodable, Sendable {
    public let joinedAt: String?
    public let nickname: String?
    public let pronouns: String?
    public let avatar: Attachment?
    public let roles: [String]?
    public let timeout: String?
    public let canPublish: Bool?
    public let canReceive: Bool?

    enum CodingKeys: String, CodingKey {
        case nickname, pronouns, avatar, roles, timeout
        case joinedAt = "joined_at"
        case canPublish = "can_publish"
        case canReceive = "can_receive"
    }
}

public struct PartialRole: Decodable, Sendable {
    public let name: String?
    public let permissions: RolePermissions?
    public let colour: String?
    public let hoist: Bool?
    public let rank: Int64?
    public let icon: Attachment?
}

public struct PartialUser: Decodable, Sendable {
    public let username: String?
    public let discriminator: String?
    public let displayName: String?
    public let pronouns: String?
    public let avatar: Attachment?
    public let badges: Int?
    public let status: UserStatus?
    public let flags: Int?
    public let privileged: Bool?
    public let bot: BotDetails?
    public let relationship: RelationshipStatus?
    public let online: Bool?

    enum CodingKeys: String, CodingKey {
        case username, discriminator, pronouns, avatar, badges, status, flags, privileged, bot, relationship, online
        case displayName = "display_name"
    }
}

public struct PartialUserVoiceState: Decodable, Sendable {
    public let isReceiving: Bool?
    public let isPublishing: Bool?
    public let screensharing: Bool?
    public let camera: Bool?

    enum CodingKeys: String, CodingKey {
        case isReceiving = "is_receiving"
        case isPublishing = "is_publishing"
        case screensharing, camera
    }
}

// MARK: - Decoding

extension GatewayEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, id, channel, data, clear, append, user, member, server, channels, emojis, ids, v
        case channelId = "channel_id"
        case userId = "user_id"
        case emojiId = "emoji_id"
        case messageId = "message_id"
        case roleId = "role_id"
        case ranks, flags, state, from, to, update, slowmodes, ended
        case initiatorId = "initiator_id"
    }

    private struct ErrorPayload: Decodable {
        let type: String
    }

    private struct AppendPayload: Decodable {
        let embeds: [Embed]?
    }

    private struct NamePayload: Decodable {
        let name: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()

        func str(_ key: CodingKeys) throws -> String { try c.decode(String.self, forKey: key) }
        func clear() -> [String] { (try? c.decodeIfPresent([String].self, forKey: .clear)) ?? [] }

        switch type {
        case "Authenticated":
            self = .authenticated
        case "Logout":
            self = .logout
        case "Error":
            if let payload = try? c.decode(ErrorPayload.self, forKey: .data) {
                self = .error(payload.type)
            } else {
                self = .error((try? c.decode(String.self, forKey: .data)) ?? "Unknown")
            }
        case "Pong":
            self = .pong(data: try? c.decode(Int.self, forKey: .data))
        case "Bulk":
            self = .bulk(try c.decodeLossyArray(GatewayEvent.self, forKey: .v) ?? [])
        case "Ready":
            self = .ready(try single.decode(ReadyPayload.self))

        case "Message":
            self = .message(try single.decode(Message.self))
        case "MessageUpdate":
            self = .messageUpdate(id: try str(.id), channel: try str(.channel), data: try c.decode(PartialMessage.self, forKey: .data), clear: clear())
        case "MessageAppend":
            let append = try c.decode(AppendPayload.self, forKey: .append)
            self = .messageAppend(id: try str(.id), channel: try str(.channel), embeds: append.embeds ?? [])
        case "MessageDelete":
            self = .messageDelete(id: try str(.id), channel: try str(.channel))
        case "MessageReact":
            self = .messageReact(id: try str(.id), channel: try str(.channelId), userId: try str(.userId), emoji: try str(.emojiId))
        case "MessageUnreact":
            self = .messageUnreact(id: try str(.id), channel: try str(.channelId), userId: try str(.userId), emoji: try str(.emojiId))
        case "MessageRemoveReaction":
            self = .messageRemoveReaction(id: try str(.id), channel: try str(.channelId), emoji: try str(.emojiId))
        case "BulkMessageDelete":
            self = .bulkMessageDelete(channel: try str(.channel), ids: try c.decode([String].self, forKey: .ids))

        case "ServerCreate":
            self = .serverCreate(
                server: try c.decode(Server.self, forKey: .server),
                channels: try c.decodeLossyArray(Channel.self, forKey: .channels) ?? [],
                emojis: try c.decodeLossyArray(Emoji.self, forKey: .emojis) ?? []
            )
        case "ServerUpdate":
            self = .serverUpdate(id: try str(.id), data: try c.decode(PartialServer.self, forKey: .data), clear: clear())
        case "ServerDelete":
            self = .serverDelete(id: try str(.id))
        case "ServerMemberUpdate":
            self = .serverMemberUpdate(id: try c.decode(ServerMemberId.self, forKey: .id), data: try c.decode(PartialMember.self, forKey: .data), clear: clear())
        case "ServerMemberJoin":
            self = .serverMemberJoin(serverId: try str(.id), userId: try str(.user), member: try? c.decodeIfPresent(ServerMember.self, forKey: .member))
        case "ServerMemberLeave":
            self = .serverMemberLeave(serverId: try str(.id), userId: try str(.user))
        case "ServerRoleUpdate":
            self = .serverRoleUpdate(serverId: try str(.id), roleId: try str(.roleId), data: try c.decode(PartialRole.self, forKey: .data), clear: clear())
        case "ServerRoleDelete":
            self = .serverRoleDelete(serverId: try str(.id), roleId: try str(.roleId))
        case "ServerRoleRanksUpdate":
            self = .serverRoleRanksUpdate(serverId: try str(.id), ranks: try c.decode([String].self, forKey: .ranks))

        case "UserUpdate":
            self = .userUpdate(id: try str(.id), data: try c.decode(PartialUser.self, forKey: .data), clear: clear())
        case "UserRelationship":
            self = .userRelationship(user: try c.decode(User.self, forKey: .user))
        case "UserSettingsUpdate":
            self = .userSettingsUpdate(update: (try? c.decode([String: SyncedSetting].self, forKey: .update)) ?? [:])
        case "UserPlatformWipe":
            self = .userPlatformWipe(userId: try str(.userId), flags: (try? c.decode(Int.self, forKey: .flags)) ?? 0)

        case "EmojiCreate":
            self = .emojiCreate(try single.decode(Emoji.self))
        case "EmojiUpdate":
            self = .emojiUpdate(id: try str(.id), name: (try? c.decode(NamePayload.self, forKey: .data))?.name)
        case "EmojiDelete":
            self = .emojiDelete(id: try str(.id))

        case "ChannelCreate":
            self = .channelCreate(try single.decode(Channel.self))
        case "ChannelUpdate":
            self = .channelUpdate(id: try str(.id), data: try c.decode(PartialChannel.self, forKey: .data), clear: clear())
        case "ChannelDelete":
            self = .channelDelete(channelId: try str(.id))
        case "ChannelGroupJoin":
            self = .channelGroupJoin(channelId: try str(.id), userId: try str(.user))
        case "ChannelGroupLeave":
            self = .channelGroupLeave(channelId: try str(.id), userId: try str(.user))
        case "ChannelStartTyping":
            self = .channelStartTyping(channelId: try str(.id), userId: try str(.user))
        case "ChannelStopTyping":
            self = .channelStopTyping(channelId: try str(.id), userId: try str(.user))
        case "ChannelAck":
            self = .channelAck(channelId: try str(.id), userId: try str(.user), messageId: try str(.messageId))

        case "VoiceChannelJoin":
            self = .voiceChannelJoin(channelId: try str(.id), state: try c.decode(UserVoiceState.self, forKey: .state))
        case "VoiceChannelLeave":
            self = .voiceChannelLeave(channelId: try str(.id), userId: try str(.user))
        case "VoiceChannelMove":
            self = .voiceChannelMove(userId: try str(.user), from: try str(.from), to: try str(.to), state: try c.decode(UserVoiceState.self, forKey: .state))
        case "UserVoiceStateUpdate":
            self = .userVoiceStateUpdate(userId: try str(.id), channelId: try str(.channelId), data: try c.decode(PartialUserVoiceState.self, forKey: .data))

        case "VoiceCallUpdate":
            self = .voiceCallUpdate(
                initiatorId: try str(.initiatorId),
                channelId: try str(.channelId),
                ended: try c.decodeIfPresent(Bool.self, forKey: .ended) ?? false
            )

        case "UserSlowmodes":
            self = .userSlowmodes(try c.decodeIfPresent([ChannelSlowmode].self, forKey: .slowmodes) ?? [])

        default:
            self = .unknown(type: type)
        }
    }
}

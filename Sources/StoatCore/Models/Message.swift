import Foundation

public struct Message: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var nonce: String?
    public let channel: String
    public let author: String
    public var webhook: MessageWebhook?
    public var content: String?
    public var system: SystemMessage?
    public var attachments: [Attachment]?
    public var edited: String?
    public var embeds: [Embed]?
    public var mentions: [String]?
    public var roleMentions: [String]?
    public var replies: [String]?
    /// Emoji to ordered list of user IDs who reacted.
    public var reactions: [String: [String]]
    public var interactions: MessageInteractions?
    public var masquerade: Masquerade?
    public var pinned: Bool?
    public var flags: Int

    /// Author and member objects the server may attach to live message events.
    public var user: User?
    public var member: ServerMember?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nonce
        case channel
        case author
        case webhook
        case content
        case system
        case attachments
        case edited
        case embeds
        case mentions
        case roleMentions = "role_mentions"
        case replies
        case reactions
        case interactions
        case masquerade
        case pinned
        case flags
        case user
        case member
    }

    public init(
        id: String,
        nonce: String? = nil,
        channel: String,
        author: String,
        webhook: MessageWebhook? = nil,
        content: String? = nil,
        system: SystemMessage? = nil,
        attachments: [Attachment]? = nil,
        edited: String? = nil,
        embeds: [Embed]? = nil,
        mentions: [String]? = nil,
        roleMentions: [String]? = nil,
        replies: [String]? = nil,
        reactions: [String: [String]] = [:],
        interactions: MessageInteractions? = nil,
        masquerade: Masquerade? = nil,
        pinned: Bool? = nil,
        flags: Int = 0
    ) {
        self.id = id
        self.nonce = nonce
        self.channel = channel
        self.author = author
        self.webhook = webhook
        self.content = content
        self.system = system
        self.attachments = attachments
        self.edited = edited
        self.embeds = embeds
        self.mentions = mentions
        self.roleMentions = roleMentions
        self.replies = replies
        self.reactions = reactions
        self.interactions = interactions
        self.masquerade = masquerade
        self.pinned = pinned
        self.flags = flags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nonce = try c.decodeIfPresent(String.self, forKey: .nonce)
        channel = try c.decode(String.self, forKey: .channel)
        author = try c.decode(String.self, forKey: .author)
        webhook = try? c.decodeIfPresent(MessageWebhook.self, forKey: .webhook)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        system = try? c.decodeIfPresent(SystemMessage.self, forKey: .system)
        attachments = try c.decodeLossyArray(Attachment.self, forKey: .attachments)
        edited = try c.decodeIfPresent(String.self, forKey: .edited)
        embeds = try c.decodeLossyArray(Embed.self, forKey: .embeds)
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions)
        roleMentions = try c.decodeIfPresent([String].self, forKey: .roleMentions)
        replies = try c.decodeIfPresent([String].self, forKey: .replies)
        reactions = try c.decodeIfPresent([String: [String]].self, forKey: .reactions) ?? [:]
        interactions = try? c.decodeIfPresent(MessageInteractions.self, forKey: .interactions)
        masquerade = try? c.decodeIfPresent(Masquerade.self, forKey: .masquerade)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned)
        flags = try c.decodeIfPresent(Int.self, forKey: .flags) ?? 0
        user = try? c.decodeIfPresent(User.self, forKey: .user)
        member = try? c.decodeIfPresent(ServerMember.self, forKey: .member)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(nonce, forKey: .nonce)
        try c.encode(channel, forKey: .channel)
        try c.encode(author, forKey: .author)
        try c.encodeIfPresent(webhook, forKey: .webhook)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(system, forKey: .system)
        try c.encodeIfPresent(attachments, forKey: .attachments)
        try c.encodeIfPresent(edited, forKey: .edited)
        try c.encodeIfPresent(embeds, forKey: .embeds)
        try c.encodeIfPresent(mentions, forKey: .mentions)
        try c.encodeIfPresent(roleMentions, forKey: .roleMentions)
        try c.encodeIfPresent(replies, forKey: .replies)
        if !reactions.isEmpty {
            try c.encode(reactions, forKey: .reactions)
        }
        try c.encodeIfPresent(interactions, forKey: .interactions)
        try c.encodeIfPresent(masquerade, forKey: .masquerade)
        try c.encodeIfPresent(pinned, forKey: .pinned)
        if flags != 0 {
            try c.encode(flags, forKey: .flags)
        }
    }

    /// Stoat IDs are ULIDs: the first 10 Crockford base32 characters encode a millisecond timestamp.
    public var timestamp: Date {
        Message.date(fromULID: id) ?? Date()
    }

    public static func date(fromULID id: String) -> Date? {
        guard id.count >= 10 else { return nil }
        let encoding = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var time: UInt64 = 0
        for char in id.prefix(10).uppercased() {
            guard let index = encoding.firstIndex(of: char) else { return nil }
            time = (time << 5) | UInt64(index)
        }
        return Date(timeIntervalSince1970: Double(time) / 1000.0)
    }

    public var suppressesNotifications: Bool {
        flags & 1 != 0
    }

    public var mentionsEveryone: Bool {
        flags & 2 != 0
    }

    public var mentionsOnline: Bool {
        flags & 4 != 0
    }
}

public struct MessageWebhook: Codable, Sendable, Hashable {
    public let name: String
    public let avatar: String?
}

public struct MessageInteractions: Codable, Sendable, Hashable {
    public let reactions: [String]?
    public let restrictReactions: Bool

    enum CodingKeys: String, CodingKey {
        case reactions
        case restrictReactions = "restrict_reactions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reactions = try c.decodeIfPresent([String].self, forKey: .reactions)
        restrictReactions = try c.decodeIfPresent(Bool.self, forKey: .restrictReactions) ?? false
    }
}

public struct Masquerade: Codable, Sendable, Hashable {
    public let name: String?
    public let avatar: String?
    public let colour: String?

    public init(name: String? = nil, avatar: String? = nil, colour: String? = nil) {
        self.name = name
        self.avatar = avatar
        self.colour = colour
    }
}

public enum SystemMessage: Codable, Sendable, Hashable {
    case text(content: String)
    case userAdded(id: String, by: String)
    case userRemove(id: String, by: String)
    case userJoined(id: String)
    case userLeft(id: String)
    case userKicked(id: String)
    case userBanned(id: String)
    case channelRenamed(name: String, by: String)
    case channelDescriptionChanged(by: String)
    case channelIconChanged(by: String)
    case channelOwnershipChanged(from: String, to: String)
    case messagePinned(id: String, by: String)
    case messageUnpinned(id: String, by: String)
    case callStarted(by: String, finishedAt: String?)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, content, id, by, name, from, to
        case finishedAt = "finished_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        func s(_ key: CodingKeys) throws -> String { try c.decode(String.self, forKey: key) }
        switch type {
        case "text": self = .text(content: try s(.content))
        case "user_added": self = .userAdded(id: try s(.id), by: try s(.by))
        case "user_remove": self = .userRemove(id: try s(.id), by: try s(.by))
        case "user_joined": self = .userJoined(id: try s(.id))
        case "user_left": self = .userLeft(id: try s(.id))
        case "user_kicked": self = .userKicked(id: try s(.id))
        case "user_banned": self = .userBanned(id: try s(.id))
        case "channel_renamed": self = .channelRenamed(name: try s(.name), by: try s(.by))
        case "channel_description_changed": self = .channelDescriptionChanged(by: try s(.by))
        case "channel_icon_changed": self = .channelIconChanged(by: try s(.by))
        case "channel_ownership_changed": self = .channelOwnershipChanged(from: try s(.from), to: try s(.to))
        case "message_pinned": self = .messagePinned(id: try s(.id), by: try s(.by))
        case "message_unpinned": self = .messageUnpinned(id: try s(.id), by: try s(.by))
        case "call_started": self = .callStarted(by: try s(.by), finishedAt: try c.decodeIfPresent(String.self, forKey: .finishedAt))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let content):
            try c.encode("text", forKey: .type); try c.encode(content, forKey: .content)
        case .userAdded(let id, let by):
            try c.encode("user_added", forKey: .type); try c.encode(id, forKey: .id); try c.encode(by, forKey: .by)
        case .userRemove(let id, let by):
            try c.encode("user_remove", forKey: .type); try c.encode(id, forKey: .id); try c.encode(by, forKey: .by)
        case .userJoined(let id):
            try c.encode("user_joined", forKey: .type); try c.encode(id, forKey: .id)
        case .userLeft(let id):
            try c.encode("user_left", forKey: .type); try c.encode(id, forKey: .id)
        case .userKicked(let id):
            try c.encode("user_kicked", forKey: .type); try c.encode(id, forKey: .id)
        case .userBanned(let id):
            try c.encode("user_banned", forKey: .type); try c.encode(id, forKey: .id)
        case .channelRenamed(let name, let by):
            try c.encode("channel_renamed", forKey: .type); try c.encode(name, forKey: .name); try c.encode(by, forKey: .by)
        case .channelDescriptionChanged(let by):
            try c.encode("channel_description_changed", forKey: .type); try c.encode(by, forKey: .by)
        case .channelIconChanged(let by):
            try c.encode("channel_icon_changed", forKey: .type); try c.encode(by, forKey: .by)
        case .channelOwnershipChanged(let from, let to):
            try c.encode("channel_ownership_changed", forKey: .type); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        case .messagePinned(let id, let by):
            try c.encode("message_pinned", forKey: .type); try c.encode(id, forKey: .id); try c.encode(by, forKey: .by)
        case .messageUnpinned(let id, let by):
            try c.encode("message_unpinned", forKey: .type); try c.encode(id, forKey: .id); try c.encode(by, forKey: .by)
        case .callStarted(let by, let finishedAt):
            try c.encode("call_started", forKey: .type); try c.encode(by, forKey: .by); try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
        case .unknown(let type):
            try c.encode(type, forKey: .type)
        }
    }

    public var referencedUserIds: [String] {
        switch self {
        case .userAdded(let id, let by), .userRemove(let id, let by): return [id, by]
        case .userJoined(let id), .userLeft(let id), .userKicked(let id), .userBanned(let id): return [id]
        case .channelRenamed(_, let by), .channelDescriptionChanged(let by), .channelIconChanged(let by): return [by]
        case .channelOwnershipChanged(let from, let to): return [from, to]
        case .messagePinned(_, let by), .messageUnpinned(_, let by): return [by]
        case .callStarted(let by, _): return [by]
        case .text, .unknown: return []
        }
    }
}

/// Link previews and bot/webhook embeds. The server sends several tagged shapes
/// (`Website`, `Image`, `Video`, `Text`, `None`); they are flattened here.
public struct Embed: Codable, Sendable, Hashable {
    public let type: String
    public let url: String?
    public let originalUrl: String?
    public let title: String?
    public let description: String?
    public let siteName: String?
    public let iconUrl: String?
    public let colour: String?
    public let image: EmbedMedia?
    public let video: EmbedMedia?
    public let special: EmbedSpecial?
    /// Uploaded media on `Text` embeds sent by bots.
    public let media: Attachment?
    public let width: Int?
    public let height: Int?

    enum CodingKeys: String, CodingKey {
        case type, url, title, description, colour, image, video, special, media, width, height
        case originalUrl = "original_url"
        case siteName = "site_name"
        case iconUrl = "icon_url"
    }

    public init(
        type: String = "Website",
        url: String? = nil,
        originalUrl: String? = nil,
        title: String? = nil,
        description: String? = nil,
        siteName: String? = nil,
        iconUrl: String? = nil,
        colour: String? = nil,
        image: EmbedMedia? = nil,
        video: EmbedMedia? = nil,
        special: EmbedSpecial? = nil,
        media: Attachment? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.type = type
        self.url = url
        self.originalUrl = originalUrl
        self.title = title
        self.description = description
        self.siteName = siteName
        self.iconUrl = iconUrl
        self.colour = colour
        self.image = image
        self.video = video
        self.special = special
        self.media = media
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        originalUrl = try c.decodeIfPresent(String.self, forKey: .originalUrl)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        iconUrl = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        colour = try c.decodeIfPresent(String.self, forKey: .colour)
        image = try? c.decodeIfPresent(EmbedMedia.self, forKey: .image)
        video = try? c.decodeIfPresent(EmbedMedia.self, forKey: .video)
        special = try? c.decodeIfPresent(EmbedSpecial.self, forKey: .special)
        media = try? c.decodeIfPresent(Attachment.self, forKey: .media)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
    }

    public var isEmpty: Bool {
        type == "None" || (title == nil && description == nil && image == nil && video == nil && media == nil && url == nil)
    }

    /// Routes a remote media URL through the January proxy when the instance provides one.
    public static func proxiedURL(_ raw: String) -> URL? {
        if let january = StoatInstance.endpoints.january,
           let encoded = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            return URL(string: "\(january)/proxy?url=\(encoded)")
        }
        return URL(string: raw)
    }
}

public struct EmbedMedia: Codable, Sendable, Hashable {
    public let url: String
    public let width: Int?
    public let height: Int?
    public let size: String?
}

public struct EmbedSpecial: Codable, Sendable, Hashable {
    public let type: String
    public let id: String?
}

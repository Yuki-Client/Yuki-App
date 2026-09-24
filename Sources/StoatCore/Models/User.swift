import Foundation

public struct User: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public var username: String
    public var discriminator: String
    public var displayName: String?
    public var pronouns: String?
    public var avatar: Attachment?
    public var badges: Int
    public var status: UserStatus?
    public var flags: Int
    public var privileged: Bool
    public var bot: BotDetails?
    public var relationship: RelationshipStatus
    public var online: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username
        case discriminator
        case displayName = "display_name"
        case pronouns
        case avatar
        case badges
        case status
        case flags
        case privileged
        case bot
        case relationship
        case online
    }

    public init(
        id: String,
        username: String,
        discriminator: String = "0000",
        displayName: String? = nil,
        pronouns: String? = nil,
        avatar: Attachment? = nil,
        badges: Int = 0,
        status: UserStatus? = nil,
        flags: Int = 0,
        privileged: Bool = false,
        bot: BotDetails? = nil,
        relationship: RelationshipStatus = .none,
        online: Bool = false
    ) {
        self.id = id
        self.username = username
        self.discriminator = discriminator
        self.displayName = displayName
        self.pronouns = pronouns
        self.avatar = avatar
        self.badges = badges
        self.status = status
        self.flags = flags
        self.privileged = privileged
        self.bot = bot
        self.relationship = relationship
        self.online = online
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        discriminator = try c.decodeIfPresent(String.self, forKey: .discriminator) ?? "0000"
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        pronouns = try c.decodeIfPresent(String.self, forKey: .pronouns)
        avatar = try c.decodeIfPresent(Attachment.self, forKey: .avatar)
        badges = try c.decodeIfPresent(Int.self, forKey: .badges) ?? 0
        status = try c.decodeIfPresent(UserStatus.self, forKey: .status)
        flags = try c.decodeIfPresent(Int.self, forKey: .flags) ?? 0
        privileged = try c.decodeIfPresent(Bool.self, forKey: .privileged) ?? false
        bot = try c.decodeIfPresent(BotDetails.self, forKey: .bot)
        relationship = try c.decodeIfPresent(RelationshipStatus.self, forKey: .relationship) ?? .none
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? false
    }

    public var visibleName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return username
    }

    public var fullHandle: String {
        "\(username)#\(discriminator)"
    }

    /// Effective presence shown next to avatars; offline users always read as invisible.
    public var effectivePresence: Presence {
        guard online else { return .invisible }
        return status?.presence ?? .online
    }

    /// Custom status text, hidden while the user is offline or invisible.
    public var onlineStatusText: String? {
        guard online, let text = status?.text, !text.isEmpty else { return nil }
        return text
    }

    public var decodedBadges: [UserBadge] {
        var list: [UserBadge] = []

        if privileged {
            list.append(UserBadge(id: "staff", name: "Stoat Staff", description: "Works on the Stoat platform", iconSystemName: "checkmark.shield.fill", colorHex: "#FF5722"))
        }

        if bot != nil {
            list.append(UserBadge(id: "bot", name: "Bot", description: "Automated Bot Account", iconSystemName: "cpu.fill", colorHex: "#5865F2"))
        }

        for badge in UserBadge.catalogue where badges & badge.bit != 0 {
            list.append(badge.badge)
        }

        return list
    }
}

public struct UserBadge: Identifiable, Sendable, Hashable, Codable {
    public var id: String { id_name }
    public let id_name: String
    public let name: String
    public let description: String
    public let iconSystemName: String
    public let colorHex: String

    public init(id: String, name: String, description: String, iconSystemName: String, colorHex: String) {
        self.id_name = id
        self.name = name
        self.description = description
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
    }

    // Bit values from `UserBadges` in stoatchat/crates/core/models/src/v0/users.rs
    static let catalogue: [(bit: Int, badge: UserBadge)] = [
        (16, UserBadge(id: "founder", name: "Stoat Founder", description: "Founded Stoat", iconSystemName: "crown.fill", colorHex: "#FFC107")),
        (1, UserBadge(id: "developer", name: "Stoat Developer", description: "Develops Stoat", iconSystemName: "hammer.fill", colorHex: "#E91E63")),
        (4, UserBadge(id: "supporter", name: "Stoat Supporter", description: "Donated to Stoat", iconSystemName: "heart.fill", colorHex: "#FF4081")),
        (64, UserBadge(id: "active_supporter", name: "Active Stoat Supporter", description: "Actively supports Stoat", iconSystemName: "flame.fill", colorHex: "#FF9800")),
        (2, UserBadge(id: "translator", name: "Stoat Translator", description: "Helped translate Stoat", iconSystemName: "globe", colorHex: "#00BCD4")),
        (256, UserBadge(id: "early_adopter", name: "Stoat Early Adopter", description: "One of Stoat's first 1,000 users", iconSystemName: "star.fill", colorHex: "#FFD700")),
        (32, UserBadge(id: "moderation", name: "Stoat Moderator", description: "Moderates the Stoat platform", iconSystemName: "shield.lefthalf.filled", colorHex: "#3F51B5")),
        (8, UserBadge(id: "responsible_disclosure", name: "Stoat Bug Hunter", description: "Responsibly reported security issues in Stoat", iconSystemName: "ladybug.fill", colorHex: "#4CAF50")),
        (128, UserBadge(id: "paw", name: "Stoat Paw", description: "Stoat Paw", iconSystemName: "pawprint.fill", colorHex: "#8D6E63"))
    ]
}

public struct UserStatus: Codable, Sendable, Hashable {
    public var text: String?
    public var presence: Presence?

    public init(text: String? = nil, presence: Presence? = nil) {
        self.text = text
        self.presence = presence
    }
}

public enum Presence: String, Codable, Sendable, Hashable, CaseIterable {
    case online = "Online"
    case idle = "Idle"
    case focus = "Focus"
    case busy = "Busy"
    case invisible = "Invisible"
}

public enum RelationshipStatus: String, Codable, Sendable, Hashable {
    case none = "None"
    case user = "User"
    case friend = "Friend"
    case outgoing = "Outgoing"
    case incoming = "Incoming"
    case blocked = "Blocked"
    case blockedOther = "BlockedOther"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RelationshipStatus(rawValue: raw) ?? .none
    }
}

public struct BotDetails: Codable, Sendable, Hashable {
    public let owner: String

    public init(owner: String) {
        self.owner = owner
    }
}

public struct UserProfile: Codable, Sendable, Hashable {
    public let content: String?
    public let background: Attachment?

    public init(content: String? = nil, background: Attachment? = nil) {
        self.content = content
        self.background = background
    }
}

public struct MutualConnections: Decodable, Sendable {
    public let users: [String]
    public let servers: [String]
    public let channels: [String]?
}

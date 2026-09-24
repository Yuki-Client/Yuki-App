import Foundation

/// A bot owned by the current user, including its token.
public struct Bot: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let owner: String
    public var token: String
    public var isPublic: Bool
    public var analytics: Bool
    public var discoverable: Bool
    public var interactionsURL: String?
    public var termsOfServiceURL: String?
    public var privacyPolicyURL: String?
    public var flags: Int

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case owner, token, analytics, discoverable, flags
        case isPublic = "public"
        case interactionsURL = "interactions_url"
        case termsOfServiceURL = "terms_of_service_url"
        case privacyPolicyURL = "privacy_policy_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        owner = try c.decode(String.self, forKey: .owner)
        token = try c.decode(String.self, forKey: .token)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        analytics = try c.decodeIfPresent(Bool.self, forKey: .analytics) ?? false
        discoverable = try c.decodeIfPresent(Bool.self, forKey: .discoverable) ?? false
        interactionsURL = try c.decodeIfPresent(String.self, forKey: .interactionsURL)
        termsOfServiceURL = try c.decodeIfPresent(String.self, forKey: .termsOfServiceURL)
        privacyPolicyURL = try c.decodeIfPresent(String.self, forKey: .privacyPolicyURL)
        flags = try c.decodeIfPresent(Int.self, forKey: .flags) ?? 0
    }

    public var isVerified: Bool { flags & 1 != 0 }
}

/// A bot together with its user account (the response to creating or editing a bot).
public struct BotWithUser: Decodable, Sendable {
    public let bot: Bot
    public let user: User

    enum CodingKeys: String, CodingKey { case user }

    public init(from decoder: Decoder) throws {
        bot = try Bot(from: decoder)
        user = try decoder.container(keyedBy: CodingKeys.self).decode(User.self, forKey: .user)
    }
}

public struct OwnedBotsResponse: Decodable, Sendable {
    public let bots: [Bot]
    public let users: [User]
}

public struct PublicBot: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let username: String
    public let avatar: String?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username, avatar, description
    }
}

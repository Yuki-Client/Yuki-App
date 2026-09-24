import Foundation

public struct Emoji: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let parent: EmojiParent
    public let creatorId: String?
    public var name: String
    public let animated: Bool
    public let nsfw: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case parent
        case creatorId = "creator_id"
        case name
        case animated
        case nsfw
    }

    public init(
        id: String,
        parent: EmojiParent,
        creatorId: String? = nil,
        name: String,
        animated: Bool = false,
        nsfw: Bool = false
    ) {
        self.id = id
        self.parent = parent
        self.creatorId = creatorId
        self.name = name
        self.animated = animated
        self.nsfw = nsfw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parent = try c.decode(EmojiParent.self, forKey: .parent)
        creatorId = try c.decodeIfPresent(String.self, forKey: .creatorId)
        name = try c.decode(String.self, forKey: .name)
        animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? false
        nsfw = try c.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false
    }

    public func imageURL(autumnBaseURL: String = StoatInstance.autumnURL) -> URL? {
        Emoji.imageURL(id: id, autumnBaseURL: autumnBaseURL)
    }

    public static func imageURL(id: String, autumnBaseURL: String = StoatInstance.autumnURL) -> URL? {
        URL(string: "\(autumnBaseURL)/emojis/\(id)")
    }

    /// Custom emoji references in content and reactions are 26 character ULIDs.
    public static func isCustomEmojiId(_ value: String) -> Bool {
        value.count == 26 && value.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
    }
}

public enum EmojiParent: Codable, Sendable, Hashable {
    case server(id: String)
    case detached

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "Server":
            self = .server(id: try c.decode(String.self, forKey: .id))
        default:
            self = .detached
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .server(let id):
            try c.encode("Server", forKey: .type)
            try c.encode(id, forKey: .id)
        case .detached:
            try c.encode("Detached", forKey: .type)
        }
    }

    public var serverId: String? {
        if case .server(let id) = self { return id }
        return nil
    }
}

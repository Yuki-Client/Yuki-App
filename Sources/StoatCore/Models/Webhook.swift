import Foundation

/// A channel webhook. The token is only returned to people who can manage webhooks.
public struct Webhook: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var avatar: Attachment?
    public let creatorId: String
    public let channelId: String
    public var permissions: Int64
    public let token: String?

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, permissions, token
        case creatorId = "creator_id"
        case channelId = "channel_id"
    }

    /// The URL other services post to, e.g. `https://stoat.chat/api/webhooks/{id}/{token}`.
    public var executeURL: String? {
        guard let token else { return nil }
        let api = StoatInstance.endpoints.api.hasSuffix("/") ? String(StoatInstance.endpoints.api.dropLast()) : StoatInstance.endpoints.api
        return "\(api)/webhooks/\(id)/\(token)"
    }
}

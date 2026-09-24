import Foundation

public enum GatewayCommand: Encodable, Sendable {
    case authenticate(token: String)
    case ping(data: Int)
    case beginTyping(channelId: String)
    case endTyping(channelId: String)
    /// Receive member presence/profile updates for a server for the next ~15 minutes.
    case subscribe(serverId: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case data
        case channel
        case serverId = "server_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .authenticate(let token):
            try container.encode("Authenticate", forKey: .type)
            try container.encode(token, forKey: .token)
        case .ping(let data):
            try container.encode("Ping", forKey: .type)
            try container.encode(data, forKey: .data)
        case .beginTyping(let channelId):
            try container.encode("BeginTyping", forKey: .type)
            try container.encode(channelId, forKey: .channel)
        case .endTyping(let channelId):
            try container.encode("EndTyping", forKey: .type)
            try container.encode(channelId, forKey: .channel)
        case .subscribe(let serverId):
            try container.encode("Subscribe", forKey: .type)
            try container.encode(serverId, forKey: .serverId)
        }
    }
}

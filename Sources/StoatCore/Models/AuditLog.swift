import Foundation

public struct AuditLogEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let server: String
    public let reason: String?
    public let user: String
    public let target: String?
    public let action: AuditLogAction

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case server, reason, user, target, action
    }
}

/// The action on an audit log entry. The server sends many tagged shapes; their fields are
/// flattened here, with the before and after values of edits kept as raw JSON.
public struct AuditLogAction: Decodable, Sendable, Hashable {
    public let type: String
    public let author: String?
    public let channel: String?
    public let message: String?
    public let user: String?
    public let role: String?
    public let invite: String?
    public let webhook: String?
    public let emoji: String?
    public let name: String?
    public let count: Int?
    /// Old values of the fields an edit changed or removed. Missing keys had no value before.
    /// For `RolesReorder` this is the previous role order instead.
    public let before: JSONValue?
    /// New values of the fields an edit set. Keys only in `before` were removed.
    public let after: JSONValue?
    /// The new override on `ChannelRolePermissionsEdit`: `{"allow": …, "deny": …}`.
    public let permissions: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type, author, channel, message, user, role, invite, webhook, emoji, name, count, before, after, permissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        author = try? c.decodeIfPresent(String.self, forKey: .author)
        channel = try? c.decodeIfPresent(String.self, forKey: .channel)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        user = try? c.decodeIfPresent(String.self, forKey: .user)
        role = try? c.decodeIfPresent(String.self, forKey: .role)
        invite = try? c.decodeIfPresent(String.self, forKey: .invite)
        webhook = try? c.decodeIfPresent(String.self, forKey: .webhook)
        emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        before = try? c.decodeIfPresent(JSONValue.self, forKey: .before)
        after = try? c.decodeIfPresent(JSONValue.self, forKey: .after)
        permissions = try? c.decodeIfPresent(JSONValue.self, forKey: .permissions)
    }
}

public enum JSONValue: Decodable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? c.decode(Double.self) {
            self = .double(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    public var string: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    public var int: Int64? {
        switch self {
        case .int(let value): value
        case .double(let value) where value.rounded() == value: Int64(value)
        default: nil
        }
    }
}

public struct AuditLogPage: Decodable, Sendable {
    public let auditLogs: [AuditLogEntry]
    public let users: [User]
    public let members: [ServerMember]

    enum CodingKeys: String, CodingKey {
        case auditLogs = "audit_logs"
        case users, members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auditLogs = try c.decodeLossyArray(AuditLogEntry.self, forKey: .auditLogs) ?? []
        users = try c.decodeLossyArray(User.self, forKey: .users) ?? []
        members = try c.decodeLossyArray(ServerMember.self, forKey: .members) ?? []
    }
}

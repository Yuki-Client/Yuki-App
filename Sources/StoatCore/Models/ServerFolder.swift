import Foundation

/// Synced through Stoat's `server-folders` setting, in the same shape Stoat for Web uses.
public struct ServerFolder: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// Any CSS colour.
    public var colour: String?
    public var collapsed: Bool?
    public var servers: [String]

    public init(id: String, name: String, colour: String? = nil, collapsed: Bool? = nil, servers: [String]) {
        self.id = id
        self.name = name
        self.colour = colour
        self.collapsed = collapsed
        self.servers = servers
    }

    enum CodingKeys: String, CodingKey { case id, name, colour, collapsed, servers }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        colour = try? container.decode(String.self, forKey: .colour)
        collapsed = (try? container.decode(Bool.self, forKey: .collapsed)) == true ? true : nil
        servers = (try? container.decode([String].self, forKey: .servers)) ?? []
    }

    public var isCollapsed: Bool { collapsed == true }

    public var displayName: String { name.isEmpty ? "Folder" : name }

    /// Folder IDs carry this prefix so they can never collide with a server ID.
    public static let idPrefix = "folder-"

    public static func isFolderId(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    public static func newId(at date: Date = Date()) -> String {
        idPrefix + ULID.make(at: date)
    }

    /// Folders as another client wrote them, keeping only what's valid. A server can only be in
    /// one folder, so a later claim on it is dropped rather than drawing it twice.
    public static func cleaned(_ folders: [ServerFolder]) -> [ServerFolder] {
        var seenFolders = Set<String>()
        var seenServers = Set<String>()
        return folders.compactMap { folder in
            guard !folder.id.isEmpty, seenFolders.insert(folder.id).inserted else { return nil }
            var folder = folder
            folder.servers = folder.servers.filter { !$0.isEmpty && seenServers.insert($0).inserted }
            if folder.collapsed != true { folder.collapsed = nil }
            return folder
        }
    }
}

public struct ServerFoldersSetting: Codable, Sendable {
    public var folders: [ServerFolder]

    public init(folders: [ServerFolder]) {
        self.folders = folders
    }

    enum CodingKeys: String, CodingKey { case folders }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folders = (try? container.decodeLossyArray(ServerFolder.self, forKey: .folders)) ?? []
    }
}

/// The `ordering` synced setting. `servers` is the flat order older clients read; `serverSidebar`
/// holds server and folder IDs for clients that understand folders.
public struct ServerOrderingSetting: Codable, Sendable {
    public var servers: [String]
    public var serverSidebar: [String]?

    public init(servers: [String], serverSidebar: [String]?) {
        self.servers = servers
        self.serverSidebar = serverSidebar
    }

    enum CodingKeys: String, CodingKey { case servers, serverSidebar }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = Self.ids(try? container.decode([LossyString].self, forKey: .servers))
        serverSidebar = (try? container.decode([LossyString].self, forKey: .serverSidebar)).map(Self.ids)
    }

    private static func ids(_ entries: [LossyString]?) -> [String] {
        var seen = Set<String>()
        return (entries ?? []).flatMap(\.values).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Takes a server ID, or the servers of a folder stored inline, and skips anything else,
    /// the same way Stoat for Web cleans this list.
    private struct LossyString: Decodable {
        let values: [String]
        private struct Inline: Decodable { let servers: [String] }
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let id = try? container.decode(String.self) {
                values = [id]
            } else {
                values = (try? container.decode(Inline.self))?.servers ?? []
            }
        }
    }
}

/// Minimal ULID: 48-bit millisecond time and 80 random bits in Crockford base 32.
enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func make(at date: Date) -> String {
        var time = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var timeChars = [Character](repeating: "0", count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            timeChars[index] = alphabet[Int(time % 32)]
            time /= 32
        }
        let random = (0..<16).map { _ in alphabet[Int.random(in: 0..<32)] }
        return String(timeChars + random)
    }
}

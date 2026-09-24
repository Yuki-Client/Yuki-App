import Foundation

public struct DiscoverServer: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let icon: Attachment?
    public let banner: Attachment?
    public let tags: [String]
    public let members: Int
    public let activity: DiscoverActivity
    public let flags: Int
    public let isNew: Bool

    public var isOfficial: Bool { flags & 1 != 0 }
    public var isVerified: Bool { flags & 2 != 0 }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, icon, banner, tags, members, activity, flags
        case isNew = "featured_new"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        icon = try? c.decodeIfPresent(Attachment.self, forKey: .icon)
        banner = try? c.decodeIfPresent(Attachment.self, forKey: .banner)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        members = (try? c.decodeIfPresent(Int.self, forKey: .members)) ?? 0
        activity = DiscoverActivity(rawValue: (try? c.decodeIfPresent(String.self, forKey: .activity)) ?? "") ?? .none
        flags = (try? c.decodeIfPresent(Int.self, forKey: .flags)) ?? 0
        isNew = (try? c.decodeIfPresent(Bool.self, forKey: .isNew)) ?? false
    }
}

public struct DiscoverBot: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let username: String
    public let avatar: Attachment?
    public let description: String?
    public let tags: [String]
    public let servers: Int
    public let usage: DiscoverActivity

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username, avatar, profile, tags, servers, usage
    }

    private struct Profile: Decodable {
        let content: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        avatar = try? c.decodeIfPresent(Attachment.self, forKey: .avatar)
        description = (try? c.decodeIfPresent(Profile.self, forKey: .profile))?.content
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        servers = (try? c.decodeIfPresent(Int.self, forKey: .servers)) ?? 0
        usage = DiscoverActivity(rawValue: (try? c.decodeIfPresent(String.self, forKey: .usage)) ?? "") ?? .none
    }
}

/// How busy a listed server is, or how widely a bot is used.
public enum DiscoverActivity: String, Sendable, Hashable {
    case high, medium, low
    case none = "no"
}

public struct DiscoverListing<Item: Sendable & Hashable>: Sendable, Hashable {
    public let items: [Item]
    public let popularTags: [String]
}

/// Discover has no API, so this reads the JSON stt.gg's Next.js pages load. Its URL contains
/// a build ID that changes with each deploy; a stale one is refreshed and the request retried.
public actor DiscoverClient {
    public static let shared = DiscoverClient()
    public static let siteURL = URL(string: "https://stt.gg")!

    private var buildId: String?
    private var cachedServers: (date: Date, listing: DiscoverListing<DiscoverServer>)?
    private var cachedBots: (date: Date, listing: DiscoverListing<DiscoverBot>)?
    /// Listings change slowly, so they're kept for a while rather than downloaded every time.
    private static let cacheLifetime: TimeInterval = 15 * 60
    private let session: URLSession

    public enum DiscoverError: LocalizedError {
        case unavailable

        public var errorDescription: String? {
            "Discover couldn't be loaded. Try again in a moment."
        }
    }

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    public func servers(refresh: Bool = false) async throws -> DiscoverListing<DiscoverServer> {
        if !refresh, let cachedServers, Date().timeIntervalSince(cachedServers.date) < Self.cacheLifetime {
            return cachedServers.listing
        }
        struct Page: Decodable {
            struct Props: Decodable {
                let servers: [DiscoverServer]?
                let popularTags: [String]?

                enum CodingKeys: String, CodingKey { case servers, popularTags }

                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    servers = try c.decodeLossyArray(DiscoverServer.self, forKey: .servers)
                    popularTags = try? c.decodeIfPresent([String].self, forKey: .popularTags)
                }
            }
            let pageProps: Props
        }
        let page = try JSONDecoder().decode(Page.self, from: try await pageData("discover/servers"))
        let listing = DiscoverListing(items: page.pageProps.servers ?? [], popularTags: page.pageProps.popularTags ?? [])
        cachedServers = (Date(), listing)
        return listing
    }

    public func bots(refresh: Bool = false) async throws -> DiscoverListing<DiscoverBot> {
        if !refresh, let cachedBots, Date().timeIntervalSince(cachedBots.date) < Self.cacheLifetime {
            return cachedBots.listing
        }
        struct Page: Decodable {
            struct Props: Decodable {
                let bots: [DiscoverBot]?
                let popularTags: [String]?

                enum CodingKeys: String, CodingKey { case bots, popularTags }

                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    bots = try c.decodeLossyArray(DiscoverBot.self, forKey: .bots)
                    popularTags = try? c.decodeIfPresent([String].self, forKey: .popularTags)
                }
            }
            let pageProps: Props
        }
        let page = try JSONDecoder().decode(Page.self, from: try await pageData("discover/bots"))
        let listing = DiscoverListing(items: page.pageProps.bots ?? [], popularTags: page.pageProps.popularTags ?? [])
        cachedBots = (Date(), listing)
        return listing
    }

    private func pageData(_ page: String) async throws -> Data {
        for attempt in 0..<2 {
            let id = try await currentBuildId(refresh: attempt > 0)
            let url = Self.siteURL.appendingPathComponent("_next/data/\(id)/\(page).json")
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return data }
            if status != 404 { break }
        }
        throw DiscoverError.unavailable
    }

    private func currentBuildId(refresh: Bool) async throws -> String {
        if let buildId, !refresh { return buildId }
        var components = URLComponents(url: Self.siteURL.appendingPathComponent("discover/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: "yuki"),
            URLQueryItem(name: "type", value: "bots"),
            URLQueryItem(name: "embedded", value: "true")
        ]
        guard let url = components?.url else { throw DiscoverError.unavailable }
        let (data, _) = try await session.data(from: url)
        let html = String(decoding: data, as: UTF8.self)
        guard let match = html.range(of: #""buildId":"[^"]+""#, options: .regularExpression) else {
            throw DiscoverError.unavailable
        }
        let id = html[match].dropFirst(#""buildId":""#.count).dropLast()
        buildId = String(id)
        return String(id)
    }
}

public enum DiscoverRequestStatus: Decodable, Sendable, Equatable {
    case pending
    case underReview
    case approved(reason: String?)
    case denied(reason: String?)
    case removed(reason: String?)

    public init(from decoder: Decoder) throws {
        if let simple = try? decoder.singleValueContainer().decode(String.self) {
            switch simple {
            case "Pending": self = .pending
            case "UnderReview": self = .underReview
            case "Approved": self = .approved(reason: nil)
            case "Denied": self = .denied(reason: nil)
            case "Removed": self = .removed(reason: nil)
            default: self = .pending
            }
            return
        }
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let key = c.allKeys.first else { self = .pending; return }
        let reason = try? c.decodeIfPresent(String.self, forKey: key)
        switch key.stringValue {
        case "Approved": self = .approved(reason: reason)
        case "Denied": self = .denied(reason: reason)
        case "Removed": self = .removed(reason: reason)
        case "UnderReview": self = .underReview
        default: self = .pending
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

public struct DiscoverRequest: Decodable, Sendable {
    public let status: DiscoverRequestStatus
}

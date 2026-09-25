import Foundation
import os

/// Root configuration served by `GET /` on a Stoat API.
public struct InstanceConfiguration: Codable, Sendable {
    public let ws: String
    public let app: String?
    public let features: InstanceFeatures

    public init(ws: String, app: String? = nil, features: InstanceFeatures = InstanceFeatures()) {
        self.ws = ws
        self.app = app
        self.features = features
    }
}

public struct InstanceFeatures: Codable, Sendable {
    public let captcha: CaptchaFeature?
    public let email: Bool?
    public let inviteOnly: Bool?
    public let autumn: FeatureEndpoint?
    public let january: FeatureEndpoint?
    public let livekit: LiveKitFeature?
    public let limits: InstanceLimits?

    enum CodingKeys: String, CodingKey {
        case captcha, email, autumn, january, livekit, limits
        case inviteOnly = "invite_only"
    }

    public init(
        captcha: CaptchaFeature? = nil,
        email: Bool? = nil,
        inviteOnly: Bool? = nil,
        autumn: FeatureEndpoint? = nil,
        january: FeatureEndpoint? = nil,
        livekit: LiveKitFeature? = nil,
        limits: InstanceLimits? = nil
    ) {
        self.captcha = captcha
        self.email = email
        self.inviteOnly = inviteOnly
        self.autumn = autumn
        self.january = january
        self.livekit = livekit
        self.limits = limits
    }
}

public struct CaptchaFeature: Codable, Sendable {
    public let enabled: Bool
    public let key: String?
}

public struct FeatureEndpoint: Codable, Sendable {
    public let enabled: Bool
    public let url: String?

    public init(enabled: Bool, url: String? = nil) {
        self.enabled = enabled
        self.url = url
    }
}

public struct LiveKitFeature: Codable, Sendable {
    public let enabled: Bool
    public let nodes: [LiveKitNode]?
}

public struct LiveKitNode: Codable, Sendable {
    public let name: String
    public let publicUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case publicUrl = "public_url"
    }
}

public struct InstanceLimits: Codable, Sendable {
    public let global: GlobalLimits?
    public let newUser: UserLimits?
    public let `default`: UserLimits?

    enum CodingKeys: String, CodingKey {
        case global
        case newUser = "new_user"
        case `default`
    }
}

public struct GlobalLimits: Codable, Sendable {
    public let groupSize: Int?
    public let messageReplies: Int?
    public let messageReactions: Int?
    public let bodyLimitSize: Int?
    public let maxInviteDurationDays: Int?

    enum CodingKeys: String, CodingKey {
        case groupSize = "group_size"
        case messageReplies = "message_replies"
        case messageReactions = "message_reactions"
        case bodyLimitSize = "body_limit_size"
        case maxInviteDurationDays = "max_invite_duration_days"
    }
}

public struct UserLimits: Codable, Sendable {
    public let messageLength: Int?
    public let messageAttachments: Int?
    public let fileUploadSizeLimits: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case messageLength = "message_length"
        case messageAttachments = "message_attachments"
        case fileUploadSizeLimits = "file_upload_size_limits"
    }
}

public enum StoatInstance {
    public struct Endpoints: Sendable, Equatable {
        public var api: String
        public var autumn: String
        public var january: String?
        public var app: String

        public static let stoat = Endpoints(
            api: "https://stoat.chat/api",
            autumn: "https://cdn.stoatusercontent.com",
            january: "https://proxy.stoatusercontent.com",
            app: "https://stoat.chat"
        )
    }

    private static let lock = OSAllocatedUnfairLock(initialState: Endpoints.stoat)

    public static var endpoints: Endpoints {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    public static var autumnURL: String { endpoints.autumn }
    public static var appURL: String { endpoints.app }
    /// Whether Yuki is connected to stoat.chat, where Stoat-run services like Discover exist.
    public static var isOfficial: Bool { endpoints.api == Endpoints.stoat.api }

    public static func apply(configuration: InstanceConfiguration, apiURL: URL) {
        var next = endpoints
        next.api = apiURL.absoluteString
        if let autumn = configuration.features.autumn, autumn.enabled, let url = autumn.url {
            next.autumn = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        next.january = configuration.features.january?.url
        if let app = configuration.app, !app.isEmpty {
            next.app = app.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        endpoints = next
    }
}

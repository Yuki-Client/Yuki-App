import Foundation

public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let friendlyName: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case friendlyName = "friendly_name"
    }

    public init(email: String, password: String, friendlyName: String = LoginRequest.defaultFriendlyName) {
        self.email = email
        self.password = password
        self.friendlyName = friendlyName
    }

    public static let defaultFriendlyName = "Yuki for iOS"
}

public struct MFALoginRequest: Encodable, Sendable {
    public let mfaTicket: String
    public let mfaResponse: MFAResponse
    public let friendlyName: String

    enum CodingKeys: String, CodingKey {
        case mfaTicket = "mfa_ticket"
        case mfaResponse = "mfa_response"
        case friendlyName = "friendly_name"
    }

    public init(ticket: String, response: MFAResponse, friendlyName: String = LoginRequest.defaultFriendlyName) {
        self.mfaTicket = ticket
        self.mfaResponse = response
        self.friendlyName = friendlyName
    }
}

public enum MFAResponse: Encodable, Sendable {
    case totp(String)
    case recoveryCode(String)
    case password(String)

    private enum CodingKeys: String, CodingKey {
        case totpCode = "totp_code"
        case recoveryCode = "recovery_code"
        case password
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .totp(let code): try container.encode(code, forKey: .totpCode)
        case .recoveryCode(let code): try container.encode(code, forKey: .recoveryCode)
        case .password(let password): try container.encode(password, forKey: .password)
        }
    }
}

public enum MFAMethod: String, Codable, Sendable, Hashable {
    case password = "Password"
    case recovery = "Recovery"
    case totp = "Totp"
}

public enum LoginResponse: Decodable, Sendable {
    case success(SessionSuccess)
    case mfa(MFARequirement)
    case disabled(userId: String)

    private enum Discriminator: String, CodingKey {
        case result
        case userId = "user_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Discriminator.self)
        let result = try container.decode(String.self, forKey: .result)
        let singleContainer = try decoder.singleValueContainer()
        switch result {
        case "Success":
            self = .success(try singleContainer.decode(SessionSuccess.self))
        case "MFA":
            self = .mfa(try singleContainer.decode(MFARequirement.self))
        case "Disabled":
            self = .disabled(userId: try container.decode(String.self, forKey: .userId))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown login result: \(result)")
            )
        }
    }
}

public struct SessionSuccess: Codable, Sendable {
    public let id: String?
    public let userId: String
    public let token: String
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId = "user_id"
        case token
        case name
    }

    public init(id: String? = nil, userId: String, token: String, name: String? = nil) {
        self.id = id
        self.userId = userId
        self.token = token
        self.name = name
    }
}

public struct MFARequirement: Codable, Sendable {
    public let ticket: String
    public let allowedMethods: [MFAMethod]

    enum CodingKeys: String, CodingKey {
        case ticket
        case allowedMethods = "allowed_methods"
    }
}

public struct SessionInfo: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

public struct OnboardingStatus: Decodable, Sendable {
    public let onboarding: Bool
}

/// Which second factors an account has set up (`GET /auth/mfa/`).
public struct MultiFactorStatus: Decodable, Sendable, Equatable {
    public var totpEnabled: Bool
    public var recoveryActive: Bool

    enum CodingKeys: String, CodingKey {
        case totpEnabled = "totp_mfa"
        case recoveryActive = "recovery_active"
    }

    public init(totpEnabled: Bool = false, recoveryActive: Bool = false) {
        self.totpEnabled = totpEnabled
        self.recoveryActive = recoveryActive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totpEnabled = try c.decodeIfPresent(Bool.self, forKey: .totpEnabled) ?? false
        recoveryActive = try c.decodeIfPresent(Bool.self, forKey: .recoveryActive) ?? false
    }

    /// Ways to confirm a sensitive action. With an authenticator, the password alone isn't accepted.
    public var availableMethods: [MFAMethod] {
        guard totpEnabled else { return [.password] }
        return recoveryActive ? [.totp, .recovery] : [.totp]
    }
}

/// The signed-in account's login details (`GET /auth/account/`).
public struct AccountInfo: Decodable, Sendable {
    public let id: String
    public let email: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email
    }
}


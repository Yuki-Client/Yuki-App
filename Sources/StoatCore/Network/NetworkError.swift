import Foundation

public enum StoatAPIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    /// Stoat returned an error body such as `{ "type": "MissingPermission" }`.
    case server(statusCode: Int, type: String?)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case decodingError(String)
    case fileTooLarge(limit: Int)
    case network(String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server address."
        case .server(let statusCode, let type):
            if let type, let friendly = Self.friendlyMessages[type] {
                return friendly
            }
            if let type {
                return "Stoat returned an error: \(type)."
            }
            return "Request failed with status code \(statusCode)."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .rateLimited(let retryAfter):
            return "You're doing that too fast. Try again in \(Int(retryAfter.rounded(.up))) seconds."
        case .decodingError:
            return "Stoat sent a response Yuki couldn't read."
        case .fileTooLarge(let limit):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "That file is too large. The limit is \(formatter.string(fromByteCount: Int64(limit)))."
        case .network(let message):
            return message
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    public var serverType: String? {
        if case .server(_, let type) = self { return type }
        return nil
    }

    /// Whether the request never reached the server (offline, DNS, timeouts).
    public var isConnectivityError: Bool {
        if case .network = self { return true }
        return false
    }

    private static let friendlyMessages: [String: String] = [
        "InvalidCredentials": "Incorrect email or password.",
        "CaptchaFailed": "The human check didn't go through. Try it again.",
        "EmailFailed": "Stoat couldn't send that email. Check the address and try again.",
        "InvalidEmail": "That email address isn't valid.",
        "EmailInUse": "There's already an account for that email.",
        "Blacklisted": "That email provider isn't allowed.",
        "ShortPassword": "That password is too short.",
        "CompromisedPassword": "That password has appeared in a data breach. Choose another.",
        "UnverifiedAccount": "Check your email to confirm your account first.",
        "InvalidSession": "Your session has expired. Please log in again.",
        "InvalidToken": "That code is invalid or has expired.",
        "DisallowedMFAMethod": "That verification method isn't allowed for this account.",
        "MissingPermission": "You don't have permission to do that.",
        "AlreadyConnected": "You're already in a call on another device.",
        "CannotJoinCall": "This call is full.",
        "LiveKitUnavailable": "Voice calls aren't available right now.",
        "NotAVoiceChannel": "You can't start a call here.",
        "UnknownNode": "That voice server isn't available.",
        "MissingUserPermission": "You can't do that with this user.",
        "NotElevated": "You can only do that to members and roles ranked below you.",
        "TooManyRoles": "This server has reached its role limit.",
        "InSlowmode": "Slowmode is on here. Wait a moment before sending again.",
        "CannotGiveMissingPermissions": "You can't grant permissions you don't have.",
        "NotOwner": "Only the owner can do that.",
        "NotFound": "That no longer exists.",
        "UnknownChannel": "That channel no longer exists.",
        "UnknownServer": "That server no longer exists.",
        "UnknownMessage": "That message no longer exists.",
        "UnknownUser": "That user doesn't exist.",
        "InvalidUsername": "That username isn't allowed.",
        "UsernameTaken": "That username is already taken.",
        "AlreadyFriends": "You're already friends.",
        "AlreadySentRequest": "You've already sent a friend request.",
        "Blocked": "You've blocked this user.",
        "BlockedByOther": "This user has blocked you.",
        "NotFriends": "You need to be friends to do that.",
        "TooManyPendingFriendRequests": "You have too many pending friend requests.",
        "AlreadyInServer": "You're already in that server.",
        "Banned": "You're banned from that server.",
        "TooManyServers": "You've joined the maximum number of servers.",
        "TooManyChannels": "This server has reached its channel limit.",
        "TooManyEmoji": "This server has reached its emoji limit.",
        "TooManyAttachments": "Too many attachments on one message.",
        "TooManyReplies": "Too many replies on one message.",
        "TooManyEmbeds": "Too many embeds on one message.",
        "EmptyMessage": "You can't send an empty message.",
        "DuplicateNonce": "That message was already sent.",
        "PayloadTooLarge": "That message is too long.",
        "CannotEditMessage": "You can't edit that message.",
        "CannotRemoveYourself": "You can't remove yourself.",
        "CannotTimeoutYourself": "You can't time yourself out.",
        "GroupTooLarge": "That group is full.",
        "AlreadyInGroup": "They're already in this group.",
        "NotInGroup": "They're not in this group.",
        "InvalidOperation": "That action isn't allowed here.",
        "InvalidProperty": "Something in that request wasn't valid.",
        "FailedValidation": "Something in that request wasn't valid.",
        "IsBot": "Bots can't do that.",
        "IsNotBot": "Only bots can do that.",
        "ReachedMaximumBots": "You've reached the maximum number of bots.",
        "DiscriminatorChangeRatelimited": "You're changing your username too often.",
        "LockedOut": "Too many attempts. Please wait and try again.",
        "InvalidCaptcha": "The captcha didn't go through. Please try again.",
        "InternalError": "Stoat had an internal error. Please try again.",
    ]
}

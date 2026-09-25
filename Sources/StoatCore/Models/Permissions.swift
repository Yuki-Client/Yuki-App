import Foundation

/// Channel and server permission bits, from `Permission` in stoat.js / stoatchat.
public struct Permission: OptionSet, Sendable, Hashable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    public static let manageChannel = Permission(rawValue: 1 << 0)
    public static let manageServer = Permission(rawValue: 1 << 1)
    public static let managePermissions = Permission(rawValue: 1 << 2)
    public static let manageRole = Permission(rawValue: 1 << 3)
    public static let manageCustomisation = Permission(rawValue: 1 << 4)

    public static let kickMembers = Permission(rawValue: 1 << 6)
    public static let banMembers = Permission(rawValue: 1 << 7)
    public static let timeoutMembers = Permission(rawValue: 1 << 8)
    public static let assignRoles = Permission(rawValue: 1 << 9)
    public static let changeNickname = Permission(rawValue: 1 << 10)
    public static let manageNicknames = Permission(rawValue: 1 << 11)
    public static let changeAvatar = Permission(rawValue: 1 << 12)
    public static let removeAvatars = Permission(rawValue: 1 << 13)

    public static let viewChannel = Permission(rawValue: 1 << 20)
    public static let readMessageHistory = Permission(rawValue: 1 << 21)
    public static let sendMessage = Permission(rawValue: 1 << 22)
    public static let manageMessages = Permission(rawValue: 1 << 23)
    public static let manageWebhooks = Permission(rawValue: 1 << 24)
    public static let inviteOthers = Permission(rawValue: 1 << 25)
    public static let sendEmbeds = Permission(rawValue: 1 << 26)
    public static let uploadFiles = Permission(rawValue: 1 << 27)
    public static let masquerade = Permission(rawValue: 1 << 28)
    public static let react = Permission(rawValue: 1 << 29)

    public static let connect = Permission(rawValue: 1 << 30)
    public static let speak = Permission(rawValue: 1 << 31)
    public static let video = Permission(rawValue: 1 << 32)
    public static let muteMembers = Permission(rawValue: 1 << 33)
    public static let deafenMembers = Permission(rawValue: 1 << 34)
    public static let moveMembers = Permission(rawValue: 1 << 35)
    public static let listen = Permission(rawValue: 1 << 36)

    public static let mentionEveryone = Permission(rawValue: 1 << 37)
    public static let mentionRoles = Permission(rawValue: 1 << 38)
    public static let bypassSlowmode = Permission(rawValue: 1 << 39)
    public static let viewAuditLogs = Permission(rawValue: 1 << 40)
    public static let useExternalEmojis = Permission(rawValue: 1 << 41)

    public static let grantAllSafe = Permission(rawValue: 0x000F_FFFF_FFFF_FFFF)

    public static let allowInTimeout: Permission = [.viewChannel, .readMessageHistory]
    public static let viewOnly: Permission = [.viewChannel, .readMessageHistory]

    public static let `default`: Permission = [
        .viewChannel, .readMessageHistory, .sendMessage, .inviteOthers, .sendEmbeds,
        .uploadFiles, .connect, .speak, .video, .listen
    ]

    public static let directMessageDefault: Permission = Permission.default.union([.react, .manageChannel])
}

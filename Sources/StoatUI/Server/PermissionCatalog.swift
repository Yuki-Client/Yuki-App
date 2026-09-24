import SwiftUI
import StoatCore

enum PermissionContext {
    case server
    case channel
    case group
}

struct PermissionEntry: Identifiable {
    let permission: Permission
    let title: String
    let server: String?
    let channel: String?
    let group: String?

    var id: Int64 { permission.rawValue }

    init(_ permission: Permission, server: String? = nil, channel: String? = nil, group: String? = nil, any: String? = nil) {
        self.permission = permission
        self.title = permission.title
        self.server = server ?? any
        self.channel = channel ?? any
        self.group = group ?? any
    }

    func description(for context: PermissionContext) -> String? {
        switch context {
        case .server: server
        case .channel: channel
        case .group: group
        }
    }
}

struct PermissionGroup: Identifiable {
    let title: String
    let entries: [PermissionEntry]
    var id: String { title }
}

/// Permission names and descriptions, grouped the same way as Stoat for Web.
enum PermissionCatalog {
    static let groups: [PermissionGroup] = [
        PermissionGroup(title: "Admin", entries: [
            PermissionEntry(.manageChannel, server: "Create, edit and delete channels", channel: "Edit and delete this channel", group: "Edit the group's name and description"),
            PermissionEntry(.manageServer, server: "Edit the server's information and settings"),
            PermissionEntry(.managePermissions, server: "Edit any permissions on the server", channel: "Edit this channel's role and default permissions", group: "Change these settings"),
            PermissionEntry(.manageRole, server: "Create and edit roles below their own"),
            PermissionEntry(.manageCustomisation, server: "Upload and delete server emoji"),
            PermissionEntry(.viewAuditLogs, server: "See the server's moderation and settings history")
        ]),
        PermissionGroup(title: "Members", entries: [
            PermissionEntry(.kickMembers, server: "Kick lower-ranking members from the server"),
            PermissionEntry(.banMembers, server: "Ban lower-ranking members from the server"),
            PermissionEntry(.timeoutMembers, server: "Temporarily stop lower-ranking members from interacting"),
            PermissionEntry(.assignRoles, server: "Give lower-ranking members roles below their own"),
            PermissionEntry(.changeNickname, server: "Change their own nickname"),
            PermissionEntry(.manageNicknames, server: "Change other members' nicknames"),
            PermissionEntry(.changeAvatar, server: "Change their own server avatar"),
            PermissionEntry(.removeAvatars, server: "Remove other members' server avatars")
        ]),
        PermissionGroup(title: "Channels", entries: [
            PermissionEntry(.viewChannel, server: "See channels on this server", channel: "See this channel"),
            PermissionEntry(.readMessageHistory, server: "Read past messages in channels", channel: "Read past messages in this channel"),
            PermissionEntry(.sendMessage, server: "Send messages in channels", any: "Send messages here"),
            PermissionEntry(.manageMessages, any: "Delete and pin other members' messages"),
            PermissionEntry(.manageWebhooks, any: "Create and edit webhooks"),
            PermissionEntry(.inviteOthers, group: "Add new members to the group", any: "Create invites for others to use")
        ]),
        PermissionGroup(title: "Messaging", entries: [
            PermissionEntry(.sendEmbeds, any: "Show link previews and send custom embeds"),
            PermissionEntry(.uploadFiles, any: "Send attachments"),
            PermissionEntry(.masquerade, any: "Change name and avatar on individual messages"),
            PermissionEntry(.react, any: "React to messages with emoji"),
            PermissionEntry(.bypassSlowmode, server: "Ignore slowmode in channels", channel: "Ignore slowmode in this channel")
        ]),
        PermissionGroup(title: "Voice", entries: [
            PermissionEntry(.connect, server: "Join voice channels", channel: "Join this voice channel"),
            PermissionEntry(.speak, server: "Talk in voice calls", channel: "Talk in voice calls"),
            PermissionEntry(.video, server: "Share camera or screen in voice calls", channel: "Share camera or screen in voice calls"),
            PermissionEntry(.listen, server: "Hear others and see their video", channel: "Hear others and see their video"),
            PermissionEntry(.muteMembers, server: "Mute lower-ranking members in voice calls", channel: "Mute lower-ranking members in voice calls"),
            PermissionEntry(.deafenMembers, server: "Deafen lower-ranking members in voice calls", channel: "Deafen lower-ranking members in voice calls"),
            PermissionEntry(.moveMembers, server: "Move members between voice channels", channel: "Move members between voice channels")
        ]),
        PermissionGroup(title: "Mentions", entries: [
            PermissionEntry(.mentionEveryone, server: "Use @everyone and @online", channel: "Use @everyone and @online"),
            PermissionEntry(.mentionRoles, server: "Mention roles", channel: "Mention roles")
        ])
    ]
}

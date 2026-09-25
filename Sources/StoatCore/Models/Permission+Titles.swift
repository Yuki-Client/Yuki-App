import Foundation

extension Permission {
    /// Every named permission with its display name, in the order Stoat for Web lists them.
    public static let named: [(permission: Permission, title: String)] = [
        (.manageChannel, "Manage Channel"),
        (.manageServer, "Manage Server"),
        (.managePermissions, "Manage Permissions"),
        (.manageRole, "Manage Roles"),
        (.manageCustomisation, "Manage Customisation"),
        (.viewAuditLogs, "View Audit Log"),
        (.kickMembers, "Kick Members"),
        (.banMembers, "Ban Members"),
        (.timeoutMembers, "Timeout Members"),
        (.assignRoles, "Assign Roles"),
        (.changeNickname, "Change Nickname"),
        (.manageNicknames, "Manage Nicknames"),
        (.changeAvatar, "Change Avatar"),
        (.removeAvatars, "Remove Avatars"),
        (.viewChannel, "View Channel"),
        (.readMessageHistory, "Read Message History"),
        (.sendMessage, "Send Messages"),
        (.manageMessages, "Manage Messages"),
        (.manageWebhooks, "Manage Webhooks"),
        (.inviteOthers, "Invite Others"),
        (.sendEmbeds, "Send Embeds"),
        (.uploadFiles, "Upload Files"),
        (.masquerade, "Masquerade"),
        (.react, "React"),
        (.useExternalEmojis, "Use External Emojis"),
        (.bypassSlowmode, "Bypass Slowmode"),
        (.connect, "Connect"),
        (.speak, "Speak"),
        (.video, "Video"),
        (.listen, "Listen"),
        (.muteMembers, "Mute Members"),
        (.deafenMembers, "Deafen Members"),
        (.moveMembers, "Move Members"),
        (.mentionEveryone, "Mention Everyone"),
        (.mentionRoles, "Mention Roles")
    ]

    public var title: String {
        Self.named.first { $0.permission == self }?.title ?? "Permission \(rawValue)"
    }
}

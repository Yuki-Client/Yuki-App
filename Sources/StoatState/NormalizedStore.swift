import Foundation
import Observation
import StoatCore

/// Collections are separate observed properties so a presence change only re-renders views
/// reading `users`, and so on.
@Observable
@MainActor
public final class NormalizedStore {
    public var users: [String: User] = [:]
    public var servers: [String: Server] = [:]
    public var channels: [String: Channel] = [:]
    public var members: [String: [String: ServerMember]] = [:]
    public var emojis: [String: Emoji] = [:]
    public var unreads: [String: ChannelUnread] = [:]
    /// Until unreads arrive, a channel with no read position is unknown rather than unread.
    public var unreadsLoaded = false
    public var typingUsers: [String: Set<String>] = [:]
    public var voiceStates: [String: [String: UserVoiceState]] = [:]
    /// Server IDs in the synced flat order that clients without folders use.
    public var serverOrder: [String] = []
    /// Server and folder IDs in the synced sidebar order, once a client with folders has saved one.
    public var serverSidebar: [String]?
    public var serverFolders: [ServerFolder] = []
    public var notificationOptions = NotificationOptions()
    public var currentUserId: String?

    @ObservationIgnored
    public private(set) var timelines: [String: ChannelTimeline] = [:]

    public init() {}

    public func timeline(for channelId: String) -> ChannelTimeline {
        if let existing = timelines[channelId] {
            return existing
        }
        let timeline = ChannelTimeline(channelId: channelId)
        timelines[channelId] = timeline
        return timeline
    }

    public func existingTimeline(for channelId: String) -> ChannelTimeline? {
        timelines[channelId]
    }

    public func removeTimeline(for channelId: String) {
        timelines.removeValue(forKey: channelId)
    }

    public func findMessage(id: String, in channelId: String? = nil) -> Message? {
        if let channelId {
            return timelines[channelId]?.message(id: id)
        }
        for timeline in timelines.values {
            if let message = timeline.message(id: id) {
                return message
            }
        }
        return nil
    }

    public func reset() {
        users = [:]
        servers = [:]
        channels = [:]
        members = [:]
        emojis = [:]
        unreads = [:]
        unreadsLoaded = false
        typingUsers = [:]
        voiceStates = [:]
        serverOrder = []
        serverSidebar = nil
        serverFolders = []
        notificationOptions = NotificationOptions()
        currentUserId = nil
        timelines = [:]
    }

    // MARK: - Ingestion

    /// Applies a Ready payload. Ready is authoritative, so collections it covers are replaced.
    public func ingest(ready: ReadyPayload) {
        var nextUsers = users
        for user in ready.users {
            nextUsers[user.id] = user
            if user.relationship == .user {
                currentUserId = user.id
            }
        }
        users = nextUsers

        servers = Dictionary(ready.servers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        channels = Dictionary(ready.channels.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        var nextMembers: [String: [String: ServerMember]] = [:]
        for (serverId, existing) in members where servers[serverId] != nil {
            nextMembers[serverId] = existing
        }
        for member in ready.members {
            nextMembers[member.key.server, default: [:]][member.key.user] = member
        }
        members = nextMembers

        emojis = Dictionary(ready.emojis.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        var nextVoice: [String: [String: UserVoiceState]] = [:]
        for state in ready.voiceStates {
            nextVoice[state.id] = Dictionary(state.participants.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        }
        voiceStates = nextVoice

        for channelId in timelines.keys where channels[channelId] == nil {
            timelines.removeValue(forKey: channelId)
        }
    }

    // These update in place: copying the whole dictionary for each call gets slow once
    // thousands of users are loaded.
    public func upsert(users list: [User]) {
        for user in list {
            users[user.id] = user
        }
    }

    public func upsert(members list: [ServerMember]) {
        for member in list {
            members[member.key.server, default: [:]][member.key.user] = member
        }
    }

    // MARK: - Channel queries

    public var directChannels: [Channel] {
        channels.values
            .filter { channel in
                switch channel.channelType {
                case .directMessage: return channel.active ?? true
                case .group, .savedMessages: return true
                default: return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.channelType == .savedMessages { return true }
                if rhs.channelType == .savedMessages { return false }
                return (lhs.lastMessageId ?? lhs.id) > (rhs.lastMessageId ?? rhs.id)
            }
    }

    public func channels(forServer serverId: String) -> [Channel] {
        guard let server = servers[serverId] else { return [] }
        return server.channels.compactMap { channels[$0] }
            .filter { hasPermission(.viewChannel, in: $0) }
    }

    public func categorizedChannels(forServer serverId: String) -> (categorized: [(category: ServerCategory, channels: [Channel])], uncategorized: [Channel]) {
        let visible = channels(forServer: serverId)
        guard let categories = servers[serverId]?.categories, !categories.isEmpty else {
            return (categorized: [], uncategorized: visible)
        }

        let visibleById = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var categorizedIds = Set<String>()
        var sections: [(category: ServerCategory, channels: [Channel])] = []

        for category in categories {
            // A channel listed more than once only shows in the first place it's listed.
            let list = category.channels.compactMap { id in
                categorizedIds.insert(id).inserted ? visibleById[id] : nil
            }
            if !list.isEmpty {
                sections.append((category: category, channels: list))
            }
        }

        let uncategorized = visible.filter { !categorizedIds.contains($0.id) }
        return (categorized: sections, uncategorized: uncategorized)
    }

    public func hasActiveCall(serverId: String) -> Bool {
        guard let server = servers[serverId] else { return false }
        return server.channels.contains { voiceStates[$0]?.isEmpty == false }
    }

    public var sidebarLayout: ServerSidebarLayout {
        ServerSidebarLayout(order: serverSidebar ?? serverOrder, folders: serverFolders)
    }

    public var sidebarEntries: [SidebarEntry] {
        sidebarLayout.entries(servers: servers)
    }

    public var orderedServers: [Server] {
        sidebarEntries.flatMap(\.servers)
    }

    public func folder(containing serverId: String) -> ServerFolder? {
        serverFolders.first { $0.servers.contains(serverId) }
    }

    public func emojis(forServer serverId: String) -> [Emoji] {
        emojis.values.filter { $0.parent.serverId == serverId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var availableEmojis: [Emoji] {
        emojis.values.filter { emoji in
            guard let serverId = emoji.parent.serverId else { return false }
            return servers[serverId] != nil
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public struct EmojiServerSection: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let icon: Attachment?
        public let emojis: [Emoji]
    }

    /// Custom emoji grouped by server, with the current server first, then the sidebar order.
    public func emojiSections(currentServerId: String?) -> [EmojiServerSection] {
        let grouped = Dictionary(grouping: availableEmojis) { $0.parent.serverId ?? "" }
        var ordered = orderedServers
        if let currentServerId, let index = ordered.firstIndex(where: { $0.id == currentServerId }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return ordered.compactMap { server in
            guard let list = grouped[server.id], !list.isEmpty else { return nil }
            return EmojiServerSection(id: server.id, name: server.name, icon: server.icon, emojis: list)
        }
    }

    // MARK: - Members & roles

    public func member(userId: String, in serverId: String) -> ServerMember? {
        members[serverId]?[userId]
    }

    /// Roles of a member ordered from least to most important (lowest rank last), matching stoat.js.
    public func orderedRoles(userId: String, in serverId: String) -> [(id: String, role: Role)] {
        guard let server = servers[serverId], let member = members[serverId]?[userId] else { return [] }
        return member.roles
            .compactMap { id in server.roles[id].map { (id: id, role: $0) } }
            .sorted { $0.role.rank > $1.role.rank }
    }

    public func memberRoles(userId: String, in serverId: String) -> [(id: String, role: Role)] {
        orderedRoles(userId: userId, in: serverId).reversed()
    }

    public func memberRoleColor(userId: String, in serverId: String) -> String? {
        orderedRoles(userId: userId, in: serverId).last(where: { $0.role.colour?.isEmpty == false })?.role.colour
    }

    public func memberHoistedRole(userId: String, in serverId: String) -> (id: String, role: Role)? {
        orderedRoles(userId: userId, in: serverId).last(where: { $0.role.hoist })
    }

    /// Highest role rank for a member; lower numbers are more important. Owners rank above everyone.
    public func memberRanking(userId: String, in serverId: String) -> Int64 {
        guard let server = servers[serverId] else { return .max }
        if server.owner == userId { return .min }
        return orderedRoles(userId: userId, in: serverId).last?.role.rank ?? .max
    }

    public func displayName(userId: String, serverId: String?) -> String {
        knownName(userId: userId, serverId: serverId) ?? "Unknown User"
    }

    /// Nil until the user has been loaded, which in large servers can be after they start typing.
    public func knownName(userId: String, serverId: String?) -> String? {
        if let serverId, let nickname = members[serverId]?[userId]?.nickname, !nickname.isEmpty {
            return nickname
        }
        return users[userId]?.visibleName
    }

    public func avatar(userId: String, serverId: String?) -> Attachment? {
        if let serverId, let avatar = members[serverId]?[userId]?.avatar {
            return avatar
        }
        return users[userId]?.avatar
    }

    // MARK: - Unreads

    public func isMuted(channel: Channel) -> Bool {
        if notificationOptions.isChannelMuted(channel.id) { return true }
        if let serverId = channel.server, notificationOptions.isServerMuted(serverId) { return true }
        return false
    }

    public func isUnread(channel: Channel) -> Bool {
        guard unreadsLoaded, channel.channelType != .savedMessages, let lastMessageId = channel.lastMessageId else { return false }
        if isMuted(channel: channel) { return false }
        let lastRead = unreads[channel.id]?.lastId ?? "0"
        if !unreadMentions(in: channel.id).isEmpty { return true }
        if lastRead >= lastMessageId { return false }
        // Stoat can point a channel at a deleted message, leaving it unread forever; trust the
        // timeline when it's in sync.
        if let timeline = timelines[channel.id], timeline.isSynced, let newest = timeline.newestMessageId {
            return newest > lastRead
        }
        return true
    }

    /// Stoat adds role and @everyone mentions a moment late, so they can land behind the read
    /// position and never clear. Those are ignored.
    public func unreadMentions(in channelId: String) -> [String] {
        guard let unread = unreads[channelId], !unread.mentions.isEmpty else { return [] }
        let lastRead = unread.lastId ?? "0"
        return unread.mentions.filter { $0 > lastRead }
    }

    /// Channels holding mentions Stoat still lists although they've been read, which an
    /// acknowledgement will clear for every client.
    public var channelsWithStaleMentions: [String: String] {
        var result: [String: String] = [:]
        for (channelId, unread) in unreads {
            guard !unread.mentions.isEmpty, let lastRead = unread.lastId else { continue }
            if unread.mentions.allSatisfy({ $0 <= lastRead }) {
                result[channelId] = lastRead
            }
        }
        return result
    }

    public func mentionCount(channelId: String) -> Int {
        guard let channel = channels[channelId], channel.channelType != .savedMessages else { return 0 }
        return unreadMentions(in: channelId).count
    }

    public func isUnread(serverId: String) -> Bool {
        guard !notificationOptions.isServerMuted(serverId) else { return false }
        return channels(forServer: serverId).contains { isUnread(channel: $0) }
    }

    public func mentionCount(serverId: String) -> Int {
        channels(forServer: serverId).reduce(0) { $0 + mentionCount(channelId: $1.id) }
    }

    public var unreadDirectCount: Int {
        directChannels.filter { $0.channelType != .savedMessages && isUnread(channel: $0) }.count
    }

    public var badgeCount: Int {
        let serverMentions = servers.keys.reduce(0) { $0 + mentionCount(serverId: $1) }
        return serverMentions + unreadDirectCount
    }

    public func markRead(channelId: String, messageId: String) {
        guard let userId = currentUserId else { return }
        var unread = unreads[channelId] ?? ChannelUnread(channel: channelId, user: userId)
        if let lastId = unread.lastId, lastId >= messageId, unread.mentions.isEmpty {
            return
        }
        unread.lastId = max(unread.lastId ?? "0", messageId)
        unread.mentions = []
        unreads[channelId] = unread
    }

    // MARK: - Permissions

    public func hasPermission(_ permission: Permission, in channel: Channel) -> Bool {
        permissions(in: channel).contains(permission)
    }

    public func hasPermission(_ permission: Permission, in server: Server) -> Bool {
        permissions(in: server).contains(permission)
    }

    /// Calculates the current user's permissions for a server (port of stoat.js `calculatePermission`).
    public func permissions(in server: Server) -> Permission {
        guard let userId = currentUserId else { return [] }
        if users[userId]?.privileged == true || server.owner == userId {
            return .grantAllSafe
        }

        var value = server.defaultPermissions
        for entry in orderedRoles(userId: userId, in: server.id) {
            value = (value | entry.role.permissions.a) & ~entry.role.permissions.d
        }

        var result = Permission(rawValue: value)
        if members[server.id]?[userId]?.activeTimeout != nil {
            result = result.intersection(.allowInTimeout)
        }
        return result
    }

    public func permissions(in channel: Channel) -> Permission {
        guard let userId = currentUserId else { return [] }
        if users[userId]?.privileged == true {
            return .grantAllSafe
        }

        switch channel.channelType {
        case .savedMessages:
            return .grantAllSafe
        case .directMessage:
            let otherId = channel.otherRecipient(currentUserId: userId)
            let relationship = otherId.flatMap { users[$0]?.relationship }
            if relationship == .blocked || relationship == .blockedOther {
                return .viewOnly
            }
            return .directMessageDefault
        case .group:
            if channel.owner == userId {
                return .grantAllSafe
            }
            return channel.permissions.map { Permission(rawValue: $0) } ?? .directMessageDefault
        case .textChannel, .voiceChannel:
            guard let serverId = channel.server, let server = servers[serverId] else { return [] }
            if server.owner == userId {
                return .grantAllSafe
            }

            var value = permissions(in: server).rawValue
            if let defaults = channel.defaultPermissions {
                value = (value | defaults.a) & ~defaults.d
            }
            for entry in orderedRoles(userId: userId, in: serverId) {
                if let override = channel.rolePermissions[entry.id] {
                    value = (value | override.a) & ~override.d
                }
            }

            var result = Permission(rawValue: value)
            if members[serverId]?[userId]?.activeTimeout != nil {
                result = result.intersection(.allowInTimeout)
            }
            return result
        case .unknown:
            return []
        }
    }

    /// Whether the current user outranks another member (required to kick, ban, or edit them).
    public func canModerate(userId targetId: String, in serverId: String) -> Bool {
        guard let me = currentUserId, me != targetId, let server = servers[serverId] else { return false }
        if server.owner == targetId { return false }
        if server.owner == me { return true }
        return memberRanking(userId: me, in: serverId) < memberRanking(userId: targetId, in: serverId)
    }
}

/// Per-server and per-channel notification preferences, synced as the `notifications` setting.
public struct NotificationOptions: Codable, Sendable, Equatable {
    public enum Level: String, Codable, Sendable, CaseIterable {
        case all
        case mention
        case none
    }

    public struct MuteState: Codable, Sendable, Equatable {
        public var until: Double?

        public init(until: Double? = nil) {
            self.until = until
        }

        public var isActive: Bool {
            guard let until else { return true }
            return until > Date().timeIntervalSince1970 * 1000
        }
    }

    public var server: [String: Level] = [:]
    public var channel: [String: Level] = [:]
    public var serverMutes: [String: MuteState] = [:]
    public var channelMutes: [String: MuteState] = [:]

    enum CodingKeys: String, CodingKey {
        case server, channel
        case serverMutes = "server_mutes"
        case channelMutes = "channel_mutes"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy clients stored "muted" as a level; migrate it into the mute dictionaries.
        let rawServer = (try? c.decodeIfPresent([String: String].self, forKey: .server)) ?? [:]
        let rawChannel = (try? c.decodeIfPresent([String: String].self, forKey: .channel)) ?? [:]
        serverMutes = (try? c.decodeIfPresent([String: MuteState].self, forKey: .serverMutes)) ?? [:]
        channelMutes = (try? c.decodeIfPresent([String: MuteState].self, forKey: .channelMutes)) ?? [:]
        for (id, value) in rawServer {
            if value == "muted" { serverMutes[id] = MuteState() }
            if let level = Level(rawValue: value) { server[id] = level }
        }
        for (id, value) in rawChannel {
            if value == "muted" { channelMutes[id] = MuteState() }
            if let level = Level(rawValue: value) { channel[id] = level }
        }
    }

    public func isServerMuted(_ id: String) -> Bool {
        serverMutes[id]?.isActive ?? false
    }

    public func isChannelMuted(_ id: String) -> Bool {
        channelMutes[id]?.isActive ?? false
    }

    public func level(for channel: Channel) -> Level {
        if let level = self.channel[channel.id] { return level }
        if let serverId = channel.server {
            return server[serverId] ?? .mention
        }
        return .all
    }
}

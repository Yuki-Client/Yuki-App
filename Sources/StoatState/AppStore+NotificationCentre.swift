import Foundation
import StoatCore

public struct NotificationItem: Codable, Identifiable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case mention
        case roleMention
        /// @everyone or @online.
        case everyone
        case directMessage
    }

    public var message: Message
    public let kind: Kind

    public var id: String { message.id }
    public var channelId: String { message.channel }

    public init(message: Message, kind: Kind) {
        self.message = message
        self.kind = kind
    }
}

/// Stoat can't list past mentions, so Yuki keeps its own. Read state still comes from Stoat, so
/// it matches other clients.
extension AppStore {
    private static let mentionLimit = 200
    private static let directMessageLimit = 100
    private static let seedLimit = 50

    private struct SavedNotifications: Codable, Sendable {
        var items: [NotificationItem]
        var removed: [String]
    }

    private var notificationsFilename: String? {
        store.currentUserId.map { "notifications-\($0).json" }
    }

    public func isUnread(_ item: NotificationItem) -> Bool {
        store.isUnread(item)
    }

    public var visibleNotifications: [NotificationItem] {
        notificationItems.filter { store.channels[$0.channelId] != nil }
    }

    public var unreadNotificationCount: Int {
        visibleNotifications.lazy.filter { self.isUnread($0) }.count
    }

    func notificationKind(for message: Message) -> NotificationItem.Kind? {
        store.notificationKind(for: message)
    }

    func recordNotification(for message: Message) {
        guard let kind = notificationKind(for: message) else { return }
        insertNotifications([NotificationItem(message: message, kind: kind)])
    }

    private func insertNotifications(_ newItems: [NotificationItem]) {
        let known = Set(notificationItems.map(\.id))
        let additions = newItems.filter { !known.contains($0.id) && !removedNotificationIds.contains($0.id) }
        guard !additions.isEmpty else { return }

        let sorted = (notificationItems + additions).sorted { $0.id > $1.id }
        var mentions = 0
        var directMessages = 0
        notificationItems = sorted.filter { item in
            if item.kind == .directMessage {
                directMessages += 1
                return directMessages <= Self.directMessageLimit
            }
            mentions += 1
            return mentions <= Self.mentionLimit
        }
        scheduleNotificationSave()
    }

    func updateNotification(id: String, _ change: (inout Message) -> Void) {
        guard let index = notificationItems.firstIndex(where: { $0.id == id }) else { return }
        change(&notificationItems[index].message)
        scheduleNotificationSave()
    }

    func removeNotifications(ids: Set<String>) {
        let before = notificationItems.count
        notificationItems.removeAll { ids.contains($0.id) }
        if notificationItems.count != before {
            scheduleNotificationSave()
        }
    }

    public func fetchMissedNotifications() async {
        let known = Set(notificationItems.map(\.id)).union(removedNotificationIds)
        // Only mentions still ahead of what's been read: Stoat keeps listing ones for messages
        // already read, and fetching those put messages back in here long after they were dealt with.
        let missing = store.unreads.values
            .flatMap { unread in store.unreadMentions(in: unread.id.channel).map { (channel: unread.id.channel, message: $0) } }
            .filter { !known.contains($0.message) && store.channels[$0.channel] != nil }
            .sorted { $0.message > $1.message }
            .prefix(Self.seedLimit)
        guard !missing.isEmpty else { return }

        var fetched: [Message] = []
        await withTaskGroup(of: Message?.self) { group in
            var running = 0
            for entry in missing {
                if running == 4, let message = await group.next() {
                    running -= 1
                    if let message { fetched.append(message) }
                }
                group.addTask { [apiClient] in
                    try? await apiClient.fetchMessage(channelId: entry.channel, messageId: entry.message)
                }
                running += 1
            }
            for await message in group {
                if let message { fetched.append(message) }
            }
        }

        // Stoat listed these as mentions, so keep them even when the message itself doesn't say why.
        let items = fetched.map { message in
            NotificationItem(message: message, kind: notificationKind(for: message) ?? (store.channels[message.channel]?.isPrivate == true ? .directMessage : .mention))
        }
        queueUserFetch(Array(Set(items.map(\.message.author))).filter { store.users[$0] == nil })
        insertNotifications(items)
    }

    public func refreshNotifications() async {
        await syncUnreads()
        await fetchMissedNotifications()
    }

    /// Removes an item from the Notification Centre without changing whether its channel is read.
    public func dismissNotification(_ id: String) {
        removedNotificationIds.insert(id)
        removeNotifications(ids: [id])
    }

    public func clearReadNotifications() {
        let read = notificationItems.filter { !isUnread($0) }.map(\.id)
        removedNotificationIds.formUnion(read)
        removeNotifications(ids: Set(read))
    }

    public func markAllNotificationsRead() {
        let channels = Set(visibleNotifications.filter { isUnread($0) }.map(\.channelId))
        for channelId in channels {
            markChannelAsRead(channelId)
        }
    }

    func loadNotifications() async {
        guard let filename = notificationsFilename else { return }
        let saved: SavedNotifications? = await DiskCacheStore.shared.load(filename: filename)
        notificationItems = saved?.items ?? []
        removedNotificationIds = Set(saved?.removed ?? [])
    }

    func scheduleNotificationSave() {
        notificationSaveTask?.cancel()
        notificationSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let filename = self.notificationsFilename else { return }
            let removed = self.removedNotificationIds.sorted().suffix(500)
            let saved = SavedNotifications(items: self.notificationItems, removed: Array(removed))
            await DiskCacheStore.shared.save(saved, filename: filename)
        }
    }

    func clearNotifications() async {
        notificationSaveTask?.cancel()
        notificationSaveTask = nil
        if let filename = notificationsFilename {
            await DiskCacheStore.shared.clear(filename: filename)
        }
        notificationItems = []
        removedNotificationIds = []
    }
}

extension NormalizedStore {
    public func isUnread(_ item: NotificationItem) -> Bool {
        guard let unread = unreads[item.channelId] else { return true }
        return item.id > (unread.lastId ?? "0")
    }

    /// Stoat only adds role and mass mentions to unreads a moment later, so Yuki works them out
    /// itself as messages arrive.
    public func mentionsMe(_ message: Message) -> Bool {
        guard let userId = currentUserId, message.author != userId else { return false }
        if message.mentions?.contains(userId) == true { return true }
        guard let channel = channels[message.channel] else { return false }
        if let serverId = channel.server, let roleMentions = message.roleMentions, !roleMentions.isEmpty {
            let myRoles = Set(member(userId: userId, in: serverId)?.roles ?? [])
            if roleMentions.contains(where: myRoles.contains) { return true }
        }
        return message.mentionsEveryone || message.mentionsOnline
    }

    public func notificationKind(for message: Message) -> NotificationItem.Kind? {
        guard let userId = currentUserId,
              message.author != userId,
              message.system == nil,
              let channel = channels[message.channel],
              users[message.author]?.relationship != .blocked else { return nil }

        switch channel.channelType {
        case .directMessage, .group:
            return isMuted(channel: channel) ? nil : .directMessage
        case .savedMessages:
            return nil
        default:
            break
        }

        if message.mentions?.contains(userId) == true {
            return .mention
        }
        // A ping through one of your roles counts even in a muted channel: muting silences
        // notifications, while the Notification Centre is where you catch up afterwards.
        if let serverId = channel.server, let roleMentions = message.roleMentions, !roleMentions.isEmpty {
            let myRoles = Set(member(userId: userId, in: serverId)?.roles ?? [])
            if roleMentions.contains(where: myRoles.contains) {
                return .roleMention
            }
        }
        // @everyone reaches whole servers, so muting does keep it out.
        guard !isMuted(channel: channel), notificationOptions.level(for: channel) != .none else { return nil }
        if message.mentionsEveryone || message.mentionsOnline {
            return .everyone
        }
        return nil
    }
}

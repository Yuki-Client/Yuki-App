import SwiftUI
import StoatCore
import StoatState

/// Unread DMs and groups as avatars under the bell, so you can see who messaged at a glance.
struct UnreadConversationsRail: View {
    let store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let limit = 8

    var body: some View {
        let conversations = unreadConversations
        VStack(spacing: 10) {
            ForEach(conversations) { channel in
                let title = channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId)
                let count = unreadCount(in: channel)
                ServerRailButton(
                    title: title,
                    isSelected: false,
                    isUnread: false,
                    mentionCount: count
                ) {
                    icon(for: channel, title: title)
                } action: {
                    store.openChannel(channel.id)
                } menu: {
                    Button {
                        store.markChannelAsRead(channel.id)
                    } label: {
                        Label("Mark as Read", systemImage: "checkmark.message")
                    }
                }
                .accessibilityValue(count == 1 ? "1 unread message" : "\(count) unread messages")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: conversations.map(\.id))
    }

    private var unreadConversations: [Channel] {
        Array(
            store.store.directChannels
                .filter { $0.channelType != .savedMessages && store.store.isUnread(channel: $0) }
                .prefix(Self.limit)
        )
    }

    // Stoat doesn't give unread counts, so count the messages Yuki has seen arrive after the read
    // position. A conversation that went unread while Yuki was closed shows at least one.
    private func unreadCount(in channel: Channel) -> Int {
        let lastRead = store.store.unreads[channel.id]?.lastId ?? "0"
        let me = store.store.currentUserId
        var ids = Set<String>()
        for message in store.store.existingTimeline(for: channel.id)?.messages ?? [] where message.id > lastRead && message.author != me {
            ids.insert(message.id)
        }
        for item in store.notificationItems where item.channelId == channel.id && item.id > lastRead {
            ids.insert(item.id)
        }
        return max(1, ids.count)
    }

    @ViewBuilder
    private func icon(for channel: Channel, title: String) -> some View {
        if channel.channelType == .directMessage {
            let otherId = channel.otherRecipient(currentUserId: store.store.currentUserId)
            AvatarView(avatar: otherId.flatMap { store.store.users[$0]?.avatar }, fallbackText: title, size: 48, userId: otherId)
        } else if channel.icon != nil {
            AvatarView(avatar: channel.icon, fallbackText: title, size: 48)
        } else {
            Image(systemName: "person.3.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(YukiTheme.accent)
                .frame(width: 48, height: 48)
                .background(YukiTheme.cardSurface)
        }
    }
}

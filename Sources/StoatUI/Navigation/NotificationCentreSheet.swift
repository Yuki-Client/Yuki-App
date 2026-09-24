import SwiftUI
import StoatCore
import StoatState

public struct NotificationCentreSheet: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @AppStorage("yuki.notificationFilter") private var filter: Filter = .all
    @State private var showCatchUpConfirmation = false

    public init(store: AppStore) {
        self.store = store
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, mentions, messages

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .mentions: "Mentions"
            case .messages: "Messages"
            }
        }
    }

    /// One row per mention; back-to-back messages in the same conversation share a row.
    private struct Row: Identifiable {
        let item: NotificationItem
        var ids: [String]

        var id: String { item.id }
    }

    private var rows: [Row] {
        var result: [Row] = []
        for item in store.visibleNotifications {
            switch filter {
            case .mentions where item.kind == .directMessage: continue
            case .messages where item.kind != .directMessage: continue
            default: break
            }
            if item.kind == .directMessage, let last = result.last,
               last.item.kind == .directMessage, last.item.channelId == item.channelId {
                result[result.count - 1].ids.append(item.id)
                continue
            }
            result.append(Row(item: item, ids: [item.id]))
        }
        return result
    }

    public var body: some View {
        NavigationStack {
            let rows = rows
            List {
                ForEach(rows) { row in
                    let isUnread = store.isUnread(row.item)
                    Button {
                        open(row.item)
                    } label: {
                        NotificationRow(item: row.item, earlierCount: row.ids.count - 1, isUnread: isUnread)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isUnread ? YukiTheme.accent.opacity(0.07) : Color.clear)
                    .swipeActions(edge: .leading) {
                        if isUnread {
                            Button {
                                store.markChannelAsRead(row.item.channelId)
                            } label: {
                                Label("Mark as Read", systemImage: "envelope.open")
                            }
                            .tint(YukiTheme.accent)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            remove(row)
                        } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                    }
                    .contextMenu {
                        Button {
                            open(row.item)
                        } label: {
                            Label("Jump to Message", systemImage: "arrow.turn.down.right")
                        }
                        if isUnread {
                            Button {
                                store.markChannelAsRead(row.item.channelId)
                            } label: {
                                Label("Mark as Read", systemImage: "envelope.open")
                            }
                        }
                        if let content = row.item.message.content, !content.isEmpty {
                            Button {
                                UIPasteboard.general.string = content
                            } label: {
                                Label("Copy Text", systemImage: "doc.on.doc")
                            }
                        }
                        Button(role: .destructive) {
                            remove(row)
                        } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(YukiTheme.systemBackground)
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "bell")
                    } description: {
                        Text(emptyDescription)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(YukiTheme.systemBackground)
            }
            .refreshable {
                await store.refreshNotifications()
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            store.markAllNotificationsRead()
                        } label: {
                            Label("Mark All as Read", systemImage: "checkmark.message")
                        }
                        .disabled(store.unreadNotificationCount == 0)
                        Button(role: .destructive) {
                            store.clearReadNotifications()
                        } label: {
                            Label("Clear Read", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Notification options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await store.fetchMissedNotifications()
            }
            .alert("Mark everything read?", isPresented: $showCatchUpConfirmation) {
                Button("Mark Everything Read") {
                    Task { await store.markEverythingRead() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Marks every server and conversation read, which also clears unreads Stoat has left stuck.")
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No Notifications"
        case .mentions: "No Mentions"
        case .messages: "No Messages"
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .all: "Mentions and direct messages will show up here."
        case .mentions: "When someone mentions you, it'll show up here."
        case .messages: "Direct messages and group messages will show up here."
        }
    }

    private func open(_ item: NotificationItem) {
        dismiss()
        // Let the sheet start closing before navigating underneath it.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            store.openMessage(item.id, in: item.channelId)
        }
    }

    private func remove(_ row: Row) {
        for id in row.ids {
            store.dismissNotification(id)
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    let earlierCount: Int
    let isUnread: Bool

    @Environment(AppStore.self) private var appStore

    private var message: Message { item.message }
    private var channel: Channel? { appStore.store.channels[item.channelId] }
    private var serverId: String? { channel?.server }

    private var authorName: String {
        message.masquerade?.name ?? message.webhook?.name ?? appStore.store.displayName(userId: message.author, serverId: serverId)
    }

    private var namePaint: AnyShapeStyle {
        if let colour = message.masquerade?.colour, let paint = AnyShapeStyle.stoatPaint(colour) { return paint }
        if message.webhook == nil, let serverId, let paint = AnyShapeStyle.stoatPaint(appStore.store.memberRoleColor(userId: message.author, in: serverId)) {
            return paint
        }
        return AnyShapeStyle(.primary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MessageAuthorAvatar(message: message, serverId: serverId, name: authorName, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    location
                    Spacer(minLength: 6)
                    Text(MessageRowView.timestampText(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(namePaint)
                        .lineLimit(1)
                    if let tag {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(YukiTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(YukiTheme.accent.opacity(0.15)))
                            .lineLimit(1)
                    }
                }
                EmojiText(text: preview, emojiSize: 16)
                    .font(.subheadline)
                    .foregroundStyle(isUnread ? Color.primary : Color.secondary)
                    .lineLimit(4)
                if earlierCount > 0 {
                    Text(earlierCount == 1 ? "+1 earlier message" : "+\(earlierCount) earlier messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if isUnread {
                Circle()
                    .fill(YukiTheme.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: -11)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? "Unread" : "")
    }

    @ViewBuilder
    private var location: some View {
        HStack(spacing: 5) {
            switch channel?.channelType {
            case .directMessage:
                Image(systemName: "bubble.left.fill")
                    .font(.caption2)
                Text("Direct Message")
            case .group:
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                Text(channel?.displayName(withUsers: appStore.store.users, currentUserId: appStore.store.currentUserId) ?? "Group")
            default:
                if let serverId, let server = appStore.store.servers[serverId] {
                    AvatarView(avatar: server.icon, fallbackText: server.name, size: 16, isRounded: false)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text("\(server.name) · #\(channel?.name ?? "channel")")
                } else {
                    Text("#\(channel?.name ?? "channel")")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var tag: String? {
        switch item.kind {
        case .mention, .directMessage:
            return nil
        case .everyone:
            return message.mentionsOnline && !message.mentionsEveryone ? "@online" : "@everyone"
        case .roleMention:
            guard let serverId, let userId = appStore.store.currentUserId else { return "@role" }
            let myRoles = Set(appStore.store.member(userId: userId, in: serverId)?.roles ?? [])
            let name = message.roleMentions?.first(where: myRoles.contains).flatMap { appStore.store.servers[serverId]?.roles[$0]?.name }
            return "@\(name ?? "role")"
        }
    }

    private var preview: String {
        if let content = message.content, !content.isEmpty {
            return MentionFormatter.previewText(content, store: appStore.store, serverId: serverId)
        }
        if let count = message.attachments?.count, count > 0 {
            return count == 1 ? "Sent an attachment" : "Sent \(count) attachments"
        }
        return "Sent an embed"
    }
}

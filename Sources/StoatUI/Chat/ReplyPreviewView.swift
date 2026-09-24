import SwiftUI
import StoatCore
import StoatState

struct ReplyPreviewView: View {
    let channelId: String
    let messageId: String
    let serverId: String?
    let onTap: () -> Void

    @Environment(AppStore.self) private var appStore
    @State private var fetched: Message?
    @State private var didFail = false

    private var message: Message? {
        appStore.store.existingTimeline(for: channelId)?.message(id: messageId) ?? fetched
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                if let message {
                    MessageAuthorAvatar(message: message, serverId: serverId, name: name(for: message), size: 16)
                    Text(name(for: message))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(namePaint(for: message) ?? AnyShapeStyle(.primary))
                    EmojiText(text: preview(for: message, keepingEmoji: true), emojiSize: 14)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(didFail ? "Original message was deleted" : "Loading reply…")
                        .font(.caption.italic())
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: messageId) {
            guard message == nil else { return }
            fetched = await appStore.fetchReferencedMessage(channelId: channelId, messageId: messageId)
            didFail = fetched == nil
        }
        .accessibilityLabel(message.map { "Replying to \(name(for: $0)): \(preview(for: $0))" } ?? "Reply")
    }

    private func name(for message: Message) -> String {
        message.masquerade?.name ?? message.webhook?.name ?? appStore.store.displayName(userId: message.author, serverId: serverId)
    }

    private func namePaint(for message: Message) -> AnyShapeStyle? {
        if let colour = message.masquerade?.colour { return .stoatPaint(colour) }
        guard message.webhook == nil, let serverId else { return nil }
        return .stoatPaint(appStore.store.memberRoleColor(userId: message.author, in: serverId))
    }

    private func preview(for message: Message, keepingEmoji: Bool = false) -> String {
        if let content = message.content, !content.isEmpty {
            let text = keepingEmoji
                ? MentionFormatter.previewText(content, store: appStore.store, serverId: serverId)
                : MentionFormatter.plainText(content, store: appStore.store, serverId: serverId)
            return text
                .replacingOccurrences(of: "\n", with: " ")
        }
        if let count = message.attachments?.count, count > 0 {
            return count == 1 ? "Attachment" : "\(count) attachments"
        }
        return "Embed"
    }
}

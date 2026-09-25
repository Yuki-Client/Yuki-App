import SwiftUI
import StoatCore
import StoatState
import UIKit

/// The chat list is flipped, and iOS's context menu animates a copy of the row that ignores
/// the flip, so the message showed upside down and vanished on dismiss. A sheet avoids that.
struct MessageActionsSheet: View {
    let message: Message
    let serverId: String?
    let permissions: Permission
    /// Called with the chosen action once the sheet has been dismissed.
    let onAction: (MessageAction) -> Void

    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    private var quickReactions: [String] {
        ReactionHistory().quickReactions { emoji in
            guard Emoji.isCustomEmojiId(emoji) else { return true }
            guard let parent = appStore.store.emojis[emoji]?.parent.serverId else { return false }
            return serverId == nil || parent == serverId || permissions.contains(.useExternalEmojis)
        }
    }

    private var isOwn: Bool { message.author == appStore.store.currentUserId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary

                if permissions.contains(.react) {
                    reactions
                }

                actionGroup {
                    if permissions.contains(.sendMessage) {
                        row("Reply", systemImage: "arrowshape.turn.up.left") { choose(.reply) }
                    }
                    if isOwn, message.content?.isEmpty == false {
                        row("Edit", systemImage: "pencil") { choose(.edit) }
                    }
                    if let content = message.content, !content.isEmpty {
                        row("Copy Text", systemImage: "doc.on.doc") { copy(content) }
                    }
                    if !message.reactions.isEmpty {
                        row("View Reactions", systemImage: "face.smiling") { choose(.showReactions(nil)) }
                    }
                    row("Mark Unread", systemImage: "envelope.badge") { choose(.markUnread) }
                }

                actionGroup {
                    row("Copy Link", systemImage: "link") { copy(messageLink) }
                    row("Copy ID", systemImage: "number") { copy(message.id) }
                    if permissions.contains(.manageMessages) {
                        row(message.pinned == true ? "Unpin" : "Pin", systemImage: message.pinned == true ? "pin.slash" : "pin") {
                            choose(.togglePin)
                        }
                    }
                }

                actionGroup {
                    if !isOwn {
                        row("Report", systemImage: "exclamationmark.bubble", tint: .red) { choose(.report) }
                    }
                    if isOwn || permissions.contains(.manageMessages) {
                        row("Delete", systemImage: "trash", tint: .red) { choose(.delete) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(YukiTheme.groupedBackground)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            MessageAuthorAvatar(message: message, serverId: serverId, name: authorName, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(authorName)
                    .font(.subheadline.weight(.semibold))
                EmojiText(text: snippet, emojiSize: 13)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var reactions: some View {
        HStack(spacing: 8) {
            ForEach(quickReactions, id: \.self) { emoji in
                let hasReacted = appStore.store.currentUserId.map { message.reactions[emoji]?.contains($0) == true } ?? false
                Button {
                    choose(.react(emoji))
                } label: {
                    ReactionEmojiView(emoji: emoji, size: 27)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Circle().fill(hasReacted ? YukiTheme.accent.opacity(0.25) : YukiTheme.cardSurface))
                        .overlay(Circle().stroke(YukiTheme.accent.opacity(hasReacted ? 0.7 : 0), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasReacted ? "Remove \(reactionName(emoji)) reaction" : "React with \(reactionName(emoji))")
            }
            Button {
                choose(.openEmojiPicker)
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Circle().fill(YukiTheme.cardSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More reactions")
        }
    }

    private func reactionName(_ emoji: String) -> String {
        guard Emoji.isCustomEmojiId(emoji) else { return emoji }
        return appStore.store.emojis[emoji].map { ":\($0.name):" } ?? "custom emoji"
    }

    private func actionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
    }

    private func row(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(tint ?? YukiTheme.accent)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(tint ?? .primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ action: MessageAction) {
        onAction(action)
        dismiss()
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        YukiHaptics.notification(.success)
        dismiss()
    }

    private var authorName: String {
        if let name = message.masquerade?.name { return name }
        if let webhook = message.webhook { return webhook.name }
        return appStore.store.displayName(userId: message.author, serverId: serverId)
    }

    private var snippet: String {
        if let content = message.content, !content.isEmpty {
            return MentionFormatter.previewText(content, store: appStore.store, serverId: serverId)
        }
        if let count = message.attachments?.count, count > 0 {
            return count == 1 ? "1 attachment" : "\(count) attachments"
        }
        if message.embeds?.isEmpty == false {
            return "Embed"
        }
        return "Message"
    }

    private var messageLink: String {
        if let serverId = appStore.store.channels[message.channel]?.server {
            return "\(StoatInstance.appURL)/server/\(serverId)/channel/\(message.channel)/\(message.id)"
        }
        return "\(StoatInstance.appURL)/channel/\(message.channel)/\(message.id)"
    }
}

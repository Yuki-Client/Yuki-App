import SwiftUI
import StoatCore
import StoatState

struct ConversationRowLabel: View {
    let store: AppStore
    let channel: Channel
    let title: String
    let isSelected: Bool
    let isUnread: Bool
    let mentions: Int

    var body: some View {
        let otherId = channel.channelType == .directMessage ? channel.otherRecipient(currentUserId: store.store.currentUserId) : nil
        let other = otherId.flatMap { store.store.users[$0] }

        HStack(spacing: 10) {
            switch channel.channelType {
            case .directMessage:
                PresenceAvatarView(user: other, userId: otherId ?? "", size: 36)
            case .savedMessages:
                Image(systemName: "note.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(YukiTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(YukiTheme.accent.opacity(0.15)))
            default:
                if channel.icon != nil {
                    AvatarView(avatar: channel.icon, fallbackText: title, size: 36)
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(YukiTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(YukiTheme.accent.opacity(0.18)))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(isUnread || isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if let draft = store.drafts[channel.id] {
                    (Text("Draft: ").foregroundStyle(YukiTheme.accent) + Text(draft.replacingOccurrences(of: "\n", with: " ")).foregroundStyle(.secondary))
                        .font(.caption)
                        .lineLimit(1)
                } else if channel.channelType == .group {
                    Text("\(channel.recipients?.count ?? 0) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let status = other?.onlineStatusText {
                    EmojiText(text: status, emojiSize: 14)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if mentions > 0 {
                MentionBadge(count: mentions)
            } else if isUnread {
                Circle().fill(YukiTheme.accent).frame(width: 8, height: 8)
            }
        }
        .foregroundStyle(isSelected || isUnread ? Color.primary : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? YukiTheme.accent.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

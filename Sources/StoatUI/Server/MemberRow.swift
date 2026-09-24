import SwiftUI
import StoatState

struct MemberRow: View {
    let userId: String
    let serverId: String?
    var isOwner = false

    @Environment(AppStore.self) private var appStore

    var body: some View {
        let user = appStore.store.users[userId]
        let name = appStore.store.displayName(userId: userId, serverId: serverId)
        let paint = serverId.flatMap { AnyShapeStyle.stoatPaint(appStore.store.memberRoleColor(userId: userId, in: $0)) }

        HStack(spacing: 12) {
            PresenceAvatarView(user: user, userId: userId, avatarOverride: serverId.flatMap { appStore.store.member(userId: userId, in: $0)?.avatar }, size: 36)
                .opacity(user?.online == true ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(paint ?? AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Owner")
                    }
                    if user?.bot != nil {
                        BotTagView()
                    }
                }
                if let status = user?.onlineStatusText {
                    EmojiText(text: status, emojiSize: 14)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(StatusBadge.label(for: user?.effectivePresence))
    }
}

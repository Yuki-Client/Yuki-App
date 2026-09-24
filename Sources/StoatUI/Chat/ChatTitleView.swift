import SwiftUI
import StoatCore
import StoatState

struct ChatTitleView: View {
    let store: AppStore
    let channel: Channel?
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if channel?.channelType == .directMessage, let otherId = channel?.otherRecipient(currentUserId: store.store.currentUserId) {
                    StatusBadge(presence: store.store.users[otherId]?.effectivePresence, size: 8)
                } else if channel?.channelType == .textChannel {
                    Image(systemName: "number")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if channel.map(store.store.isMuted(channel:)) == true {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let description = channel?.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

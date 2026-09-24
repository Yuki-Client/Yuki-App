import SwiftUI
import StoatCore
import StoatState

struct ChatComposerArea: View {
    @Bindable var store: AppStore
    let channel: Channel
    let permissions: Permission
    @Binding var text: String

    var body: some View {
        if let reason = blockedReason {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text(reason)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(YukiTheme.secondaryBackground)
        } else {
            Divider()
            MessageComposerView(store: store, channel: channel, text: $text)
        }
    }

    private var blockedReason: String? {
        if let serverId = channel.server, let userId = store.store.currentUserId,
           let until = store.store.member(userId: userId, in: serverId)?.activeTimeout {
            return "You're timed out until \(until.formatted(date: .abbreviated, time: .shortened))"
        }
        if channel.channelType == .directMessage, let otherId = channel.otherRecipient(currentUserId: store.store.currentUserId) {
            switch store.store.users[otherId]?.relationship {
            case .blocked: return "You've blocked this user"
            case .blockedOther: return "You can't message this user"
            default: break
            }
        }
        if !permissions.contains(.sendMessage) {
            return "You don't have permission to send messages here"
        }
        return nil
    }
}

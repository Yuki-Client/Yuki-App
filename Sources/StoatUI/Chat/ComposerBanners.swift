import SwiftUI
import StoatState

struct ReplyingBanner: View {
    let store: AppStore
    let serverId: String?

    var body: some View {
        if !store.replyingTo.isEmpty {
            VStack(spacing: 0) {
                ForEach(store.replyingTo) { draft in
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                            .foregroundColor(YukiTheme.accent)
                        Text("Replying to ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        + Text(store.store.displayName(userId: draft.message.author, serverId: serverId))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button {
                            store.toggleReplyMention(draft.message.id)
                        } label: {
                            Label(draft.mention ? "@ON" : "@OFF", systemImage: draft.mention ? "at.circle.fill" : "at.circle")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(draft.mention ? YukiTheme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(draft.mention ? "Mention on" : "Mention off")
                        Button {
                            withAnimation { store.removeReply(draft.message.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel reply")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(YukiTheme.cardSurface)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct EditingBanner: View {
    let store: AppStore

    var body: some View {
        if store.editingMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(YukiTheme.accent)
                Text("Editing message")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(YukiTheme.accent)
                Spacer()
                Button("Cancel") {
                    withAnimation {
                        store.editingMessage = nil
                    }
                }
                .font(.caption.weight(.medium))
                .frame(height: 36)
            }
            .padding(.horizontal, 16)
            .background(YukiTheme.cardSurface)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

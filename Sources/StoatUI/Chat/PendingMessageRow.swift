import SwiftUI
import StoatState

struct PendingMessageRow: View {
    let pending: PendingMessage
    var serverId: String?
    /// Matches how the message will be grouped once sent, so nothing jumps when it's confirmed.
    var isContinuation = false
    let onRetry: () -> Void
    let onDiscard: () -> Void

    @Environment(AppStore.self) private var appStore

    private var isFailed: Bool {
        if case .failed = pending.state { return true }
        return false
    }

    private var isUploading: Bool {
        !isFailed && pending.attachments.contains { (pending.uploadProgress[$0.id] ?? 0) < 1 }
    }

    var body: some View {
        let userId = appStore.store.currentUserId ?? ""
        HStack(alignment: .top, spacing: 12) {
            if isContinuation {
                Color.clear.frame(width: 38, height: 1)
            } else {
                AvatarView(
                    avatar: appStore.store.avatar(userId: userId, serverId: serverId),
                    fallbackText: appStore.currentUser?.visibleName ?? "?",
                    size: 38,
                    userId: userId
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                if !isContinuation {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(appStore.store.displayName(userId: userId, serverId: serverId))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(serverId.flatMap { AnyShapeStyle.stoatPaint(appStore.store.memberRoleColor(userId: userId, in: $0)) } ?? AnyShapeStyle(.primary))
                            .lineLimit(1)
                        Text(MessageRowView.timestampText(pending.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if !pending.content.isEmpty {
                    YukiMarkdownView(pending.content, serverId: serverId)
                        .opacity(isFailed ? 1 : 0.45)
                }
                ForEach(pending.attachments) { attachment in
                    PendingAttachmentView(attachment: attachment, progress: pending.uploadProgress[attachment.id], isFailed: isFailed)
                }
                if isUploading {
                    Button("Cancel Upload", role: .destructive, action: onDiscard)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }

                if case .failed(let reason) = pending.state {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(reason, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        HStack(spacing: 12) {
                            Button("Retry", action: onRetry)
                            Button("Delete", role: .destructive, action: onDiscard)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, isContinuation ? 1 : 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isFailed ? "Failed to send" : "Sending")
    }
}

import SwiftUI
import StoatState

struct FeedbackOverlay: View {
    @Bindable var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if let notification = store.incomingNotification {
                Button {
                    store.openChannel(notification.channelId)
                    store.incomingNotification = nil
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(avatar: store.store.users[notification.authorId]?.avatar, fallbackText: notification.title, size: 34, userId: notification.authorId)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notification.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            EmojiText(text: notification.body, emojiSize: 14)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: notification.id) {
                    try? await Task.sleep(for: .seconds(4))
                    if store.incomingNotification?.id == notification.id {
                        store.incomingNotification = nil
                    }
                }
                .accessibilityHint("Double tap to open the conversation")
            }

            if let toast = store.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.style == .error ? "exclamationmark.triangle.fill" : toast.style == .success ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(toast.style == .error ? .orange : toast.style == .success ? .green : YukiTheme.accent)
                    Text(toast.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .onTapGesture { store.toast = nil }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3.5))
                    if store.toast?.id == toast.id {
                        store.toast = nil
                    }
                }
                .accessibilityAddTraits(.isStaticText)
                .onAppear {
                    UIAccessibility.post(notification: .announcement, argument: toast.message)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: store.incomingNotification)
    }
}

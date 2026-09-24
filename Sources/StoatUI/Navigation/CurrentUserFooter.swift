import SwiftUI
import StoatCore
import StoatState

struct CurrentUserFooter: View {
    let store: AppStore
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let user = store.currentUser {
                Menu {
                    Section("Status") {
                        ForEach([Presence.online, .idle, .focus, .busy, .invisible], id: \.self) { presence in
                            Button {
                                Task { await store.updateStatus(text: nil, presence: presence) }
                            } label: {
                                Label(StatusBadge.label(for: presence), systemImage: user.status?.presence == presence ? "checkmark" : "circle.fill")
                            }
                        }
                    }
                    Button(action: openSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    HStack(spacing: 10) {
                        PresenceAvatarView(user: user, userId: user.id, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.visibleName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            EmojiText(text: user.status?.text?.isEmpty == false ? user.status!.text! : user.fullHandle, emojiSize: 14)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Your status: \(StatusBadge.label(for: user.effectivePresence))")

                Spacer()

                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

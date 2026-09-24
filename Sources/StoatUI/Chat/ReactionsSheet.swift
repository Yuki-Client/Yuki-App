import SwiftUI
import StoatCore
import StoatState

struct ReactionsSheet: View {
    @Bindable var store: AppStore
    let channelId: String
    let messageId: String
    let serverId: String?

    @State private var selectedEmoji: String?
    @State private var profileUserId: String?

    init(store: AppStore, channelId: String, messageId: String, serverId: String?, initialEmoji: String?) {
        self.store = store
        self.channelId = channelId
        self.messageId = messageId
        self.serverId = serverId
        _selectedEmoji = State(initialValue: initialEmoji)
    }

    /// Read live, so reactions added or removed while the sheet is open show up.
    private var reactions: [String: [String]] {
        store.store.existingTimeline(for: channelId)?.message(id: messageId)?.reactions ?? [:]
    }

    private var emojis: [String] {
        reactions.keys
            .filter { !(reactions[$0]?.isEmpty ?? true) }
            .sorted { (reactions[$0]?.count ?? 0, $1) > (reactions[$1]?.count ?? 0, $0) }
    }

    private var current: String? {
        selectedEmoji.flatMap { emojis.contains($0) ? $0 : nil } ?? emojis.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(emojis, id: \.self) { emoji in
                            let isSelected = emoji == current
                            Button {
                                YukiHaptics.selection()
                                selectedEmoji = emoji
                            } label: {
                                HStack(spacing: 5) {
                                    ReactionEmojiView(emoji: emoji, size: 18)
                                    Text("\(reactions[emoji]?.count ?? 0)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(isSelected ? YukiTheme.accent : .secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(isSelected ? YukiTheme.accent.opacity(0.18) : YukiTheme.cardSurface))
                                .overlay(Capsule().stroke(isSelected ? YukiTheme.accent.opacity(0.6) : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                List {
                    ForEach(current.flatMap { reactions[$0] } ?? [], id: \.self) { userId in
                        Button {
                            profileUserId = userId
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    avatar: store.store.avatar(userId: userId, serverId: serverId),
                                    fallbackText: store.store.displayName(userId: userId, serverId: serverId),
                                    size: 36,
                                    userId: userId
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(store.store.displayName(userId: userId, serverId: serverId))
                                        .foregroundStyle(.primary)
                                    if let user = store.store.users[userId] {
                                        Text(user.fullHandle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if emojis.isEmpty {
                    ContentUnavailableView("No Reactions", systemImage: "face.smiling")
                }
            }
            .task {
                let unknown = Set(reactions.values.flatMap { $0 }).filter { store.store.users[$0] == nil }
                if !unknown.isEmpty {
                    store.queueUserFetch(Array(unknown))
                }
            }
            .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
                UserProfileSheet(store: store, userId: item.value, serverId: serverId)
            }
        }
    }
}

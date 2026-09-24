import SwiftUI
import StoatCore
import StoatState

/// With nothing typed it shows where you've been recently and anything unread.
public struct QuickSwitcherSheet: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    public init(store: AppStore) {
        self.store = store
    }

    enum Destination: Identifiable {
        case channel(Channel)
        case server(Server)

        var id: String {
            switch self {
            case .channel(let channel): "c\(channel.id)"
            case .server(let server): "s\(server.id)"
            }
        }
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var results: [Destination] {
        let store = store.store
        var scored: [(score: Int, order: String, destination: Destination)] = []

        func add(_ destination: Destination, name: String, boost: Int) {
            guard !trimmed.isEmpty else {
                scored.append((boost, name.lowercased(), destination))
                return
            }
            let lowered = name.lowercased()
            let score: Int
            if lowered == trimmed {
                score = 100
            } else if lowered.hasPrefix(trimmed) {
                score = 70
            } else if lowered.contains(trimmed) {
                score = 40
            } else if matchesInitials(lowered, trimmed) {
                score = 25
            } else {
                return
            }
            scored.append((score + boost, lowered, destination))
        }

        for channel in store.directChannels {
            let name = channel.displayName(withUsers: store.users, currentUserId: store.currentUserId)
            add(.channel(channel), name: name, boost: unreadBoost(channel) + 6)
        }
        for server in store.orderedServers {
            add(.server(server), name: server.name, boost: 2)
            for channel in store.channels(forServer: server.id) where store.hasPermission(.viewChannel, in: channel) {
                add(.channel(channel), name: channel.name ?? "channel", boost: unreadBoost(channel))
            }
        }

        return scored
            .sorted { ($0.score, $1.order) > ($1.score, $0.order) }
            .prefix(trimmed.isEmpty ? 20 : 40)
            .map(\.destination)
    }

    private func unreadBoost(_ channel: Channel) -> Int {
        let mentions = store.store.mentionCount(channelId: channel.id)
        if mentions > 0 { return 12 }
        return store.store.isUnread(channel: channel) ? 6 : 0
    }

    /// Matches "gm" against "general messages", the way people type quick switcher searches.
    private func matchesInitials(_ name: String, _ query: String) -> Bool {
        guard query.count >= 2 else { return false }
        let initials = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first)
        return String(initials).hasPrefix(query)
    }

    public var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(results) { destination in
                        Button {
                            open(destination)
                        } label: {
                            row(destination)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(YukiTheme.systemBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channels, people and servers")
            .navigationTitle("Jump To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onSubmit(of: .search) {
                if let first = results.first { open(first) }
            }
        }
    }

    @ViewBuilder
    private func row(_ destination: Destination) -> some View {
        switch destination {
        case .channel(let channel):
            let mentions = store.store.mentionCount(channelId: channel.id)
            let isUnread = store.store.isUnread(channel: channel)
            HStack(spacing: 10) {
                icon(for: channel)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.isPrivate
                         ? channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId)
                         : channel.name ?? "channel")
                        .font(.body.weight(isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    if let serverName = channel.server.flatMap({ store.store.servers[$0]?.name }) {
                        Text(serverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if channel.channelType == .group {
                        Text("Group")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if mentions > 0 {
                    MentionBadge(count: mentions)
                } else if isUnread {
                    Circle().fill(Color.primary).frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        case .server(let server):
            HStack(spacing: 10) {
                AvatarView(avatar: server.icon, fallbackText: server.name, size: 30, isRounded: false)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(server.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func icon(for channel: Channel) -> some View {
        switch channel.channelType {
        case .directMessage:
            let otherId = channel.otherRecipient(currentUserId: store.store.currentUserId)
            PresenceAvatarView(user: otherId.flatMap { store.store.users[$0] }, userId: otherId ?? "", size: 30)
        case .group:
            AvatarView(avatar: channel.icon, fallbackText: channel.name ?? "Group", size: 30)
        case .savedMessages:
            Image(systemName: "note.text")
                .foregroundStyle(YukiTheme.accent)
                .frame(width: 30, height: 30)
        default:
            Image(systemName: channel.channelType == .voiceChannel ? "speaker.wave.2.fill" : channel.voice != nil ? "number.square" : "number")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
    }

    private func open(_ destination: Destination) {
        YukiHaptics.selection()
        dismiss()
        switch destination {
        case .channel(let channel):
            store.openChannel(channel.id)
        case .server(let server):
            store.selectServer(server.id)
            store.showChannelList()
        }
    }
}

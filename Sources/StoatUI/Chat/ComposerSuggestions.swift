import SwiftUI
import StoatCore
import StoatState

enum ComposerSuggestion: Identifiable {
    case user(User, displayName: String)
    case role(id: String, role: Role)
    case everyone(String)
    case channel(Channel)
    case customEmoji(Emoji)
    case unicodeEmoji(String, name: String)

    var id: String {
        switch self {
        case .user(let user, _): "u\(user.id)"
        case .role(let id, _): "r\(id)"
        case .everyone(let label): "a\(label)"
        case .channel(let channel): "c\(channel.id)"
        case .customEmoji(let emoji): "e\(emoji.id)"
        case .unicodeEmoji(let emoji, _): "x\(emoji)"
        }
    }

    var insertion: String {
        switch self {
        case .user(let user, _): "<@\(user.id)> "
        case .role(let id, _): "<%\(id)> "
        case .everyone(let label): "@\(label) "
        case .channel(let channel): "<#\(channel.id)> "
        case .customEmoji(let emoji): ":\(emoji.id): "
        case .unicodeEmoji(let emoji, _): emoji + " "
        }
    }
}

@MainActor
struct ComposerQuery {
    let trigger: Character
    let query: String

    init?(text: String) {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              let lastLine = last.split(separator: "\n", omittingEmptySubsequences: false).last,
              let trigger = lastLine.first, "@:#".contains(trigger) else { return nil }
        let query = String(lastLine.dropFirst())
        if trigger == ":" && query.count < 2 { return nil }
        if query.contains(">") || (trigger == ":" && query.hasSuffix(":")) { return nil }
        self.trigger = trigger
        self.query = query.lowercased()
    }

    func suggestions(store: NormalizedStore, channel: Channel) -> [ComposerSuggestion] {
        switch trigger {
        case "@":
            return roles(store: store, channel: channel) + users(store: store, channel: channel)
        case "#":
            guard let serverId = channel.server else { return [] }
            return store.channels(forServer: serverId)
                .filter { query.isEmpty || ($0.name ?? "").lowercased().contains(query) }
                .prefix(6)
                .map { .channel($0) }
        default:
            let custom = store.availableEmojis
                .filter { $0.name.lowercased().contains(query) && store.canUseEmoji($0.id, in: channel) }
                .prefix(5)
                .map { ComposerSuggestion.customEmoji($0) }
            let unicode = EmojiCatalog.search(query, limit: 6 - custom.count)
                .map { ComposerSuggestion.unicodeEmoji($0.emoji, name: $0.name) }
            return Array(custom) + unicode
        }
    }

    // Stoat refuses role and @everyone mentions without permission, so they're only offered with it.
    private func roles(store: NormalizedStore, channel: Channel) -> [ComposerSuggestion] {
        guard let serverId = channel.server, let server = store.servers[serverId] else { return [] }
        var results: [ComposerSuggestion] = []
        if store.hasPermission(.mentionRoles, in: channel) {
            results += server.roles
                .filter { query.isEmpty || $0.value.name.lowercased().contains(query) }
                .sorted { $0.value.rank < $1.value.rank }
                .prefix(4)
                .map { .role(id: $0.key, role: $0.value) }
        }
        if store.hasPermission(.mentionEveryone, in: channel) {
            results += ["everyone", "online"]
                .filter { query.isEmpty || $0.hasPrefix(query) }
                .map { .everyone($0) }
        }
        return results
    }

    private func users(store: NormalizedStore, channel: Channel) -> [ComposerSuggestion] {
        let candidates = channel.server.map { Array(store.members[$0]?.keys ?? [:].keys) } ?? channel.recipients ?? []
        let matches: [(user: User, name: String)] = candidates.compactMap { id in
            guard let user = store.users[id] else { return nil }
            let name = store.displayName(userId: id, serverId: channel.server)
            guard query.isEmpty || name.lowercased().contains(query) || user.username.lowercased().contains(query) else { return nil }
            return (user, name)
        }
        return matches
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(6)
            .map { .user($0.user, displayName: $0.name) }
    }
}

struct ComposerSuggestionList: View {
    let store: AppStore
    let serverId: String?
    let suggestions: [ComposerSuggestion]
    let onSelect: (ComposerSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        row(suggestion)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(YukiTheme.cardSurface))
    }

    @ViewBuilder
    private func row(_ suggestion: ComposerSuggestion) -> some View {
        switch suggestion {
        case .user(let user, let name):
            AvatarView(avatar: store.store.avatar(userId: user.id, serverId: serverId), fallbackText: name, size: 24, userId: user.id)
            Text(name).font(.subheadline.weight(.medium))
            Text(user.username).font(.caption).foregroundStyle(.secondary)
        case .role(_, let role):
            RoleColourDot(colour: role.colour)
                .frame(width: 24)
            Text("@\(role.name)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AnyShapeStyle.stoatPaint(role.colour) ?? AnyShapeStyle(.primary))
            Text("Role").font(.caption).foregroundStyle(.secondary)
        case .everyone(let label):
            Image(systemName: "megaphone").foregroundStyle(.secondary).frame(width: 24)
            Text("@\(label)").font(.subheadline.weight(.medium))
            Text(label == "everyone" ? "Everyone here" : "People online").font(.caption).foregroundStyle(.secondary)
        case .channel(let channel):
            Image(systemName: "number").foregroundStyle(.secondary).frame(width: 24)
            Text(channel.name ?? "channel").font(.subheadline.weight(.medium))
        case .customEmoji(let emoji):
            ReactionEmojiView(emoji: emoji.id, size: 22).frame(width: 24)
            Text(":\(emoji.name):").font(.subheadline)
        case .unicodeEmoji(let emoji, let name):
            ReactionEmojiView(emoji: emoji, size: 22).frame(width: 24)
            Text(":\(name):").font(.subheadline)
        }
    }
}

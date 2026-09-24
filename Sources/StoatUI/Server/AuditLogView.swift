import SwiftUI
import StoatCore
import StoatState

struct AuditLogView: View {
    @Bindable var store: AppStore
    let serverId: String

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case messages = "Messages"
        case members = "Members"
        case channels = "Channels"
        case roles = "Roles"
        case server = "Server"

        var id: String { rawValue }

        var types: [String] {
            switch self {
            case .all: []
            case .messages: ["MessageDelete", "MessageBulkDelete", "MessagePin", "MessageUnpin"]
            case .members: ["MemberEdit", "MemberKick", "BanCreate", "BanDelete"]
            case .channels: ["ChannelCreate", "ChannelEdit", "ChannelDelete", "ChannelRolePermissionsEdit", "WebhookCreate", "WebhookDelete", "InviteCreate", "InviteDelete"]
            case .roles: ["RoleCreate", "RoleEdit", "RoleDelete", "RolesReorder"]
            case .server: ["ServerEdit", "EmojiCreate", "EmojiUpdate", "EmojiDelete"]
            }
        }
    }

    @State private var entries: [AuditLogEntry] = []
    @State private var filter: Filter = .all
    @State private var isLoading = false
    @State private var reachedEnd = false

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section {
                if entries.isEmpty && !isLoading {
                    ContentUnavailableView("Nothing Logged", systemImage: "list.bullet.clipboard", description: Text("Moderation and settings changes appear here."))
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    AuditLogRow(
                        store: store,
                        serverId: serverId,
                        entry: entry,
                        previous: entries[(index + 1)...].first { AuditLogChangeBuilder.isPreviousOverride($0, of: entry) }
                    )
                        .onAppear {
                            if entry.id == entries.last?.id {
                                Task { await load(more: true) }
                            }
                        }
                }
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .navigationTitle("Audit Log")
        .refreshable { await load(more: false) }
        .task(id: filter) { await load(more: false) }
    }

    private func load(more: Bool) async {
        guard !isLoading, !(more && reachedEnd) else { return }
        isLoading = true
        defer { isLoading = false }
        let requested = filter
        let page = await store.fetchAuditLogs(serverId: serverId, before: more ? entries.last?.id : nil, types: requested.types)
        guard requested == filter, let page else { return }
        if more {
            let known = Set(entries.map(\.id))
            entries += page.filter { !known.contains($0.id) }
        } else {
            entries = page
        }
        reachedEnd = page.count < 50
    }
}

private struct AuditLogRow: View {
    @Bindable var store: AppStore
    let serverId: String
    let entry: AuditLogEntry
    let previous: AuditLogEntry?

    @State private var showAllChanges = false

    private static let collapsedLimit = 4

    private var changes: [AuditLogChange] {
        AuditLogChangeBuilder(
            userName: { user($0) },
            roleName: { roleName($0) },
            channelName: { channelName($0) }
        )
        .changes(for: entry, previous: previous)
    }

    var body: some View {
        let changes = changes
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                avatar: store.store.avatar(userId: entry.user, serverId: serverId),
                fallbackText: store.store.displayName(userId: entry.user, serverId: serverId),
                size: 32,
                userId: entry.user
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(summary)
                    .font(.subheadline)
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array((showAllChanges ? changes : Array(changes.prefix(Self.collapsedLimit))).enumerated()), id: \.offset) { _, change in
                            AuditLogChangeLine(change: change)
                        }
                        if changes.count > Self.collapsedLimit {
                            Button(showAllChanges ? "Show less" : "Show all \(changes.count) changes") {
                                withAnimation(.easeOut(duration: 0.2)) { showAllChanges.toggle() }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if entry.action.type == "ChannelRolePermissionsEdit", previous == nil, !changes.isEmpty {
                    Text("Stoat doesn't record what these were before.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let reason = entry.reason, !reason.isEmpty {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = Message.date(fromULID: entry.id) {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var summary: AttributedString {
        var actor = AttributedString(user(entry.user))
        actor.font = .subheadline.weight(.semibold)
        return actor + AttributedString(" " + description)
    }

    private var description: String {
        let action = entry.action
        let channel = action.channel.map(channelName) ?? "a channel"
        switch action.type {
        case "MessageDelete":
            return "deleted a message by \(user(action.author)) in \(channel)"
        case "MessageBulkDelete":
            return "deleted \(action.count ?? 0) messages in \(channel)"
        case "MessagePin":
            return "pinned a message by \(user(action.author)) in \(channel)"
        case "MessageUnpin":
            return "unpinned a message by \(user(action.author)) in \(channel)"
        case "BanCreate":
            return "banned \(user(action.user))"
        case "BanDelete":
            return "unbanned \(user(action.user))"
        case "MemberKick":
            return "kicked \(user(action.user))"
        case "MemberEdit":
            return "updated \(user(action.user))"
        case "ChannelCreate":
            return "created #\(action.name ?? "channel")"
        case "ChannelDelete":
            return "deleted #\(action.name ?? "channel")"
        case "ChannelEdit":
            return "edited \(channel)"
        case "ChannelRolePermissionsEdit":
            return "changed \(roleName(action.role))'s permissions in \(channel)"
        case "ServerEdit":
            return "edited the server"
        case "RoleCreate":
            return "created the role \(action.name ?? "role")"
        case "RoleDelete":
            return "deleted the role \(action.name ?? "role")"
        case "RoleEdit":
            return "edited \(roleName(action.role))"
        case "RolesReorder":
            return "reordered roles"
        case "InviteCreate":
            return "created invite \(action.invite ?? "") for \(channel)"
        case "InviteDelete":
            return "deleted invite \(action.invite ?? "") for \(channel)"
        case "WebhookCreate":
            return "created webhook \(action.name ?? "") in \(channel)"
        case "WebhookDelete":
            return "deleted webhook \(action.name ?? "") in \(channel)"
        case "EmojiCreate":
            return "added emoji :\(action.name ?? "emoji"):"
        case "EmojiUpdate":
            return "edited an emoji"
        case "EmojiDelete":
            return "deleted emoji :\(action.name ?? "emoji"):"
        default:
            return action.type
        }
    }

    private var symbol: String {
        switch entry.action.type {
        case "MessageDelete", "MessageBulkDelete": "trash"
        case "MessagePin", "MessageUnpin": "pin"
        case "BanCreate", "BanDelete": "hammer"
        case "MemberKick": "figure.walk.departure"
        case "MemberEdit": "person.crop.circle"
        case "ChannelCreate", "ChannelDelete", "ChannelEdit": "number"
        case "ChannelRolePermissionsEdit": "lock.shield"
        case "RoleCreate", "RoleDelete", "RoleEdit", "RolesReorder": "tag"
        case "InviteCreate", "InviteDelete": "link"
        case "WebhookCreate", "WebhookDelete": "point.3.connected.trianglepath.dotted"
        case "EmojiCreate", "EmojiUpdate", "EmojiDelete": "face.smiling"
        default: "gearshape"
        }
    }

    private func user(_ id: String?) -> String {
        guard let id else { return "someone" }
        return store.store.displayName(userId: id, serverId: serverId)
    }

    private func channelName(_ id: String) -> String {
        store.store.channels[id]?.name.map { "#\($0)" } ?? "a deleted channel"
    }

    private func roleName(_ id: String?) -> String {
        guard let id, let role = store.store.servers[serverId]?.roles[id] else { return "a deleted role" }
        return role.name
    }
}

private struct AuditLogChangeLine: View {
    let change: AuditLogChange

    var body: some View {
        Group {
            switch change {
            case .value(let field, let old, let new):
                (Text("\(field): ").foregroundStyle(.secondary) + valueText(old: old, new: new))
            case .added(let field, let item):
                (Text("+ ").foregroundStyle(.green).bold() + Text(item) + Text("  \(field)").foregroundStyle(.tertiary))
            case .removed(let field, let item):
                (Text("− ").foregroundStyle(.red).bold() + Text(item).strikethrough() + Text("  \(field)").foregroundStyle(.tertiary))
            case .permission(let scope, let name, let old, let new):
                (Text(scope.map { "\($0) · " } ?? "").foregroundStyle(.secondary)
                    + Text("\(name): ")
                    + (old.map { Text($0.rawValue).foregroundStyle(color(for: $0)) + Text(" → ").foregroundStyle(.tertiary) } ?? Text(""))
                    + Text(new.rawValue).foregroundStyle(color(for: new)).bold())
            case .note(let text):
                Text(text).foregroundStyle(.secondary).italic()
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(old: String?, new: String?) -> Text {
        switch (old, new) {
        case let (old?, new?):
            Text(old.isEmpty ? "(empty)" : old).strikethrough().foregroundStyle(.secondary)
                + Text(" → ").foregroundStyle(.tertiary)
                + Text(new.isEmpty ? "(empty)" : new)
        case let (nil, new?):
            Text(new)
        case let (old?, nil):
            Text(old).strikethrough().foregroundStyle(.secondary) + Text(" (removed)").foregroundStyle(.tertiary)
        case (nil, nil):
            Text("changed")
        }
    }

    private func color(for state: AuditLogChange.PermissionState) -> Color {
        switch state {
        case .allowed, .on: .green
        case .denied: .red
        case .neutral, .off: .secondary
        }
    }
}

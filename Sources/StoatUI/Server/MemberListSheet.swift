import SwiftUI
import StoatCore
import StoatState

/// Grouping is rebuilt in the background at most every couple of seconds, and big servers only
/// load online members, so this stays usable with tens of thousands of people.
public struct MemberListSheet: View {
    @Bindable var store: AppStore
    let channel: Channel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sections: [MemberSection] = []
    @State private var summary: String?
    @State private var isLoading = false
    @State private var isLarge = false
    @State private var isSearching = false
    @State private var profileUserId: String?

    /// With at least this many members online, a server counts as large: offline members aren't
    /// downloaded or listed, and search asks Stoat instead.
    private static let largeServerOnlineCount = 250

    public init(store: AppStore, channel: Channel) {
        self.store = store
        self.channel = channel
    }

    fileprivate struct MemberSection: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let userIds: [String]
    }

    fileprivate struct Entry: Sendable {
        let id: String
        let name: String
        let username: String
        let isOnline: Bool
        let hoistedRoleId: String?
    }

    fileprivate struct RoleInfo: Sendable {
        let name: String
        let rank: Int64
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.userIds, id: \.self) { userId in
                            Button {
                                profileUserId = userId
                            } label: {
                                MemberRow(userId: userId, serverId: channel.server, isOwner: isOwner(userId))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if isLarge {
                    if isSearching {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Searching everyone…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if trimmedQuery.isEmpty, !sections.isEmpty {
                        Section {
                        } footer: {
                            Text("Offline members aren't listed in large servers. Search to find anyone.")
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    if isLoading {
                        ProgressView()
                    } else if !trimmedQuery.isEmpty, !isSearching {
                        ContentUnavailableView.search(text: trimmedQuery)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search members")
            .listSectionSpacing(.compact)
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Members")
                            .font(.headline)
                        if let summary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await load()
            }
            .task {
                await rebuildOnChanges()
            }
            .task(id: query) {
                await search()
            }
            .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
                UserProfileSheet(store: store, userId: item.value, serverId: channel.server)
            }
        }
    }

    private func load() async {
        await rebuild()
        guard let serverId = channel.server else {
            store.queueUserFetch(channel.recipients ?? [])
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Online members first: quick even in huge servers, and enough to tell if the server is one.
        let online = await store.fetchServerMembers(serverId: serverId, onlineOnly: true)
        guard !Task.isCancelled else { return }
        isLarge = (online ?? 0) >= Self.largeServerOnlineCount
        await rebuild()
        guard !isLarge else { return }
        await store.fetchServerMembers(serverId: serverId)
        guard !Task.isCancelled else { return }
        await rebuild()
    }

    private func search() async {
        let text = trimmedQuery
        if !text.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        await rebuild()
        guard isLarge, text.count >= 2, let serverId = channel.server else { return }
        isSearching = true
        _ = await store.searchServerMembers(serverId: serverId, query: text)
        guard !Task.isCancelled else { return }
        isSearching = false
        await rebuild()
    }

    private func rebuildOnChanges() async {
        while !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = store.store.members
                    _ = store.store.users
                } onChange: {
                    continuation.resume()
                }
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await rebuild()
        }
    }

    private func rebuild() async {
        let serverId = channel.server
        let ids = serverId.map { Array((store.store.members[$0] ?? [:]).keys) } ?? (channel.recipients ?? [])
        var entries: [Entry] = []
        entries.reserveCapacity(ids.count)
        for id in ids {
            let user = store.store.users[id]
            let isOnline = user?.online == true
            entries.append(Entry(
                id: id,
                name: store.store.displayName(userId: id, serverId: serverId),
                username: user?.username ?? "",
                isOnline: isOnline,
                hoistedRoleId: isOnline ? serverId.flatMap { store.store.memberHoistedRole(userId: id, in: $0)?.id } : nil
            ))
        }
        let roles = serverId.flatMap { store.store.servers[$0]?.roles.mapValues { RoleInfo(name: $0.name, rank: $0.rank) } } ?? [:]
        let query = trimmedQuery.lowercased()
        let isLarge = isLarge
        let isServer = serverId != nil

        let result = await Task.detached(priority: .userInitiated) {
            Self.group(entries, roles: roles, query: query, isLarge: isLarge, isServer: isServer)
        }.value
        guard !Task.isCancelled else { return }
        if sections != result.sections { sections = result.sections }
        if summary != result.summary { summary = result.summary }
    }

    private nonisolated static func group(
        _ entries: [Entry],
        roles: [String: RoleInfo],
        query: String,
        isLarge: Bool,
        isServer: Bool
    ) -> (sections: [MemberSection], summary: String?) {
        let onlineCount = entries.lazy.filter(\.isOnline).count
        let summary: String? = entries.isEmpty ? nil : isLarge
            ? "\(onlineCount.formatted()) online"
            : "\(onlineCount.formatted()) online · \(entries.count.formatted()) \(entries.count == 1 ? "member" : "members")"

        func sorted(_ list: [Entry]) -> [String] {
            list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map(\.id)
        }

        let matching = query.isEmpty ? entries : entries.filter {
            $0.name.lowercased().contains(query) || $0.username.lowercased().contains(query)
        }

        guard isServer else {
            return ([MemberSection(id: "members", title: "Members · \(matching.count)", userIds: sorted(matching))], summary)
        }

        // Searching a large server: one list of everyone found, online people first.
        if isLarge, !query.isEmpty {
            guard !matching.isEmpty else { return ([], summary) }
            let online = matching.filter(\.isOnline), offline = matching.filter { !$0.isOnline }
            return ([MemberSection(id: "results", title: "Results · \(matching.count)", userIds: sorted(online) + sorted(offline))], summary)
        }

        var hoisted: [String: [Entry]] = [:]
        var online: [Entry] = []
        var offline: [Entry] = []
        for entry in matching {
            if entry.isOnline, let roleId = entry.hoistedRoleId, roles[roleId] != nil {
                hoisted[roleId, default: []].append(entry)
            } else if entry.isOnline {
                online.append(entry)
            } else if !isLarge {
                offline.append(entry)
            }
        }

        var sections: [MemberSection] = hoisted
            .compactMap { roleId, members in roles[roleId].map { (roleId, $0, members) } }
            .sorted { $0.1.rank < $1.1.rank }
            .map { MemberSection(id: $0.0, title: "\($0.1.name) · \($0.2.count)", userIds: sorted($0.2)) }
        if !online.isEmpty {
            sections.append(MemberSection(id: "online", title: "Online · \(online.count)", userIds: sorted(online)))
        }
        if !offline.isEmpty {
            sections.append(MemberSection(id: "offline", title: "Offline · \(offline.count)", userIds: sorted(offline)))
        }
        return (sections, summary)
    }

    private func isOwner(_ userId: String) -> Bool {
        if let serverId = channel.server {
            return store.store.servers[serverId]?.owner == userId
        }
        return channel.owner == userId
    }
}

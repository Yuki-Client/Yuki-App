import SwiftUI
import StoatCore
import StoatState

public struct DiscoverView: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .servers
    @State private var query = ""
    @State private var tag: String?
    @State private var servers: DiscoverListing<DiscoverServer>?
    @State private var bots: DiscoverListing<DiscoverBot>?
    @State private var errorMessage: String?
    @State private var joinServerId: String?
    @State private var botToAdd: DiscoverBot?

    public init(store: AppStore) {
        self.store = store
    }

    enum Tab: String, CaseIterable, Identifiable {
        case servers = "Servers"
        case bots = "Bots"

        var id: String { rawValue }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matches(name: String, description: String?, tags: [String]) -> Bool {
        if let tag, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        guard !trimmedQuery.isEmpty else { return true }
        return name.lowercased().contains(trimmedQuery)
            || (description?.lowercased().contains(trimmedQuery) ?? false)
            || tags.contains { $0.lowercased().contains(trimmedQuery) }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    tagChips
                    switch tab {
                    case .servers: serverResults
                    case .bots: botResults
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(YukiTheme.systemBackground)
            .overlay {
                if let errorMessage, (tab == .servers ? servers : nil) == nil, (tab == .bots ? bots : nil) == nil {
                    ContentUnavailableView {
                        Label("Discover Unavailable", systemImage: "safari")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await load(refresh: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if isLoading {
                    ProgressView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(YukiTheme.systemBackground)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: tab == .servers ? "Search servers" : "Search bots")
            .refreshable { await load(refresh: true) }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: tab) {
                tag = nil
                await load(refresh: false)
            }
            .sheet(item: Binding(get: { joinServerId.map(IdentifiedString.init) }, set: { joinServerId = $0?.value })) { item in
                JoinOrCreateServerSheet(store: store, initialInviteCode: item.value)
            }
            .sheet(item: $botToAdd) { bot in
                AddBotSheet(store: store, botId: bot.id, botName: bot.username)
            }
        }
    }

    private var isLoading: Bool {
        errorMessage == nil && (tab == .servers ? servers == nil : bots == nil)
    }

    private var popularTags: [String] {
        (tab == .servers ? servers?.popularTags : bots?.popularTags) ?? []
    }

    @ViewBuilder
    private var tagChips: some View {
        if !popularTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularTags, id: \.self) { name in
                        let isSelected = tag == name
                        Button {
                            YukiHaptics.selection()
                            tag = isSelected ? nil : name
                        } label: {
                            Text("#\(name)")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(Capsule().fill(isSelected ? YukiTheme.accent : YukiTheme.cardSurface))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var serverResults: some View {
        if let servers {
            let results = servers.items.filter { matches(name: $0.name, description: $0.description, tags: $0.tags) }
            if results.isEmpty {
                noResults
            }
            ForEach(results) { server in
                Button {
                    open(server)
                } label: {
                    DiscoverServerCard(server: server, isMember: store.store.servers[server.id] != nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var botResults: some View {
        if let bots {
            let results = bots.items.filter { matches(name: $0.username, description: $0.description, tags: $0.tags) }
            if results.isEmpty {
                noResults
            }
            ForEach(results) { bot in
                Button {
                    botToAdd = bot
                } label: {
                    DiscoverBotCard(bot: bot)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noResults: some View {
        ContentUnavailableView.search(text: query.isEmpty ? "#\(tag ?? "")" : query)
            .padding(.top, 40)
    }

    private func open(_ server: DiscoverServer) {
        if store.store.servers[server.id] != nil {
            dismiss()
            store.selectServer(server.id)
            store.showChannelList()
        } else {
            // Stoat accepts a Discover server's ID in place of an invite code.
            joinServerId = server.id
        }
    }

    private func load(refresh: Bool) async {
        errorMessage = nil
        do {
            switch tab {
            case .servers:
                if servers == nil || refresh { servers = try await DiscoverClient.shared.servers(refresh: refresh) }
            case .bots:
                if bots == nil || refresh { bots = try await DiscoverClient.shared.bots(refresh: refresh) }
            }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private extension DiscoverActivity {
    var label: String? {
        switch self {
        case .high: "Very active"
        case .medium: "Active"
        case .low: "Quiet"
        case .none: nil
        }
    }

    var color: Color {
        switch self {
        case .high: .green
        case .medium: .yellow
        case .low, .none: .gray
        }
    }
}

private struct DiscoverServerCard: View {
    let server: DiscoverServer
    let isMember: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // The banner fills a fixed-size area rather than sizing it, so a very wide or tall
                // image can't make the card wider than the screen.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .overlay {
                        if let banner = server.banner {
                            RemoteImage(url: banner.downloadURL(), maxPixelSize: 900) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { _ in
                                YukiTheme.cardSurface
                            }
                        } else {
                            LinearGradient(colors: [YukiTheme.accent.opacity(0.45), YukiTheme.accentDeep.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                    .clipped()

                AvatarView(avatar: server.icon, fallbackText: server.name, size: 52, isRounded: false)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(YukiTheme.cardSurface, lineWidth: 3))
                    .offset(x: 12, y: 26)
            }
            .zIndex(1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)
                    if server.isOfficial || server.isVerified {
                        Image(systemName: server.isOfficial ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(YukiTheme.accent)
                            .accessibilityLabel(server.isOfficial ? "Official" : "Verified")
                    }
                    Spacer(minLength: 4)
                    if isMember {
                        Text("Joined")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(YukiTheme.accent)
                    } else if server.isNew {
                        Text("New")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(YukiTheme.accent))
                    }
                }
                .padding(.leading, 70)

                if let description = server.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 6)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                        Text("\(server.members.formatted()) \(server.members == 1 ? "member" : "members")")
                    }
                    if let activity = server.activity.label {
                        HStack(spacing: 4) {
                            Circle().fill(server.activity.color).frame(width: 7, height: 7)
                            Text(activity)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !server.tags.isEmpty {
                    TagRow(tags: server.tags)
                }
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isMember ? "Opens the server" : "Shows the server so you can join")
    }
}

private struct DiscoverBotCard: View {
    let bot: DiscoverBot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(avatar: bot.avatar, fallbackText: bot.username, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(bot.username)
                        .font(.headline)
                        .lineLimit(1)
                    BotTagView()
                }
                if let description = bot.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                    Text("In \(bot.servers.formatted()) \(bot.servers == 1 ? "server" : "servers")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !bot.tags.isEmpty {
                    TagRow(tags: bot.tags)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Add this bot to a server or group")
    }
}

private struct TagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(4), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: \(tags.prefix(4).joined(separator: ", "))")
    }
}

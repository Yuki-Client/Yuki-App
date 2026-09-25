import SwiftUI
import StoatCore
import StoatState
import StoatVoice

public struct ChannelListView: View {
    @Bindable var store: AppStore
    @State private var showSettings = false
    @State private var showNewConversation = false
    @State private var showFriends = false
    @State private var showCreateChannel = false
    @State private var createChannelCategoryId: String?
    @State private var showCategoryEditor = false
    @State private var showServerSettings = false
    @State private var detailsChannelId: String?
    @State private var inviteChannelId: String?
    @State private var closeTarget: Channel?
    @Environment(VoiceCallController.self) private var voice
    @State private var serverChangedAt = Date.distantPast
    @State private var showQuickSwitcher = false
    @State private var conversationQuery = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true
    @AppStorage("yuki.collapsedCategories") private var collapsedStorage = ""

    public init(store: AppStore) {
        self.store = store
    }

    private var collapsedCategories: Set<String> {
        Set(collapsedStorage.split(separator: ",").map(String.init))
    }

    private func toggleCategory(_ id: String) {
        var set = collapsedCategories
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        collapsedStorage = set.joined(separator: ",")
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header(topInset: proxy.safeAreaInsets.top)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let serverId = store.selectedServerId, store.store.servers[serverId] != nil {
                            serverChannels(serverId: serverId)
                        } else {
                            directMessages
                        }
                    }
                    .padding(.vertical, 8)
                }
                // A fresh scroll view per server: otherwise, after scrolling far down a long channel
                // list, a shorter one stays scrolled past its end and looks empty.
                .id(store.selectedServerId ?? AppStore.homeKey)
                .scrollDismissesKeyboard(.immediately)
                .transition(.opacity.combined(with: .offset(y: 10)))
                .animation(YukiMotion.transition(reduceMotion: reduceMotion, enabled: animationsEnabled), value: store.selectedServerId)

                Divider()
                VoiceCallBar(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(YukiMotion.transition(reduceMotion: reduceMotion, enabled: animationsEnabled), value: voice.channelId)
                // Sit the footer partly inside the home indicator area instead of floating above it.
                CurrentUserFooter(store: store) { showSettings = true }
                    .padding(.bottom, max(4, proxy.safeAreaInsets.bottom - 20))
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
        }
        .background(YukiTheme.secondaryBackground)
        .onChange(of: store.selectedServerId) {
            serverChangedAt = .now
        }
        .sheet(isPresented: $showQuickSwitcher) {
            QuickSwitcherSheet(store: store)
        }
        .sheet(isPresented: $showSettings) {
            UserSettingsSheet(store: store)
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationSheet(store: store)
        }
        .sheet(isPresented: $showFriends) {
            FriendsListView(store: store)
        }
        .sheet(isPresented: $showCreateChannel) {
            if let serverId = store.selectedServerId {
                CreateChannelSheet(store: store, serverId: serverId, categoryId: createChannelCategoryId)
            }
        }
        .sheet(isPresented: $showCategoryEditor) {
            if let serverId = store.selectedServerId {
                NavigationStack {
                    ServerCategoriesView(store: store, serverId: serverId, showsDoneButton: true)
                }
            }
        }
        .sheet(isPresented: $showServerSettings) {
            if let serverId = store.selectedServerId {
                ServerSettingsSheet(store: store, serverId: serverId)
            }
        }
        .sheet(item: Binding(get: { detailsChannelId.map(IdentifiedString.init) }, set: { detailsChannelId = $0?.value })) { item in
            ChannelDetailsSheet(store: store, channelId: item.value)
        }
        .sheet(item: Binding(get: { inviteChannelId.map(IdentifiedString.init) }, set: { inviteChannelId = $0?.value })) { item in
            InviteShareSheet(store: store, channelId: item.value)
                .presentationDetents([.height(360)])
        }
        .alert(
            closeTarget?.channelType == .group ? "Leave group?" : "Close conversation?",
            isPresented: Binding(get: { closeTarget != nil }, set: { if !$0 { closeTarget = nil } })
        ) {
            Button(closeTarget?.channelType == .group ? "Leave Group" : "Close", role: .destructive) {
                if let channel = closeTarget {
                    Task { await store.closeConversation(channelId: channel.id) }
                }
                closeTarget = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Height of the header row, matched by the server rail so the first icon lines up with the title.
    static let headerRowHeight: CGFloat = 52

    @ViewBuilder
    private func header(topInset: CGFloat) -> some View {
        if let serverId = store.selectedServerId, let server = store.store.servers[serverId] {
            serverHeader(server, topInset: topInset)
        } else {
            HStack {
                Text("Direct Messages")
                    .font(.headline)
                Spacer()
                quickSwitcherButton(onBanner: false)
                Button {
                    showNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("New conversation")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(height: Self.headerRowHeight)
            .padding(.top, topInset)
        }
    }

    private func serverHeader(_ server: Server, topInset: CGFloat) -> some View {
        let permissions = store.store.permissions(in: server)
        return ZStack(alignment: .top) {
            // The banner runs up under the status bar, with the title row at the top so it lines up
            // with the rail's first icon; the rest of the banner shows below the title.
            if let banner = server.banner {
                Color.clear
                    .frame(height: topInset + 110)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RemoteImage(url: banner.downloadURL(), maxPixelSize: 800, animates: true) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { _ in
                            Color.clear
                        }
                    }
                    .clipped()
                    .overlay(LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            }

            HStack {
                Menu {
                    if permissions.contains(.inviteOthers) {
                        Button {
                            createInvite(server)
                        } label: {
                            Label("Invite People", systemImage: "person.badge.plus")
                        }
                    }
                    Button {
                        showServerSettings = true
                    } label: {
                        Label("Server Settings", systemImage: "gearshape")
                    }
                    if permissions.contains(.manageChannel) {
                        Button {
                            createChannelCategoryId = nil
                            showCreateChannel = true
                        } label: {
                            Label("Create Channel", systemImage: "plus.bubble")
                        }
                        Button {
                            showCategoryEditor = true
                        } label: {
                            Label("Edit Categories", systemImage: "folder")
                        }
                    }
                    Button {
                        Task { await store.markServerAsRead(server.id) }
                    } label: {
                        Label("Mark as Read", systemImage: "checkmark.message")
                    }
                    let muted = store.store.notificationOptions.isServerMuted(server.id)
                    Button {
                        Task { await store.setServerMuted(!muted, serverId: server.id) }
                    } label: {
                        Label(muted ? "Unmute" : "Mute", systemImage: muted ? "bell" : "bell.slash")
                    }
                } label: {
                    HStack(spacing: 6) {
                        if server.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(YukiTheme.accent)
                        }
                        Text(server.name)
                            .font(.headline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(server.banner == nil ? Color.primary : Color.white)
                }
                .accessibilityLabel("\(server.name) options")

                Spacer()

                quickSwitcherButton(onBanner: server.banner != nil)
                if permissions.contains(.inviteOthers) {
                    Button {
                        createInvite(server)
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(server.banner == nil ? YukiTheme.accent : .white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Invite people")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(height: Self.headerRowHeight)
            .padding(.top, topInset)
        }
    }

    private func quickSwitcherButton(onBanner: Bool) -> some View {
        Button {
            showQuickSwitcher = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onBanner ? .white : YukiTheme.accent)
                .frame(width: 40, height: 44)
        }
        .accessibilityLabel("Jump to a channel or person")
        .keyboardShortcut("k", modifiers: .command)
    }

    private func createInvite(_ server: Server) {
        let channel = store.selectedChannelId.flatMap { store.store.channels[$0] }.flatMap { $0.server == server.id ? $0 : nil }
            ?? store.store.channels(forServer: server.id).first { store.store.hasPermission(.inviteOthers, in: $0) }
        guard let channel else {
            store.showError("There's no channel you can create an invite for.")
            return
        }
        inviteChannelId = channel.id
    }

    @ViewBuilder
    private func serverChannels(serverId: String) -> some View {
        let (categorized, uncategorized) = store.store.categorizedChannels(forServer: serverId)

        ForEach(uncategorized) { channel in
            channelRow(channel)
        }

        ForEach(categorized, id: \.category.id) { section in
            let isCollapsed = collapsedCategories.contains(section.category.id)
            Button {
                YukiHaptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggleCategory(section.category.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Text(section.category.title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let server = store.store.servers[serverId], store.store.hasPermission(.manageChannel, in: server) {
                    Button {
                        createChannelCategoryId = section.category.id
                        showCreateChannel = true
                    } label: {
                        Label("Create Channel", systemImage: "plus.bubble")
                    }
                    Button {
                        showCategoryEditor = true
                    } label: {
                        Label("Edit Categories", systemImage: "folder")
                    }
                }
            } preview: {
                Text(section.category.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(width: 300, alignment: .leading)
                    .background(YukiTheme.secondaryBackground)
            }
            .accessibilityLabel("\(section.category.title) category")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            ForEach(section.channels) { channel in
                // Unread channels stay visible inside collapsed categories, like Stoat for Web.
                if !isCollapsed || store.selectedChannelId == channel.id || store.store.isUnread(channel: channel) {
                    channelRow(channel)
                }
            }
        }

        if categorized.isEmpty && uncategorized.isEmpty {
            Text("No channels you can view.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    /// Taps are ignored just after switching servers, while the list changes under the finger,
    /// so a stray tap doesn't open the wrong channel.
    private var acceptsTaps: Bool {
        Date.now.timeIntervalSince(serverChangedAt) > 0.5 && YukiSwipeGuard.acceptsTaps
    }

    /// The row to highlight: the open channel, or else the one swiping right to left would open,
    /// so switching servers shows where you'll land.
    private var highlightedChannelId: String? {
        store.selectedChannelId ?? store.lastChannel(forServer: store.selectedServerId)
    }

    private func channelRow(_ channel: Channel) -> some View {
        let isSelected = highlightedChannelId == channel.id
        let isUnread = store.store.isUnread(channel: channel)
        let mentions = store.store.mentionCount(channelId: channel.id)
        let isMuted = store.store.isMuted(channel: channel)

        return VStack(alignment: .leading, spacing: 2) {
            Button {
                guard acceptsTaps else { return }
                YukiHaptics.selection()
                store.openChannel(channel.id)
            } label: {
                ChannelRowLabel(
                    channel: channel,
                    isSelected: isSelected,
                    isUnread: isUnread,
                    isMuted: isMuted,
                    hasDraft: store.drafts[channel.id] != nil,
                    mentions: mentions,
                    voiceCount: store.store.voiceStates[channel.id]?.count ?? 0
                )
            }
            .buttonStyle(YukiPressStyle())
            .contextMenu {
                channelMenu(channel, isUnread: isUnread, isMuted: isMuted)
            } preview: {
                ChannelRowLabel(channel: channel, isSelected: false, isUnread: isUnread, isMuted: isMuted, hasDraft: false, mentions: mentions)
                    .frame(width: 300)
                    .padding(4)
                    .background(YukiTheme.secondaryBackground)
                    .environment(store)
                    .environment(voice)
            }
            .padding(.horizontal, 8)
            .accessibilityLabel(channel.name ?? "channel")
            .accessibilityValue([mentions > 0 ? "\(mentions) mentions" : nil, isUnread ? "unread" : nil, isMuted ? "muted" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            ChannelVoiceParticipants(store: store, channel: channel)
        }
    }

    @ViewBuilder
    private func channelMenu(_ channel: Channel, isUnread: Bool, isMuted: Bool) -> some View {
        if isUnread {
            Button {
                store.markChannelAsRead(channel.id)
            } label: {
                Label("Mark as Read", systemImage: "checkmark.message")
            }
        }
        discardDraftButton(channel.id)
        Button {
            Task { await store.setChannelMuted(!isMuted, channelId: channel.id) }
        } label: {
            Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "bell" : "bell.slash")
        }
        if store.store.hasPermission(.inviteOthers, in: channel), channel.server != nil {
            Button {
                inviteChannelId = channel.id
            } label: {
                Label("Invite People", systemImage: "person.badge.plus")
            }
        }
        Button {
            detailsChannelId = channel.id
        } label: {
            Label("Channel Details", systemImage: "info.circle")
        }
        Button {
            UIPasteboard.general.string = channel.id
        } label: {
            Label("Copy Channel ID", systemImage: "number")
        }
    }

    @ViewBuilder
    private func discardDraftButton(_ channelId: String) -> some View {
        if store.drafts[channelId] != nil {
            Button(role: .destructive) {
                store.setDraft("", for: channelId)
            } label: {
                Label("Discard Draft", systemImage: "pencil.slash")
            }
        }
    }

    @ViewBuilder
    private var directMessages: some View {
        Button {
            showFriends = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(YukiTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(YukiTheme.accent.opacity(0.15)))
                Text("Friends")
                    .font(.body.weight(.semibold))
                Spacer()
                let pending = store.incomingFriendRequests.count
                if pending > 0 {
                    MentionBadge(count: pending)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel("Friends")

        conversationSearchField

        Text("CONVERSATIONS")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 4)

        let conversations = filteredConversations
        if conversations.isEmpty {
            Text(conversationQuery.isEmpty ? "No conversations yet." : "No conversations match “\(conversationQuery)”.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
        } else {
            ForEach(conversations) { channel in
                dmRow(channel)
            }
        }
    }

    private var conversationSearchField: some View {
        SearchField(prompt: "Search conversations", text: $conversationQuery) {
            if let first = filteredConversations.first {
                store.openChannel(first.id)
                conversationQuery = ""
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filteredConversations: [Channel] {
        let conversations = store.store.directChannels
        let query = conversationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        let users = store.store.users
        let me = store.store.currentUserId
        func matches(_ text: String?) -> Bool {
            guard let text else { return false }
            return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return conversations.filter { channel in
            if matches(channel.displayName(withUsers: users, currentUserId: me)) || matches(channel.name) { return true }
            return (channel.recipients ?? []).contains { id in
                guard id != me, let user = users[id] else { return false }
                return matches(user.displayName) || matches(user.username)
            }
        }
    }

    private func dmRow(_ channel: Channel) -> some View {
        let isSelected = highlightedChannelId == channel.id
        let isUnread = store.store.isUnread(channel: channel)
        let mentions = store.store.mentionCount(channelId: channel.id)
        let title = channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId)
        return Button {
            guard acceptsTaps else { return }
            YukiHaptics.selection()
            store.openChannel(channel.id)
        } label: {
            ConversationRowLabel(store: store, channel: channel, title: title, isSelected: isSelected, isUnread: isUnread, mentions: mentions)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isUnread {
                Button {
                    store.markChannelAsRead(channel.id)
                } label: {
                    Label("Mark as Read", systemImage: "checkmark.message")
                }
            }
            discardDraftButton(channel.id)
            let muted = store.store.isMuted(channel: channel)
            Button {
                Task { await store.setChannelMuted(!muted, channelId: channel.id) }
            } label: {
                Label(muted ? "Unmute" : "Mute", systemImage: muted ? "bell" : "bell.slash")
            }
            if channel.channelType != .savedMessages {
                Button {
                    detailsChannelId = channel.id
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                Button(role: .destructive) {
                    closeTarget = channel
                } label: {
                    Label(channel.channelType == .group ? "Leave Group" : "Close DM", systemImage: "xmark.circle")
                }
            }
        } preview: {
            // Previews are drawn in their own window, which doesn't inherit the environment.
            ConversationRowLabel(store: store, channel: channel, title: title, isSelected: false, isUnread: isUnread, mentions: mentions)
                .frame(width: 300)
                .padding(6)
                .background(YukiTheme.secondaryBackground)
                .environment(store)
                .environment(voice)
        }
        .padding(.horizontal, 8)
        .accessibilityLabel(title)
        .accessibilityValue([mentions > 0 ? "\(mentions) mentions" : nil, isUnread ? "unread" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

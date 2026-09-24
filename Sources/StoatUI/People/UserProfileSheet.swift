import SwiftUI
import StoatCore
import StoatState

public struct UserProfileSheet: View {
    @Bindable var store: AppStore
    let userId: String
    let serverId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var mutuals: MutualConnections?
    @State private var showReport = false
    @State private var addableBot: PublicBot?
    @State private var showAddBot = false
    @State private var showBlockConfirm = false
    @State private var moderation: ModerationAction?
    @State private var mutualFriendId: String?

    enum ModerationAction: String, Identifiable {
        case nickname, roles, timeout, kick, ban
        var id: String { rawValue }
    }

    public init(store: AppStore, userId: String, serverId: String?) {
        self.store = store
        self.userId = userId
        self.serverId = serverId
    }

    private var user: User? { store.store.users[userId] }
    private var isSelf: Bool { userId == store.store.currentUserId }
    private var member: ServerMember? { serverId.flatMap { store.store.member(userId: userId, in: $0) } }
    private var server: Server? { serverId.flatMap { store.store.servers[$0] } }
    private var serverPermissions: Permission { server.map { store.store.permissions(in: $0) } ?? [] }
    private var canModerate: Bool { serverId.map { store.store.canModerate(userId: userId, in: $0) } ?? false }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    actionButtons
                    if let content = profile?.content, !content.isEmpty {
                        section("About Me") {
                            YukiMarkdownView(content, serverId: serverId)
                        }
                    }
                    if let member, let serverId {
                        memberSection(member, serverId: serverId)
                    }
                    mutualSection
                    section("Account") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let date = Message.date(fromULID: userId) {
                                Label("Joined Stoat \(date.formatted(date: .long, time: .omitted))", systemImage: "calendar")
                            }
                            Button {
                                UIPasteboard.general.string = userId
                                YukiHaptics.notification(.success)
                            } label: {
                                Label("Copy User ID", systemImage: "number")
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(YukiTheme.systemBackground)
            .presentsLinks(store: store)
            // Pulled down to close, so there's no Done button or navigation bar.
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
            .task {
                _ = await store.loadUser(userId: userId)
                async let loadedProfile = store.loadProfile(userId: userId)
                async let loadedMutuals = store.loadMutuals(userId: userId)
                profile = await loadedProfile
                mutuals = await loadedMutuals
                if store.store.users[userId]?.bot != nil {
                    addableBot = await store.fetchPublicBot(id: userId)
                }
            }
            .sheet(item: Binding(get: { mutualFriendId.map(IdentifiedString.init) }, set: { mutualFriendId = $0?.value })) { item in
                UserProfileSheet(store: store, userId: item.value, serverId: nil)
            }
            .sheet(isPresented: $showAddBot) {
                AddBotSheet(store: store, botId: userId, botName: addableBot?.username ?? "Bot")
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(store: store, target: .user(id: userId, messageId: nil), subject: "user")
            }
            .sheet(item: $moderation) { action in
                if let serverId {
                    ModerationSheet(store: store, action: action, userId: userId, serverId: serverId)
                }
            }
            .alert("Block \(user?.visibleName ?? "this user")?", isPresented: $showBlockConfirm) {
                Button("Block", role: .destructive) {
                    Task { await store.blockUser(userId: userId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They won't be able to message you, and their messages will be hidden.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The banner is an overlay on a fixed-size shape: a fill-scaled image as a direct child
            // would report its own (wider) size and push the whole sheet off-screen.
            Color.clear
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let background = profile?.background {
                        RemoteImage(url: background.downloadURL(), maxPixelSize: 1200, animates: true) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { _ in
                            LinearGradient(colors: [YukiTheme.accentDeep, YukiTheme.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    } else {
                        LinearGradient(colors: [YukiTheme.accentDeep.opacity(0.8), YukiTheme.accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    PresenceAvatarView(user: user, userId: userId, avatarOverride: member?.avatar, size: 84)
                        .padding(4)
                        .background(Circle().fill(YukiTheme.systemBackground))
                        .offset(x: 16, y: 42)
                }
                .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.store.displayName(userId: userId, serverId: serverId))
                        .font(.title2.bold())
                    if let pronouns = member?.pronouns ?? user?.pronouns, !pronouns.isEmpty {
                        Text(pronouns)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if user?.bot != nil {
                        BotTagView()
                    }
                }
                if let user {
                    Text(user.fullHandle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let status = isSelf ? user?.status?.text.flatMap({ $0.isEmpty ? nil : $0 }) : user?.onlineStatusText {
                    Label {
                        EmojiText(text: status, emojiSize: 17)
                    } icon: {
                        Image(systemName: "bubble.left")
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }
                if let badges = user?.decodedBadges, !badges.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(badges) { badge in
                            UserBadgeChip(badge: badge, style: .compact)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !isSelf, let user {
            HStack(spacing: 10) {
                if user.relationship != .blocked && user.relationship != .blockedOther {
                    Button {
                        dismiss()
                        Task { await store.openDirectMessage(with: userId) }
                    } label: {
                        Label("Message", systemImage: "bubble.left.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if user.bot != nil, addableBot != nil {
                    Button {
                        showAddBot = true
                    } label: {
                        Label("Add to Server", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if user.bot == nil {
                    switch user.relationship {
                    case .friend:
                        Menu {
                            Button("Remove Friend", role: .destructive) {
                                Task { await store.removeFriend(userId: userId) }
                            }
                        } label: {
                            Label("Friends", systemImage: "person.fill.checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .incoming:
                        Button {
                            Task { await store.acceptFriend(userId: userId) }
                        } label: {
                            Label("Accept", systemImage: "person.fill.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .outgoing:
                        Button {
                            Task { await store.removeFriend(userId: userId) }
                        } label: {
                            Label("Cancel Request", systemImage: "person.fill.xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .none, .user:
                        Button {
                            Task { _ = await store.sendFriendRequest(username: user.fullHandle) }
                        } label: {
                            Label("Add Friend", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .blocked:
                        Button {
                            Task { await store.unblockUser(userId: userId) }
                        } label: {
                            Label("Unblock", systemImage: "hand.raised.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .blockedOther:
                        EmptyView()
                    }
                }

                Menu {
                    if user.relationship == .blocked {
                        Button {
                            Task { await store.unblockUser(userId: userId) }
                        } label: {
                            Label("Unblock", systemImage: "hand.raised.slash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showBlockConfirm = true
                        } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                    }
                    Button(role: .destructive) {
                        showReport = true
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minHeight: 22)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More actions")
            }
            .controlSize(.large)
            .padding(.horizontal, 16)
        }
    }

    private func memberSection(_ member: ServerMember, serverId: String) -> some View {
        let roles = store.store.memberRoles(userId: userId, in: serverId)
        return section(server?.name ?? "Server") {
            VStack(alignment: .leading, spacing: 12) {
                if let joined = member.joinedAt.flatMap(StoatDate.parse) {
                    Label("Member since \(joined.formatted(date: .long, time: .omitted))", systemImage: "person.badge.clock")
                        .font(.subheadline)
                }
                if let until = member.activeTimeout {
                    Label("Timed out until \(until.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if !roles.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(roles, id: \.id) { entry in
                            HStack(spacing: 5) {
                                RoleColourDot(colour: entry.role.colour, size: 10)
                                Text(entry.role.name)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(YukiTheme.cardSurface))
                        }
                    }
                }

                let canEditNickname = isSelf ? serverPermissions.contains(.changeNickname) : (serverPermissions.contains(.manageNicknames) && canModerate)
                let canAssignRoles = serverPermissions.contains(.assignRoles) && (canModerate || isSelf)
                let canTimeout = serverPermissions.contains(.timeoutMembers) && canModerate
                let canKick = serverPermissions.contains(.kickMembers) && canModerate
                let canBan = serverPermissions.contains(.banMembers) && canModerate

                if canEditNickname || canAssignRoles || canTimeout || canKick || canBan {
                    VStack(alignment: .leading, spacing: 10) {
                        if canEditNickname {
                            moderationButton("Change Nickname", icon: "pencil", action: .nickname)
                        }
                        if canAssignRoles {
                            moderationButton("Manage Roles", icon: "tag", action: .roles)
                        }
                        if canTimeout {
                            moderationButton(member.activeTimeout == nil ? "Timeout" : "Edit Timeout", icon: "clock", action: .timeout)
                        }
                        if canKick {
                            moderationButton("Kick", icon: "figure.walk.departure", action: .kick, destructive: true)
                        }
                        if canBan {
                            moderationButton("Ban", icon: "hammer", action: .ban, destructive: true)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func moderationButton(_ title: String, icon: String, action: ModerationAction, destructive: Bool = false) -> some View {
        Button {
            moderation = action
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(destructive ? .red : YukiTheme.accent)
        }
    }

    @ViewBuilder
    private var mutualSection: some View {
        if let mutuals, !isSelf {
            let servers = mutuals.servers.compactMap { store.store.servers[$0] }
            let friends = mutuals.users.compactMap { store.store.users[$0] }
            if !servers.isEmpty || !friends.isEmpty {
                section("In Common") {
                    VStack(alignment: .leading, spacing: 14) {
                        if !servers.isEmpty {
                            mutualRow(title: servers.count == 1 ? "1 Mutual Server" : "\(servers.count) Mutual Servers") {
                                ForEach(servers) { server in
                                    Button {
                                        dismiss()
                                        store.selectServer(server.id)
                                    } label: {
                                        mutualTile(name: server.name) {
                                            AvatarView(avatar: server.icon, fallbackText: server.name, size: 44, isRounded: false)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !friends.isEmpty {
                            mutualRow(title: friends.count == 1 ? "1 Mutual Friend" : "\(friends.count) Mutual Friends") {
                                ForEach(friends) { friend in
                                    Button {
                                        mutualFriendId = friend.id
                                    } label: {
                                        mutualTile(name: friend.visibleName) {
                                            PresenceAvatarView(user: friend, userId: friend.id, size: 44)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func mutualRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    content()
                }
            }
        }
    }

    private func mutualTile<Icon: View>(name: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            icon()
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(YukiTheme.secondaryBackground))
        .padding(.horizontal, 16)
    }
}

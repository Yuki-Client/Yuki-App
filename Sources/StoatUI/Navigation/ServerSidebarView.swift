import SwiftUI
import StoatCore
import StoatVoice
import StoatState

public struct ServerSidebarView: View {
    @Bindable var store: AppStore
    @State private var showAddServer = false
    @State private var showReorder = false
    @State private var showNotifications = false
    @State private var showDiscover = false
    @State private var settingsServerId: String?
    @State private var leaveServerId: String?
    @State private var newFolderServerId: String?
    @State private var renamingFolderId: String?
    @State private var folderName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(VoiceCallController.self) private var voice

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ServerRailButton(
                    title: "Home",
                    isSelected: store.selectedServerId == nil,
                    isUnread: store.store.unreadDirectCount > 0,
                    mentionCount: store.store.unreadDirectCount,
                    call: callServerId == AppStore.homeKey ? .joined : nil
                ) {
                    homeIcon
                } action: {
                    store.selectServer(nil)
                }

                ServerRailButton(
                    title: "Notifications",
                    isSelected: false,
                    isUnread: false,
                    mentionCount: store.unreadNotificationCount
                ) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(YukiTheme.cardSurface)
                } action: {
                    showNotifications = true
                }

                UnreadConversationsRail(store: store)

                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 2)

                ForEach(store.store.sidebarEntries) { entry in
                    switch entry {
                    case .server(let server):
                        serverEntry(server)
                    case .folder(let folder, let servers):
                        folderEntry(folder, servers: servers)
                    }
                }

                Button {
                    YukiHaptics.selection()
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(YukiTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a server")

                if StoatInstance.isOfficial {
                    Button {
                        YukiHaptics.selection()
                        showDiscover = true
                    } label: {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.green)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discover servers and bots")
                }
            }
            // No top padding: the Home button's row lines up with the channel list's header row.
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: store.store.sidebarLayout)
        }
        .frame(width: 72)
        .background(YukiTheme.groupedBackground)
        .sheet(isPresented: $showAddServer) {
            JoinOrCreateServerSheet(store: store)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverView(store: store)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCentreSheet(store: store)
        }
        .sheet(isPresented: $showReorder) {
            ReorderServersSheet(store: store)
        }
        .sheet(item: Binding(get: { settingsServerId.map(IdentifiedString.init) }, set: { settingsServerId = $0?.value })) { item in
            ServerSettingsSheet(store: store, serverId: item.value)
        }
        .alert(
            leaveTitle,
            isPresented: Binding(get: { leaveServerId != nil }, set: { if !$0 { leaveServerId = nil } })
        ) {
            Button(isOwner(leaveServerId) ? "Delete Server" : "Leave Server", role: .destructive) {
                if let id = leaveServerId {
                    Task { _ = await store.leaveServer(id) }
                }
                leaveServerId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOwner(leaveServerId) ? "This permanently deletes the server for everyone." : "You'll need a new invite to rejoin.")
        }
        .alert("New Folder", isPresented: Binding(get: { newFolderServerId != nil }, set: { if !$0 { newFolderServerId = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Create") {
                if let serverId = newFolderServerId {
                    let name = folderName
                    Task { await store.createFolder(named: name, with: [serverId]) }
                }
                newFolderServerId = nil
            }
            Button("Cancel", role: .cancel) { newFolderServerId = nil }
        } message: {
            Text("Add more servers from their menus, or by dragging them onto the folder.")
        }
        .alert("Rename Folder", isPresented: Binding(get: { renamingFolderId != nil }, set: { if !$0 { renamingFolderId = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Save") {
                if let folderId = renamingFolderId {
                    let name = folderName
                    Task { await store.renameFolder(folderId, to: name) }
                }
                renamingFolderId = nil
            }
            Button("Cancel", role: .cancel) { renamingFolderId = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Servers")
    }

    private func serverEntry(_ server: Server) -> some View {
        ServerRailButton(
            title: server.name,
            isSelected: store.selectedServerId == server.id,
            isUnread: store.store.isUnread(serverId: server.id),
            mentionCount: store.store.mentionCount(serverId: server.id),
            call: callIndicator(for: server.id),
            dragId: server.id,
            onDrop: { drop($0, onto: server.id) }
        ) {
            serverIcon(server)
        } action: {
            store.selectServer(server.id)
        } menu: {
            serverMenu(server)
        }
    }

    private func folderEntry(_ folder: ServerFolder, servers: [Server]) -> some View {
        let tint = Color(stoatColour: folder.colour) ?? YukiTheme.accent
        let collapsed = folder.isCollapsed
        return VStack(spacing: 10) {
            ServerRailButton(
                title: folder.displayName,
                isSelected: collapsed && servers.contains { $0.id == store.selectedServerId },
                isUnread: collapsed && servers.contains { store.store.isUnread(serverId: $0.id) },
                mentionCount: collapsed ? servers.reduce(0) { $0 + store.store.mentionCount(serverId: $1.id) } : 0,
                call: collapsed ? folderCallIndicator(servers) : nil,
                dragId: folder.id,
                onDrop: { drop($0, onto: folder.id) }
            ) {
                folderIcon(folder, servers: servers, tint: tint)
            } action: {
                Task { await store.toggleFolder(folder.id) }
            } menu: {
                folderMenu(folder, servers: servers)
            }
            .accessibilityHint(collapsed ? "Opens the folder" : "Closes the folder")

            if !collapsed {
                ForEach(servers) { server in
                    serverEntry(server)
                }
            }
        }
        .padding(.bottom, collapsed ? 0 : 6)
        .background {
            if !collapsed {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func folderIcon(_ folder: ServerFolder, servers: [Server], tint: Color) -> some View {
        if folder.isCollapsed {
            let shown = Array(servers.prefix(4))
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < shown.count {
                                AvatarView(avatar: shown[index].icon, fallbackText: shown[index].name, size: 16, isRounded: false)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            } else {
                                Color.clear.frame(width: 16, height: 16)
                            }
                        }
                    }
                }
            }
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.28))
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.2))
        }
    }

    private func folderCallIndicator(_ servers: [Server]) -> RailCall? {
        let calls = servers.compactMap { callIndicator(for: $0.id) }
        return calls.contains(.joined) ? .joined : calls.first
    }

    private static let folderColours: [(name: String, hex: String)] = [
        ("Ice", "#38b8fa"), ("Blue", "#3b82f6"), ("Purple", "#8b5cf6"), ("Pink", "#ec4899"), ("Red", "#ef4444"),
        ("Orange", "#f97316"), ("Yellow", "#eab308"), ("Green", "#22c55e"), ("Grey", "#94a3b8")
    ]

    @ViewBuilder
    private func folderMenu(_ folder: ServerFolder, servers: [Server]) -> some View {
        Button {
            Task {
                for server in servers {
                    await store.markServerAsRead(server.id)
                }
            }
        } label: {
            Label("Mark as Read", systemImage: "checkmark.message")
        }

        Button {
            folderName = folder.name
            renamingFolderId = folder.id
        } label: {
            Label("Rename Folder", systemImage: "pencil")
        }

        Menu {
            Button {
                Task { await store.setFolderColour(folder.id, to: nil) }
            } label: {
                if folder.colour == nil { Label("Default", systemImage: "checkmark") } else { Text("Default") }
            }
            ForEach(Self.folderColours, id: \.hex) { option in
                Button {
                    Task { await store.setFolderColour(folder.id, to: option.hex) }
                } label: {
                    if folder.colour?.lowercased() == option.hex { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                }
            }
        } label: {
            Label("Colour", systemImage: "paintpalette")
        }

        Button {
            showReorder = true
        } label: {
            Label("Reorder Servers", systemImage: "arrow.up.arrow.down")
        }

        Button {
            Task { await store.deleteFolder(folder.id) }
        } label: {
            Label("Remove Folder", systemImage: "folder.badge.minus")
        }
    }

    private var visibleFolders: [ServerFolder] {
        store.store.sidebarEntries.compactMap { entry in
            if case .folder(let folder, _) = entry { return folder }
            return nil
        }
    }

    private var homeIcon: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 20))
            .foregroundStyle(store.selectedServerId == nil ? .white : .primary)
            .frame(width: 48, height: 48)
            .background(
                store.selectedServerId == nil
                    ? AnyShapeStyle(LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(YukiTheme.cardSurface)
            )
    }

    @ViewBuilder
    private func serverIcon(_ server: Server) -> some View {
        if let icon = server.icon {
            AvatarView(avatar: icon, fallbackText: server.name, size: 48, isRounded: false)
        } else {
            Text(server.initials)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(YukiTheme.cardSurface)
        }
    }

    private var callServerId: String? {
        guard let channelId = voice.channelId, let channel = store.store.channels[channelId] else { return nil }
        return channel.server ?? AppStore.homeKey
    }

    private func callIndicator(for serverId: String) -> RailCall? {
        if callServerId == serverId { return .joined }
        return store.store.hasActiveCall(serverId: serverId) ? .active : nil
    }

    private func drop(_ id: String, onto targetId: String) -> Bool {
        guard id != targetId,
              store.store.servers[id] != nil || store.store.serverFolders.contains(where: { $0.id == id }) else { return false }
        YukiHaptics.impact(.medium)
        Task { await store.moveSidebarItem(id, onto: targetId) }
        return true
    }

    private var leaveTitle: String {
        let name = leaveServerId.flatMap { store.store.servers[$0]?.name } ?? "server"
        return isOwner(leaveServerId) ? "Delete \(name)?" : "Leave \(name)?"
    }

    private func isOwner(_ serverId: String?) -> Bool {
        guard let serverId else { return false }
        return store.store.servers[serverId]?.owner == store.store.currentUserId
    }

    @ViewBuilder
    private func serverMenu(_ server: Server) -> some View {
        Button {
            Task { await store.markServerAsRead(server.id) }
        } label: {
            Label("Mark as Read", systemImage: "checkmark.message")
        }

        let muted = store.store.notificationOptions.isServerMuted(server.id)
        Button {
            Task { await store.setServerMuted(!muted, serverId: server.id) }
        } label: {
            Label(muted ? "Unmute Server" : "Mute Server", systemImage: muted ? "bell" : "bell.slash")
        }

        Button {
            settingsServerId = server.id
        } label: {
            Label("Server Settings", systemImage: "gearshape")
        }

        let currentFolder = store.store.folder(containing: server.id)
        Menu {
            ForEach(visibleFolders.filter { $0.id != currentFolder?.id }) { folder in
                Button(folder.displayName) {
                    Task { await store.addServer(server.id, toFolder: folder.id) }
                }
            }
            Button {
                folderName = ""
                newFolderServerId = server.id
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label(currentFolder == nil ? "Add to Folder" : "Move to Folder", systemImage: "folder")
        }
        if let currentFolder {
            Button {
                Task { await store.removeServerFromFolder(server.id) }
            } label: {
                Label("Remove from \(currentFolder.displayName)", systemImage: "folder.badge.minus")
            }
        }

        Button {
            showReorder = true
        } label: {
            Label("Reorder Servers", systemImage: "arrow.up.arrow.down")
        }

        Button {
            UIPasteboard.general.string = server.id
        } label: {
            Label("Copy Server ID", systemImage: "number")
        }

        Button(role: .destructive) {
            leaveServerId = server.id
        } label: {
            Label(server.owner == store.store.currentUserId ? "Delete Server" : "Leave Server", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }
}

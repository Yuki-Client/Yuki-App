import SwiftUI
import PhotosUI
import StoatCore
import StoatState

public struct ServerSettingsSheet: View {
    @Bindable var store: AppStore
    public let serverId: String

    @Environment(\.dismiss) private var dismiss
    @State private var showLeaveConfirm = false
    @State private var showReport = false

    public init(store: AppStore, serverId: String) {
        self.store = store
        self.serverId = serverId
    }

    private var server: Server? { store.store.servers[serverId] }
    private var permissions: Permission { server.map { store.store.permissions(in: $0) } ?? [] }
    private var isOwner: Bool { server?.owner == store.store.currentUserId }

    public var body: some View {
        NavigationStack {
            List {
                if let server {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(avatar: server.icon, fallbackText: server.name, size: 60, isRounded: false)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(server.name).font(.headline)
                                    if server.isVerified {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(YukiTheme.accent)
                                    }
                                }
                                if let description = server.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Notifications") {
                        Toggle("Mute Server", isOn: Binding(
                            get: { store.store.notificationOptions.isServerMuted(serverId) },
                            set: { muted in Task { await store.setServerMuted(muted, serverId: serverId) } }
                        ))
                        Picker("Notify Me", selection: Binding(
                            get: { store.store.notificationOptions.server[serverId] ?? .mention },
                            set: { level in Task { await store.setNotificationLevel(level, serverId: serverId) } }
                        )) {
                            Text("All Messages").tag(NotificationOptions.Level.all)
                            Text("Mentions Only").tag(NotificationOptions.Level.mention)
                            Text("Nothing").tag(NotificationOptions.Level.none)
                        }
                    }

                    Section("You") {
                        NavigationLink {
                            ServerIdentityView(store: store, serverId: serverId)
                        } label: {
                            Label("Server Profile", systemImage: "person.crop.circle")
                        }
                        .disabled(!permissions.contains(.changeNickname) && !permissions.contains(.changeAvatar))
                    }

                    if !permissions.isDisjoint(with: [.manageServer, .manageChannel, .manageCustomisation, .banMembers, .manageRole, .managePermissions, .viewAuditLogs]) {
                        Section("Manage") {
                            if permissions.contains(.manageServer) {
                                NavigationLink {
                                    ServerOverviewEditor(store: store, serverId: serverId)
                                } label: {
                                    Label("Overview", systemImage: "square.and.pencil")
                                }
                                NavigationLink {
                                    ServerInvitesView(store: store, serverId: serverId)
                                } label: {
                                    Label("Invites", systemImage: "link")
                                }
                                NavigationLink {
                                    SystemMessagesView(store: store, serverId: serverId)
                                } label: {
                                    Label("System Messages", systemImage: "megaphone")
                                }
                            }
                            if permissions.contains(.manageChannel) {
                                NavigationLink {
                                    ServerCategoriesView(store: store, serverId: serverId)
                                } label: {
                                    Label("Categories", systemImage: "folder")
                                }
                            }
                            if permissions.contains(.manageRole) || permissions.contains(.managePermissions) {
                                NavigationLink {
                                    ServerRolesView(store: store, serverId: serverId)
                                } label: {
                                    Label("Roles & Permissions", systemImage: "tag")
                                }
                            }
                            if permissions.contains(.manageCustomisation) {
                                NavigationLink {
                                    ServerEmojiView(store: store, serverId: serverId)
                                } label: {
                                    Label("Emoji", systemImage: "face.smiling")
                                }
                            }
                            if permissions.contains(.banMembers) {
                                NavigationLink {
                                    ServerBansView(store: store, serverId: serverId)
                                } label: {
                                    Label("Bans", systemImage: "hammer")
                                }
                            }
                            if isOwner, StoatInstance.isOfficial {
                                NavigationLink {
                                    DiscoverListingView(store: store, kind: .server, id: serverId, name: server.name, isListed: server.discoverable)
                                } label: {
                                    Label("Discover", systemImage: "safari")
                                }
                            }
                            if permissions.contains(.viewAuditLogs) {
                                NavigationLink {
                                    AuditLogView(store: store, serverId: serverId)
                                } label: {
                                    Label("Audit Log", systemImage: "list.bullet.clipboard")
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            UIPasteboard.general.string = serverId
                            YukiHaptics.notification(.success)
                        } label: {
                            Label("Copy Server ID", systemImage: "number")
                        }
                        if !isOwner {
                            Button(role: .destructive) {
                                showReport = true
                            } label: {
                                Label("Report Server", systemImage: "exclamationmark.bubble")
                            }
                        }
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label(isOwner ? "Delete Server" : "Leave Server", systemImage: isOwner ? "trash" : "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(isOwner ? "Delete \(server?.name ?? "server")?" : "Leave \(server?.name ?? "server")?", isPresented: $showLeaveConfirm) {
                Button(isOwner ? "Delete Server" : "Leave Server", role: .destructive) {
                    Task {
                        if await store.leaveServer(serverId) {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isOwner ? "This permanently deletes the server and all of its messages for everyone." : "You'll need a new invite to rejoin.")
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(store: store, target: .server(id: serverId), subject: "server")
            }
        }
    }
}

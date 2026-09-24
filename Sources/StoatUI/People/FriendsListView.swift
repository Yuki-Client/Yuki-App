import SwiftUI
import StoatCore
import StoatState

public struct FriendsListView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public enum FriendTab: String, CaseIterable, Identifiable {
        case online = "Online"
        case all = "All"
        case pending = "Pending"
        case blocked = "Blocked"
        public var id: String { rawValue }
    }

    @State private var selectedTab: FriendTab = .online
    @State private var showAddFriend = false
    @State private var username = ""
    @State private var profileUserId: String?

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $selectedTab) {
                        ForEach(FriendTab.allCases) { tab in
                            if tab == .pending, !store.incomingFriendRequests.isEmpty {
                                Text("Pending (\(store.incomingFriendRequests.count))").tag(tab)
                            } else {
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch selectedTab {
                case .online:
                    userSection(store.friends.filter(\.online), empty: "No friends online right now.")
                case .all:
                    userSection(store.friends, empty: "You haven't added any friends yet.")
                case .pending:
                    if !store.incomingFriendRequests.isEmpty {
                        Section("Incoming") {
                            ForEach(store.incomingFriendRequests) { user in
                                row(user) {
                                    Button {
                                        Task { await store.acceptFriend(userId: user.id) }
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                                    }
                                    .accessibilityLabel("Accept")
                                    Button {
                                        Task { await store.removeFriend(userId: user.id) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red)
                                    }
                                    .accessibilityLabel("Decline")
                                }
                            }
                        }
                    }
                    Section("Outgoing") {
                        if store.outgoingFriendRequests.isEmpty {
                            Text("No outgoing requests.").foregroundStyle(.secondary)
                        }
                        ForEach(store.outgoingFriendRequests) { user in
                            row(user) {
                                Button("Cancel") {
                                    Task { await store.removeFriend(userId: user.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                case .blocked:
                    Section {
                        if store.blockedUsers.isEmpty {
                            Text("You haven't blocked anyone.").foregroundStyle(.secondary)
                        }
                        ForEach(store.blockedUsers) { user in
                            row(user) {
                                Button("Unblock") {
                                    Task { await store.unblockUser(userId: user.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Add friend")
                }
            }
            .alert("Add Friend", isPresented: $showAddFriend) {
                TextField("username#1234", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { username = "" }
                Button("Send Request") {
                    let target = username
                    username = ""
                    Task {
                        if await store.sendFriendRequest(username: target) {
                            store.showSuccess("Friend request sent.")
                        }
                    }
                }
            } message: {
                Text("Enter their username and tag, like username#1234.")
            }
            .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
                UserProfileSheet(store: store, userId: item.value, serverId: nil)
            }
        }
    }

    @ViewBuilder
    private func userSection(_ users: [User], empty: String) -> some View {
        Section {
            if users.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                row(user) {
                    Button {
                        dismiss()
                        Task { await store.openDirectMessage(with: user.id) }
                    } label: {
                        Image(systemName: "bubble.left.fill").foregroundStyle(YukiTheme.accent)
                    }
                    .accessibilityLabel("Message \(user.visibleName)")
                }
            }
        }
    }

    private func row<Actions: View>(_ user: User, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Button {
                profileUserId = user.id
            } label: {
                HStack(spacing: 12) {
                    PresenceAvatarView(user: user, userId: user.id, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.visibleName).font(.body.weight(.medium))
                        EmojiText(text: user.onlineStatusText ?? user.fullHandle, emojiSize: 14)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            actions()
        }
    }
}

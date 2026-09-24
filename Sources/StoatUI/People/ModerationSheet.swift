import SwiftUI
import StoatCore
import StoatState

struct ModerationSheet: View {
    @Bindable var store: AppStore
    let action: UserProfileSheet.ModerationAction
    let userId: String
    let serverId: String

    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var reason = ""
    @State private var selectedRoles: Set<String> = []
    @State private var deleteMessageSeconds = 0
    @State private var isWorking = false

    private var name: String { store.store.displayName(userId: userId, serverId: serverId) }

    private static let deleteMessageOptions: [(label: String, seconds: Int)] = [
        ("Don't Delete Any", 0), ("Previous Hour", 3600), ("Previous 6 Hours", 21_600), ("Previous 12 Hours", 43_200),
        ("Previous 24 Hours", 86_400), ("Previous 3 Days", 259_200), ("Previous 7 Days", 604_800)
    ]

    private static let timeoutOptions: [(label: String, seconds: TimeInterval)] = [
        ("60 seconds", 60), ("5 minutes", 300), ("10 minutes", 600), ("1 hour", 3600), ("1 day", 86_400), ("1 week", 604_800)
    ]

    var body: some View {
        NavigationStack {
            Form {
                switch action {
                case .nickname:
                    Section {
                        TextField(store.store.users[userId]?.visibleName ?? "Nickname", text: $nickname)
                    } footer: {
                        Text("Leave empty to reset the nickname.")
                    }
                case .roles:
                    Section("Roles") {
                        ForEach(assignableRoles, id: \.id) { entry in
                            Toggle(isOn: Binding(
                                get: { selectedRoles.contains(entry.id) },
                                set: { isOn in
                                    if isOn { selectedRoles.insert(entry.id) } else { selectedRoles.remove(entry.id) }
                                }
                            )) {
                                HStack(spacing: 8) {
                                    RoleColourDot(colour: entry.role.colour, size: 12)
                                    Text(entry.role.name)
                                }
                            }
                        }
                        if assignableRoles.isEmpty {
                            Text("There are no roles you can assign.")
                                .foregroundStyle(.secondary)
                        }
                    }
                case .timeout:
                    Section("Time out \(name) for") {
                        ForEach(Self.timeoutOptions, id: \.seconds) { option in
                            Button(option.label) {
                                perform { await store.setTimeout(until: Date().addingTimeInterval(option.seconds), userId: userId, serverId: serverId) }
                            }
                        }
                    }
                    if store.store.member(userId: userId, in: serverId)?.activeTimeout != nil {
                        Section {
                            Button("Remove Timeout") {
                                perform { await store.setTimeout(until: nil, userId: userId, serverId: serverId) }
                            }
                        }
                    }
                case .kick:
                    Section {
                        Text("\(name) will be removed from the server. They can rejoin with a new invite.")
                    }
                    Section {
                        Button("Kick \(name)", role: .destructive) {
                            perform { await store.kickMember(userId: userId, serverId: serverId) }
                        }
                    }
                case .ban:
                    Section("Reason") {
                        TextField("Optional", text: $reason, axis: .vertical)
                    }
                    Section {
                        Picker("Delete Messages", selection: $deleteMessageSeconds) {
                            ForEach(Self.deleteMessageOptions, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                    } footer: {
                        Text("Removes what \(name) sent anywhere in this server over that time, even if they've already left.")
                    }
                    Section {
                        Button("Ban \(name)", role: .destructive) {
                            perform {
                                await store.banMember(userId: userId, serverId: serverId, reason: reason, deleteMessageSeconds: deleteMessageSeconds)
                            }
                        }
                    }
                }
            }
            .disabled(isWorking)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if action == .nickname || action == .roles {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if action == .nickname {
                                perform { await store.setNickname(nickname, userId: userId, serverId: serverId) }
                            } else {
                                perform { await store.setRoles(Array(selectedRoles), userId: userId, serverId: serverId) }
                            }
                        }
                    }
                }
            }
            .onAppear {
                let member = store.store.member(userId: userId, in: serverId)
                nickname = member?.nickname ?? ""
                selectedRoles = Set(member?.roles ?? [])
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch action {
        case .nickname: return "Nickname"
        case .roles: return "Roles"
        case .timeout: return "Timeout"
        case .kick: return "Kick Member"
        case .ban: return "Ban Member"
        }
    }

    /// Roles ranked below the current user's highest role.
    private var assignableRoles: [(id: String, role: Role)] {
        guard let server = store.store.servers[serverId], let me = store.store.currentUserId else { return [] }
        let myRank = store.store.memberRanking(userId: me, in: serverId)
        return server.roles
            .map { (id: $0.key, role: $0.value) }
            .filter { server.owner == me || $0.role.rank > myRank }
            .sorted { $0.role.rank < $1.role.rank }
    }

    private func perform(_ operation: @escaping () async -> Bool) {
        isWorking = true
        Task {
            let success = await operation()
            isWorking = false
            if success {
                YukiHaptics.notification(.success)
                dismiss()
            }
        }
    }
}

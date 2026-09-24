import SwiftUI
import StoatCore
import StoatState

public struct NewConversationSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: [String] = []
    @State private var groupName = ""
    @State private var isCreating = false

    public init(store: AppStore) {
        self.store = store
    }

    private var groupLimit: Int {
        (store.instanceConfiguration?.features.limits?.global?.groupSize ?? 100) - 1
    }

    private var friends: [User] {
        let lowered = query.lowercased()
        return store.friends.filter {
            lowered.isEmpty || $0.visibleName.lowercased().contains(lowered) || $0.username.lowercased().contains(lowered)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                if selected.count > 1 {
                    Section("Group Name") {
                        TextField(defaultGroupName, text: $groupName)
                    }
                }

                Section {
                    if friends.isEmpty {
                        Text(store.friends.isEmpty ? "Add friends to start a conversation." : "No matches.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(friends) { user in
                        Button {
                            toggle(user.id)
                        } label: {
                            HStack(spacing: 12) {
                                PresenceAvatarView(user: user, userId: user.id, size: 36)
                                VStack(alignment: .leading) {
                                    Text(user.visibleName)
                                    Text(user.fullHandle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(user.id) ? YukiTheme.accent : .secondary)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(user.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Friends")
                } footer: {
                    Text("Pick one friend for a direct message, or several to create a group.")
                }
            }
            .searchable(text: $query, prompt: "Search friends")
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.count > 1 ? "Create Group" : "Message") { start() }
                        .disabled(selected.isEmpty || isCreating)
                }
            }
        }
    }

    private var defaultGroupName: String {
        selected.compactMap { store.store.users[$0]?.visibleName }.prefix(3).joined(separator: ", ")
    }

    private func toggle(_ id: String) {
        YukiHaptics.selection()
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if selected.count < groupLimit {
            selected.append(id)
        }
    }

    private func start() {
        isCreating = true
        Task {
            if selected.count == 1, let id = selected.first {
                await store.openDirectMessage(with: id)
                dismiss()
            } else {
                let name = groupName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultGroupName : groupName
                if await store.createGroup(name: String(name.prefix(32)), users: selected) != nil {
                    dismiss()
                }
            }
            isCreating = false
        }
    }
}

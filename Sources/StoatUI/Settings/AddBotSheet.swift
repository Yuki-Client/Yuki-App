import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct AddBotSheet: View {
    @Bindable var store: AppStore
    let botId: String
    let botName: String

    @Environment(\.dismiss) private var dismiss
    @State private var addingTo: String?

    private var servers: [Server] {
        store.store.orderedServers.filter { store.store.hasPermission(.manageServer, in: $0) }
    }

    private var groups: [Channel] {
        store.store.directChannels.filter { $0.channelType == .group && $0.owner == store.store.currentUserId }
    }

    var body: some View {
        NavigationStack {
            List {
                if servers.isEmpty && groups.isEmpty {
                    ContentUnavailableView("Nowhere to Add", systemImage: "server.rack", description: Text("You need Manage Server in a server, or to own a group, to add bots."))
                }
                if !servers.isEmpty {
                    Section("Servers") {
                        ForEach(servers) { server in
                            destinationRow(id: server.id, title: server.name) {
                                AvatarView(avatar: server.icon, fallbackText: server.name, size: 32, isRounded: false)
                            } action: {
                                await store.addBot(id: botId, to: .server(server.id))
                            }
                        }
                    }
                }
                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { group in
                            destinationRow(id: group.id, title: group.name ?? "Group") {
                                AvatarView(avatar: group.icon, fallbackText: group.name ?? "G", size: 32)
                            } action: {
                                await store.addBot(id: botId, to: .group(group.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add \(botName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func destinationRow<Icon: View>(id: String, title: String, @ViewBuilder icon: () -> Icon, action: @escaping () async -> Bool) -> some View {
        Button {
            addingTo = id
            Task {
                if await action() {
                    dismiss()
                }
                addingTo = nil
            }
        } label: {
            HStack(spacing: 12) {
                icon()
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if addingTo == id {
                    ProgressView()
                }
            }
        }
        .disabled(addingTo != nil)
    }
}

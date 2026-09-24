import SwiftUI
import StoatCore
import StoatState

struct ReorderServersSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private struct FolderSection: Identifiable {
        let folder: ServerFolder
        let servers: [Server]
        var id: String { folder.id }
    }

    var body: some View {
        let entries = store.store.sidebarEntries
        let folders = entries.compactMap { entry -> FolderSection? in
            if case .folder(let folder, let servers) = entry { return FolderSection(folder: folder, servers: servers) }
            return nil
        }
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        switch entry {
                        case .server(let server):
                            serverRow(server)
                        case .folder(let folder, let servers):
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color(stoatColour: folder.colour) ?? YukiTheme.accent)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(folder.displayName)
                                    Text(servers.count == 1 ? "1 server" : "\(servers.count) servers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        Task { await store.moveSidebarEntries(from: source, to: destination) }
                    }
                } header: {
                    Text("Server List")
                }

                ForEach(folders) { section in
                    Section(section.folder.displayName) {
                        ForEach(section.servers) { server in
                            serverRow(server)
                        }
                        .onMove { source, destination in
                            Task { await store.moveServersInFolder(section.folder.id, from: source, to: destination) }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func serverRow(_ server: Server) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatar: server.icon, fallbackText: server.name, size: 32, isRounded: false)
            Text(server.name)
        }
    }
}

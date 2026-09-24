import SwiftUI
import StoatCore
import StoatState

struct ServerRolesView: View {
    @Bindable var store: AppStore
    let serverId: String

    @State private var editMode: EditMode = .inactive
    @State private var showCreate = false
    @State private var newRoleName = ""
    @State private var isCreating = false
    @State private var openRoleId: String?

    private var server: Server? { store.store.servers[serverId] }
    private var myPermissions: Permission { server.map { store.store.permissions(in: $0) } ?? [] }

    var body: some View {
        let roles = store.rolesByRank(serverId: serverId)
        let isOwner = server?.owner == store.store.currentUserId

        List {
            Section {
                NavigationLink {
                    ServerDefaultPermissionsView(store: store, serverId: serverId)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(YukiTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Everyone")
                            Text("Permissions available without any role")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if roles.isEmpty {
                    Text("No roles yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(roles, id: \.id) { entry in
                    let editable = store.canEditRole(entry.id, serverId: serverId)
                    NavigationLink {
                        RoleEditorView(store: store, serverId: serverId, roleId: entry.id)
                    } label: {
                        HStack(spacing: 12) {
                            RoleColourDot(colour: entry.role.colour, size: 16)
                                .frame(width: 22)
                            Text(entry.role.name)
                                .foregroundStyle(AnyShapeStyle.stoatPaint(entry.role.colour) ?? AnyShapeStyle(.primary))
                            Spacer()
                            if entry.role.hoist {
                                Image(systemName: "list.bullet.indent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Shown separately")
                            }
                            if !editable {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Ranked above you")
                            }
                        }
                    }
                    .moveDisabled(!isOwner && !editable)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = entry.id
                        } label: {
                            Label("Copy Role ID", systemImage: "number")
                        }
                    }
                }
                .onMove { source, destination in
                    let proposed = AppStore.reorder(roles.map(\.id), from: source, to: destination)
                    Task { _ = await store.setRoleOrder(proposed, serverId: serverId) }
                }
            } header: {
                Text("Roles")
            } footer: {
                Text("Roles higher in the list take priority. You can only change roles ranked below your own highest role.")
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Roles")
        .toolbar {
            if myPermissions.contains(.manageRole) {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: {
                        Text(editMode.isEditing ? "Done" : "Reorder")
                    }
                    .disabled(roles.count < 2)

                    Button {
                        newRoleName = ""
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Role")
                    .disabled(isCreating)
                }
            }
        }
        .alert("New Role", isPresented: $showCreate) {
            TextField("Role name", text: $newRoleName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                isCreating = true
                Task {
                    if let id = await store.createRole(name: newRoleName, serverId: serverId) {
                        openRoleId = id
                    }
                    isCreating = false
                }
            }
            .disabled(newRoleName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("New roles start at the bottom of the list with no extra permissions.")
        }
        .navigationDestination(item: $openRoleId) { roleId in
            RoleEditorView(store: store, serverId: serverId, roleId: roleId)
        }
    }
}

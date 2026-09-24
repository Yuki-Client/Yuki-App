import SwiftUI
import StoatCore
import StoatState

struct ChannelPermissionsView: View {
    @Bindable var store: AppStore
    let channelId: String

    @State private var addingRoleId: String?

    private var channel: Channel? { store.store.channels[channelId] }

    var body: some View {
        let serverId = channel?.server ?? ""
        let roles = store.rolesByRank(serverId: serverId)
        let overrides = roles.filter { !PermissionOverrideValue(channel?.rolePermissions[$0.id]).isEmpty }
        let available = roles.filter { PermissionOverrideValue(channel?.rolePermissions[$0.id]).isEmpty && store.outranksRole($0.id, serverId: serverId) }

        List {
            Section {
                NavigationLink {
                    ChannelOverrideEditorView(store: store, channelId: channelId, roleId: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(YukiTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Everyone")
                            Text(summary(PermissionOverrideValue(channel?.defaultPermissions), empty: "Uses the server's permissions"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if overrides.isEmpty {
                    Text("No role overrides yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(overrides, id: \.id) { entry in
                    NavigationLink {
                        ChannelOverrideEditorView(store: store, channelId: channelId, roleId: entry.id)
                    } label: {
                        HStack(spacing: 12) {
                            RoleColourDot(colour: entry.role.colour)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.role.name)
                                Text(summary(PermissionOverrideValue(channel?.rolePermissions[entry.id]), empty: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!store.outranksRole(entry.id, serverId: serverId))
                }
                if !available.isEmpty {
                    Menu {
                        ForEach(available, id: \.id) { entry in
                            Button(entry.role.name) { addingRoleId = entry.id }
                        }
                    } label: {
                        Label("Add Role Override", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Role Overrides")
            } footer: {
                Text("Overrides change what a role can do in this channel only. You can only override roles ranked below you.")
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $addingRoleId) { roleId in
            ChannelOverrideEditorView(store: store, channelId: channelId, roleId: roleId)
        }
    }

    private func summary(_ value: PermissionOverrideValue, empty: String) -> String {
        if value.isEmpty { return empty }
        var parts: [String] = []
        if value.allowedCount > 0 { parts.append("Allows \(value.allowedCount)") }
        if value.deniedCount > 0 { parts.append("Denies \(value.deniedCount)") }
        return parts.joined(separator: " · ")
    }
}

/// Edits a channel's default override (`roleId == nil`) or one role's override.
struct ChannelOverrideEditorView: View {
    @Bindable var store: AppStore
    let channelId: String
    let roleId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var value = PermissionOverrideValue()
    @State private var isSaving = false

    private var channel: Channel? { store.store.channels[channelId] }
    private var current: PermissionOverrideValue {
        guard let channel else { return PermissionOverrideValue() }
        if let roleId { return PermissionOverrideValue(channel.rolePermissions[roleId]) }
        return PermissionOverrideValue(channel.defaultPermissions)
    }
    private var myPermissions: Permission { channel.map { store.store.permissions(in: $0) } ?? [] }
    private var role: Role? {
        guard let roleId, let serverId = channel?.server else { return nil }
        return store.store.servers[serverId]?.roles[roleId]
    }

    var body: some View {
        Form {
            Section {
                EmptyView()
            } footer: {
                Text(roleId == nil
                     ? "Changes what everyone can do in #\(channel?.name ?? "this channel"). A dash keeps the server's setting."
                     : "Changes what \(role?.name ?? "this role") can do in #\(channel?.name ?? "this channel"). A dash keeps the role's server setting.")
            }
            PermissionSections(context: .channel, style: .overrides, value: $value, grantable: myPermissions)

            if roleId != nil, !current.isEmpty {
                Section {
                    Button("Remove Override", role: .destructive) {
                        value = PermissionOverrideValue()
                        save()
                    }
                }
            }
        }
        .navigationTitle(role?.name ?? "Everyone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .disabled(value == current || isSaving)
            }
        }
        .onAppear { value = current }
    }

    private func save() {
        isSaving = true
        Task {
            if await store.setChannelPermissions(value, roleId: roleId, channelId: channelId) {
                store.showSuccess("Permissions saved.")
                dismiss()
            }
            isSaving = false
        }
    }
}

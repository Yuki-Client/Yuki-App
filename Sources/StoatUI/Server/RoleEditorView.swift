import SwiftUI
import StoatCore
import StoatState

struct RoleEditorView: View {
    @Bindable var store: AppStore
    let serverId: String
    let roleId: String

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colour: String?
    @State private var hoist = false
    @State private var permissions = PermissionOverrideValue()
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    private var server: Server? { store.store.servers[serverId] }
    private var role: Role? { server?.roles[roleId] }
    private var myPermissions: Permission { server.map { store.store.permissions(in: $0) } ?? [] }
    private var canEdit: Bool { store.canEditRole(roleId, serverId: serverId) }
    private var canEditPermissions: Bool { myPermissions.contains(.managePermissions) && store.outranksRole(roleId, serverId: serverId) }

    private var appearanceChanged: Bool {
        guard let role else { return false }
        return name != role.name || colour != role.colour || hoist != role.hoist
    }

    private var permissionsChanged: Bool {
        guard let role else { return false }
        return permissions != PermissionOverrideValue(role.permissions)
    }

    var body: some View {
        Group {
            if let role {
                form(role)
            } else {
                ContentUnavailableView("Role Deleted", systemImage: "tag.slash", description: Text("This role no longer exists."))
            }
        }
        .navigationTitle(role?.name ?? "Role")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(appearanceChanged || permissionsChanged)
        .toolbar {
            if appearanceChanged || permissionsChanged {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            guard !hasLoaded, let role else { return }
            hasLoaded = true
            load(role)
        }
        .alert("Delete \(role?.name ?? "role")?", isPresented: $showDeleteConfirm) {
            Button("Delete Role", role: .destructive) {
                Task {
                    if await store.deleteRole(roleId: roleId, serverId: serverId) {
                        store.showSuccess("Role deleted.")
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone with this role will lose it. This can't be undone.")
        }
    }

    @ViewBuilder
    private func form(_ role: Role) -> some View {
        Form {
            if !canEdit {
                Section {
                    Label("This role is ranked at or above your highest role, so you can't change it.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Name") {
                TextField("Role name", text: $name)
                    .onChange(of: name) { _, value in
                        if value.count > 32 { name = String(value.prefix(32)) }
                    }
            }
            .disabled(!canEdit)

            Section("Colour") {
                RoleColourPicker(colour: $colour, previewName: name.isEmpty ? "Role" : name)
            }
            .disabled(!canEdit)

            Section {
                Toggle("Show Members Separately", isOn: $hoist)
            } footer: {
                Text("Members with this role get their own section in the member list.")
            }
            .disabled(!canEdit)

            if !canEditPermissions {
                Section {
                    Text(myPermissions.contains(.managePermissions)
                         ? "You can view this role's permissions but can't change them."
                         : "You need the Manage Permissions permission to change what this role can do.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            PermissionSections(context: .server, style: .overrides, value: $permissions, grantable: myPermissions, isEditable: canEditPermissions)

            Section {
                Button {
                    UIPasteboard.general.string = roleId
                    YukiHaptics.notification(.success)
                } label: {
                    Label("Copy Role ID", systemImage: "number")
                }
                if canEdit {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Role", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func load(_ role: Role) {
        name = role.name
        colour = role.colour
        hoist = role.hoist
        permissions = PermissionOverrideValue(role.permissions)
    }

    private func save() {
        guard let role else { return }
        isSaving = true
        Task {
            var success = true
            if appearanceChanged {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                success = await store.updateRole(
                    roleId: roleId,
                    serverId: serverId,
                    name: trimmed == role.name ? nil : trimmed,
                    colour: colour == role.colour ? nil : .some(colour),
                    hoist: hoist == role.hoist ? nil : hoist
                )
            }
            if success, permissionsChanged {
                success = await store.setRolePermissions(permissions, roleId: roleId, serverId: serverId)
            }
            isSaving = false
            if success, let updated = self.role {
                load(updated)
                store.showSuccess("Role saved.")
            }
        }
    }
}

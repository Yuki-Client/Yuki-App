import SwiftUI
import StoatCore
import StoatState

struct ServerDefaultPermissionsView: View {
    @Bindable var store: AppStore
    let serverId: String

    @Environment(\.dismiss) private var dismiss
    @State private var value = PermissionOverrideValue()
    @State private var isSaving = false

    private var server: Server? { store.store.servers[serverId] }
    private var myPermissions: Permission { server.map { store.store.permissions(in: $0) } ?? [] }
    private var canEdit: Bool { myPermissions.contains(.managePermissions) }
    private var hasChanges: Bool { value.allow != server?.defaultPermissions }

    var body: some View {
        Form {
            Section {
                EmptyView()
            } footer: {
                Text("These apply to every member, including people without any roles.")
            }
            PermissionSections(context: .server, style: .toggles, value: $value, grantable: myPermissions, isEditable: canEdit)
        }
        .navigationTitle("Everyone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            if await store.setDefaultPermissions(value.allow, serverId: serverId) {
                                store.showSuccess("Permissions saved.")
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
        }
        .onAppear {
            value = PermissionOverrideValue(allow: server?.defaultPermissions ?? 0)
        }
    }
}

import SwiftUI
import StoatCore
import StoatState

/// Only the group owner can change these.
struct GroupPermissionsView: View {
    @Bindable var store: AppStore
    let channelId: String

    @Environment(\.dismiss) private var dismiss
    @State private var value = PermissionOverrideValue()
    @State private var isSaving = false

    private var channel: Channel? { store.store.channels[channelId] }
    private var current: Int64 { channel?.permissions ?? Permission.directMessageDefault.rawValue }

    var body: some View {
        Form {
            Section {
                EmptyView()
            } footer: {
                Text("These apply to everyone in the group except you.")
            }
            PermissionSections(context: .group, style: .toggles, value: $value, grantable: .grantAllSafe)
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    isSaving = true
                    Task {
                        if await store.setGroupPermissions(value.allow, channelId: channelId) {
                            store.showSuccess("Permissions saved.")
                            dismiss()
                        }
                        isSaving = false
                    }
                }
                .disabled(value.allow == current || isSaving)
            }
        }
        .onAppear { value = PermissionOverrideValue(allow: current) }
    }
}

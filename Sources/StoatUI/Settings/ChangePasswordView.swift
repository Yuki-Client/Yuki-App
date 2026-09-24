import SwiftUI
import CoreImage.CIFilterBuiltins
import StoatState

struct ChangePasswordView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isSaving = false

    private var problem: String? {
        if new.isEmpty { return nil }
        if new.count < 8 { return "Use at least 8 characters." }
        if !confirm.isEmpty && confirm != new { return "The new passwords don't match." }
        return nil
    }

    var body: some View {
        Form {
            Section("Current Password") {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
            }
            Section {
                SecureField("New password", text: $new)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } header: {
                Text("New Password")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Change Password")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    isSaving = true
                    Task {
                        if await store.changePassword(current: current, new: new) {
                            dismiss()
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || current.isEmpty || new.count < 8 || new != confirm)
            }
        }
    }
}

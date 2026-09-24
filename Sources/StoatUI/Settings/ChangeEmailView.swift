import SwiftUI
import CoreImage.CIFilterBuiltins
import StoatState

struct ChangeEmailView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var sentTo: String?

    var body: some View {
        Form {
            Section {
                TextField("New email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Current password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("We'll send a confirmation link to the new address. Your email changes once you open it.")
            }
        }
        .navigationTitle("Change Email")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Sending…" : "Save") {
                    isSaving = true
                    let address = email.trimmingCharacters(in: .whitespaces)
                    Task {
                        if await store.changeEmail(address, currentPassword: password) {
                            sentTo = address
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || !email.contains("@") || password.isEmpty)
            }
        }
        .alert("Check your email", isPresented: Binding(get: { sentTo != nil }, set: { if !$0 { sentTo = nil; dismiss() } })) {
            Button("OK") {}
        } message: {
            Text("Open the link sent to \(sentTo ?? "your new address") to finish changing your email.")
        }
    }
}

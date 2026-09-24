import SwiftUI
import StoatState

struct AccountSettingsView: View {
    @Bindable var store: AppStore
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Current password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Change Username")
            } footer: {
                Text("Your tag is \(store.currentUser?.fullHandle ?? ""). Changing username may change your discriminator.")
            }

            Section {
                Button(isSaving ? "Saving…" : "Save") {
                    isSaving = true
                    Task {
                        if await store.changeUsername(username, password: password) {
                            password = ""
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || username.isEmpty || password.isEmpty || username == store.currentUser?.username)
            }
        }
        .navigationTitle("Username")
        .onAppear {
            username = store.currentUser?.username ?? ""
        }
    }
}

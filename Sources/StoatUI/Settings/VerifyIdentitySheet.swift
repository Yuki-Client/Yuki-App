import SwiftUI
import StoatCore
import CoreImage.CIFilterBuiltins
import StoatState

struct VerifyIdentitySheet: View {
    @Bindable var store: AppStore
    let title: String
    let onVerified: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var methods: [MFAMethod]?
    @State private var method: MFAMethod = .password
    @State private var value = ""
    @State private var isVerifying = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if methods == nil {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                } else {
                    Section {
                        field
                            .focused($isFocused)
                            .onSubmit(verify)
                    } header: {
                        Text(prompt)
                    }

                    if let methods, methods.count > 1 {
                        Section {
                            Button(method == .recovery ? "Use Authenticator Code" : "Use a Recovery Code") {
                                method = method == .recovery ? .totp : .recovery
                                value = ""
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isVerifying ? "Checking…" : "Continue", action: verify)
                        .disabled(isVerifying || value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                let status = await store.fetchMFAStatus()
                let available = status?.availableMethods ?? [.password]
                method = available.first ?? .password
                methods = available
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private var prompt: String {
        switch method {
        case .password: "Enter your password to continue"
        case .totp: "Enter the code from your authenticator app"
        case .recovery: "Enter one of your recovery codes"
        }
    }

    @ViewBuilder
    private var field: some View {
        switch method {
        case .password:
            SecureField("Password", text: $value)
                .textContentType(.password)
        case .totp:
            TextField("123456", text: $value)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit())
        case .recovery:
            TextField("xxxxx-xxxxx", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        }
    }

    private func verify() {
        let entered = value.trimmingCharacters(in: .whitespaces)
        guard !entered.isEmpty, !isVerifying else { return }
        let response: MFAResponse = switch method {
        case .password: .password(value)
        case .totp: .totp(entered.filter(\.isNumber))
        case .recovery: .recoveryCode(entered)
        }
        isVerifying = true
        Task {
            let ticket = await store.createMFATicket(response)
            isVerifying = false
            if let ticket {
                value = ""
                dismiss()
                onVerified(ticket)
            }
        }
    }
}

import SwiftUI
import StoatCore
import StoatState

/// Stoat emails a link; the token at the end of it sets the new password.
struct PasswordResetView: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var token = ""
    @State private var newPassword = ""
    @State private var signOutEverywhere = true
    @State private var stage: Stage = .request
    @State private var isWorking = false
    @State private var captchaRequest: CaptchaRequest?
    @FocusState private var focused: Field?

    private enum Stage { case request, confirm, done }
    private enum Field { case email, token, password }

    private struct CaptchaRequest: Identifiable {
        let id = UUID()
        let siteKey: String
        let onToken: (String?) -> Void
    }

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .request:
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .email)
                    } footer: {
                        Text("Stoat sends a reset link to this address if there's an account for it.")
                    }
                case .confirm:
                    Section {
                        TextField("Reset code", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .token)
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .password)
                        Toggle("Log out other devices", isOn: $signOutEverywhere)
                    } header: {
                        Text("Check Your Email")
                    } footer: {
                        Text("Open the link Stoat sent to \(email), or paste the code from the end of it here. Passwords must be at least 8 characters.")
                    }
                case .done:
                    Section {
                        Label("Password changed. Log in with your new password.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if isWorking {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Working…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch stage {
                    case .request:
                        Button("Send Email") { sendEmail() }
                            .disabled(!email.contains("@") || isWorking)
                    case .confirm:
                        Button("Change") { confirm() }
                            .disabled(token.isEmpty || newPassword.count < 8 || isWorking)
                    case .done:
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(item: $captchaRequest) { request in
                CaptchaSheet(siteKey: request.siteKey, onFinish: request.onToken)
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func sendEmail() {
        focused = nil
        guard let siteKey = store.captchaKey else {
            send(captcha: nil)
            return
        }
        captchaRequest = CaptchaRequest(siteKey: siteKey) { token in
            captchaRequest = nil
            guard let token else { return }
            send(captcha: token)
        }
    }

    private func send(captcha: String?) {
        Task {
            isWorking = true
            let sent = await store.sendPasswordReset(email: email, captcha: captcha)
            isWorking = false
            if sent {
                YukiHaptics.notification(.success)
                stage = .confirm
            }
        }
    }

    private func confirm() {
        focused = nil
        Task {
            isWorking = true
            let changed = await store.resetPassword(token: token, newPassword: newPassword, signOutEverywhere: signOutEverywhere)
            isWorking = false
            if changed {
                YukiHaptics.notification(.success)
                stage = .done
            }
        }
    }
}

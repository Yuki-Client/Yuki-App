import SwiftUI
import StoatCore
import StoatState

struct CreateAccountView: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var invite = ""
    @State private var code = ""
    @State private var stage: Stage = .details
    @State private var isWorking = false
    @State private var captchaRequest: CaptchaRequest?
    @FocusState private var focused: Field?

    private enum Stage { case details, verify, done }
    private enum Field { case email, password, invite, code }

    private struct CaptchaRequest: Identifiable {
        let id = UUID()
        let siteKey: String
        let onToken: (String?) -> Void
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8 && (!store.requiresInvite || !invite.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .details:
                    detailsFields
                case .verify:
                    verifyFields
                case .done:
                    Section {
                        Label("Account created. Log in with your email and password.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch stage {
                    case .details:
                        Button("Sign Up") { submitDetails() }
                            .disabled(!canSubmit || isWorking)
                    case .verify:
                        Button("Verify") { submitCode() }
                            .disabled(code.isEmpty || isWorking)
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

    private var detailsFields: some View {
        Group {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .focused($focused, equals: .password)
                if store.requiresInvite {
                    TextField("Invite code", text: $invite)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .invite)
                }
            } footer: {
                Text(store.requiresInvite
                     ? "This Stoat instance needs an invite code. Passwords must be at least 8 characters."
                     : "Passwords must be at least 8 characters. Stoat emails you a code to confirm the address.")
            }

            if isWorking {
                Section {
                    HStack {
                        ProgressView()
                        Text("Creating your account…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var verifyFields: some View {
        Group {
            Section {
                TextField("Verification code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .code)
            } header: {
                Text("Check Your Email")
            } footer: {
                Text("Stoat sent a link to \(email). Open it, or paste the code from the end of the link here.")
            }
            Section {
                Button("Send the Email Again") {
                    withCaptcha { token in
                        Task {
                            isWorking = true
                            if await store.resendVerification(email: email, captcha: token) {
                                store.showSuccess("Verification email sent.")
                            }
                            isWorking = false
                        }
                    }
                }
                .disabled(isWorking)
            }
        }
    }

    private func withCaptcha(_ action: @escaping (String?) -> Void) {
        guard let siteKey = store.captchaKey else {
            action(nil)
            return
        }
        captchaRequest = CaptchaRequest(siteKey: siteKey) { token in
            captchaRequest = nil
            guard let token else { return }
            action(token)
        }
    }

    private func submitDetails() {
        focused = nil
        withCaptcha { token in
            Task {
                isWorking = true
                let created = await store.createAccount(email: email, password: password, invite: invite, captcha: token)
                isWorking = false
                if created {
                    YukiHaptics.notification(.success)
                    stage = .verify
                }
            }
        }
    }

    private func submitCode() {
        focused = nil
        Task {
            isWorking = true
            let verified = await store.verifyAccount(code: code)
            isWorking = false
            if verified {
                YukiHaptics.notification(.success)
                stage = .done
            }
        }
    }
}

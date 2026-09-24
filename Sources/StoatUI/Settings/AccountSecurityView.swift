import SwiftUI
import CoreImage.CIFilterBuiltins
import StoatCore
import StoatState

struct AccountSecurityView: View {
    @Bindable var store: AppStore

    private enum Action: String, Identifiable {
        case viewRecoveryCodes, resetRecoveryCodes, setUpAuthenticator, removeAuthenticator, disableAccount, deleteAccount
        var id: String { rawValue }

        var title: String {
            switch self {
            case .viewRecoveryCodes, .resetRecoveryCodes: "Recovery Codes"
            case .setUpAuthenticator, .removeAuthenticator: "Authenticator"
            case .disableAccount: "Disable Account"
            case .deleteAccount: "Delete Account"
            }
        }
    }

    private struct Codes: Identifiable {
        let id = UUID()
        let values: [String]
    }

    @State private var account: AccountInfo?
    @State private var mfa: MultiFactorStatus?
    @State private var revealEmail = false
    @State private var verifying: Action?
    @State private var recoveryCodes: Codes?
    @State private var authenticatorSecret: IdentifiedString?
    @State private var confirmDisable = false
    @State private var confirmDelete = false
    @State private var confirmRemoveAuthenticator = false

    private var ownsServers: Bool {
        guard let me = store.store.currentUserId else { return false }
        return store.store.servers.values.contains { $0.owner == me }
    }

    var body: some View {
        List {
            Section("Login") {
                LabeledContent("Email") {
                    Button {
                        revealEmail.toggle()
                    } label: {
                        Text(verbatim: displayedEmail)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(revealEmail ? "Hides your email" : "Shows your email")
                }
                NavigationLink {
                    ChangeEmailView(store: store)
                } label: {
                    Label("Change Email", systemImage: "envelope")
                }
                NavigationLink {
                    ChangePasswordView(store: store)
                } label: {
                    Label("Change Password", systemImage: "key")
                }
                NavigationLink {
                    AccountSettingsView(store: store)
                } label: {
                    Label("Change Username", systemImage: "at")
                }
            }

            Section {
                if let mfa {
                    if mfa.totpEnabled {
                        Label("Authenticator app is on", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Button(role: .destructive) {
                            confirmRemoveAuthenticator = true
                        } label: {
                            Label("Remove Authenticator App", systemImage: "minus.circle")
                        }
                    } else {
                        Button {
                            verifying = .setUpAuthenticator
                        } label: {
                            Label("Set Up Authenticator App", systemImage: "lock.shield")
                        }
                    }
                } else {
                    ProgressView()
                }
            } header: {
                Text("Two-Factor Authentication")
            } footer: {
                Text("Ask for a one-time code from an app like Passwords, 1Password or Google Authenticator when signing in.")
            }

            if let mfa {
                Section {
                    if mfa.recoveryActive {
                        Button {
                            verifying = .viewRecoveryCodes
                        } label: {
                            Label("View Recovery Codes", systemImage: "list.number")
                        }
                        Button {
                            verifying = .resetRecoveryCodes
                        } label: {
                            Label("Reset Recovery Codes", systemImage: "arrow.clockwise")
                        }
                    } else {
                        Button {
                            verifying = .resetRecoveryCodes
                        } label: {
                            Label("Generate Recovery Codes", systemImage: "list.number")
                        }
                    }
                } header: {
                    Text("Recovery Codes")
                } footer: {
                    Text("Each code signs you in once if you lose access to your authenticator. Keep them somewhere safe.")
                }
            }

            Section {
                NavigationLink {
                    SessionsView(store: store)
                } label: {
                    Label("Sessions", systemImage: "iphone.and.arrow.forward")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDisable = true
                } label: {
                    Label("Disable Account", systemImage: "nosign")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .disabled(ownsServers)
            } header: {
                Text("Account")
            } footer: {
                Text(ownsServers
                     ? "Disabling keeps your data but locks the account until you contact support. To delete your account, first transfer or delete the servers you own."
                     : "Disabling keeps your data but locks the account until you contact support. Deleting asks you to confirm by email, then removes the account.")
            }
        }
        .navigationTitle("Account & Security")
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Remove the authenticator app?", isPresented: $confirmRemoveAuthenticator) {
            Button("Remove Authenticator", role: .destructive) { verifying = .removeAuthenticator }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing in will only need your password.")
        }
        .alert("Disable your account?", isPresented: $confirmDisable) {
            Button("Disable Account", role: .destructive) { verifying = .disableAccount }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be signed out and won't be able to sign back in without contacting Stoat support.")
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete Account", role: .destructive) { verifying = .deleteAccount }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stoat will email you a link to confirm. Once confirmed, your account is deleted.")
        }
        .sheet(item: $verifying) { action in
            VerifyIdentitySheet(store: store, title: action.title) { ticket in
                Task { await perform(action, ticket: ticket) }
            }
        }
        .sheet(item: $recoveryCodes) { codes in
            RecoveryCodesSheet(codes: codes.values)
        }
        .sheet(item: $authenticatorSecret) { secret in
            EnableAuthenticatorSheet(store: store, secret: secret.value, accountName: store.currentUser?.username ?? "Stoat") {
                Task { await reload() }
            }
        }
    }

    private var displayedEmail: String {
        guard let email = account?.email else { return "…" }
        if revealEmail { return email }
        guard let at = email.firstIndex(of: "@") else { return "••••" }
        return String(email.prefix(1)) + "•••••" + email[at...]
    }

    private func reload() async {
        async let accountInfo = store.fetchAccountInfo()
        async let status = store.fetchMFAStatus()
        account = await accountInfo
        mfa = await status
    }

    private func perform(_ action: Action, ticket: String) async {
        // Let the verification sheet finish closing before another sheet is presented.
        try? await Task.sleep(for: .milliseconds(400))
        switch action {
        case .viewRecoveryCodes, .resetRecoveryCodes:
            if let codes = await store.recoveryCodes(ticket: ticket, regenerate: action == .resetRecoveryCodes) {
                recoveryCodes = Codes(values: codes)
                await reload()
            }
        case .setUpAuthenticator:
            if let secret = await store.generateTOTPSecret(ticket: ticket) {
                authenticatorSecret = IdentifiedString(value: secret)
            }
        case .removeAuthenticator:
            if await store.disableTOTP(ticket: ticket) {
                await reload()
            }
        case .disableAccount:
            _ = await store.disableAccount(ticket: ticket)
        case .deleteAccount:
            _ = await store.deleteAccount(ticket: ticket)
        }
    }
}

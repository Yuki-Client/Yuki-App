import SwiftUI
import StoatCore
import StoatState

public struct LoginView: View {
    @Bindable var store: AppStore

    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = ""
    @State private var showServerConfig = false
    @State private var showAbout = false
    @State private var showCreateAccount = false
    @State private var showPasswordReset = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password, server }

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    logo

                    if let errorMessage = store.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(Color.red.opacity(0.1)))
                            .accessibilityAddTraits(.isStaticText)
                    }

                    switch store.phase {
                    case .awaitingMFA(_, let methods):
                        MFAChallengeView(store: store, methods: methods)
                    case .onboarding:
                        OnboardingView(store: store)
                    default:
                        credentialsForm
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(YukiTheme.systemBackground)
            .task {
                serverURL = await store.apiClient.baseURL.absoluteString
            }
        }
    }

    private var logo: some View {
        VStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                .frame(width: 104, height: 104)
                .background(Circle().fill(LinearGradient(colors: [YukiTheme.accent.opacity(0.3), YukiTheme.accentDeep.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .padding(.top, 40)
                .accessibilityHidden(true)

            Text("Yuki")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Text("A crisp, swift, unofficial client for Stoat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            field("EMAIL") {
                TextField(text: $email, prompt: Text(verbatim: "name@example.com")) { Text("Email") }
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            field("PASSWORD") {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }

            DisclosureGroup("Advanced: Custom Server", isExpanded: $showServerConfig) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(text: $serverURL, prompt: Text(verbatim: "https://stoat.chat/api")) { Text("Server") }
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .server)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusSmall).fill(YukiTheme.tertiaryBackground))
                    Text("The API address of a self-hosted Stoat instance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .font(.footnote)
            .tint(.secondary)

            Button(action: submit) {
                HStack {
                    if store.isConnecting {
                        ProgressView().tint(.white)
                    }
                    Text(store.isConnecting ? "Logging In…" : "Log In")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium)
                        .fill(canSubmit ? AnyShapeStyle(LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                )
                .foregroundColor(.white)
            }
            .disabled(!canSubmit || store.isConnecting)

            VStack(spacing: 6) {
                Button("Create an account") { showCreateAccount = true }
                Button("Forgot your password?") { showPasswordReset = true }
            }
            .font(.footnote)

            VStack(spacing: 4) {
                Text("Yuki isn't affiliated with or endorsed by Stoat.")
                Button("About Yuki & Legal") { showAbout = true }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .sheet(isPresented: $showCreateAccount) {
                CreateAccountView(store: store)
            }
            .sheet(isPresented: $showPasswordReset) {
                PasswordResetView(store: store)
            }
            .sheet(isPresented: $showAbout) {
                NavigationStack {
                    AboutYukiView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showAbout = false }
                            }
                        }
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content()
                .padding()
                .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(YukiTheme.secondaryBackground))
                .accessibilityLabel(label.capitalized)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !store.isConnecting else { return }
        focusedField = nil
        Task {
            store.clearError()
            guard await store.configureInstance(apiURL: serverURL.isEmpty ? StoatInstance.Endpoints.stoat.api : serverURL) else { return }
            _ = await store.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            if store.isLoggedIn {
                password = ""
            }
        }
    }
}

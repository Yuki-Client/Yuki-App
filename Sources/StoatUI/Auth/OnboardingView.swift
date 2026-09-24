import SwiftUI
import StoatState

struct OnboardingView: View {
    @Bindable var store: AppStore
    @State private var username = ""

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Choose a Username")
                    .font(.title3.bold())
                Text("This is how people find and mention you. You can change it later in settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(YukiTheme.secondaryBackground))

            Button {
                Task { _ = await store.completeOnboarding(username: username.trimmingCharacters(in: .whitespaces)) }
            } label: {
                HStack {
                    if store.isConnecting { ProgressView().tint(.white) }
                    Text("Continue").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(YukiTheme.accent))
                .foregroundColor(.white)
            }
            .disabled(username.trimmingCharacters(in: .whitespaces).count < 2 || store.isConnecting)

            Button("Log Out") {
                Task { await store.logout() }
            }
            .font(.footnote)
        }
    }
}

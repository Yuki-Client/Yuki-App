import SwiftUI
import StoatCore
import StoatState

struct MFAChallengeView: View {
    @Bindable var store: AppStore
    let methods: [MFAMethod]

    @State private var method: MFAMethod = .totp
    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Two-Factor Authentication")
                    .font(.title3.bold())
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if methods.count > 1 {
                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self) { item in
                        Text(title(for: item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            Group {
                if method == .password {
                    SecureField("Password", text: $code)
                        .textContentType(.password)
                } else {
                    TextField(method == .totp ? "123456" : "xxxx-xxxx", text: $code)
                        .textContentType(method == .totp ? .oneTimeCode : nil)
                        .keyboardType(method == .totp ? .numberPad : .asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .multilineTextAlignment(.center)
                }
            }
            .focused($isFocused)
            .padding()
            .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(YukiTheme.secondaryBackground))
            .onSubmit(submit)

            Button(action: submit) {
                HStack {
                    if store.isConnecting { ProgressView().tint(.white) }
                    Text("Verify").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: YukiTheme.cornerRadiusMedium).fill(YukiTheme.accent))
                .foregroundColor(.white)
            }
            .disabled(code.isEmpty || store.isConnecting)

            Button("Back to Login") {
                store.cancelMFA()
            }
            .font(.footnote)
        }
        .onAppear {
            method = methods.contains(.totp) ? .totp : methods.first ?? .totp
            isFocused = true
        }
        .onChange(of: method) { _, _ in code = "" }
    }

    private var prompt: String {
        switch method {
        case .totp: return "Enter the 6-digit code from your authenticator app."
        case .recovery: return "Enter one of your recovery codes."
        case .password: return "Confirm your password to continue."
        }
    }

    private func title(for method: MFAMethod) -> String {
        switch method {
        case .totp: return "Authenticator"
        case .recovery: return "Recovery Code"
        case .password: return "Password"
        }
    }

    private func submit() {
        let value = code.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        let response: MFAResponse
        switch method {
        case .totp: response = .totp(value)
        case .recovery: response = .recoveryCode(value)
        case .password: response = .password(value)
        }
        Task {
            if !(await store.submitMFA(response)) {
                code = ""
            }
        }
    }
}

import SwiftUI
import HCaptcha
import UIKit
import StoatCore

/// Hands back Stoat's captcha token, or nil if it's dismissed.
struct CaptchaSheet: View {
    let siteKey: String
    let onFinish: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = CaptchaHostView()
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                YukiTheme.systemBackground.ignoresSafeArea()
                if failed {
                    ContentUnavailableView {
                        Label("Check Didn't Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Yuki couldn't show Stoat's human check. Check your connection and try again.")
                    }
                } else {
                    host
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Confirm You're Human")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onFinish(nil)
                        dismiss()
                    }
                }
            }
            .task {
                await run()
            }
        }
    }

    private func run() async {
        guard let baseURL = URL(string: StoatInstance.appURL),
              let captcha = try? HCaptcha(apiKey: siteKey, baseURL: baseURL) else {
            failed = true
            return
        }
        captcha.configureWebView { webView in
            webView.frame = CGRect(x: 0, y: 0, width: 330, height: 505)
            webView.backgroundColor = .clear
            webView.isOpaque = false
        }
        captcha.validate(on: host.view) { result in
            let token = try? result.dematerialize()
            Task { @MainActor in
                onFinish(token)
                dismiss()
            }
        }
    }
}

private struct CaptchaHostView: UIViewRepresentable {
    let view = UIView()

    func makeUIView(context: Context) -> UIView {
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

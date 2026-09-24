import SwiftUI
import CoreImage.CIFilterBuiltins
import StoatState

struct EnableAuthenticatorSheet: View {
    @Bindable var store: AppStore
    let secret: String
    let accountName: String
    let onEnabled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var code = ""
    @State private var isEnabling = false

    private var setupURL: URL? {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        components.path = "/Stoat:\(accountName)"
        components.queryItems = [URLQueryItem(name: "secret", value: secret), URLQueryItem(name: "issuer", value: "Stoat")]
        return components.url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let setupURL, let qr = Self.qrCode(for: setupURL.absoluteString) {
                        HStack {
                            Spacer()
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                                .padding(10)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("QR code for your authenticator app")
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                    if let setupURL {
                        Button {
                            openURL(setupURL)
                        } label: {
                            Label("Add to Authenticator App", systemImage: "key.viewfinder")
                        }
                    }
                } footer: {
                    Text("Scan the code with another device, or add it to an app on this iPhone.")
                }

                Section {
                    HStack {
                        Text(verbatim: groupedSecret)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = secret
                            YukiHaptics.notification(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy setup key")
                    }
                } header: {
                    Text("Setup Key")
                }

                Section {
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit())
                } header: {
                    Text("Enter the 6-digit code it shows")
                }
            }
            .navigationTitle("Authenticator App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEnabling ? "Enabling…" : "Enable") {
                        isEnabling = true
                        Task {
                            if await store.enableTOTP(code: code) {
                                onEnabled()
                                dismiss()
                            }
                            isEnabling = false
                        }
                    }
                    .disabled(isEnabling || code.filter(\.isNumber).count != 6)
                }
            }
        }
        .interactiveDismissDisabled(isEnabling)
    }

    private var groupedSecret: String {
        stride(from: 0, to: secret.count, by: 4).map { index in
            let start = secret.index(secret.startIndex, offsetBy: index)
            let end = secret.index(start, offsetBy: 4, limitedBy: secret.endIndex) ?? secret.endIndex
            return String(secret[start..<end])
        }
        .joined(separator: " ")
    }

    private static func qrCode(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

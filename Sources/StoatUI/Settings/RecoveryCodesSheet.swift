import SwiftUI
import CoreImage.CIFilterBuiltins

struct RecoveryCodesSheet: View {
    let codes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(codes, id: \.self) { code in
                            Text(verbatim: code)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Save these somewhere safe, like a password manager. Each code works once.")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = codes.joined(separator: "\n")
                        YukiHaptics.notification(.success)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    ShareLink(item: codes.joined(separator: "\n")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Recovery Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

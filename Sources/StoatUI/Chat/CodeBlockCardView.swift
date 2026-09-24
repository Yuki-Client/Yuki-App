import SwiftUI
import UIKit

public struct CodeBlockCardView: View {
    public let language: String
    public let code: String
    @State private var copied = false

    public init(language: String, code: String) {
        self.language = language
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundColor(YukiTheme.accent)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    YukiHaptics.notification(.success)
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

import SwiftUI

struct InviteShareSheet: View {
    let link: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite People")
                .font(.headline)
                .padding(.top, 20)
            Text(link)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(YukiTheme.cardSurface))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                    YukiHaptics.notification(.success)
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if let url = URL(string: link) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

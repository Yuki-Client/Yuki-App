import SwiftUI
import StoatState

struct TypingIndicatorBar: View {
    let store: AppStore
    let channelId: String
    let serverId: String?

    var body: some View {
        if let text {
            HStack(spacing: 8) {
                TypingDotsView()
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String? {
        guard let ids = store.store.typingUsers[channelId], !ids.isEmpty else { return nil }
        // People not loaded yet (common in big servers) are fetched as they start typing.
        let names = ids.sorted().compactMap { store.store.knownName(userId: $0, serverId: serverId) }
        switch names.count {
        case 0: return "Someone is typing…"
        case 1: return "\(names[0]) is typing…"
        case 2: return "\(names[0]) and \(names[1]) are typing…"
        case 3: return "\(names[0]), \(names[1]) and \(names[2]) are typing…"
        default: return "Several people are typing…"
        }
    }
}

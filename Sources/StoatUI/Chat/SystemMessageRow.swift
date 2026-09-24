import SwiftUI
import StoatCore
import StoatState

struct SystemMessageRow: View {
    let message: Message
    let system: SystemMessage
    let serverId: String?

    @Environment(AppStore.self) private var appStore
    @Environment(\.yukiLinkHandler) private var linkHandler

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 38)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tint(.primary)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "yuki", url.host == "user" {
                        linkHandler.openUser(url.lastPathComponent)
                    }
                    return .handled
                })
            Text(MessageRowView.timestampText(message.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func name(_ id: String) -> AttributedString {
        var run = AttributedString(appStore.store.displayName(userId: id, serverId: serverId))
        run.link = URL(string: "yuki://user/\(id)")
        run.inlinePresentationIntent = .stronglyEmphasized
        return run
    }

    private var description: AttributedString {
        func text(_ string: String) -> AttributedString { AttributedString(string) }
        switch system {
        case .text(let content): return text(content)
        case .userAdded(let id, let by): return name(by) + text(" added ") + name(id) + text(" to the group")
        case .userRemove(let id, let by): return name(by) + text(" removed ") + name(id) + text(" from the group")
        case .userJoined(let id): return name(id) + text(" joined")
        case .userLeft(let id): return name(id) + text(" left")
        case .userKicked(let id): return name(id) + text(" was kicked")
        case .userBanned(let id): return name(id) + text(" was banned")
        case .channelRenamed(let newName, let by): return name(by) + text(" renamed the channel to \(newName)")
        case .channelDescriptionChanged(let by): return name(by) + text(" changed the channel description")
        case .channelIconChanged(let by): return name(by) + text(" changed the channel icon")
        case .channelOwnershipChanged(let from, let to): return name(from) + text(" transferred ownership to ") + name(to)
        case .messagePinned(_, let by): return name(by) + text(" pinned a message")
        case .messageUnpinned(_, let by): return name(by) + text(" unpinned a message")
        case .callStarted(let by, let finishedAt):
            guard let finishedAt, let end = StoatDate.parse(finishedAt) else { return name(by) + text(" started a call") }
            return name(by) + text(" started a call that lasted \(Self.duration(from: message.timestamp, to: end))")
        case .unknown: return text("System message")
        }
    }

    private static func duration(from start: Date, to end: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: max(1, end.timeIntervalSince(start))) ?? "a moment"
    }

    private var icon: String {
        switch system {
        case .userJoined, .userAdded: return "arrow.right.circle.fill"
        case .userLeft, .userRemove: return "arrow.left.circle.fill"
        case .userKicked: return "figure.walk.departure"
        case .userBanned: return "hammer.fill"
        case .channelRenamed, .channelDescriptionChanged, .channelIconChanged: return "pencil.circle.fill"
        case .channelOwnershipChanged: return "crown.fill"
        case .messagePinned, .messageUnpinned: return "pin.fill"
        case .callStarted: return "phone.fill"
        case .text, .unknown: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch system {
        case .userJoined, .userAdded: return .green
        case .userLeft, .userRemove, .userKicked, .userBanned: return .red
        case .messagePinned, .messageUnpinned: return .yellow
        default: return .secondary
        }
    }
}

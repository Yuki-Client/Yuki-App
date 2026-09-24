import SwiftUI
import StoatCore

struct ChannelIntroView: View {
    let channel: Channel?
    let title: String
    let canReadHistory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(YukiTheme.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(YukiTheme.cardSurface))
            Text(heading)
                .font(.title2.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !canReadHistory {
                Text("You don't have permission to read earlier messages here.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: String {
        switch channel?.channelType {
        case .directMessage: title
        case .textChannel: "Welcome to #\(title)"
        default: "Welcome to \(title)"
        }
    }

    private var subtitle: String {
        switch channel?.channelType {
        case .directMessage: "This is the beginning of your conversation with \(title)."
        case .group: "This is the beginning of the group."
        case .savedMessages: "Keep notes, links and files here. Only you can see them."
        default: channel?.description ?? "This is the start of the channel."
        }
    }

    private var icon: String {
        switch channel?.channelType {
        case .directMessage: "at"
        case .group: "person.3.fill"
        case .savedMessages: "note.text"
        case .voiceChannel: "speaker.wave.2.fill"
        default: "number"
        }
    }
}

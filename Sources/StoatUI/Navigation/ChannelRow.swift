import SwiftUI
import StoatCore
import StoatState
import StoatVoice

struct ChannelRowLabel: View {
    let channel: Channel
    let isSelected: Bool
    let isUnread: Bool
    let isMuted: Bool
    let hasDraft: Bool
    let mentions: Int
    var voiceCount = 0

    var body: some View {
        HStack(spacing: 8) {
            if let icon = channel.icon {
                AvatarView(avatar: icon, fallbackText: channel.name ?? "#", size: 20, isRounded: false)
            } else {
                Image(systemName: channel.channelType == .voiceChannel ? "speaker.wave.2.fill" : channel.voice != nil ? "number.square" : "number")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
            }
            Text(channel.name ?? "channel")
                .font(.body.weight(isUnread || isSelected ? .semibold : .regular))
                .lineLimit(1)
            if channel.nsfw {
                Text("18+")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 4)
            if let limit = channel.voice?.maxUsers {
                Text("\(voiceCount)/\(limit)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .accessibilityLabel("\(voiceCount) of \(limit) in the call")
            }
            if hasDraft {
                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YukiTheme.accent)
                    .accessibilityLabel("Has draft")
            }
            if isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.caption2)
            }
            if mentions > 0 {
                MentionBadge(count: mentions)
            }
        }
        .foregroundStyle(isSelected || isUnread ? Color.primary : Color.secondary)
        .opacity(isMuted && !isSelected ? 0.6 : 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? YukiTheme.accent.opacity(0.18) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isUnread && !isSelected {
                Capsule().fill(Color.primary).frame(width: 4, height: 8).offset(x: -8)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ChannelVoiceParticipants: View {
    let store: AppStore
    let channel: Channel
    @Environment(VoiceCallController.self) private var voice

    var body: some View {
        ForEach(Array((store.store.voiceStates[channel.id] ?? [:]).keys), id: \.self) { userId in
            let name = store.store.displayName(userId: userId, serverId: channel.server)
            HStack(spacing: 6) {
                AvatarView(avatar: store.store.avatar(userId: userId, serverId: channel.server), fallbackText: name, size: 18, userId: userId)
                    .padding(1.5)
                    .overlay {
                        Circle()
                            .stroke(Color.green, lineWidth: 1.5)
                            .opacity(voice.channelId == channel.id && voice.speakingUserIds.contains(userId) ? 1 : 0)
                    }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name) in voice")
        }
    }
}

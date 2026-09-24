import SwiftUI
import StoatCore
import StoatState
import StoatVoice

extension Channel {
    /// Whether Stoat allows calls here: text channels with voice turned on, DMs and groups.
    var supportsCalls: Bool {
        switch channelType {
        case .directMessage, .group: return true
        case .textChannel: return voice != nil
        default: return false
        }
    }
}

extension AppStore {
    func callParticipants(in channelId: String) -> [UserVoiceState] {
        (store.voiceStates[channelId] ?? [:]).values.sorted {
            ($0.joinedAt ?? "", $0.id) < ($1.joinedAt ?? "", $1.id)
        }
    }

}

struct VoiceCallControls: View {
    @Environment(VoiceCallController.self) private var voice

    var body: some View {
        HStack(spacing: 8) {
            control(
                systemImage: voice.isMicrophoneOn ? "mic.fill" : "mic.slash.fill",
                label: voice.isMicrophoneOn ? "Mute" : "Unmute",
                isOff: !voice.isMicrophoneOn
            ) {
                YukiHaptics.selection()
                voice.toggleMute()
            }
            .disabled(!voice.canSpeak && !voice.isDeafened)

            control(
                systemImage: voice.isDeafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: voice.isDeafened ? "Undeafen" : "Deafen",
                isOff: voice.isDeafened
            ) {
                YukiHaptics.selection()
                voice.toggleDeafen()
            }

            Button {
                YukiHaptics.impact(.medium)
                voice.leave()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave Call")
        }
    }

    private func control(systemImage: String, label: String, isOff: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOff ? Color.red : Color.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(isOff ? Color.red.opacity(0.18) : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct VoiceParticipantAvatar: View {
    let state: UserVoiceState
    let serverId: String?
    var size: CGFloat = 34
    let isSpeaking: Bool

    @Environment(AppStore.self) private var appStore

    var body: some View {
        let name = appStore.store.displayName(userId: state.id, serverId: serverId)
        AvatarView(avatar: appStore.store.avatar(userId: state.id, serverId: serverId), fallbackText: name, size: size, userId: state.id)
            .padding(2)
            .overlay {
                Circle()
                    .stroke(Color.green, lineWidth: 2.5)
                    .opacity(isSpeaking ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isSpeaking)
            }
            .overlay(alignment: .bottomTrailing) {
                if !state.isReceiving || !state.isPublishing {
                    Image(systemName: state.isReceiving ? "mic.slash.fill" : "speaker.slash.fill")
                        .font(.system(size: size * 0.26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(Circle().fill(Color.red))
                        .overlay(Circle().stroke(YukiTheme.cardSurface, lineWidth: 1.5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue([
                isSpeaking ? "Speaking" : nil,
                !state.isReceiving ? "Deafened" : !state.isPublishing ? "Muted" : nil
            ].compactMap { $0 }.joined(separator: ", "))
    }
}

struct VoiceCallPanel: View {
    let channel: Channel
    @Bindable var store: AppStore

    @Environment(VoiceCallController.self) private var voice
    @State private var showCall = false

    private var isHere: Bool { voice.channelId == channel.id }

    var body: some View {
        let participants = store.callParticipants(in: channel.id)
        let limit = channel.voice?.maxUsers
        // Stoat lets people who can manage the channel into a full call anyway.
        let isFull = limit.map { participants.count >= $0 } == true && !store.store.hasPermission(.manageChannel, in: channel)
        HStack(spacing: 10) {
            Button {
                showCall = true
            } label: {
                summary(participants)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows everyone in the call")
            Spacer(minLength: 4)
            if isHere {
                if voice.status == .connecting {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                VoiceCallControls()
            } else {
                Button {
                    YukiHaptics.impact(.medium)
                    voice.join(channel.id, store: store)
                } label: {
                    Label(isFull ? "Full" : "Join", systemImage: isFull ? "person.fill.xmark" : "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isFull)
                .accessibilityLabel(isFull ? "Call is full" : "Join Call")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(YukiTheme.cardSurface))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .sheet(isPresented: $showCall) {
            VoiceCallSheet(channelId: channel.id, store: store)
        }
    }

    private func summary(_ participants: [UserVoiceState]) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(participants.prefix(5)) { participant in
                    VoiceParticipantAvatar(
                        state: participant,
                        serverId: channel.server,
                        size: 30,
                        isSpeaking: isHere && voice.speakingUserIds.contains(participant.id)
                    )
                    .background(Circle().fill(YukiTheme.cardSurface))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title(count: participants.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHere && voice.status == .connected ? Color.green : Color.primary)
                    .lineLimit(1)
                if participants.count > 5 {
                    Text("+\(participants.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func title(count: Int) -> String {
        if isHere {
            switch voice.status {
            case .connecting: return "Joining…"
            case .reconnecting: return "Reconnecting…"
            case .connected, .idle: return "In the Call"
            }
        }
        if let limit = channel.voice?.maxUsers {
            return "\(count) of \(limit) in the call"
        }
        return count == 1 ? "1 person in the call" : "\(count) people in the call"
    }
}

struct VoiceCallBar: View {
    @Bindable var store: AppStore

    @Environment(VoiceCallController.self) private var voice
    @State private var showCall = false

    var body: some View {
        if let channelId = voice.channelId {
            HStack(spacing: 10) {
                Button {
                    showCall = true
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            if voice.status == .connected {
                                Image(systemName: "waveform")
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(statusText)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(voice.status == .connected ? Color.green : Color.orange)
                        Text(store.callLocation(for: channelId))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the call")

                VoiceCallControls()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(YukiTheme.cardSurface)
            .sheet(isPresented: $showCall) {
                VoiceCallSheet(channelId: channelId, store: store)
            }
        }
    }

    private var statusText: String {
        switch voice.status {
        case .connected, .idle: "Voice Connected"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        }
    }
}

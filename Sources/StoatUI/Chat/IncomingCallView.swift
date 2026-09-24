import SwiftUI
import AVFoundation
import StoatCore
import StoatState
import StoatVoice

struct IncomingCallBanner: View {
    let call: AppStore.IncomingCall
    @Bindable var store: AppStore

    @Environment(VoiceCallController.self) private var voice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var channel: Channel? { store.store.channels[call.channelId] }

    var body: some View {
        let callerName = store.store.displayName(userId: call.callerId, serverId: nil)
        HStack(spacing: 12) {
            AvatarView(avatar: store.store.avatar(userId: call.callerId, serverId: nil), fallbackText: callerName, size: 48, userId: call.callerId)
                .padding(3)
                .overlay {
                    Circle()
                        .stroke(Color.green, lineWidth: 2)
                        .scaleEffect(pulse ? 1.25 : 1)
                        .opacity(pulse ? 0 : 0.9)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(callerName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                YukiHaptics.impact(.light)
                store.dismissIncomingCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decline")
            Button {
                YukiHaptics.impact(.medium)
                let channelId = call.channelId
                store.dismissIncomingCall()
                store.openChannel(channelId)
                voice.join(channelId, store: store)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.green))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join Call")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(YukiTheme.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.green.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(callerName) is calling")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
        .task(id: call.channelId) {
            await ring()
        }
    }

    private var subtitle: String {
        guard let channel, channel.channelType == .group else { return "Incoming call" }
        return "Calling \(channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId))"
    }

    /// Stays quiet when the user is already in a call, so the ring doesn't play into it.
    private func ring() async {
        let player = voice.isInCall ? nil : RingtonePlayer()
        while !Task.isCancelled {
            if voice.isInCall {
                YukiHaptics.notification(.warning)
            } else {
                player?.play()
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            try? await Task.sleep(for: .seconds(2.5))
        }
        player?.stop()
    }
}

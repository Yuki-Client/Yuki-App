import SwiftUI
import AVKit
import StoatCore
import StoatState
import StoatVoice

struct VoiceCallSheet: View {
    let channelId: String
    @Bindable var store: AppStore

    @Environment(VoiceCallController.self) private var voice
    @Environment(\.dismiss) private var dismiss
    @State private var volumeUserId: String?
    @State private var fullScreenFeedId: String?

    private var channel: Channel? { store.store.channels[channelId] }
    private var isHere: Bool { voice.channelId == channelId }

    var body: some View {
        let participants = store.callParticipants(in: channelId)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if isHere {
                        ForEach(voice.videoFeeds) { feed in
                            Button {
                                fullScreenFeedId = feed.id
                            } label: {
                                VideoFeedCard(feed: feed, name: feed.isLocal ? "You" : name(of: feed.userId))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if participants.isEmpty {
                        ContentUnavailableView("No One's Here", systemImage: "person.wave.2", description: Text("Join to start the call."))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                            ForEach(participants) { participant in
                                Button {
                                    volumeUserId = participant.id
                                } label: {
                                    participantTile(participant)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(YukiTheme.systemBackground)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if isHere {
                        HStack(spacing: 8) {
                            AudioRoutePicker()
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.primary.opacity(0.1)))
                                .accessibilityLabel("Audio Output")
                            if voice.canShareVideo {
                                callButton(
                                    systemImage: voice.isCameraOn ? "video.fill" : "video.slash.fill",
                                    label: voice.isCameraOn ? "Turn Camera Off" : "Turn Camera On",
                                    isOn: voice.isCameraOn
                                ) {
                                    YukiHaptics.selection()
                                    voice.toggleCamera()
                                }
                                if voice.isCameraOn {
                                    callButton(systemImage: "arrow.triangle.2.circlepath.camera", label: "Switch Camera", isOn: false) {
                                        voice.flipCamera()
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        VoiceCallControls()
                    } else {
                        Button {
                            YukiHaptics.impact(.medium)
                            voice.join(channelId, store: store)
                        } label: {
                            Label(participants.isEmpty ? "Start Call" : "Join Call", systemImage: "phone.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(YukiTheme.cardSurface)
            }
            .navigationTitle(store.callLocation(for: channelId))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.selectedChannelId != channelId || !store.isLoggedIn {
                        Button("Open Chat") {
                            dismiss()
                            store.openChannel(channelId)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: Binding(get: { volumeUserId.map(IdentifiedString.init) }, set: { volumeUserId = $0?.value })) { item in
                ParticipantVolumeSheet(userId: item.value, serverId: channel?.server, isInCall: isHere, store: store)
                    .presentationDetents([.height(300)])
            }
            .fullScreenCover(item: Binding(get: { fullScreenFeedId.map(IdentifiedString.init) }, set: { fullScreenFeedId = $0?.value })) { item in
                FullScreenVideoView(feedId: item.value, nameOf: name(of:))
            }
        }
    }

    private func callButton(systemImage: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(isOn ? Color.white : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func participantTile(_ participant: UserVoiceState) -> some View {
        let volume = voice.volume(for: participant.id)
        return VStack(spacing: 6) {
            VoiceParticipantAvatar(
                state: participant,
                serverId: channel?.server,
                size: 64,
                isSpeaking: isHere && voice.speakingUserIds.contains(participant.id)
            )
            Text(name(of: participant.id))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if volume != 1 && participant.id != store.store.currentUserId {
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if participant.screensharing || participant.camera {
                Image(systemName: participant.screensharing ? "rectangle.on.rectangle" : "video.fill")
                    .font(.caption2)
                    .foregroundStyle(YukiTheme.accent)
                    .accessibilityLabel(participant.screensharing ? "Sharing screen" : "Camera on")
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func name(of userId: String) -> String {
        store.store.displayName(userId: userId, serverId: channel?.server)
    }
}

private struct VideoFeedCard: View {
    let feed: VoiceCallController.VideoFeed
    let name: String

    var body: some View {
        VoiceVideoView(feed: feed)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label(name, systemImage: feed.isScreenShare ? "rectangle.on.rectangle" : "video.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(feed.isScreenShare ? "\(name)'s screen" : "\(name)'s camera")
            .accessibilityHint("Shows it full screen")
    }
}

private struct FullScreenVideoView: View {
    let feedId: String
    let nameOf: (String) -> String

    @Environment(VoiceCallController.self) private var voice
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let feed = voice.videoFeeds.first(where: { $0.id == feedId }) {
                VoiceVideoView(feed: feed)
                    .scaleEffect(scale * pinch)
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2.5 }
                    }
                    .ignoresSafeArea()
                    .accessibilityLabel(feed.isScreenShare ? "\(nameOf(feed.userId))'s screen" : "\(nameOf(feed.userId))'s camera")
            } else {
                Color.clear.onAppear { dismiss() }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
        .onChange(of: voice.videoFeeds.map(\.id)) { _, ids in
            if !ids.contains(feedId) { dismiss() }
        }
    }
}

private struct ParticipantVolumeSheet: View {
    let userId: String
    let serverId: String?
    let isInCall: Bool
    @Bindable var store: AppStore

    @Environment(VoiceCallController.self) private var voice
    @State private var showProfile = false

    private var isSelf: Bool { userId == store.store.currentUserId }

    var body: some View {
        let name = store.store.displayName(userId: userId, serverId: serverId)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(avatar: store.store.avatar(userId: userId, serverId: serverId), fallbackText: name, size: 48, userId: userId)
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Profile") { showProfile = true }
                    .buttonStyle(.bordered)
            }

            if isSelf {
                Text("This is you.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isInCall {
                let volume = voice.volume(for: userId)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int((volume * 100).rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { voice.volume(for: userId) }, set: { voice.setVolume($0, for: userId) }), in: 0...2)
                            .accessibilityLabel("Volume for \(name)")
                            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text(volume == 0 ? "Muted for you only." : "Only changes what you hear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(volume == 0 ? "Unmute for Me" : "Mute for Me") {
                        voice.setVolume(volume == 0 ? 1 : 0, for: userId)
                    }
                    Spacer()
                    if volume != 1 {
                        Button("Reset") { voice.setVolume(1, for: userId) }
                    }
                }
                .font(.subheadline)
            } else {
                Text("Join the call to change how loud \(name) is for you.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(YukiTheme.groupedBackground)
        .sheet(isPresented: $showProfile) {
            UserProfileSheet(store: store, userId: userId, serverId: serverId)
        }
    }
}

private struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .label
        view.activeTintColor = UIColor(YukiTheme.accent)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

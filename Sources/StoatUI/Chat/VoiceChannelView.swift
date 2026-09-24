import SwiftUI
import StoatCore
import StoatState

/// Stoat only runs calls in text channels with voice, DMs and groups (see `VoiceCallPanel`),
/// so channels of the old voice type can't be joined.
public struct VoiceChannelView: View {
    @Bindable var store: AppStore
    public let channelId: String

    @State private var profileUserId: String?

    public init(store: AppStore, channelId: String) {
        self.store = store
        self.channelId = channelId
    }

    private var channel: Channel? { store.store.channels[channelId] }

    private var participants: [UserVoiceState] {
        (store.store.voiceStates[channelId] ?? [:]).values.sorted {
            store.store.displayName(userId: $0.id, serverId: channel?.server)
                .localizedCaseInsensitiveCompare(store.store.displayName(userId: $1.id, serverId: channel?.server)) == .orderedAscending
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(YukiTheme.accent)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(YukiTheme.cardSurface))
                    Text(channel?.name ?? "Voice Channel")
                        .font(.title2.bold())
                    if let description = channel?.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                Label("This is an older kind of voice channel that Stoat no longer lets anyone join. Calls now happen in text channels with voice, and in DMs and groups.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(YukiTheme.cardSurface))
                    .padding(.horizontal, 16)

                if participants.isEmpty {
                    ContentUnavailableView("No one's here", systemImage: "person.wave.2", description: Text("Nobody is in this voice channel right now."))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IN THE CALL · \(participants.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(participants) { participant in
                                Button {
                                    profileUserId = participant.id
                                } label: {
                                    VoiceParticipantTile(state: participant, serverId: channel?.server)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(YukiTheme.systemBackground)
        .navigationTitle(channel?.name ?? "Voice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
            UserProfileSheet(store: store, userId: item.value, serverId: channel?.server)
        }
        .task(id: channelId) {
            store.markChannelAsRead(channelId)
        }
    }
}

struct VoiceParticipantTile: View {
    let state: UserVoiceState
    let serverId: String?
    @Environment(AppStore.self) private var appStore

    var body: some View {
        let name = appStore.store.displayName(userId: state.id, serverId: serverId)
        VStack(spacing: 8) {
            AvatarView(avatar: appStore.store.avatar(userId: state.id, serverId: serverId), fallbackText: name, size: 56, userId: state.id)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                Image(systemName: state.isPublishing ? "mic.fill" : "mic.slash.fill")
                    .foregroundStyle(state.isPublishing ? .green : .secondary)
                    .accessibilityLabel(state.isPublishing ? "Microphone on" : "Muted")
                if !state.isReceiving {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Deafened")
                }
                if state.camera {
                    Image(systemName: "video.fill")
                        .foregroundStyle(YukiTheme.accent)
                        .accessibilityLabel("Camera on")
                }
                if state.screensharing {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(YukiTheme.accent)
                        .accessibilityLabel("Sharing screen")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(YukiTheme.cardSurface))
        .accessibilityElement(children: .combine)
    }
}

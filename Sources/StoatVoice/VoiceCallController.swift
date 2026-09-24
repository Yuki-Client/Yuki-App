import Foundation
import AVFoundation
import CallKit
import LiveKit
import StoatCore
import StoatState

/// Stoat hands out a LiveKit token from `join_call`. Who's in a call comes from the gateway's
/// voice states; LiveKit carries the audio and video and says who's speaking.
@MainActor
@Observable
public final class VoiceCallController {
    public struct VideoFeed: Identifiable {
        public let id: String
        public let userId: String
        public let isScreenShare: Bool
        /// The user's own camera, shown mirrored.
        public let isLocal: Bool
        public let track: VideoTrack
    }

    public enum Status: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
    }

    /// Whether any call is connecting or connected, for code that plays other audio.
    public private(set) static var isCallActive = false

    public private(set) var status: Status = .idle
    public private(set) var channelId: String?
    /// IDs of users speaking right now, including the current user.
    public private(set) var speakingUserIds: Set<String> = []
    /// Muted by choice. Stays set between calls, as in Stoat for Web.
    public private(set) var isMuted: Bool
    /// Deafened by choice: no call audio plays and the microphone is off. Stays set between calls.
    public private(set) var isDeafened: Bool
    public private(set) var canSpeak = true
    public private(set) var canShareVideo = false
    public private(set) var isCameraOn = false
    /// A channel the user tried to join while already in a call on another device, so they can
    /// be asked whether to move the call here.
    public var pendingMoveChannelId: String?
    /// Cameras and screen shares from other people (screen shares first), then the user's own camera.
    public private(set) var videoFeeds: [VideoFeed] = []
    /// Volume for each person (by user ID), 0 to 2, where 1 is normal. Kept between calls.
    public private(set) var userVolumes: [String: Double]
    /// An incoming call to ring with Yuki's own card, because the system call screen isn't available.
    public private(set) var bannerCallChannelId: String?

    @ObservationIgnored private var room: Room?
    @ObservationIgnored private var events: RoomEvents?
    @ObservationIgnored private var joinTask: Task<Void, Never>?
    @ObservationIgnored private let callKit = CallKitBridge()
    @ObservationIgnored private let sounds = CallSounds()
    @ObservationIgnored private var callUUID: UUID?
    @ObservationIgnored private var reportedMuted: Bool?
    @ObservationIgnored private var audioWatchdog: Task<Void, Never>?
    @ObservationIgnored private var ringing: (uuid: UUID, channelId: String)?
    @ObservationIgnored private weak var store: AppStore?

    private static let mutedKey = "yuki.voice.muted"
    private static let deafenedKey = "yuki.voice.deafened"
    private static let volumesKey = "yuki.voice.volumes"

    public init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)
        isDeafened = UserDefaults.standard.bool(forKey: Self.deafenedKey)
        userVolumes = UserDefaults.standard.dictionary(forKey: Self.volumesKey) as? [String: Double] ?? [:]
        callKit.onAction = { [weak self] action in
            self?.handleSystemAction(action)
        }
    }

    public var isInCall: Bool { channelId != nil }

    public var usesSystemCallScreen: Bool { callKit.isAvailable }

    public var isMicrophoneOn: Bool {
        canSpeak && !isMuted && !isDeafened
    }

    // MARK: Joining and leaving

    /// Joins the call in a channel, leaving any other call first. With `moveFromOtherDevice`,
    /// a call the user is in elsewhere is ended so this one can start.
    public func join(_ channelId: String, store: AppStore, moveFromOtherDevice: Bool = false) {
        guard self.channelId != channelId || status == .idle else { return }
        startJoining(channelId, store: store, moveFromOtherDevice: moveFromOtherDevice, answeredCallUUID: nil)
    }

    public func leave() {
        endCall(systemReason: nil)
    }

    private func startJoining(_ channelId: String, store: AppStore, moveFromOtherDevice: Bool, answeredCallUUID: UUID?) {
        self.store = store
        joinTask?.cancel()
        joinTask = Task { [weak self] in
            await self?.connect(channelId, store: store, moveFromOtherDevice: moveFromOtherDevice, answeredCallUUID: answeredCallUUID)
        }
    }

    private func connect(_ channelId: String, store: AppStore, moveFromOtherDevice: Bool, answeredCallUUID: UUID?) async {
        guard let channel = store.store.channels[channelId] else { return }
        if room != nil || (callUUID != nil && callUUID != answeredCallUUID) {
            let task = joinTask
            joinTask = nil
            endCall(systemReason: nil)
            joinTask = task
        }
        guard channel.isPrivate || store.store.hasPermission(.connect, in: channel) else {
            if let answeredCallUUID { callKit.reportEnded(answeredCallUUID, reason: .failed) }
            store.showError("You don't have permission to join this call.")
            return
        }

        self.channelId = channelId
        status = .connecting
        Self.isCallActive = true
        let allowedToSpeak = channel.isPrivate || store.store.hasPermission(.speak, in: channel)
        canShareVideo = channel.isPrivate || store.store.hasPermission(.video, in: channel)
        let microphoneAllowed = allowedToSpeak ? await AVAudioApplication.requestRecordPermission() : false
        canSpeak = allowedToSpeak && microphoneAllowed
        if allowedToSpeak && !microphoneAllowed {
            store.showError("Microphone access is off, so you'll join muted. You can turn it on in Settings.")
        }

        await setUpCallAudio(title: store.callLocation(for: channelId), answeredCallUUID: answeredCallUUID)
        guard self.channelId == channelId, !Task.isCancelled else { return }

        do {
            let node = await Self.fastestNode(store.instanceConfiguration?.features.livekit?.nodes ?? [])
            // Starting a call in a conversation lets the other people in it know.
            let recipients = channel.isPrivate
                ? channel.recipients?.filter { $0 != store.store.currentUserId }
                : nil
            let credentials = try await store.apiClient.joinCall(
                channelId: channelId,
                node: node,
                forceDisconnect: moveFromOtherDevice,
                recipients: recipients
            )
            try Task.checkCancellation()

            let events = RoomEvents { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            let room = Room(
                delegate: events,
                connectOptions: ConnectOptions(autoSubscribe: true),
                roomOptions: RoomOptions(
                    defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, autoGainControl: true, noiseSuppression: true, highpassFilter: true),
                    adaptiveStream: true,
                    dynacast: true
                )
            )
            self.room = room
            self.events = events
            try await room.connect(url: credentials.url, token: credentials.token)
            guard self.room === room else { return }
            status = .connected
            DiagnosticsLog.log(.voice, "Joined the call in \(channelId) on \(credentials.url)")
            if let uuid = callUUID, answeredCallUUID == nil {
                callKit.reportConnected(uuid)
            }
            sounds.play(.joined)
            await applyMicrophone()
            syncSystemMute()
            applyVolumes()
            refreshVideoFeeds()
        } catch is CancellationError {
            return
        } catch StoatAPIError.server(_, "AlreadyConnected"?) {
            endCall(systemReason: .failed)
            pendingMoveChannelId = channelId
        } catch {
            guard self.channelId == channelId else { return }
            endCall(systemReason: .failed)
            store.showError(error)
        }
    }

    /// Ends the current call. `systemReason` is nil when the user hung up in Yuki (so the system
    /// is asked to end its call too), or why it ended otherwise.
    private func endCall(systemReason: CXCallEndedReason?) {
        joinTask?.cancel()
        joinTask = nil
        audioWatchdog?.cancel()
        audioWatchdog = nil
        if let uuid = callUUID {
            if let systemReason {
                callKit.reportEnded(uuid, reason: systemReason)
            } else {
                callKit.requestEnd(uuid)
            }
        }
        callUUID = nil
        reportedMuted = nil
        let room = room
        reset()
        Task { await room?.disconnect() }
    }

    private func reset() {
        room = nil
        events = nil
        channelId = nil
        status = .idle
        speakingUserIds = []
        videoFeeds = []
        isCameraOn = false
        Self.isCallActive = false
    }

    // MARK: Call audio

    /// Reports the call to CallKit, which then owns the audio session. Falls back to LiveKit
    /// managing audio when CallKit isn't available or refuses the call.
    private func setUpCallAudio(title: String, answeredCallUUID: UUID?) async {
        if let answeredCallUUID {
            callUUID = answeredCallUUID
            useCallKitAudio()
            startAudioWatchdog()
            return
        }
        guard callKit.isAvailable else {
            useAutomaticAudio()
            return
        }
        let uuid = UUID()
        useCallKitAudio()
        do {
            try await callKit.startCall(uuid, title: title)
            callUUID = uuid
            startAudioWatchdog()
        } catch {
            DiagnosticsLog.log(.voice, "CallKit unavailable (\(error)); managing call audio directly")
            useAutomaticAudio()
        }
    }

    private func useCallKitAudio() {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        if !callKit.isAudioActive {
            try? AudioManager.shared.setEngineAvailability(.none)
        }
    }

    private func useAutomaticAudio() {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        try? AudioManager.shared.setEngineAvailability(.default)
    }

    /// If the system doesn't start call audio soon after the call is reported, Yuki starts it
    /// itself rather than leaving the call silent.
    private func startAudioWatchdog() {
        audioWatchdog?.cancel()
        audioWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.isInCall, !self.callKit.isAudioActive else { return }
            DiagnosticsLog.log(.voice, "CallKit didn't start call audio; managing it directly")
            self.useAutomaticAudio()
        }
    }

    // MARK: System actions

    private func handleSystemAction(_ action: CallKitBridge.SystemAction) {
        switch action {
        case .answer(let uuid):
            guard let ringing, ringing.uuid == uuid, let store else {
                callKit.reportEnded(uuid, reason: .failed)
                return
            }
            self.ringing = nil
            store.dismissIncomingCall()
            store.openChannel(ringing.channelId)
            // Set up before the system activates audio, which follows straight after answering.
            useCallKitAudio()
            startJoining(ringing.channelId, store: store, moveFromOtherDevice: false, answeredCallUUID: uuid)

        case .end(let uuid):
            if uuid == callUUID {
                callUUID = nil
                endCall(systemReason: nil)
            } else if let ringing, ringing.uuid == uuid {
                self.ringing = nil
                store?.dismissIncomingCall()
            }

        case .setMuted(let uuid, let muted):
            guard uuid == callUUID else { return }
            reportedMuted = muted
            if muted != !isMicrophoneOn {
                toggleMute()
            }
        }
    }

    private func syncSystemMute() {
        guard let uuid = callUUID else { return }
        let muted = !isMicrophoneOn
        guard reportedMuted != muted else { return }
        reportedMuted = muted
        callKit.requestMuted(uuid, muted: muted)
    }

    // MARK: Incoming calls

    public func ring(_ call: AppStore.IncomingCall, store: AppStore) {
        self.store = store
        guard ringing?.channelId != call.channelId, bannerCallChannelId != call.channelId else { return }
        guard callKit.isAvailable else {
            bannerCallChannelId = call.channelId
            return
        }
        let uuid = UUID()
        ringing = (uuid, call.channelId)
        Task {
            do {
                try await callKit.reportIncoming(uuid, callerName: store.callerDescription(for: call))
            } catch {
                guard ringing?.uuid == uuid else { return }
                ringing = nil
                // Do Not Disturb and blocked callers mean don't ring at all.
                let code = (error as? CXErrorCodeIncomingCallError)?.code
                if code != .filteredByDoNotDisturb, code != .filteredByBlockList {
                    bannerCallChannelId = call.channelId
                }
            }
        }
    }

    public func stopRinging() {
        if let ringing {
            callKit.reportEnded(ringing.uuid, reason: .remoteEnded)
            self.ringing = nil
        }
        bannerCallChannelId = nil
    }

    // MARK: Controls

    public func toggleMute() {
        if isDeafened {
            // Unmuting while deafened undeafens too, as in Stoat for Web.
            isMuted = false
            setDeafened(false)
        } else {
            isMuted.toggle()
        }
        UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
        if status == .connected {
            sounds.play(isMicrophoneOn ? .unmuted : .muted)
        }
        syncSystemMute()
        Task { await applyMicrophone() }
    }

    public func toggleDeafen() {
        setDeafened(!isDeafened)
        if status == .connected {
            sounds.play(isDeafened ? .muted : .unmuted)
        }
        syncSystemMute()
        Task { await applyMicrophone() }
    }

    private func setDeafened(_ deafened: Bool) {
        isDeafened = deafened
        UserDefaults.standard.set(deafened, forKey: Self.deafenedKey)
        applyVolumes()
    }

    public func volume(for userId: String) -> Double {
        userVolumes[userId] ?? 1
    }

    public func setVolume(_ volume: Double, for userId: String) {
        let clamped = min(max(volume, 0), 2)
        if abs(clamped - 1) < 0.02 {
            userVolumes.removeValue(forKey: userId)
        } else {
            userVolumes[userId] = clamped
        }
        UserDefaults.standard.set(userVolumes, forKey: Self.volumesKey)
        applyVolumes()
    }

    public func toggleCamera() {
        guard let room, status == .connected, canShareVideo else { return }
        let enable = !isCameraOn
        Task {
            if enable, !(await AVCaptureDevice.requestAccess(for: .video)) {
                store?.showError("Camera access is off. You can turn it on in Settings.")
                return
            }
            do {
                try await room.localParticipant.setCamera(enabled: enable)
                guard self.room === room else { return }
                isCameraOn = enable
                refreshVideoFeeds()
            } catch {
                store?.showError(error)
            }
        }
    }

    public func flipCamera() {
        guard let room, isCameraOn else { return }
        Task {
            let capturer = room.localParticipant.localVideoTracks
                .compactMap { $0.track as? LocalVideoTrack }
                .first { $0.source == .camera }?
                .capturer as? CameraCapturer
            _ = try? await capturer?.switchCameraPosition()
        }
    }

    private func applyMicrophone() async {
        guard let room, status == .connected || status == .reconnecting else { return }
        do {
            try await room.localParticipant.setMicrophone(enabled: isMicrophoneOn)
        } catch {
            DiagnosticsLog.log(.voice, "Couldn't set the microphone: \(error)")
        }
    }

    private func applyVolumes() {
        guard let room else { return }
        let volumes = userVolumes
        let isDeafened = isDeafened
        // Setting a volume waits on WebRTC's signalling thread, so keep it off the main thread.
        Task.detached {
            for participant in room.remoteParticipants.values {
                let userId = participant.identity?.stringValue ?? ""
                let volume = isDeafened ? 0 : volumes[userId] ?? 1
                for publication in participant.audioTracks {
                    (publication.track as? RemoteAudioTrack)?.volume = volume
                }
            }
        }
    }

    private func refreshVideoFeeds() {
        guard let room else {
            videoFeeds = []
            return
        }
        var feeds: [VideoFeed] = []
        for participant in room.remoteParticipants.values {
            guard let userId = participant.identity?.stringValue else { continue }
            for publication in participant.videoTracks where !publication.isMuted {
                guard let track = publication.track as? VideoTrack else { continue }
                feeds.append(VideoFeed(
                    id: publication.sid.stringValue,
                    userId: userId,
                    isScreenShare: publication.source == .screenShareVideo,
                    isLocal: false,
                    track: track
                ))
            }
        }
        feeds.sort { ($0.isScreenShare ? 0 : 1, $0.userId) < ($1.isScreenShare ? 0 : 1, $1.userId) }
        if isCameraOn, let userId = store?.store.currentUserId,
           let local = room.localParticipant.localVideoTracks.first(where: { $0.source == .camera }),
           let track = local.track as? VideoTrack {
            feeds.append(VideoFeed(id: "local-camera", userId: userId, isScreenShare: false, isLocal: true, track: track))
        }
        videoFeeds = feeds
    }

    // MARK: Room events

    private func handle(_ event: RoomEvents.Event) {
        guard room != nil else { return }
        switch event {
        case .connectionState(let state):
            switch state {
            case .connected:
                status = .connected
            case .reconnecting:
                status = .reconnecting
            case .disconnected:
                if status == .connected || status == .reconnecting {
                    endCall(systemReason: .remoteEnded)
                }
            case .connecting, .disconnecting:
                break
            }
        case .speakers(let ids):
            speakingUserIds = Set(ids)
        case .tracksChanged:
            applyVolumes()
            refreshVideoFeeds()
        case .participantJoined:
            if status == .connected { sounds.play(.joined) }
        case .participantLeft:
            if status == .connected { sounds.play(.left) }
            refreshVideoFeeds()
        }
    }

    // MARK: Nodes

    /// The voice server that answers first, as Stoat for Web picks it. Only used when the call
    /// hasn't started yet; otherwise Stoat uses the call's existing server.
    nonisolated static func fastestNode(_ nodes: [LiveKitNode]) async -> String? {
        guard nodes.count > 1 else { return nodes.first?.name }
        let fastest = await withTaskGroup(of: String?.self) { group -> String? in
            for node in nodes {
                group.addTask {
                    guard let address = node.publicUrl?.replacingOccurrences(of: "wss://", with: "https://"),
                          let url = URL(string: address) else { return nil }
                    var request = URLRequest(url: url, timeoutInterval: 3)
                    request.httpMethod = "HEAD"
                    guard (try? await URLSession.shared.data(for: request)) != nil else { return nil }
                    return node.name
                }
            }
            for await name in group {
                if let name {
                    group.cancelAll()
                    return name
                }
            }
            return nil
        }
        return fastest ?? nodes.first?.name
    }
}

extension AppStore {
    /// Where a call is: "#channel · Server", or the conversation's name.
    public func callLocation(for channelId: String) -> String {
        guard let channel = store.channels[channelId] else { return "Voice" }
        if channel.isPrivate {
            return channel.displayName(withUsers: store.users, currentUserId: store.currentUserId)
        }
        let server = channel.server.flatMap { store.servers[$0]?.name }
        return "#\(channel.name ?? "channel")" + (server.map { " · \($0)" } ?? "")
    }

    public func callerDescription(for call: IncomingCall) -> String {
        let caller = store.displayName(userId: call.callerId, serverId: nil)
        guard let channel = store.channels[call.channelId], channel.channelType == .group else { return caller }
        return "\(caller) in \(channel.displayName(withUsers: store.users, currentUserId: store.currentUserId))"
    }
}

/// Receives LiveKit's room callbacks, which arrive on its own threads, and passes on the ones
/// Yuki uses.
private final class RoomEvents: NSObject, RoomDelegate, Sendable {
    enum Event: Sendable {
        case connectionState(ConnectionState)
        case speakers([String])
        case tracksChanged
        case participantJoined
        case participantLeft
    }

    private let send: @Sendable (Event) -> Void

    init(send: @escaping @Sendable (Event) -> Void) {
        self.send = send
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        send(.connectionState(connectionState))
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        send(.speakers(participants.compactMap { $0.identity?.stringValue }))
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        send(.tracksChanged)
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        send(.tracksChanged)
    }

    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        send(.tracksChanged)
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        send(.participantJoined)
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        send(.participantLeft)
    }
}

import SwiftUI
import AVFoundation
import Observation
import StoatCore
import StoatVoice

@Observable
@MainActor
final class AudioPlaybackModel {
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var holdsAudio = false
    @ObservationIgnored private let url: URL?

    private static var knownDurations: [URL: Double] = [:]

    init(url: URL?) {
        self.url = url
        if let url, let known = Self.knownDurations[url] {
            duration = known
        }
    }

    func loadDuration() async {
        guard duration == 0, let url else { return }
        guard let time = try? await AVURLAsset(url: url).load(.duration) else { return }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return }
        Self.knownDurations[url] = seconds
        duration = seconds
    }

    func toggle() {
        if player == nil {
            prepare()
        }
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            releaseAudio()
        } else {
            // During a call the session belongs to the call; changing it would cut the call's audio.
            if !VoiceCallController.isCallActive, !holdsAudio {
                holdsAudio = (try? AudioSessionPolicy.begin()) != nil
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        let seconds = fraction * duration
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    private func prepare() {
        guard let url else { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        Task { [weak self] in
            if let time = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite, seconds > 0 {
                    self?.duration = seconds
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            MainActor.assumeIsolated {
                self?.currentTime = seconds
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.currentTime = 0
                self?.player?.seek(to: .zero)
                self?.releaseAudio()
            }
        }
    }

    private func releaseAudio() {
        guard holdsAudio else { return }
        holdsAudio = false
        AudioSessionPolicy.end()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        releaseAudio()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player = nil
    }
}

public struct AudioAttachmentCard: View {
    public let attachment: Attachment
    @State private var model: AudioPlaybackModel
    @State private var transcript: Transcript
    @State private var showsTranscript: Bool

    private enum Transcript {
        case none
        case working
        case text(String)
        case failed(String)
    }

    public init(attachment: Attachment) {
        self.attachment = attachment
        _model = State(initialValue: AudioPlaybackModel(url: attachment.originalURL()))
        let known = VoiceTranscriber.cachedTranscript(for: attachment.id)
        _transcript = State(initialValue: known.map(Transcript.text) ?? .none)
        _showsTranscript = State(initialValue: known != nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            player
            if showsTranscript {
                transcriptView
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YukiTheme.cardSurface)
        )
        .frame(maxWidth: 340)
        .task { await model.loadDuration() }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio: \(attachment.filename)")
    }

    private var player: some View {
        HStack(spacing: 12) {
            Button {
                YukiHaptics.impact()
                model.toggle()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(YukiTheme.systemBackground)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(YukiTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let bars = 28
                    let progress = model.duration > 0 ? model.currentTime / model.duration : 0
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<bars, id: \.self) { index in
                            Capsule()
                                .fill(Double(index) / Double(bars) < progress ? YukiTheme.accent : Color.secondary.opacity(0.4))
                                .frame(height: 24 * barHeight(index))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        model.seek(to: min(max(value.location.x / proxy.size.width, 0), 1))
                    })
                }
                .frame(height: 24)

                HStack {
                    Text("\(format(model.currentTime)) / \(format(model.duration))")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(attachment.filename)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button(action: toggleTranscript) {
                Group {
                    if case .working = transcript {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: showsTranscript ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(YukiTheme.accent)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled({ if case .working = transcript { true } else { false } }())
            .accessibilityLabel(showsTranscript ? "Hide Transcript" : "Transcribe")
        }
    }

    @ViewBuilder
    private var transcriptView: some View {
        switch transcript {
        case .none:
            EmptyView()
        case .working:
            Text("Transcribing…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .text(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleTranscript() {
        YukiHaptics.impact()
        switch transcript {
        case .text:
            withAnimation(.easeInOut(duration: 0.2)) { showsTranscript.toggle() }
        case .working:
            break
        case .none, .failed:
            guard let url = attachment.originalURL() else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                transcript = .working
                showsTranscript = true
            }
            Task {
                let result: Transcript
                do {
                    result = .text(try await VoiceTranscriber.transcribe(id: attachment.id, url: url, filename: attachment.filename))
                } catch {
                    result = .failed((error as? VoiceTranscriber.Failure)?.errorDescription ?? "Couldn't transcribe this recording.")
                }
                withAnimation(.easeInOut(duration: 0.2)) { transcript = result }
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // Stable pseudo-waveform derived from the file ID.
        let scalars = Array(attachment.id.unicodeScalars)
        let value = scalars.isEmpty ? 0 : Int(scalars[index % scalars.count].value) * (index + 7)
        return 0.25 + CGFloat(value % 75) / 100
    }

    private func format(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

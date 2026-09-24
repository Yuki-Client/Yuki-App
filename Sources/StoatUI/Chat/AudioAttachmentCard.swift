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

    init(url: URL?) {
        self.url = url
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

    public init(attachment: Attachment) {
        self.attachment = attachment
        _model = State(initialValue: AudioPlaybackModel(url: attachment.originalURL()))
    }

    public var body: some View {
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
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YukiTheme.cardSurface)
        )
        .frame(maxWidth: 340)
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio: \(attachment.filename)")
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

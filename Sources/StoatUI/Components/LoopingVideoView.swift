import SwiftUI
import AVFoundation
import UIKit
import StoatCore
import StoatVoice

/// A muted, looping, inline video for GIFs (Tenor and Gifbox serve GIFs as MP4).
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.configure(url: url)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        func configure(url: URL) {
            guard url != currentURL else { return }
            stop()
            currentURL = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            self.player = player
            if !VoiceCallController.isCallActive {
                AudioSessionPolicy.prepareForSilentPlayback()
            }
            player.play()
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            playerLayer.player = nil
            currentURL = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                player?.pause()
            } else {
                player?.play()
            }
        }
    }
}

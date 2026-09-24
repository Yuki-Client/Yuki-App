import SwiftUI
import AVKit
import UIKit
import StoatCore
import StoatVoice

/// Presents UIKit screens over whatever is currently on top, including open sheets.
@MainActor
enum TopPresenter {
    static var topViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Plays a video in the system player, whose close button hides along with its controls.
    static func playVideo(_ url: URL) {
        let holdsAudio = !VoiceCallController.isCallActive && (try? AudioSessionPolicy.begin()) != nil
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.modalPresentationStyle = .fullScreen
        topViewController?.present(controller, animated: true) {
            player.play()
            guard holdsAudio else { return }
            // AVPlayerViewController has no callback for being closed, so watch for it leaving
            // the screen, then hand audio back to whatever was playing before.
            Task { @MainActor [weak controller] in
                while let controller, controller.viewIfLoaded?.window != nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                player.pause()
                AudioSessionPolicy.end()
            }
        }
    }
}

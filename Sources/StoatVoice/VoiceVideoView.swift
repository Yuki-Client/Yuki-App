import SwiftUI
import LiveKit

/// Draws a camera or screen share from a call, so views outside this module don't need LiveKit.
public struct VoiceVideoView: View {
    let feed: VoiceCallController.VideoFeed
    /// Fills the frame (cropping) instead of fitting inside it.
    var fills: Bool

    public init(feed: VoiceCallController.VideoFeed, fills: Bool = false) {
        self.feed = feed
        self.fills = fills
    }

    public var body: some View {
        SwiftUIVideoView(feed.track, layoutMode: fills ? .fill : .fit, mirrorMode: feed.isLocal ? .auto : .off)
    }
}

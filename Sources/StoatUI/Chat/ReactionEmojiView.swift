import SwiftUI
import StoatCore

struct ReactionEmojiView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        if Emoji.isCustomEmojiId(emoji) {
            RemoteImage(url: Emoji.imageURL(id: emoji), maxPixelSize: size * 3, animates: true, animatedContentMode: .scaleAspectFit) { image in
                image.resizable().scaledToFit()
            } placeholder: { _ in
                Image(systemName: "face.smiling").foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        } else {
            Text(emoji).font(.system(size: size * 0.9))
        }
    }
}

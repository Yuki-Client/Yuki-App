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
            let emoji = UnicodeEmoji.removingPackMarkers(emoji)
            let letters = (emoji.count == 1 && emoji.first != nil) ? UnicodeEmoji.loneRegionalIndicatorLetters(in: emoji.first!) : []
            if !letters.isEmpty {
                HStack(spacing: 1) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                        Image(uiImage: RegionalIndicatorTile.image(for: letter, pointSize: size))
                    }
                }
                .accessibilityLabel(String(letters))
            } else {
                Text(emoji).font(.system(size: size * 0.9))
            }
        }
    }
}

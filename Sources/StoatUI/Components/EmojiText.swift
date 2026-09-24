import SwiftUI
import StoatCore
import StoatState

struct EmojiText: View {
    let text: String
    var emojiSize: CGFloat = 16

    @Environment(AppStore.self) private var appStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let emojiCache = EmojiImageCache.shared

    private static let pattern = try! NSRegularExpression(pattern: #":([0-9A-HJKMNP-TV-Z]{26}):"#)

    var body: some View {
        if !reduceMotion, MarkdownParser.emojiIds(in: text).contains(where: emojiCache.isAnimated) {
            // Text can't animate inline images, so redraw at the emoji frame rate, as in messages.
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                rendered(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            rendered(at: nil)
        }
    }

    private func rendered(at time: TimeInterval?) -> Text {
        let range = NSRange(text.startIndex..., in: text)
        let matches = Self.pattern.matches(in: text, range: range)
        guard !matches.isEmpty else { return Text(verbatim: text) }

        var result = Text("")
        var cursor = text.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: text), let idRange = Range(match.range(at: 1), in: text) else { continue }
            if cursor < whole.lowerBound {
                result = Text("\(result)\(Text(verbatim: String(text[cursor..<whole.lowerBound])))")
            }
            let id = String(text[idRange])
            if let image = emojiCache.image(for: id, pointSize: emojiSize, at: time) {
                result = Text("\(result)\(Image(uiImage: image).renderingMode(.original))")
            } else if !emojiCache.hasFailed(id) {
                result = Text("\(result)\(Image(uiImage: emojiCache.placeholder(pointSize: emojiSize)))")
            } else {
                let name = appStore.store.emojis[id]?.name ?? "emoji"
                result = Text("\(result)\(Text(verbatim: ":\(name):"))")
            }
            cursor = whole.upperBound
        }
        if cursor < text.endIndex {
            result = Text("\(result)\(Text(verbatim: String(text[cursor...])))")
        }
        return result
    }
}

import SwiftUI
import UIKit
import StoatCore

/// A regional indicator letter on its own, drawn as the blue letter tile Stoat for Web shows.
/// iOS only has glyphs for them in pairs that make a flag.
enum RegionalIndicatorTile {
    private static let background = UIColor(red: 0x3B / 255, green: 0x88 / 255, blue: 0xC3 / 255, alpha: 1)

    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func image(for letter: Character, pointSize: CGFloat) -> UIImage {
        let key = "\(letter)@\(Int(pointSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let side = pointSize
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let inset = side * 0.06
            let rect = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset)
            background.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.12).fill()
            let font = UIFont.systemFont(ofSize: rect.height * 0.7, weight: .heavy)
            let label = NSAttributedString(string: String(letter), attributes: [.font: font, .foregroundColor: UIColor.white])
            let size = label.size()
            label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// `text` with lone regional indicators swapped for tiles.
    static func text(_ text: String, pointSize: CGFloat) -> Text {
        let pieces = UnicodeEmoji.splittingLoneRegionalIndicators(text)
        if case .text(let only)? = pieces.first, pieces.count == 1 { return Text(verbatim: only) }
        var result = Text("")
        for piece in pieces {
            switch piece {
            case .text(let run):
                result = Text("\(result)\(Text(verbatim: run))")
            case .letter(let letter):
                result = Text("\(result)\(Image(uiImage: image(for: letter, pointSize: pointSize)).renderingMode(.original))")
            }
        }
        return result
    }
}

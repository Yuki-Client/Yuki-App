import SwiftUI
import SwiftMath
import UIKit

/// Images are drawn as templates so they take the text's colour.
@MainActor
enum MathRenderer {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()
    /// Anything longer is almost certainly not maths, and would be slow to lay out.
    private static let maxLength = 500

    /// Returns nil when the LaTeX can't be drawn, so the caller can show the source instead.
    static func image(latex: String, fontSize: CGFloat) -> UIImage? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }

        let key = "\(Int(fontSize))|\(trimmed)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let math = MTMathImage(latex: trimmed, fontSize: fontSize, textColor: .label, labelMode: .text, textAlignment: .left)
        let (error, image) = math.asImage()
        guard error == nil, let image else { return nil }
        let template = image.withRenderingMode(.alwaysTemplate)
        cache.setObject(template, forKey: key)
        return template
    }
}

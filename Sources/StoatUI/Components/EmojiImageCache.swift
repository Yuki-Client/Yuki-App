import SwiftUI
import StoatCore
import UIKit

/// Loads custom emoji and pre-renders them at a fixed point size for inline `Text` images.
@Observable
@MainActor
final class EmojiImageCache {
    static let shared = EmojiImageCache()

    private struct Animation {
        let frames: [UIImage]
        let frameDuration: TimeInterval
    }

    private var images: [String: UIImage] = [:]
    private var animations: [String: Animation] = [:]
    private var animatedIds: Set<String> = []
    private var failedIds: Set<String> = []
    @ObservationIgnored private var loading: Set<String> = []
    /// Sizes rendered straight away from an image that was already decoded, e.g. an emoji seen in
    /// a message and then in a reply preview. Not observed, since it's filled in while views draw.
    @ObservationIgnored private var renderedNow: [String: UIImage] = [:]
    @ObservationIgnored private var placeholders: [Int: UIImage] = [:]
    @ObservationIgnored private var animationOrder: [String] = []
    @ObservationIgnored private var memoryWarnings: NSObjectProtocol?

    /// Frames are rendered at the emoji's display size, so long animations are thinned out.
    private static let maxFrames = 48
    // Each animation holds all its frames, so only the most recent ones are kept.
    private static let maxAnimations = 60
    private static let maxStillImages = 600

    private init() {
        memoryWarnings = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                EmojiImageCache.shared.evictAll()
            }
        }
    }

    private func evictAll() {
        animations = [:]
        animationOrder = []
        images = [:]
        renderedNow = [:]
    }

    func image(for id: String, pointSize: CGFloat, at time: TimeInterval? = nil) -> UIImage? {
        let key = "\(id)@\(Int(pointSize))"
        if let time, let animation = animations[key] {
            let index = Int(time / animation.frameDuration) % animation.frames.count
            return animation.frames[index]
        }
        if let image = images[key] ?? renderedNow[key] {
            return image
        }
        if let url = Emoji.imageURL(id: id),
           let source = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: 128),
           (source.images?.count ?? 1) <= 1 {
            let image = Self.render(source, pointSize: pointSize)
            if renderedNow.count >= Self.maxStillImages { renderedNow = [:] }
            renderedNow[key] = image
            return image
        }
        load(id: id, pointSize: pointSize, key: key)
        return nil
    }

    /// A transparent image the size of an emoji, shown while it loads so text doesn't flash
    /// `:name:` or shift when the emoji appears.
    func placeholder(pointSize: CGFloat) -> UIImage {
        let size = Int(pointSize)
        if let image = placeholders[size] { return image }
        let image = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize)).image { _ in }
        placeholders[size] = image
        return image
    }

    func hasFailed(_ id: String) -> Bool {
        failedIds.contains(id)
    }

    func isAnimated(_ id: String) -> Bool {
        animatedIds.contains(id)
    }

    private func load(id: String, pointSize: CGFloat, key: String) {
        guard !loading.contains(key), let url = Emoji.imageURL(id: id) else { return }
        loading.insert(key)
        Task {
            if let source = await ImagePipeline.shared.image(for: url, maxPixelSize: 128) {
                if let sourceFrames = source.images, sourceFrames.count > 1 {
                    let step = max(1, Int((Double(sourceFrames.count) / Double(Self.maxFrames)).rounded(.up)))
                    let frames = stride(from: 0, to: sourceFrames.count, by: step).map {
                        Self.render(sourceFrames[$0], pointSize: pointSize)
                    }
                    let total = source.duration > 0 ? source.duration : Double(sourceFrames.count) * 0.1
                    images[key] = frames[0]
                    animations[key] = Animation(frames: frames, frameDuration: max(0.02, total / Double(frames.count)))
                    animationOrder.append(key)
                    if animationOrder.count > Self.maxAnimations {
                        let evicted = animationOrder.removeFirst()
                        animations[evicted] = nil
                        images[evicted] = nil
                    }
                    animatedIds.insert(id)
                } else {
                    if images.count >= Self.maxStillImages { images = [:] }
                    images[key] = Self.render(source, pointSize: pointSize)
                }
            } else {
                failedIds.insert(id)
            }
            loading.remove(key)
        }
    }

    private static func render(_ source: UIImage, pointSize: CGFloat) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        return UIGraphicsImageRenderer(size: size, format: .default()).image { _ in
            let aspect = source.size.width / max(source.size.height, 1)
            let drawSize = aspect >= 1
                ? CGSize(width: pointSize, height: pointSize / aspect)
                : CGSize(width: pointSize * aspect, height: pointSize)
            let origin = CGPoint(x: (pointSize - drawSize.width) / 2, y: (pointSize - drawSize.height) / 2)
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

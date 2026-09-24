import SwiftUI
import ImageIO
import UIKit

actor ImagePipeline {
    static let shared = ImagePipeline()

    /// NSCache is thread-safe, so synchronous reads from views are allowed.
    private nonisolated(unsafe) let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        cache.totalCostLimit = 200 * 1024 * 1024
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    /// Decodes are cached per size bucket so a small avatar decode isn't reused for a large view.
    nonisolated static func bucket(for maxPixelSize: CGFloat?) -> Int {
        let size = Int(maxPixelSize ?? 2048)
        return [128, 256, 512, 1024, 2048, 4096].first { $0 >= size } ?? 4096
    }

    nonisolated static func key(for url: URL, maxPixelSize: CGFloat?) -> String {
        "\(url.absoluteString)#\(bucket(for: maxPixelSize))"
    }

    nonisolated func cachedImage(for url: URL, maxPixelSize: CGFloat?) -> UIImage? {
        cache.object(forKey: Self.key(for: url, maxPixelSize: maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: CGFloat?) async -> UIImage? {
        let key = Self.key(for: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let session = session
        let pixelSize = CGFloat(Self.bucket(for: maxPixelSize))
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return Self.decode(data, maxPixelSize: pixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            let frames = CGFloat(image.images?.count ?? 1)
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4 * frames)
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    private static let maxFrames = 240

    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        let count = CGImageSourceGetCount(source)
        if count > 1 {
            // Every frame is held decoded in memory, so animations are capped in size and frame count.
            var frameOptions = options
            frameOptions[kCGImageSourceThumbnailMaxPixelSize] = min(maxPixelSize, 720)
            let step = max(1, Int((Double(count) / Double(maxFrames)).rounded(.up)))
            var frames: [UIImage] = []
            var duration: Double = 0
            for index in stride(from: 0, to: count, by: step) {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, frameOptions as CFDictionary) else { continue }
                frames.append(UIImage(cgImage: frame))
                duration += frameDelay(source, index: index) * Double(step)
            }
            if frames.count > 1 {
                return UIImage.animatedImage(with: frames, duration: duration > 0 ? duration : Double(frames.count) * 0.1)
            }
            return frames.first
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func frameDelay(_ source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime)
        ]
        for (dictionaryKey, unclampedKey, clampedKey) in containers {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else { continue }
            let delay = (dictionary[unclampedKey] as? Double) ?? (dictionary[clampedKey] as? Double) ?? 0
            // Browsers treat very short delays as 100 ms; match that so GIFs don't race.
            return delay < 0.02 ? 0.1 : delay
        }
        return 0.1
    }
}

/// Cached images render synchronously so they don't flicker.
public struct RemoteImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let maxPixelSize: CGFloat?
    private let animates: Bool
    private let animatedContentMode: UIView.ContentMode
    private let content: (Image) -> Content
    private let placeholder: (Bool) -> Placeholder

    @State private var loaded: UIImage?
    @State private var failed = false

    public init(
        url: URL?,
        maxPixelSize: CGFloat? = nil,
        animates: Bool = false,
        animatedContentMode: UIView.ContentMode = .scaleAspectFill,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping (Bool) -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.animates = animates
        self.animatedContentMode = animatedContentMode
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let image = loaded ?? url.flatMap({ ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize) }) {
                if animates, image.images != nil {
                    AnimatedImageView(image: image, contentMode: animatedContentMode)
                } else {
                    content(Image(uiImage: image))
                }
            } else {
                placeholder(failed)
            }
        }
        .task(id: url) {
            guard let url else {
                failed = true
                return
            }
            if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                loaded = cached
                return
            }
            loaded = nil
            failed = false
            let image = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            loaded = image
            failed = image == nil
        }
    }
}

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.accessibilityIgnoresInvertColors = true
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode
        // Animated UIImages play automatically; Reduce Motion shows the first frame instead.
        let display = UIAccessibility.isReduceMotionEnabled ? (image.images?.first ?? image) : image
        if view.image !== display {
            view.image = display
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
    }
}

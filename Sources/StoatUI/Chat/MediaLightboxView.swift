import SwiftUI
import Photos
import StoatCore
import UIKit

public struct MediaLightboxView: View {
    public let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var saveState: SaveState = .idle
    /// The top bar hides when the image is tapped, like Photos.
    @State private var showsChrome = true
    @State private var dismissProgress: CGFloat = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    enum SaveState { case idle, saving, saved, failed }

    public init(attachment: Attachment) {
        self.attachment = attachment
    }

    public var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dismissProgress * 0.85)
                .ignoresSafeArea()

            if let image {
                ZoomableImageView(
                    image: image,
                    onSingleTap: {
                        // VoiceOver users can't find the buttons again once hidden.
                        guard !voiceOverEnabled else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
                    },
                    onDismissProgress: { progress in
                        let settles = progress == 0 || progress == 1
                        withAnimation(settles ? .easeOut(duration: 0.22) : nil) { dismissProgress = progress }
                    },
                    onDismiss: {
                        // The image already flew off screen, so close without the slide-down animation.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { dismiss() }
                    }
                )
                .ignoresSafeArea()
            } else if failed {
                ContentUnavailableView("Couldn't load image", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(attachment.filename, image: Image(uiImage: image))) {
                            circleIcon("square.and.arrow.up")
                        }
                        .accessibilityLabel("Share image")

                        Button {
                            save(image)
                        } label: {
                            circleIcon(saveState == .saved ? "checkmark" : saveState == .failed ? "exclamationmark" : "square.and.arrow.down")
                        }
                        .disabled(saveState == .saving)
                        .accessibilityLabel("Save image to Photos")
                    }

                    Button {
                        dismiss()
                    } label: {
                        circleIcon("xmark")
                    }
                    .accessibilityLabel("Close")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )

                Spacer()
            }
            .opacity(showsChrome ? max(0, 1 - dismissProgress * 3) : 0)
            .allowsHitTesting(showsChrome && dismissProgress == 0)
        }
        .presentationBackground(.clear)
        .statusBarHidden(!showsChrome)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        .accessibilityAction(.escape) { dismiss() }
        .task {
            guard let url = attachment.originalURL() ?? attachment.downloadURL() else {
                failed = true
                return
            }
            image = await ImagePipeline.shared.image(for: url, maxPixelSize: 4096)
            failed = image == nil
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.15)))
    }

    /// Photos runs the change block on its own queue. Declared outside the view's main-actor
    /// isolation so the block isn't main-actor isolated: Swift checks that at runtime and crashed.
    nonisolated private static func addToPhotoLibrary(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    private func save(_ image: UIImage) {
        saveState = .saving
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveState = .failed
                return
            }
            do {
                try await Self.addToPhotoLibrary(image)
                YukiHaptics.notification(.success)
                saveState = .saved
            } catch {
                saveState = .failed
            }
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: () -> Void = {}
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.image = image
        update(view)
        return view
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        if view.image !== image {
            view.image = image
        }
        update(view)
    }

    private func update(_ view: ZoomingImageScrollView) {
        view.onSingleTap = onSingleTap
        view.onDismissProgress = onDismissProgress
        view.onDismiss = onDismiss
    }
}

/// Lays the image out by frame: it's fitted to the bounds at zoom 1 and kept centred with content insets.
final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedForSize: CGSize = .zero
    var onSingleTap: () -> Void = {}
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    private let dismissPan = UIPanGestureRecognizer()
    private lazy var dismissPanDelegate = DismissPanDelegate(scrollView: self)

    var image: UIImage? {
        didSet {
            imageView.image = image
            fittedForSize = .zero
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        maximumZoomScale = 5
        minimumZoomScale = 1
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        dismissPan.addTarget(self, action: #selector(dismissPanned(_:)))
        dismissPan.delegate = dismissPanDelegate
        addGestureRecognizer(dismissPan)
    }

    /// Only a mostly vertical drag on an image that isn't zoomed in swipes it away.
    fileprivate var canSwipeToDismiss: Bool {
        guard image != nil, zoomScale <= minimumZoomScale + 0.01 else { return false }
        let velocity = dismissPan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x) * 1.2
    }

    @objc private func dismissPanned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self)
        let progress = min(1, abs(translation.y) / max(bounds.height * 0.45, 1))
        let shrink = 1 - progress * 0.2

        switch pan.state {
        case .began:
            // Pinching while dragging would fight over the image's transform.
            pinchGestureRecognizer?.isEnabled = false
        case .changed:
            imageView.transform = CGAffineTransform(translationX: translation.x * 0.5, y: translation.y).scaledBy(x: shrink, y: shrink)
            onDismissProgress(progress)
        case .ended, .cancelled, .failed:
            pinchGestureRecognizer?.isEnabled = true
            let velocity = pan.velocity(in: self).y
            if pan.state == .ended, abs(translation.y) > 110 || abs(velocity) > 900 {
                let direction: CGFloat = translation.y + velocity * 0.1 >= 0 ? 1 : -1
                onDismissProgress(1)
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                    self.imageView.transform = CGAffineTransform(translationX: translation.x * 0.5, y: direction * self.bounds.height).scaledBy(x: shrink, y: shrink)
                } completion: { _ in
                    self.onDismiss()
                }
            } else {
                onDismissProgress(0)
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.imageView.transform = .identity
                }
            }
        default:
            break
        }
    }

    @objc private func singleTapped() {
        onSingleTap()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedForSize {
            fitImage()
        }
    }

    private func fitImage() {
        guard let image, bounds.width > 0, bounds.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        fittedForSize = bounds.size
        zoomScale = 1
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
    }

    private func centerContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let width = bounds.width / 2.5
            let height = bounds.height / 2.5
            zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
        }
    }
}

/// Decides when the swipe-to-close drag may start, kept separate so the scroll view's own
/// gesture handling is left alone.
private final class DismissPanDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var scrollView: ZoomingImageScrollView?

    init(scrollView: ZoomingImageScrollView) {
        self.scrollView = scrollView
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        scrollView?.canSwipeToDismiss ?? false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

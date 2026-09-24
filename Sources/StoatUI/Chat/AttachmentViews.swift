import SwiftUI
import StoatCore
import StoatState

enum AttachmentLayout {
    static func fittedSize(_ size: CGSize?, maxWidth: CGFloat = 280, maxHeight: CGFloat = 320) -> CGSize {
        guard let size, size.width > 0, size.height > 0 else { return CGSize(width: 220, height: 180) }
        let scale = min(maxWidth / size.width, maxHeight / size.height, 1)
        return CGSize(width: max(80, size.width * scale), height: max(60, size.height * scale))
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct PreparingAttachment: Identifiable {
    enum Kind {
        case image, video, file
    }

    let id: UUID
    let kind: Kind
    var progress: Double?
    var task: Task<Void, Never>?
}

struct AttachmentThumbnail: View {
    let attachment: OutgoingAttachment

    var body: some View {
        switch attachment.kind {
        case .image, .video:
            ZStack(alignment: .bottomLeading) {
                if let image = AttachmentPreviewCache.image(for: attachment.id.uuidString, data: attachment.preview) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipped()
                } else {
                    Image(systemName: attachment.kind == .video ? "film" : "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if attachment.kind == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                        if let duration = attachment.duration {
                            Text(AttachmentLayout.durationText(duration))
                        }
                    }
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(attachment.kind == .video ? "Video" : "Photo")
        case .audio, .file:
            VStack(spacing: 4) {
                Image(systemName: attachment.kind == .audio ? "waveform" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(YukiTheme.accent)
                Text(attachment.filename)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .accessibilityElement(children: .combine)
        }
    }
}

struct PreparingThumbnail: View {
    let item: PreparingAttachment

    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            YukiTheme.cardSurface
                .opacity(shimmer ? 0.6 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmer)
            if item.kind == .video, let progress = item.progress, progress > 0 {
                UploadProgressRing(progress: progress, size: 34)
            } else {
                Image(systemName: item.kind == .video ? "film" : item.kind == .image ? "photo" : "doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { shimmer = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.kind == .video ? "Preparing video" : "Loading attachment")
        .accessibilityValue(item.progress.map { "\(Int($0 * 100)) percent" } ?? "")
    }
}

struct UploadProgressRing: View {
    let progress: Double
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.45))
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 3)
                .padding(4)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.easeOut(duration: 0.2), value: progress)
            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.28, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uploading")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// An attachment on a message that's still sending, drawn at the size it will have once sent.
struct PendingAttachmentView: View {
    let attachment: OutgoingAttachment
    let progress: Double?
    let isFailed: Bool

    private var isUploading: Bool {
        !isFailed && (progress ?? 0) < 1
    }

    var body: some View {
        switch attachment.kind {
        case .image, .video:
            media
        case .audio, .file:
            card
        }
    }

    private var media: some View {
        let frame = AttachmentLayout.fittedSize(attachment.pixelSize, maxHeight: attachment.kind == .video ? 240 : 320)
        return ZStack {
            if let image = AttachmentPreviewCache.image(for: attachment.id.uuidString, data: attachment.preview) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                YukiTheme.cardSurface
            }
            if isUploading {
                Color.black.opacity(0.25)
                UploadProgressRing(progress: progress ?? 0)
            } else if attachment.kind == .video, !isFailed {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .bottomLeading) {
            if attachment.kind == .video, let duration = attachment.duration {
                Text(AttachmentLayout.durationText(duration))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachment.kind == .video ? "Video" : "Photo")
        .accessibilityValue(isUploading ? "Uploading, \(Int((progress ?? 0) * 100)) percent" : "")
    }

    private var card: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.kind == .audio ? "waveform" : "doc.fill")
                .font(.title3)
                .foregroundStyle(YukiTheme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.kind == .audio ? "Voice Message" : attachment.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if isUploading {
                    ProgressView(value: progress ?? 0)
                        .tint(YukiTheme.accent)
                } else {
                    Text(attachment.duration.map(AttachmentLayout.durationText) ?? ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(YukiTheme.cardSurface))
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import StoatCore

struct EmbedView: View {
    let embed: Embed
    /// Server the message belongs to, for resolving role colours and nicknames in bot embeds.
    var serverId: String?
    let onPlayVideo: (URL) -> Void
    let onOpenImage: (Attachment) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if embed.isGIF, let gif = gifSource {
            gifView(gif)
        } else {
            standardBody
        }
    }

    @ViewBuilder
    private var standardBody: some View {
        switch embed.type {
        case "Image":
            if let raw = embed.url, let url = Embed.proxiedURL(raw) {
                remoteMedia(url: url, width: embed.width, height: embed.height) {
                    openURL(URL(string: raw) ?? url)
                }
            }
        case "Video":
            if let raw = embed.url, let url = Embed.proxiedURL(raw) {
                videoButton(url: url, width: embed.width, height: embed.height)
            }
        default:
            card
        }
    }

    private enum GifSource {
        case video(URL, width: Int?, height: Int?)
        case image(URL, width: Int?, height: Int?)
    }

    private var gifSource: GifSource? {
        // Videos load directly: iOS's player needs byte-range requests, which the media proxy doesn't support.
        if let video = embed.video, let url = URL(string: video.url) {
            return .video(url, width: video.width, height: video.height)
        }
        if embed.type == "Video", let raw = embed.url, let url = URL(string: raw) {
            return .video(url, width: embed.width, height: embed.height)
        }
        if embed.type == "Image", let raw = embed.url, let url = gifURL(raw) {
            return .image(url, width: embed.width, height: embed.height)
        }
        if let image = embed.image, let url = gifURL(image.url) {
            return .image(url, width: image.width, height: image.height)
        }
        return nil
    }

    /// Known GIF hosts are loaded directly, like Stoat for Web; anything else goes through the proxy.
    private func gifURL(_ raw: String) -> URL? {
        guard let host = URL(string: raw)?.host?.lowercased() else { return nil }
        if host.hasSuffix("tenor.com") || host.hasSuffix("giphy.com") {
            return URL(string: raw)
        }
        return Embed.proxiedURL(raw)
    }

    @ViewBuilder
    private func gifView(_ source: GifSource) -> some View {
        switch source {
        case .video(let url, let width, let height):
            let frame = size(width: width, height: height, maxWidth: 260)
            Group {
                if reduceMotion {
                    ZStack {
                        if let poster = embed.image, let posterURL = gifURL(poster.url) {
                            RemoteImage(url: posterURL, maxPixelSize: 600) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { _ in
                                YukiTheme.cardSurface
                            }
                        } else {
                            YukiTheme.cardSurface
                        }
                        Text("GIF")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.black.opacity(0.55)))
                    }
                } else {
                    LoopingVideoView(url: url)
                        .background(YukiTheme.cardSurface)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onPlayVideo(url) }
            .padding(.top, 2)
            .accessibilityLabel(embed.title.map { "GIF: \($0)" } ?? "GIF")
            .accessibilityAddTraits(.isButton)
        case .image(let url, let width, let height):
            remoteMedia(url: url, width: width, height: height, maxWidth: 260) {
                if let raw = embed.originalUrl ?? embed.url, let link = URL(string: raw) {
                    openURL(link)
                }
            }
            .padding(.top, 2)
            .accessibilityLabel(embed.title.map { "GIF: \($0)" } ?? "GIF")
        }
    }

    private var accent: Color {
        Color(stoatColour: embed.colour) ?? YukiTheme.accent
    }

    private var card: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                if embed.siteName != nil || embed.iconUrl != nil {
                    HStack(spacing: 6) {
                        if let icon = embed.iconUrl, let url = Embed.proxiedURL(icon) {
                            RemoteImage(url: url, maxPixelSize: 48) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { _ in
                                EmptyView()
                            }
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if let siteName = embed.siteName {
                            Text(siteName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let title = embed.title, !title.isEmpty {
                    if let raw = embed.url, let url = URL(string: raw) {
                        Link(destination: url) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(YukiTheme.accent)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                if let description = embed.description, !description.isEmpty {
                    if embed.type == "Text" {
                        // Bot embeds use full message markdown: mentions, timestamps, channels, emoji.
                        YukiMarkdownView(description, serverId: serverId, font: .subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(5)
                    }
                }

                if let media = embed.media {
                    RemoteImage(url: media.downloadURL(), maxPixelSize: 900) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { _ in
                        RoundedRectangle(cornerRadius: 8).fill(YukiTheme.cardSurface).frame(height: 140)
                    }
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { onOpenImage(media) }
                } else if let video = embed.video, let url = Embed.proxiedURL(video.url) {
                    videoButton(url: url, width: video.width, height: video.height, thumbnail: embed.image)
                } else if let image = embed.image, let url = Embed.proxiedURL(image.url) {
                    let isLarge = image.size == "Large"
                    remoteMedia(url: url, width: image.width, height: image.height, maxWidth: isLarge ? 260 : 80) {
                        if let raw = embed.url, let link = URL(string: raw) {
                            openURL(link)
                        }
                    }
                }
            }
            .padding(10)

            Spacer(minLength: 0)
        }
        .background(YukiTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 340, alignment: .leading)
        .padding(.top, 2)
    }

    private func size(width: Int?, height: Int?, maxWidth: CGFloat) -> CGSize {
        guard let width, let height, width > 0, height > 0 else { return CGSize(width: maxWidth, height: maxWidth * 0.6) }
        let scale = min(maxWidth / CGFloat(width), 240 / CGFloat(height), 1)
        return CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }

    private func remoteMedia(url: URL, width: Int?, height: Int?, maxWidth: CGFloat = 280, action: @escaping () -> Void) -> some View {
        let frame = size(width: width, height: height, maxWidth: maxWidth)
        return RemoteImage(url: url, maxPixelSize: 900, animates: true) { image in
            image.resizable().scaledToFill()
        } placeholder: { _ in
            RoundedRectangle(cornerRadius: 8).fill(YukiTheme.cardSurface)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func videoButton(url: URL, width: Int?, height: Int?, thumbnail: EmbedMedia? = nil) -> some View {
        let frame = size(width: width, height: height, maxWidth: 280)
        return Button {
            if embed.special?.type == "YouTube" || embed.special?.type == "Twitch", let raw = embed.url, let page = URL(string: raw) {
                openURL(page)
            } else {
                onPlayVideo(url)
            }
        } label: {
            ZStack {
                if let thumbnail, let thumbURL = Embed.proxiedURL(thumbnail.url) {
                    RemoteImage(url: thumbURL, maxPixelSize: 900) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { _ in
                        Color.black
                    }
                } else {
                    Color.black
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video")
    }
}

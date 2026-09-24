import SwiftUI
import UIKit
import StoatCore
import StoatState

public struct YukiMarkdownView: View {
    public let text: String
    public var serverId: String?
    public var font: Font = .body

    @Environment(AppStore.self) private var appStore
    @State private var revealSpoilers = false
    private let emojiCache = EmojiImageCache.shared

    public init(_ text: String, serverId: String? = nil, font: Font = .body) {
        self.text = text
        self.serverId = serverId
        self.font = font
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        let jumbo = MarkdownParser.isEmojiOnly(MarkdownParser.removingImages(from: text))
        let animates = !reduceMotion && MarkdownParser.emojiIds(in: text).contains { emojiCache.isAnimated($0) }

        Group {
            if animates {
                // Text can't animate inline images, so redraw it at the emoji frame rate.
                // Only messages that contain an animated emoji pay for this.
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    blocksView(jumbo: jumbo, time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                blocksView(jumbo: jumbo, time: nil)
            }
        }
        .task(id: text) {
            let mentioned = MarkdownParser.mentionedUserIds(in: text).filter { appStore.store.users[$0] == nil }
            if !mentioned.isEmpty {
                appStore.queueUserFetch(mentioned)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "yuki" else {
                return linkHandler.openExternal(url)
            }
            let id = url.lastPathComponent
            switch url.host {
            case "spoiler":
                withAnimation(.easeOut(duration: 0.2)) { revealSpoilers.toggle() }
            case "user":
                linkHandler.openUser(id)
            case "channel":
                linkHandler.openChannel(id)
            default:
                break
            }
            return .handled
        })
    }

    @Environment(\.yukiLinkHandler) private var linkHandler

    private func blocksView(jumbo: Bool, time: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.blocks(for: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let content):
                    inlineText(content, jumbo: jumbo, time: time)
                        .font(font)
                        .fixedSize(horizontal: false, vertical: true)
                case .heading(let level, let content):
                    inlineText(content, jumbo: false, time: time)
                        .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                        .fixedSize(horizontal: false, vertical: true)
                case .quote(let content):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3)
                        inlineText(content, jumbo: false, time: time)
                            .font(font)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let language, let code):
                    CodeBlockCardView(language: language, code: code)
                }
            }
        }
    }

    private func inlineText(_ source: String, jumbo: Bool, time: TimeInterval?) -> Text {
        let parsed = MarkdownParser.inline(source)
        var result = Text("")
        var buffer = AttributedString()

        func flush() {
            guard !buffer.characters.isEmpty else { return }
            result = Text("\(result)\(Text(buffer))")
            buffer = AttributedString()
        }

        for piece in parsed {
            switch piece {
            case .styled(let attributed):
                buffer.append(attributed)
            case .token(let token, let attributes):
                switch token {
                case .user(let id):
                    let name = appStore.store.displayName(userId: id, serverId: serverId)
                    let isMe = id == appStore.store.currentUserId
                    buffer.append(mention("@\(name)", url: "yuki://user/\(id)", highlight: isMe, base: attributes))
                case .role(let id):
                    let role = serverId.flatMap { appStore.store.servers[$0]?.roles[id] }
                        ?? appStore.store.servers.values.lazy.compactMap { $0.roles[id] }.first
                    let color = Color(stoatColour: role?.colour)
                    buffer.append(mention("@\(role?.name ?? "Unknown Role")", url: nil, highlight: false, color: color, base: attributes))
                case .channel(let id):
                    let name = appStore.store.channels[id]?.name ?? "unknown-channel"
                    buffer.append(mention("#\(name)", url: "yuki://channel/\(id)", highlight: false, base: attributes))
                case .everyone(let label):
                    buffer.append(mention("@\(label)", url: nil, highlight: false, base: attributes))
                case .math(let latex, let isBlock):
                    let size = jumbo ? 30.0 : isBlock ? 20.0 : 17.0
                    if let image = MathRenderer.image(latex: latex, fontSize: size) {
                        flush()
                        result = Text("\(result)\(Image(uiImage: image).renderingMode(.template))")
                    } else {
                        // Not maths Yuki can draw: show the source, as it was written.
                        var run = AttributedString(isBlock ? "$$\(latex)$$" : "$\(latex)$")
                        run.mergeAttributes(attributes)
                        buffer.append(run)
                    }
                case .emoji(let id):
                    if let image = emojiCache.image(for: id, pointSize: jumbo ? 44 : 20, at: time) {
                        flush()
                        result = Text("\(result)\(Image(uiImage: image).renderingMode(.original))")
                    } else if !emojiCache.hasFailed(id) {
                        flush()
                        let placeholder = emojiCache.placeholder(pointSize: jumbo ? 44 : 20)
                        result = Text("\(result)\(Image(uiImage: placeholder))")
                    } else {
                        let name = appStore.store.emojis[id]?.name ?? "emoji"
                        var placeholder = AttributedString(":\(name):")
                        placeholder.mergeAttributes(attributes)
                        placeholder.foregroundColor = .secondary
                        buffer.append(placeholder)
                    }
                case .timestamp(let date, let style):
                    var run = AttributedString(MarkdownParser.format(date: date, style: style))
                    run.mergeAttributes(attributes)
                    run.backgroundColor = Color.secondary.opacity(0.18)
                    buffer.append(run)
                case .spoiler(let content):
                    var run = content
                    if revealSpoilers {
                        run.backgroundColor = Color.secondary.opacity(0.18)
                    } else {
                        run.foregroundColor = .clear
                        run.backgroundColor = Color.secondary.opacity(0.55)
                    }
                    run.link = URL(string: "yuki://spoiler")
                    run.underlineStyle = nil
                    buffer.append(run)
                }
            }
        }
        flush()
        return result
    }

    private func mention(_ label: String, url: String?, highlight: Bool, color: Color? = nil, base: AttributeContainer) -> AttributedString {
        var run = AttributedString(label)
        run.mergeAttributes(base)
        let tint = color ?? YukiTheme.accent
        run.foregroundColor = tint
        run.backgroundColor = tint.opacity(highlight ? 0.3 : 0.16)
        // Bold via presentation intent so mentions keep the surrounding text's size (e.g. in embeds).
        run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
        if let url {
            run.link = URL(string: url)
        }
        return run
    }
}

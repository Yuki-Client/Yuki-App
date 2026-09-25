import Foundation
import StoatCore

/// Resolves Stoat content tokens (`<@user>`, `<%role>`, `<#channel>`, `:emoji_id:`) for plain-text contexts
/// such as notifications and reply previews.
@MainActor
public enum MentionFormatter {
    private static let userMention = try! NSRegularExpression(pattern: "<@([0-9A-HJKMNP-TV-Z]{26})>")
    private static let roleMention = try! NSRegularExpression(pattern: "<%([0-9A-HJKMNP-TV-Z]{26})>")
    private static let channelMention = try! NSRegularExpression(pattern: "<#([0-9A-HJKMNP-TV-Z]{26})>")
    private static let customEmoji = try! NSRegularExpression(pattern: ":([0-9A-HJKMNP-TV-Z]{26}):")

    /// - Parameter keepingEmoji: leaves custom emoji as `:ID:` for views that draw them (see `EmojiText`).
    public static func plainText(_ content: String, store: NormalizedStore, serverId: String? = nil, keepingEmoji: Bool = false) -> String {
        var result = UnicodeEmoji.removingPackMarkers(content)
        result = replace(userMention, in: result) { id in
            "@" + store.displayName(userId: id, serverId: serverId)
        }
        result = replace(roleMention, in: result) { id in
            let name = serverId.flatMap { store.servers[$0]?.roles[id]?.name }
                ?? store.servers.values.lazy.compactMap { $0.roles[id]?.name }.first
            return "@" + (name ?? "role")
        }
        result = replace(channelMention, in: result) { id in
            "#" + (store.channels[id]?.name ?? "channel")
        }
        if keepingEmoji { return result }
        result = replace(customEmoji, in: result) { id in
            store.emojis[id].map { ":\($0.name):" } ?? ":emoji:"
        }
        return result
    }

    /// Content for one-line previews: mentions resolved, markdown symbols like `**` removed,
    /// and custom emoji left as `:ID:` for `EmojiText` to draw.
    public static func previewText(_ content: String, store: NormalizedStore, serverId: String? = nil) -> String {
        let text = plainText(content, store: store, serverId: serverId, keepingEmoji: true)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let attributed = try? AttributedString(markdown: text, options: options) else { return text }
        return String(attributed.characters)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, transform: (String) -> String) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var output = ""
        var cursor = 0
        for match in matches {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += transform(ns.substring(with: match.range(at: 1)))
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }
}

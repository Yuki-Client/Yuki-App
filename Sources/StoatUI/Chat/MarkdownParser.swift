import SwiftUI
import StoatCore

enum MarkdownParser {
    private static let userMentionRegex = try! NSRegularExpression(pattern: #"<@([0-9A-HJKMNP-TV-Z]{26})>"#)

    static func mentionedUserIds(in text: String) -> [String] {
        guard text.contains("<@") else { return [] }
        var seen = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        return userMentionRegex.matches(in: text, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: text) else { return nil }
            let id = String(text[idRange])
            return seen.insert(id).inserted ? id : nil
        }
    }

    enum Block {
        case paragraph(String)
        case heading(Int, String)
        case quote(String)
        case code(language: String, code: String)
    }

    enum Token {
        case user(String)
        case role(String)
        case channel(String)
        case everyone(String)
        case emoji(String)
        case timestamp(Date, String?)
        case spoiler(AttributedString)
        /// LaTeX maths, as Stoat's web client renders with KaTeX. `isBlock` is `$$…$$`.
        case math(String, isBlock: Bool)
    }

    enum Piece {
        case styled(AttributedString)
        case token(Token, AttributeContainer)
    }

    private final class BlockBox {
        let blocks: [Block]
        init(_ blocks: [Block]) { self.blocks = blocks }
    }

    nonisolated(unsafe) private static let blockCache: NSCache<NSString, BlockBox> = {
        let cache = NSCache<NSString, BlockBox>()
        cache.countLimit = 1000
        return cache
    }()

    static func blocks(for text: String) -> [Block] {
        if let cached = blockCache.object(forKey: text as NSString) {
            return cached.blocks
        }
        let parsed = parseBlocks(removingImages(from: UnicodeEmoji.removingPackMarkers(text)))
        blockCache.setObject(BlockBox(parsed), forKey: text as NSString)
        return parsed
    }

    /// Matches an inline code span (kept) or markdown image syntax (removed).
    private static let imagePattern = try! NSRegularExpression(pattern: #"(`+[^`\n]*`+)|!\[[^\]\n]*\]\([^)\s]*\)"#)

    /// Stoat for Web renders markdown images as nothing, which bots rely on to attach a GIF without
    /// showing its link.
    static func removingImages(from text: String) -> String {
        guard text.contains("![") else { return text }
        var inFence = false
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                lines.append(line)
                continue
            }
            guard !inFence, line.contains("![") else {
                lines.append(line)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            let stripped = imagePattern.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            lines.append(stripped)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var remaining = Substring(text)

        while let fenceStart = remaining.range(of: "```") {
            appendTextBlocks(String(remaining[..<fenceStart.lowerBound]), to: &blocks)
            let afterFence = remaining[fenceStart.upperBound...]
            guard let fenceEnd = afterFence.range(of: "```") else {
                appendTextBlocks(String(remaining[fenceStart.lowerBound...]), to: &blocks)
                return blocks
            }
            var body = String(afterFence[..<fenceEnd.lowerBound])
            var language = ""
            if let newline = body.firstIndex(of: "\n") {
                let candidate = body[..<newline].trimmingCharacters(in: .whitespaces)
                if !candidate.contains(" "), candidate.count <= 20 {
                    language = candidate
                    body = String(body[body.index(after: newline)...])
                }
            }
            if body.hasSuffix("\n") { body.removeLast() }
            blocks.append(.code(language: language, code: body))
            remaining = afterFence[fenceEnd.upperBound...]
        }
        appendTextBlocks(String(remaining), to: &blocks)
        return blocks
    }

    private static func appendTextBlocks(_ text: String, to blocks: inout [Block]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var paragraph: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(">") {
                flushParagraph()
                var content = line.dropFirst()
                if content.hasPrefix(" ") { content = content.dropFirst() }
                quote.append(String(content))
            } else if let heading = headingLevel(line) {
                flushParagraph()
                flushQuote()
                blocks.append(.heading(heading.level, heading.text))
            } else {
                flushQuote()
                var rendered = line
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    rendered = "• " + line.dropFirst(2)
                }
                paragraph.append(rendered)
            }
        }
        flushParagraph()
        flushQuote()
    }

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        for level in 1...3 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return (level, String(line.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static let tokenPattern = try! NSRegularExpression(
        // The last two groups are LaTeX: `$$…$$`, and `$…$` when it holds something that looks
        // like maths, so prices ("$5 to $10") aren't swallowed.
        pattern: #"<@([0-9A-HJKMNP-TV-Z]{26})>|<%([0-9A-HJKMNP-TV-Z]{26})>|<#([0-9A-HJKMNP-TV-Z]{26})>|:([0-9A-HJKMNP-TV-Z]{26}):|<t:(-?\d{1,13})(?::([tTdDfFR]))?>|\|\|(.+?)\|\||@(everyone|online)\b|(?<!\\)\$\$(\S(?:[^$]*\S)?)\$\$|(?<!\\)\$(\S(?:[^$\n]*\S)?)\$(?!\d)"#
    )
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Splits a paragraph into styled text and tokens. Tokens are swapped for placeholders before
    /// markdown parsing so surrounding styles (bold, italics) still apply to them.
    private final class PieceBox {
        let pieces: [Piece]
        init(_ pieces: [Piece]) { self.pieces = pieces }
    }

    nonisolated(unsafe) private static let inlineCache: NSCache<NSString, PieceBox> = {
        let cache = NSCache<NSString, PieceBox>()
        cache.countLimit = 2000
        return cache
    }()

    private static let emojiRegex = try! NSRegularExpression(pattern: #":([0-9A-HJKMNP-TV-Z]{26}):"#)

    static func emojiIds(in text: String) -> [String] {
        guard text.contains(":") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return emojiRegex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Parsed inline pieces, cached because animated emoji redraw the same text many times a second.
    static func inline(_ source: String) -> [Piece] {
        if let cached = inlineCache.object(forKey: source as NSString) {
            return cached.pieces
        }
        let pieces = parseInline(source)
        inlineCache.setObject(PieceBox(pieces), forKey: source as NSString)
        return pieces
    }

    private static func parseInline(_ source: String) -> [Piece] {
        let ns = source as NSString
        let matches = tokenPattern.matches(in: source, range: NSRange(location: 0, length: ns.length))

        var tokens: [Token] = []
        var prepared = ""
        var cursor = 0
        for match in matches {
            prepared += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length

            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }

            let token: Token?
            if let id = group(1) {
                token = .user(id)
            } else if let id = group(2) {
                token = .role(id)
            } else if let id = group(3) {
                token = .channel(id)
            } else if let id = group(4) {
                token = .emoji(id)
            } else if let raw = group(5), let seconds = Double(raw) {
                token = .timestamp(Date(timeIntervalSince1970: seconds), group(6))
            } else if let content = group(7) {
                token = .spoiler(styled(content))
            } else if let label = group(8) {
                token = .everyone(label)
            } else if let latex = group(9) {
                token = .math(latex, isBlock: true)
            } else if let latex = group(10), latex.contains(where: { "\\{}^_".contains($0) }) {
                token = .math(latex, isBlock: false)
            } else {
                token = nil
            }

            if let token {
                prepared += "\u{27E6}\(tokens.count)\u{27E7}"
                tokens.append(token)
            } else {
                prepared += ns.substring(with: match.range)
            }
        }
        prepared += ns.substring(from: cursor)

        let attributed = styled(prepared)
        guard !tokens.isEmpty else { return [.styled(attributed)] }

        var pieces: [Piece] = []
        var current = attributed[attributed.startIndex..<attributed.endIndex]
        while let open = current.range(of: "\u{27E6}"),
              let close = current[open.upperBound...].range(of: "\u{27E7}") {
            let before = current[current.startIndex..<open.lowerBound]
            if !before.characters.isEmpty {
                pieces.append(.styled(AttributedString(before)))
            }
            let indexText = String(current[open.upperBound..<close.lowerBound].characters)
            if let index = Int(indexText), index < tokens.count {
                let attributes = current[open.lowerBound..<close.upperBound].runs.first?.attributes ?? AttributeContainer()
                pieces.append(.token(tokens[index], attributes))
            }
            current = current[close.upperBound..<current.endIndex]
        }
        if !current.characters.isEmpty {
            pieces.append(.styled(AttributedString(current)))
        }
        return pieces
    }

    static func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let escaped = escapeUnderscoresInURLs(text)
        var attributed = (try? AttributedString(markdown: escaped, options: options)) ?? AttributedString(text)

        guard let linkDetector else { return attributed }
        let plain = String(attributed.characters)
        let nsPlain = plain as NSString
        for match in linkDetector.matches(in: plain, range: NSRange(location: 0, length: nsPlain.length)) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https",
                  let stringRange = Range(match.range, in: plain),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
            if attributed[lower..<upper].runs.contains(where: { $0.link != nil }) { continue }
            attributed[lower..<upper].link = url
        }
        return attributed
    }

    /// Keeps underscores inside bare URLs from being read as italics.
    private static func escapeUnderscoresInURLs(_ text: String) -> String {
        guard text.contains("_"), text.contains("://") else { return text }
        return text
            .components(separatedBy: " ")
            .map { word in
                word.contains("://") && !word.contains("](") ? word.replacingOccurrences(of: "_", with: "\\_") : word
            }
            .joined(separator: " ")
    }

    static func format(date: Date, style: String?) -> String {
        switch style {
        case "t": return date.formatted(date: .omitted, time: .shortened)
        case "T": return date.formatted(date: .omitted, time: .standard)
        case "d": return date.formatted(date: .numeric, time: .omitted)
        case "D": return date.formatted(date: .long, time: .omitted)
        case "F": return date.formatted(date: .complete, time: .shortened)
        case "R": return date.formatted(.relative(presentation: .named))
        default: return date.formatted(date: .long, time: .shortened)
        }
    }

    /// True when the content is only custom or unicode emoji (up to 10), for jumbo rendering.
    static func isEmojiOnly(_ text: String) -> Bool {
        let trimmed = UnicodeEmoji.removingPackMarkers(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300 else { return false }
        let withoutCustom = trimmed.replacingOccurrences(of: #":[0-9A-HJKMNP-TV-Z]{26}:"#, with: "", options: .regularExpression)
        let customCount = (trimmed.count - withoutCustom.count) / 28
        let remaining = withoutCustom.filter { !$0.isWhitespace }
        let unicodeCount = remaining.count
        guard remaining.allSatisfy({ $0.unicodeScalars.first?.properties.isEmojiPresentation == true || ($0.unicodeScalars.count > 1 && $0.unicodeScalars.first?.properties.isEmoji == true) }) else {
            return false
        }
        let total = customCount + unicodeCount
        return total > 0 && total <= 10
    }
}

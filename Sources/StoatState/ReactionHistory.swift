import Foundation

public struct ReactionHistory {
    public struct Usage: Codable, Equatable, Sendable {
        public var count: Int
        public var lastUsed: Date
    }

    public static let defaultReactions = ["👍", "❤️", "😂", "😮", "😢", "🔥"]
    static let usageKey = "yuki.reactionUsage"
    /// The emoji picker's recently used list (see `EmojiPickerSheet`).
    static let pickerRecentsKey = "yuki.recentEmoji"
    /// A use counts half as much after this long, so old favourites give way to new ones.
    static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    private static let maxRemembered = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var usage: [String: Usage] {
        guard let data = defaults.data(forKey: Self.usageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Usage].self, from: data)) ?? [:]
    }

    public func record(_ emoji: String, at date: Date = Date()) {
        var usage = usage
        var entry = usage[emoji] ?? Usage(count: 0, lastUsed: date)
        entry.count += 1
        entry.lastUsed = date
        usage[emoji] = entry
        if usage.count > Self.maxRemembered {
            let kept = usage.sorted { Self.score($0.value, at: date) > Self.score($1.value, at: date) }.prefix(Self.maxRemembered)
            usage = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        defaults.set(try? JSONEncoder().encode(usage), forKey: Self.usageKey)
    }

    /// Most used lately, then recent picker choices, then the defaults.
    public func quickReactions(count: Int = 6, at date: Date = Date(), isAvailable: (String) -> Bool = { _ in true }) -> [String] {
        let used = usage
            .sorted { lhs, rhs in
                let left = Self.score(lhs.value, at: date), right = Self.score(rhs.value, at: date)
                return left == right ? lhs.value.lastUsed > rhs.value.lastUsed : left > right
            }
            .map(\.key)
        let recents = (defaults.string(forKey: Self.pickerRecentsKey) ?? "").split(separator: " ").map(String.init)

        var result: [String] = []
        for emoji in used + recents + Self.defaultReactions where !result.contains(emoji) && isAvailable(emoji) {
            result.append(emoji)
            if result.count == count { break }
        }
        return result
    }

    static func score(_ usage: Usage, at date: Date) -> Double {
        let age = max(0, date.timeIntervalSince(usage.lastUsed))
        return Double(usage.count) * pow(0.5, age / halfLife)
    }
}

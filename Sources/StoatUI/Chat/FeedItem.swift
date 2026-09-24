import Foundation
import StoatCore

enum FeedItem: Identifiable {
    case dateSeparator(Date)
    case unreadDivider
    case message(Message, isContinuation: Bool)

    static let groupingWindow: TimeInterval = 7 * 60

    var id: String {
        switch self {
        case .dateSeparator(let date): "date-\(Int(date.timeIntervalSince1970))"
        case .unreadDivider: "unread-divider"
        case .message(let message, _): message.id
        }
    }

    static func build(
        from messages: [Message],
        unreadMarkerId: String?,
        currentUserId: String?,
        isBlocked: (String) -> Bool
    ) -> [FeedItem] {
        var items: [FeedItem] = []
        var previous: Message?
        var dividerInserted = false
        let calendar = Calendar.current

        for message in messages {
            if isBlocked(message.author) {
                previous = nil
                continue
            }
            let sameDay = previous.map { calendar.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? false
            if !sameDay {
                items.append(.dateSeparator(calendar.startOfDay(for: message.timestamp)))
                previous = nil
            }
            if !dividerInserted, let unreadMarkerId, message.id > unreadMarkerId, message.author != currentUserId {
                items.append(.unreadDivider)
                dividerInserted = true
                previous = nil
            }
            let isContinuation = previous.map { continues($0, with: message) } ?? false
            items.append(.message(message, isContinuation: isContinuation))
            previous = message
        }
        return items
    }

    private static func continues(_ prior: Message, with message: Message) -> Bool {
        prior.author == message.author
            && prior.system == nil && message.system == nil
            && prior.masquerade == message.masquerade
            && prior.webhook == message.webhook
            && (message.replies?.isEmpty ?? true)
            && message.timestamp.timeIntervalSince(prior.timestamp) < groupingWindow
    }
}

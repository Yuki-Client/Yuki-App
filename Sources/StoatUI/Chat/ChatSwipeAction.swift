import SwiftUI

enum ChatSwipeAction: String, CaseIterable, Identifiable {
    case reply
    case members
    case off

    static let storageKey = "yuki.chatSwipe"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply: "Reply"
        case .members: "Members"
        case .off: "Off"
        }
    }

    var explanation: String {
        switch self {
        case .reply: "Swipe a message right to left to reply to it."
        case .members: "Swipe right to left in a server or group chat to see its members."
        case .off: "Swiping right to left in a chat does nothing."
        }
    }
}

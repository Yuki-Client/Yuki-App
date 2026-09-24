import Foundation
import StoatCore

public enum StoatLink: Equatable, Sendable {
    case invite(String)
    case channel(String, messageId: String?)
    case discover
    case user(String)

    private static let webHosts: Set<String> = ["stoat.chat", "app.revolt.chat", "revolt.chat"]
    private static let inviteHosts: Set<String> = ["stt.gg", "rvlt.gg"]

    /// Parses links such as `https://stoat.chat/server/S/channel/C/M`, `/channel/C` (relative links
    /// in bot embeds), `https://stt.gg/code` and `yuki://channel/C/M`. Returns nil for anything else.
    public static func parse(_ url: URL, appHost: String? = URL(string: StoatInstance.appURL)?.host) -> StoatLink? {
        let parts = url.pathComponents.filter { $0 != "/" }

        if url.scheme == "yuki" {
            switch url.host {
            case "invite":
                return parts.first.map { .invite($0) }
            case "discover":
                return .discover
            case "user":
                guard let userId = parts.first, isId(userId) else { return nil }
                return .user(userId)
            case "channel":
                guard let channelId = parts.first, isId(channelId) else { return nil }
                return .channel(channelId, messageId: parts.dropFirst().first.flatMap { isId($0) ? $0 : nil })
            default:
                return nil
            }
        }

        if let host = url.host?.lowercased() {
            if inviteHosts.contains(host) {
                if parts.first == "discover" { return .discover }
                return parts.first.map { .invite($0) }
            }
            guard url.scheme == "https" || url.scheme == "http",
                  webHosts.contains(host) || host == appHost?.lowercased() else { return nil }
        } else if url.scheme != nil || !url.path.hasPrefix("/") {
            // Only scheme-less absolute paths count as relative app links.
            return nil
        }

        if parts.first == "discover" {
            return .discover
        }
        if let index = parts.firstIndex(of: "invite"), index + 1 < parts.count {
            return .invite(parts[index + 1])
        }
        if let index = parts.firstIndex(of: "channel"), index + 1 < parts.count, isId(parts[index + 1]) {
            let messageId = index + 2 < parts.count && isId(parts[index + 2]) ? parts[index + 2] : nil
            return .channel(parts[index + 1], messageId: messageId)
        }
        return nil
    }

    private static func isId(_ value: String) -> Bool {
        value.count == 26 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}

public struct MessageJump: Equatable, Sendable {
    public let channelId: String
    public let messageId: String
    let token = UUID()
}

extension AppStore {
    public func openMessage(_ messageId: String, in channelId: String) {
        guard store.channels[channelId] != nil else {
            showError("You don't have access to that channel.")
            return
        }
        pendingJump = MessageJump(channelId: channelId, messageId: messageId)
        openChannel(channelId)
    }

    public func takePendingJump(for channelId: String) -> String? {
        guard let jump = pendingJump, jump.channelId == channelId else { return nil }
        pendingJump = nil
        return jump.messageId
    }

    /// Opens a parsed in-app link. Invites are left to the caller, which shows a preview first.
    @discardableResult
    public func open(_ link: StoatLink) -> Bool {
        switch link {
        case .invite, .discover, .user:
            return false
        case .channel(let channelId, let messageId):
            guard store.channels[channelId] != nil else {
                showError("You don't have access to that channel.")
                return true
            }
            if let messageId {
                openMessage(messageId, in: channelId)
            } else {
                openChannel(channelId)
            }
            return true
        }
    }
}

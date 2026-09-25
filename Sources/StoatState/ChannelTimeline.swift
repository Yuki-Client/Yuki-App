import Foundation
import Observation
import StoatCore

public struct PendingMessage: Identifiable, Sendable, Hashable {
    public enum State: Sendable, Hashable {
        case sending
        case failed(String)
    }

    public let id: UUID
    /// Idempotency key for the current attempt; replaced when retrying after the server rejected it.
    public var nonce: String
    public let channelId: String
    public let content: String
    public let attachments: [OutgoingAttachment]
    public let replies: [DeltaAPIClient.ReplyIntent]
    public var state: State
    public let createdAt: Date
    public var uploadProgress: [UUID: Double] = [:]
    /// Server IDs of attachments already uploaded, so a retry doesn't upload them again.
    public var uploadedAttachmentIds: [UUID: String] = [:]

    public init(
        id: UUID = UUID(),
        nonce: String,
        channelId: String,
        content: String,
        attachments: [OutgoingAttachment],
        replies: [DeltaAPIClient.ReplyIntent],
        state: State,
        createdAt: Date
    ) {
        self.id = id
        self.nonce = nonce
        self.channelId = channelId
        self.content = content
        self.attachments = attachments
        self.replies = replies
        self.state = state
        self.createdAt = createdAt
    }

    public static func == (lhs: PendingMessage, rhs: PendingMessage) -> Bool {
        lhs.id == rhs.id && lhs.nonce == rhs.nonce && lhs.state == rhs.state && lhs.uploadProgress == rhs.uploadProgress
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct OutgoingAttachment: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case image, video, audio, file
    }

    public let id: UUID
    public let data: Data
    public let filename: String
    public let contentType: String
    public let kind: Kind
    /// A small JPEG for thumbnails: the image itself, or a frame of a video.
    public let preview: Data?
    /// Pixel size, so the message can be laid out at its final size before it's sent.
    public let pixelSize: CGSize?
    public let duration: Double?

    public var isImage: Bool { kind == .image }

    /// Stoat has no spoiler flag on files; clients blur any whose name starts with `SPOILER_`.
    public var isSpoiler: Bool {
        filename.lowercased().hasPrefix(Self.spoilerPrefix.lowercased())
    }

    private static let spoilerPrefix = "SPOILER_"

    public func markedAsSpoiler(_ spoiler: Bool) -> OutgoingAttachment {
        guard spoiler != isSpoiler else { return self }
        let name = spoiler ? Self.spoilerPrefix + filename : String(filename.dropFirst(Self.spoilerPrefix.count))
        return OutgoingAttachment(
            id: id,
            data: data,
            filename: name,
            contentType: contentType,
            kind: kind,
            preview: preview,
            pixelSize: pixelSize,
            duration: duration
        )
    }

    public init(
        id: UUID = UUID(),
        data: Data,
        filename: String,
        contentType: String,
        kind: Kind,
        preview: Data? = nil,
        pixelSize: CGSize? = nil,
        duration: Double? = nil
    ) {
        self.id = id
        self.data = data
        self.filename = filename
        self.contentType = contentType
        self.kind = kind
        self.preview = preview
        self.pixelSize = pixelSize
        self.duration = duration
    }

    public static func == (lhs: OutgoingAttachment, rhs: OutgoingAttachment) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Loaded messages for one channel, kept sorted oldest to newest by ULID.
@Observable
@MainActor
public final class ChannelTimeline {
    public let channelId: String
    public private(set) var messages: [Message] = []
    public var pending: [PendingMessage] = []

    public var hasMoreBefore = true
    public var isLoadingBefore = false
    public var isLoadingLatest = false
    /// Whether the newest page has been fetched since the last (re)connection.
    public var isSynced = false
    /// True after jumping to an older message: the loaded history stops short of the newest messages.
    public var isViewingHistory = false
    /// Newest message of the contiguous older history, where loading newer pages continues from.
    public var historyEndId: String?
    public var isLoadingAfter = false
    public var loadError: String?

    public init(channelId: String) {
        self.channelId = channelId
    }

    public var isEmpty: Bool { messages.isEmpty && pending.isEmpty }

    public func message(id: String) -> Message? {
        guard let index = index(of: id) else { return nil }
        return messages[index]
    }

    private func index(of id: String) -> Int? {
        let position = insertionIndex(for: id)
        guard position < messages.count, messages[position].id == id else { return nil }
        return position
    }

    private func insertionIndex(for id: String) -> Int {
        var low = 0
        var high = messages.count
        while low < high {
            let mid = (low + high) / 2
            if messages[mid].id < id {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    @discardableResult
    public func upsert(_ message: Message) -> Bool {
        if let nonce = message.nonce {
            pending.removeAll { $0.nonce == nonce }
        }
        let position = insertionIndex(for: message.id)
        if position < messages.count, messages[position].id == message.id {
            messages[position] = message
            return false
        }
        messages.insert(message, at: position)
        return true
    }

    public func merge(_ page: [Message]) {
        guard !page.isEmpty else { return }
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let confirmedNonces = Set(page.compactMap(\.nonce))
        for message in page {
            byId[message.id] = message
        }
        messages = byId.values.sorted { $0.id < $1.id }
        if !confirmedNonces.isEmpty {
            pending.removeAll { confirmedNonces.contains($0.nonce) }
        }
    }

    /// Replaces the loaded window, used when a fresh latest page doesn't overlap the cache.
    public func replace(with page: [Message]) {
        messages = page.sorted { $0.id < $1.id }
        let confirmedNonces = Set(page.compactMap(\.nonce))
        pending.removeAll { confirmedNonces.contains($0.nonce) }
    }

    public func update(id: String, _ mutate: (inout Message) -> Void) {
        guard let index = index(of: id) else { return }
        var message = messages[index]
        mutate(&message)
        messages[index] = message
    }

    public func remove(id: String) {
        guard let index = index(of: id) else { return }
        messages.remove(at: index)
    }

    public func remove(ids: Set<String>) {
        messages.removeAll { ids.contains($0.id) }
    }

    public func removeAll(where predicate: (Message) -> Bool) {
        messages.removeAll(where: predicate)
    }

    /// Keeps only the newest messages to bound memory once a channel is no longer on screen.
    public func trim(keepingLast count: Int) {
        guard messages.count > count else { return }
        messages.removeFirst(messages.count - count)
        hasMoreBefore = true
    }

    public var newestMessageId: String? { messages.last?.id }
    public var oldestMessageId: String? { messages.first?.id }
}

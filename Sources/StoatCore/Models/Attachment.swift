import Foundation

public struct Attachment: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let tag: String
    public let filename: String
    public let metadata: FileMetadata
    public let contentType: String
    public let size: Int
    public let deleted: Bool?
    public let reported: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case tag
        case filename
        case metadata
        case contentType = "content_type"
        case size
        case deleted
        case reported
    }

    public init(
        id: String,
        tag: String = "attachments",
        filename: String,
        metadata: FileMetadata = .file,
        contentType: String,
        size: Int,
        deleted: Bool? = nil,
        reported: Bool? = nil
    ) {
        self.id = id
        self.tag = tag
        self.filename = filename
        self.metadata = metadata
        self.contentType = contentType
        self.size = size
        self.deleted = deleted
        self.reported = reported
    }

    /// Preview URL, resized and converted by Autumn where applicable.
    public func downloadURL(autumnBaseURL: String = StoatInstance.autumnURL) -> URL? {
        URL(string: "\(autumnBaseURL)/\(tag)/\(id)")
    }

    public func originalURL(autumnBaseURL: String = StoatInstance.autumnURL) -> URL? {
        URL(string: "\(autumnBaseURL)/\(tag)/\(id)/original")
    }

    public var isImage: Bool {
        if case .image = metadata { return true }
        return contentType.hasPrefix("image/")
    }

    public var isVideo: Bool {
        if case .video = metadata { return true }
        return contentType.hasPrefix("video/")
    }

    public var isAudio: Bool {
        if case .audio = metadata { return true }
        return contentType.hasPrefix("audio/")
    }

    public var isSpoiler: Bool {
        filename.lowercased().hasPrefix("spoiler_")
    }

    public var dimensions: CGSize? {
        switch metadata {
        case .image(let width, let height), .video(let width, let height):
            guard width > 0, height > 0 else { return nil }
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        default:
            return nil
        }
    }
}

public enum FileMetadata: Codable, Sendable, Hashable {
    case file
    case text
    case image(width: Int, height: Int)
    case video(width: Int, height: Int)
    case audio

    private enum TagKey: String, CodingKey {
        case type
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Image":
            self = .image(
                width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 0,
                height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
            )
        case "Video":
            self = .video(
                width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 0,
                height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
            )
        case "Audio":
            self = .audio
        case "Text":
            self = .text
        default:
            self = .file
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .image(let width, let height):
            try container.encode("Image", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case .video(let width, let height):
            try container.encode("Video", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case .audio:
            try container.encode("Audio", forKey: .type)
        case .text:
            try container.encode("Text", forKey: .type)
        case .file:
            try container.encode("File", forKey: .type)
        }
    }
}

/// Decodes an array while skipping elements that fail to decode, so one unexpected
/// object from the server cannot wipe out an entire payload.
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    private struct Skip: Decodable {}

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        if let count = container.count {
            result.reserveCapacity(count)
        }
        while !container.isAtEnd {
            do {
                result.append(try container.decode(Element.self))
            } catch {
                #if DEBUG
                print("[LossyArray] Skipped \(Element.self): \(error)")
                #endif
                _ = try? container.decode(Skip.self)
            }
        }
        elements = result
    }
}

extension KeyedDecodingContainer {
    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T]? {
        try decodeIfPresent(LossyArray<T>.self, forKey: key)?.elements
    }
}

import Foundation

/// Stoat's GIF search service (Gifbox), which fronts Tenor and needs the user's session.
public actor GifboxClient {
    public static let shared = GifboxClient()

    public static let baseURL = URL(string: "https://api.gifbox.me")!

    public struct Category: Decodable, Sendable, Hashable {
        public let title: String
        public let image: String
    }

    public struct Media: Decodable, Sendable, Hashable {
        public let url: String
        public let dimensions: [Int]?
    }

    public struct Result: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        /// Page URL that's sent as the message; Stoat embeds it as a GIF.
        public let url: String
        public let mediaFormats: [String: Media]

        enum CodingKeys: String, CodingKey {
            case id, url
            case mediaFormats = "media_formats"
        }

        public var aspectRatio: CGFloat {
            for media in mediaFormats.values {
                if let dimensions = media.dimensions, dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 {
                    return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
                }
            }
            return 1
        }

        public var posterURL: URL? {
            for key in ["preview", "tinygifpreview", "gifpreview"] {
                if let raw = mediaFormats[key]?.url, let url = URL(string: raw) {
                    return url
                }
            }
            return nil
        }

        /// A small looping MP4 for previews. iOS can't play the WebM that Stoat for Web uses.
        public var previewVideoURL: URL? {
            for key in ["tinymp4", "nanomp4", "mp4", "loopedmp4"] {
                if let raw = mediaFormats[key]?.url, let url = URL(string: raw) {
                    return url
                }
            }
            // Older Tenor-backed results only list WebM; Tenor serves MP4 under the same ID.
            for key in ["tinywebm", "webm"] {
                if let raw = mediaFormats[key]?.url, let url = GifboxClient.tenorURL(raw, formatCode: "AAAPo", fileExtension: "mp4") {
                    return url
                }
            }
            return nil
        }
    }

    public struct Page: Decodable, Sendable {
        public let results: [Result]
        public let next: String?
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func categories(token: String?, locale: String = GifboxClient.locale) async throws -> [Category] {
        try await get("categories", query: [URLQueryItem(name: "locale", value: locale)], token: token)
    }

    public func trending(token: String?, position: String? = nil, locale: String = GifboxClient.locale) async throws -> Page {
        var query = [URLQueryItem(name: "locale", value: locale), URLQueryItem(name: "limit", value: "30")]
        if let position { query.append(URLQueryItem(name: "position", value: position)) }
        return try await get("trending", query: query, token: token)
    }

    public func search(_ text: String, token: String?, position: String? = nil, locale: String = GifboxClient.locale) async throws -> Page {
        var query = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "query", value: text),
            URLQueryItem(name: "limit", value: "30")
        ]
        if let position { query.append(URLQueryItem(name: "position", value: position)) }
        return try await get("search", query: query, token: token)
    }

    public static var locale: String {
        let identifier = Locale.current.identifier.replacingOccurrences(of: "-", with: "_")
        return identifier.isEmpty ? "en_US" : identifier
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], token: String?) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Session-Token")
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400 else {
                let type = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
                throw status == 401 ? StoatAPIError.unauthorized : StoatAPIError.server(statusCode: status, type: type)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw StoatAPIError.decodingError(error.localizedDescription)
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw StoatAPIError.network(error.localizedDescription)
        }
    }

    /// Rewrites a Tenor media URL (`https://media.tenor.com/{id}{code}/{name}.{ext}`) to another format.
    public nonisolated static func tenorURL(_ raw: String, formatCode: String, fileExtension: String) -> URL? {
        guard var components = URLComponents(string: raw),
              let host = components.host, host.hasSuffix("tenor.com") else { return nil }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[parts.count - 2].count > 5 else { return nil }
        let token = parts[parts.count - 2]
        parts[parts.count - 2] = String(token.dropLast(5)) + formatCode
        let name = (parts[parts.count - 1] as NSString).deletingPathExtension
        parts[parts.count - 1] = "\(name).\(fileExtension)"
        components.path = "/" + parts.joined(separator: "/")
        return components.url
    }
}

extension Embed {
    private static let gifHosts: Set<String> = ["tenor.com", "giphy.com", "gifbox.me"]

    /// GIF embeds are shown as looping media without the link card, like Stoat for Web.
    public var isGIF: Bool {
        if special?.type == "GIF" { return true }
        let raw: String?
        switch type {
        case "Website": raw = originalUrl ?? url
        case "Image", "Video": raw = url
        default: raw = nil
        }
        guard let raw, let host = URL(string: raw)?.host?.lowercased() else { return false }
        return Self.gifHosts.contains(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }
}

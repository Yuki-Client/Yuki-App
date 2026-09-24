import Foundation
import UniformTypeIdentifiers

public actor AutumnClient {
    public static let shared = AutumnClient()
    private let urlSession: URLSession

    public enum Tag: String, Sendable {
        case attachments
        case avatars
        case backgrounds
        case icons
        case banners
        case emojis

        var fallbackLimit: Int {
            switch self {
            case .attachments: return 20_000_000
            case .avatars: return 4_000_000
            case .backgrounds, .banners: return 6_000_000
            case .icons: return 2_500_000
            case .emojis: return 500_000
            }
        }
    }

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func upload(
        data: Data,
        filename: String,
        contentType: String? = nil,
        tag: Tag = .attachments,
        token: String?,
        sizeLimit: Int? = nil,
        autumnURL: String = StoatInstance.autumnURL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let limit = sizeLimit ?? tag.fallbackLimit
        guard data.count <= limit else {
            throw StoatAPIError.fileTooLarge(limit: limit)
        }
        guard let url = URL(string: "\(autumnURL)/\(tag.rawValue)") else {
            throw StoatAPIError.invalidURL
        }

        let safeName = Self.sanitize(filename)
        let mimeType = contentType ?? Self.mimeType(for: safeName)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Yuki-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Session-Token")
        }

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let responseData: Data
        let response: URLResponse
        do {
            let delegate = progress.map(UploadProgressDelegate.init)
            (responseData, response) = try await urlSession.upload(for: request, from: body, delegate: delegate)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw StoatAPIError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoatAPIError.unknown
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            struct ErrorBody: Decodable { let type: String? }
            let type = try? JSONDecoder().decode(ErrorBody.self, from: responseData).type
            if httpResponse.statusCode == 413 || type == "FileTooLarge" {
                throw StoatAPIError.fileTooLarge(limit: limit)
            }
            if httpResponse.statusCode == 401 {
                throw StoatAPIError.unauthorized
            }
            throw StoatAPIError.server(statusCode: httpResponse.statusCode, type: type)
        }

        struct AutumnResponse: Decodable {
            let id: String
        }

        do {
            return try JSONDecoder().decode(AutumnResponse.self, from: responseData).id
        } catch {
            throw StoatAPIError.decodingError("Autumn response: \(error)")
        }
    }

    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    static func sanitize(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "file" : cleaned
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

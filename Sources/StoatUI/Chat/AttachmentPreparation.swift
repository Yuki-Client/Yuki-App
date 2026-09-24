import SwiftUI
import AVFoundation
import CoreTransferable
import ImageIO
import UniformTypeIdentifiers
import UIKit
import StoatState

/// A video picked from Photos, copied to a temporary file instead of being loaded into memory.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

enum AttachmentPreparationError: LocalizedError {
    case unreadable
    case videoTooLarge(limit: Int)
    case tooLarge(limit: Int)

    var errorDescription: String? {
        let megabytes = { (limit: Int) in ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file) }
        switch self {
        case .unreadable: return "That file couldn't be read."
        case .videoTooLarge(let limit): return "That video is too long to send, even compressed. Stoat allows up to \(megabytes(limit))."
        case .tooLarge(let limit): return "That file is too large. Stoat allows up to \(megabytes(limit))."
        }
    }
}

/// Images become JPEG (or stay GIF/PNG) and videos H.264 MP4 small enough for Stoat. Runs off
/// the main actor.
enum AttachmentPreparation {
    private static let previewPixels: CGFloat = 600

    nonisolated static func image(data: Data, type: UTType, limit: Int) async throws -> OutgoingAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw AttachmentPreparationError.unreadable }
        let pixelSize = Self.pixelSize(of: source)
        let preview = Self.previewJPEG(from: source)

        // GIFs keep their animation and PNGs their transparency, when they fit.
        if type.conforms(to: .gif), data.count <= limit {
            return OutgoingAttachment(data: data, filename: "image.gif", contentType: "image/gif", kind: .image, preview: preview, pixelSize: pixelSize)
        }
        if type.conforms(to: .png), data.count <= limit {
            return OutgoingAttachment(data: data, filename: "image.png", contentType: "image/png", kind: .image, preview: preview, pixelSize: pixelSize)
        }

        // HEIC and other formats aren't widely viewable, so convert to JPEG, shrinking if needed.
        for (maxPixels, quality) in [(CGFloat(0), 0.9), (4096, 0.85), (2560, 0.8), (1600, 0.75)] {
            guard let jpeg = Self.jpeg(from: source, maxPixels: maxPixels, quality: quality) else { continue }
            if jpeg.data.count <= limit {
                return OutgoingAttachment(data: jpeg.data, filename: "image.jpg", contentType: "image/jpeg", kind: .image, preview: preview, pixelSize: jpeg.size)
            }
        }
        throw AttachmentPreparationError.tooLarge(limit: limit)
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        // Orientations 5-8 are rotated a quarter turn.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    private static func previewJPEG(from source: CGImageSource) -> Data? {
        jpeg(from: source, maxPixels: previewPixels, quality: 0.7)?.data
    }

    /// Re-encodes as JPEG, upright, no larger than `maxPixels` on the long side (0 keeps full size).
    private static func jpeg(from source: CGImageSource, maxPixels: CGFloat, quality: Double) -> (data: Data, size: CGSize)? {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if maxPixels > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixels
        } else if let size = pixelSize(of: source) {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(size.width, size.height)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodeJPEG(image, quality: quality).map { ($0, CGSize(width: image.width, height: image.height)) }
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// `progress` reports compression (0...1). The source file is deleted afterwards.
    nonisolated static func video(at url: URL, limit: Int, progress: @escaping @Sendable (Double) -> Void) async throws -> OutgoingAttachment {
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
        var pixelSize: CGSize?
        var isH264 = false
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let natural = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                let rotated = natural.applying(transform)
                pixelSize = CGSize(width: abs(rotated.width), height: abs(rotated.height))
            }
            if let formats = try? await track.load(.formatDescriptions) {
                isH264 = formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: previewPixels, height: previewPixels)
        let preview = (try? await generator.image(at: .zero).image).flatMap { encodeJPEG($0, quality: 0.7) }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        if isH264, ["mp4", "m4v"].contains(url.pathExtension.lowercased()), fileSize <= limit {
            let data = try Data(contentsOf: url)
            progress(1)
            return OutgoingAttachment(data: data, filename: "video.mp4", contentType: "video/mp4", kind: .video, preview: preview, pixelSize: pixelSize, duration: duration)
        }

        // Try the sharpest preset whose estimate fits, stepping down if the result is still too big.
        let presets = [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480]
        for (index, preset) in presets.enumerated() {
            let isLast = index == presets.count - 1
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            if !isLast, let estimate = try? await session.estimatedOutputFileLengthInBytes, estimate > Int64(Double(limit) * 0.95) {
                continue
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            session.outputURL = output
            session.outputFileType = .mp4
            // Moves the index to the start of the file so it can play while downloading.
            session.shouldOptimizeForNetworkUse = true
            try await export(session, progress: progress)

            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            guard size <= limit else { continue }
            let data = try Data(contentsOf: output)
            return OutgoingAttachment(data: data, filename: "video.mp4", contentType: "video/mp4", kind: .video, preview: preview, pixelSize: pixelSize, duration: duration)
        }
        throw AttachmentPreparationError.videoTooLarge(limit: limit)
    }

    private nonisolated static func export(_ session: AVAssetExportSession, progress: @escaping @Sendable (Double) -> Void) async throws {
        nonisolated(unsafe) let session = session
        let polling = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { polling.cancel() }
        try await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            session.cancelExport()
        }
        try Task.checkCancellation()
        if session.status != .completed {
            throw session.error ?? AttachmentPreparationError.unreadable
        }
        progress(1)
    }

    nonisolated static func file(at url: URL, limit: Int) async throws -> OutgoingAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension)

        // Photos and videos picked from Files get the same treatment as ones from Photos.
        if let type, type.conforms(to: .image), let data = try? Data(contentsOf: url) {
            return try await image(data: data, type: type, limit: limit)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw AttachmentPreparationError.tooLarge(limit: limit) }
        guard let data = try? Data(contentsOf: url) else { throw AttachmentPreparationError.unreadable }
        let kind: OutgoingAttachment.Kind = type?.conforms(to: .audio) == true ? .audio : type?.conforms(to: .movie) == true ? .video : .file
        return OutgoingAttachment(
            data: data,
            filename: url.lastPathComponent,
            contentType: type?.preferredMIMEType ?? "application/octet-stream",
            kind: kind
        )
    }
}

/// Decodes attachment previews once, so typing in the composer doesn't decode them again.
@MainActor
enum AttachmentPreviewCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    static func image(for key: String, data: Data?) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

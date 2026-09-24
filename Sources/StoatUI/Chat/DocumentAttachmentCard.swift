import SwiftUI
import QuickLook
import StoatCore

public struct DocumentAttachmentCard: View {
    public let attachment: Attachment
    @State private var previewURL: URL?
    @State private var isDownloading = false
    @State private var downloadFailed = false

    public init(attachment: Attachment) {
        self.attachment = attachment
    }

    public var body: some View {
        Button {
            Task { await open() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(YukiTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(YukiTheme.accent.opacity(0.15)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.filename)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(downloadFailed ? "Download failed. Tap to retry." : ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(downloadFailed ? .red : .secondary)
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(YukiTheme.accent)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(YukiTheme.cardSurface))
            .frame(maxWidth: 340)
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .quickLookPreview($previewURL)
        .accessibilityLabel("File: \(attachment.filename), \(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))")
        .accessibilityHint("Double tap to open")
    }

    private func open() async {
        guard let remote = attachment.originalURL() else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("attachments/\(attachment.id)", isDirectory: true)
        let destination = directory.appendingPathComponent(attachment.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            previewURL = destination
            return
        }

        isDownloading = true
        downloadFailed = false
        defer { isDownloading = false }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            previewURL = destination
        } catch {
            downloadFailed = true
        }
    }

    private var iconName: String {
        switch (attachment.filename as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "zip", "tar", "gz", "rar", "7z": return "doc.zipper"
        case "swift", "py", "rs", "js", "ts", "json", "html", "css", "c", "cpp", "go", "java", "kt": return "chevron.left.forwardslash.chevron.right"
        case "csv", "xlsx", "xls", "numbers": return "tablecells.fill"
        case "txt", "md", "log": return "doc.text.fill"
        case "mp3", "wav", "m4a", "ogg", "flac": return "waveform"
        case "mp4", "mov", "mkv", "webm": return "film.fill"
        default: return "doc.fill"
        }
    }
}

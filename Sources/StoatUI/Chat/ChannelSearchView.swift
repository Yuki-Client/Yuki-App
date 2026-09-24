import SwiftUI
import StoatCore
import StoatState

public struct ChannelSearchView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let channelId: String
    let channelName: String
    let onJumpToMessage: (String) -> Void

    @State private var query = ""
    @State private var results: [Message] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var hasSearched = false

    public init(channelId: String, channelName: String, onJumpToMessage: @escaping (String) -> Void) {
        self.channelId = channelId
        self.channelName = channelName
        self.onJumpToMessage = onJumpToMessage
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    ContentUnavailableView("Search failed", systemImage: "exclamationmark.magnifyingglass", description: Text(errorText))
                } else if !hasSearched {
                    ContentUnavailableView("Search \(channelName)", systemImage: "text.magnifyingglass", description: Text("Find messages by keyword."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { message in
                        Button {
                            dismiss()
                            onJumpToMessage(message.id)
                        } label: {
                            MessageResultCard(message: message, highlight: query)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search messages")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .task(id: query) {
                guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await search()
            }
            .background(YukiTheme.systemBackground)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorText = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            results = try await appStore.searchMessages(channelId: channelId, query: trimmed)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct MessageResultCard: View {
    @Environment(AppStore.self) private var appStore
    let message: Message
    var highlight: String?

    private var serverId: String? {
        appStore.store.channels[message.channel]?.server
    }

    private var authorName: String {
        message.masquerade?.name ?? message.webhook?.name ?? appStore.store.displayName(userId: message.author, serverId: serverId)
    }

    /// Pictures to show with the message: image attachments, then images from link previews
    /// (a linked GIF, for example).
    private var thumbnails: [URL] {
        var urls: [URL] = []
        for attachment in message.attachments ?? [] where attachment.isImage {
            if let url = attachment.downloadURL() { urls.append(url) }
        }
        for embed in message.embeds ?? [] {
            if embed.type == "Image", let raw = embed.url, let url = Embed.proxiedURL(raw) {
                // A linked image or GIF: the embed's own address is the picture.
                urls.append(url)
            } else if let media = embed.image, let url = Embed.proxiedURL(media.url) {
                urls.append(url)
            } else if let media = embed.media, let url = media.downloadURL() {
                urls.append(url)
            }
        }
        var seen = Set<URL>()
        return Array(urls.filter { seen.insert($0).inserted }.prefix(3))
    }

    private var otherAttachmentCount: Int? {
        let count = (message.attachments ?? []).filter { !$0.isImage }.count
        return count > 0 ? count : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MessageAuthorAvatar(message: message, serverId: serverId, name: authorName, size: 24)
                Text(authorName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(MessageRowView.timestampText(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let content = message.content, !content.isEmpty {
                Group {
                    if let highlight, !highlight.isEmpty {
                        Text(highlighted(MentionFormatter.plainText(content, store: appStore.store, serverId: serverId)))
                    } else {
                        EmojiText(text: MentionFormatter.previewText(content, store: appStore.store, serverId: serverId), emojiSize: 16)
                    }
                }
                .font(.subheadline)
                .lineLimit(4)
            }
            if !thumbnails.isEmpty {
                HStack(spacing: 6) {
                    ForEach(thumbnails, id: \.self) { url in
                        RemoteImage(url: url, maxPixelSize: 240, animates: true) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { _ in
                            YukiTheme.cardSurface
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .accessibilityHidden(true)
            }
            if let other = otherAttachmentCount, other > 0 {
                Label(other == 1 ? "1 attachment" : "\(other) attachments", systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(YukiTheme.accent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(YukiTheme.cardSurface))
        .accessibilityElement(children: .combine)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let highlight, !highlight.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: highlight, options: .caseInsensitive) {
            attributed[range].foregroundColor = YukiTheme.accent
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            searchStart = range.upperBound
        }
        return attributed
    }
}

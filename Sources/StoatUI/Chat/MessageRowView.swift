import SwiftUI
import StoatCore
import StoatState
import UIKit

public enum MessageAction {
    case reply
    case react(String)
    case openEmojiPicker
    case edit
    case delete
    case togglePin
    case report
    case jumpTo(String)
    case openUser(String)
    case markUnread
    case showActions
    case showReactions(String?)
}

public struct MessageRowView: View {
    public let message: Message
    public let serverId: String?
    /// Hides the avatar and name when the previous message is from the same author shortly before.
    public var isContinuation = false
    public var isHighlighted = false
    public var permissions: Permission = []
    public var onAction: (MessageAction) -> Void

    @Environment(AppStore.self) private var appStore
    @State private var lightboxAttachment: Attachment?
    @State private var revealedSpoilers: Set<String> = []
    @AppStorage(ChatSwipeAction.storageKey) private var swipeAction: ChatSwipeAction = .reply
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeArmed = false

    private static let replySwipeThreshold: CGFloat = 60

    public init(
        message: Message,
        serverId: String?,
        isContinuation: Bool = false,
        isHighlighted: Bool = false,
        permissions: Permission = [],
        onAction: @escaping (MessageAction) -> Void
    ) {
        self.message = message
        self.serverId = serverId
        self.isContinuation = isContinuation
        self.isHighlighted = isHighlighted
        self.permissions = permissions
        self.onAction = onAction
    }

    private var store: NormalizedStore { appStore.store }
    private var currentUserId: String? { store.currentUserId }
    private var isOwn: Bool { message.author == currentUserId }

    private var author: User? { store.users[message.author] }

    private var authorName: String {
        if let name = message.masquerade?.name { return name }
        if let webhook = message.webhook { return webhook.name }
        return store.displayName(userId: message.author, serverId: serverId)
    }

    private var authorPaint: AnyShapeStyle? {
        if let colour = message.masquerade?.colour { return .stoatPaint(colour) }
        guard let serverId else { return nil }
        return .stoatPaint(store.memberRoleColor(userId: message.author, in: serverId))
    }

    /// A message that's just a GIF link shows only the GIF, like Stoat for Web.
    private var isOnlyGIF: Bool {
        guard let embeds = message.embeds, embeds.count == 1, embeds[0].isGIF,
              let content = message.content else { return false }
        let withoutLinks = content.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        return withoutLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mentionsMe: Bool {
        guard let currentUserId else { return false }
        if message.mentions?.contains(currentUserId) == true { return true }
        if let serverId, let roles = message.roleMentions {
            let myRoles = Set(store.member(userId: currentUserId, in: serverId)?.roles ?? [])
            return roles.contains { myRoles.contains($0) }
        }
        return false
    }

    public var body: some View {
        if let system = message.system {
            SystemMessageRow(message: message, system: system, serverId: serverId)
        } else {
            standardBody
        }
    }

    private var canSwipeToReply: Bool {
        swipeAction == .reply && permissions.contains(.sendMessage)
    }

    private var standardBody: some View {
        rowContent
            .contentShape(Rectangle())
            .offset(x: swipeOffset)
            .overlay(alignment: .trailing) {
                if swipeOffset < 0 {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(swipeArmed ? YukiTheme.accent : .secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(YukiTheme.cardSurface))
                        .scaleEffect(swipeArmed ? 1.1 : 0.9)
                        .opacity(min(1, Double(-swipeOffset / Self.replySwipeThreshold)))
                        .padding(.trailing, 12)
                        .accessibilityHidden(true)
                }
            }
            .simultaneousGesture(replySwipe, including: canSwipeToReply ? .all : .subviews)
            // A long press opens a sheet rather than a context menu: in the flipped chat list, the
            // context menu's lift and dismiss animations drew the message upside down.
            .onLongPressGesture(minimumDuration: 0.35) {
                YukiHaptics.impact(.medium)
                onAction(.showActions)
            }
            .fullScreenCover(item: $lightboxAttachment) { attachment in
                MediaLightboxView(attachment: attachment)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityActions {
                Button("More actions") { onAction(.showActions) }
                if permissions.contains(.sendMessage) {
                    Button("Reply") { onAction(.reply) }
                }
                if permissions.contains(.react) {
                    Button("Add reaction") { onAction(.openEmojiPicker) }
                }
                if !message.reactions.isEmpty {
                    Button("View reactions") { onAction(.showReactions(nil)) }
                }
                if isOwn {
                    Button("Edit") { onAction(.edit) }
                }
                if isOwn || permissions.contains(.manageMessages) {
                    Button("Delete") { onAction(.delete) }
                }
            }
    }

    private var replySwipe: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let horizontal = value.translation.width
                // Only start when the drag is clearly sideways, so scrolling isn't disturbed.
                if swipeOffset == 0 {
                    guard horizontal < 0, abs(horizontal) > abs(value.translation.height) * 1.8 else { return }
                }
                let pulled = min(horizontal, 0)
                swipeOffset = pulled > -Self.replySwipeThreshold ? pulled : -Self.replySwipeThreshold + (pulled + Self.replySwipeThreshold) * 0.3
                let armed = pulled <= -Self.replySwipeThreshold
                if armed != swipeArmed {
                    swipeArmed = armed
                    if armed { YukiHaptics.impact(.light) }
                }
            }
            .onEnded { _ in
                if swipeArmed {
                    onAction(.reply)
                }
                swipeArmed = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    swipeOffset = 0
                }
            }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let replies = message.replies, !replies.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(replies, id: \.self) { replyId in
                        ReplyPreviewView(channelId: message.channel, messageId: replyId, serverId: serverId) {
                            onAction(.jumpTo(replyId))
                        }
                    }
                }
                .padding(.leading, 50)
            }

            HStack(alignment: .top, spacing: 12) {
                if isContinuation {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.clear)
                        .frame(width: 38, alignment: .trailing)
                        .padding(.top, 4)
                } else {
                    Button {
                        onAction(.openUser(message.author))
                    } label: {
                        avatar
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View profile of \(authorName)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !isContinuation {
                        header
                    }

                    if let content = message.content, !content.isEmpty, !isOnlyGIF, !MarkdownParser.blocks(for: content).isEmpty {
                        YukiMarkdownView(content, serverId: serverId)
                    }

                    if let attachments = message.attachments, !attachments.isEmpty {
                        ForEach(attachments) { attachment in
                            attachmentView(attachment)
                        }
                    }

                    if let embeds = message.embeds?.filter({ !$0.isEmpty }), !embeds.isEmpty {
                        ForEach(Array(embeds.enumerated()), id: \.offset) { _, embed in
                            EmbedView(embed: embed, serverId: serverId) { url in TopPresenter.playVideo(url) } onOpenImage: { attachment in
                                lightboxAttachment = attachment
                            }
                        }
                    }

                    if !message.reactions.isEmpty || !(message.interactions?.reactions?.isEmpty ?? true) {
                        reactionsView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isContinuation ? 1 : 8)
        .padding(.bottom, 2)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        MessageAuthorAvatar(message: message, serverId: serverId, name: authorName, size: 38)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                onAction(.openUser(message.author))
            } label: {
                Text(authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(authorPaint ?? AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if message.masquerade == nil, message.webhook == nil,
               let pronouns = serverId.flatMap({ store.member(userId: message.author, in: $0)?.pronouns }) ?? author?.pronouns,
               !pronouns.isEmpty {
                Text(pronouns)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if message.webhook != nil || author?.bot != nil {
                BotTagView()
            }
            if message.masquerade != nil, message.webhook == nil {
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Masquerade")
            }
            if author?.privileged == true {
                StaffTagView()
            }

            Text(MessageRowView.timestampText(message.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)

            if message.edited != nil {
                Text("(edited)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.yellow.opacity(0.8))
                    .accessibilityLabel("Pinned")
            }
        }
    }

    static func timestampText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday at " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHighlighted {
            Rectangle().fill(YukiTheme.accent.opacity(0.18))
        } else if mentionsMe {
            HStack(spacing: 0) {
                Rectangle().fill(Color.orange).frame(width: 3)
                Rectangle().fill(Color.orange.opacity(0.08))
            }
        } else {
            Color.clear
        }
    }

    private var accessibilityDescription: String {
        var parts = [authorName]
        if let content = message.content, !content.isEmpty {
            parts.append(MentionFormatter.plainText(content, store: store, serverId: serverId))
        }
        if let count = message.attachments?.count, count > 0 {
            parts.append(count == 1 ? "1 attachment" : "\(count) attachments")
        }
        parts.append(MessageRowView.timestampText(message.timestamp))
        if message.edited != nil { parts.append("edited") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func attachmentView(_ attachment: Attachment) -> some View {
        if attachment.isImage {
            imageAttachment(attachment)
        } else if attachment.isVideo {
            videoAttachment(attachment)
        } else if attachment.isAudio {
            AudioAttachmentCard(attachment: attachment)
        } else {
            DocumentAttachmentCard(attachment: attachment)
        }
    }

    private func fittedSize(_ size: CGSize?, maxWidth: CGFloat = 280, maxHeight: CGFloat = 320) -> CGSize {
        AttachmentLayout.fittedSize(size, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    /// The preview of an attachment this device just uploaded, shown until the uploaded copy loads.
    private func localPreview(_ attachment: Attachment) -> UIImage? {
        guard let data = appStore.localAttachmentPreviews[attachment.id] else { return nil }
        return AttachmentPreviewCache.image(for: attachment.id, data: data)
    }

    private func imageAttachment(_ attachment: Attachment) -> some View {
        let frame = fittedSize(attachment.dimensions)
        let isHidden = attachment.isSpoiler && !revealedSpoilers.contains(attachment.id)
        return RemoteImage(url: attachment.downloadURL(), maxPixelSize: 900, animates: true) { image in
            image.resizable().scaledToFill()
        } placeholder: { failed in
            if let preview = localPreview(attachment) {
                Image(uiImage: preview).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(YukiTheme.cardSurface)
                    if failed {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .blur(radius: isHidden ? 24 : 0)
        .overlay {
            if isHidden {
                Text("SPOILER")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isHidden {
                revealedSpoilers.insert(attachment.id)
            } else {
                lightboxAttachment = attachment
            }
        }
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(isHidden ? "Spoiler image" : "Image \(attachment.filename)")
    }

    private func videoAttachment(_ attachment: Attachment) -> some View {
        let frame = fittedSize(attachment.dimensions, maxHeight: 240)
        return Button {
            if let url = attachment.originalURL() { TopPresenter.playVideo(url) }
        } label: {
            ZStack {
                RemoteImage(url: attachment.downloadURL(), maxPixelSize: 900) { image in
                    image.resizable().scaledToFill()
                } placeholder: { _ in
                    if let preview = localPreview(attachment) {
                        Image(uiImage: preview).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(YukiTheme.cardSurface)
                    }
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video \(attachment.filename)")
    }

    private var reactionsView: some View {
        let restricted = message.interactions?.reactions ?? []
        let keys = restricted + message.reactions.keys
            .filter { !restricted.contains($0) }
            .sorted { (message.reactions[$0]?.count ?? 0, $1) > (message.reactions[$1]?.count ?? 0, $0) }

        return FlowLayout(spacing: 6) {
            ForEach(keys, id: \.self) { emoji in
                let users = message.reactions[emoji] ?? []
                let hasReacted = currentUserId.map { users.contains($0) } ?? false
                ReactionChip(
                    emoji: emoji,
                    count: users.count,
                    label: reactionLabel(emoji),
                    hasReacted: hasReacted,
                    canToggle: permissions.contains(.react) || hasReacted,
                    onToggle: { onAction(.react(emoji)) },
                    onShowReactions: { onAction(.showReactions(emoji)) }
                )
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if permissions.contains(.react), message.interactions?.restrictReactions != true {
                Button {
                    onAction(.openEmojiPicker)
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(YukiTheme.cardSurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add reaction")
            }
        }
        .padding(.top, 2)
        .animation(YukiMotion.transition(reduceMotion: reduceMotion, enabled: animationsEnabled), value: keys)
    }

    private func reactionLabel(_ emoji: String) -> String {
        if Emoji.isCustomEmojiId(emoji) {
            return store.emojis[emoji].map { ":\($0.name):" } ?? "Custom emoji"
        }
        return emoji
    }
}

private struct ReactionChip: View {
    let emoji: String
    let count: Int
    let label: String
    let hasReacted: Bool
    let canToggle: Bool
    let onToggle: () -> Void
    let onShowReactions: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ReactionEmojiView(emoji: emoji, size: 16)
            Text("\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundColor(hasReacted ? YukiTheme.accent : .secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(hasReacted ? YukiTheme.accent.opacity(0.18) : YukiTheme.cardSurface))
        .overlay(Capsule().stroke(hasReacted ? YukiTheme.accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture {
            if canToggle { onToggle() }
        }
        // Holding a reaction shows who reacted, instead of the message's actions.
        .onLongPressGesture(minimumDuration: 0.35) {
            YukiHaptics.impact(.medium)
            onShowReactions()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityHint(canToggle ? (hasReacted ? "Double tap to remove your reaction" : "Double tap to react") : "")
        .accessibilityAddTraits(hasReacted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if canToggle { onToggle() } }
        .accessibilityAction(named: "View who reacted", onShowReactions)
    }
}

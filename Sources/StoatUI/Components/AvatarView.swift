import SwiftUI
import StoatCore

public struct AvatarView: View {
    public let avatar: Attachment?
    public let fallbackText: String
    public let size: CGFloat
    /// When set and there is no uploaded avatar, Stoat's generated default avatar is used.
    public var userId: String?
    public var isRounded = true

    public init(avatar: Attachment?, fallbackText: String, size: CGFloat = 40, userId: String? = nil, isRounded: Bool = true) {
        self.avatar = avatar
        self.fallbackText = fallbackText
        self.size = size
        self.userId = userId
        self.isRounded = isRounded
    }

    private var url: URL? {
        if let avatar {
            return avatar.downloadURL()
        }
        if let userId {
            return URL(string: "\(StoatInstance.endpoints.api)/users/\(userId)/default_avatar")
        }
        return nil
    }

    public var body: some View {
        RemoteImage(url: url, maxPixelSize: size * 3) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: { _ in
            fallbackView
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: isRounded ? size / 2 : size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallbackView: some View {
        ZStack {
            LinearGradient(
                colors: [YukiTheme.accent.opacity(0.9), YukiTheme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(fallbackText.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

public struct PresenceAvatarView: View {
    public let user: User?
    public let userId: String
    public var avatarOverride: Attachment?
    public let size: CGFloat
    public var showsPresence = true

    public init(user: User?, userId: String, avatarOverride: Attachment? = nil, size: CGFloat, showsPresence: Bool = true) {
        self.user = user
        self.userId = userId
        self.avatarOverride = avatarOverride
        self.size = size
        self.showsPresence = showsPresence
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(
                avatar: avatarOverride ?? user?.avatar,
                fallbackText: user?.visibleName ?? "?",
                size: size,
                userId: userId
            )
            if showsPresence {
                StatusBadge(presence: user?.effectivePresence ?? .invisible, size: max(9, size * 0.3))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

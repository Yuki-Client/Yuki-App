import SwiftUI
import StoatCore
import StoatState

struct MessageAuthorAvatar: View {
    let message: Message
    let serverId: String?
    let name: String
    let size: CGFloat

    @Environment(AppStore.self) private var appStore

    var body: some View {
        if let masquerade = message.masquerade?.avatar, let url = Embed.proxiedURL(masquerade) {
            remote(url)
        } else if let webhookAvatar = message.webhook?.avatar, let url = URL(string: "\(StoatInstance.autumnURL)/avatars/\(webhookAvatar)") {
            remote(url)
        } else {
            AvatarView(
                avatar: appStore.store.avatar(userId: message.author, serverId: serverId),
                fallbackText: name,
                size: size,
                userId: message.webhook == nil ? message.author : nil
            )
        }
    }

    private func remote(_ url: URL) -> some View {
        RemoteImage(url: url, maxPixelSize: 120) { image in
            image.resizable().scaledToFill()
        } placeholder: { _ in
            AvatarView(avatar: nil, fallbackText: name, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

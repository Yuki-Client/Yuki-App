import SwiftUI
import StoatState

public struct YukiLinkHandler: Sendable {
    public var openUser: @MainActor @Sendable (String) -> Void
    public var openChannel: @MainActor @Sendable (String) -> Void
    /// Handles invite and other in-app links; returns `.systemAction` to open in the browser.
    public var openExternal: @MainActor @Sendable (URL) -> OpenURLAction.Result
    /// Opens a channel (and optionally a message), closing whatever sheets the link was tapped in.
    /// Nil when no screen above handles navigation.
    public var navigate: (@MainActor @Sendable (_ channelId: String, _ messageId: String?) -> Void)?

    public init(
        openUser: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        openChannel: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        openExternal: @escaping @MainActor @Sendable (URL) -> OpenURLAction.Result = { _ in .systemAction },
        navigate: (@MainActor @Sendable (_ channelId: String, _ messageId: String?) -> Void)? = nil
    ) {
        self.openUser = openUser
        self.openChannel = openChannel
        self.openExternal = openExternal
        self.navigate = navigate
    }
}

private struct YukiLinkHandlerKey: EnvironmentKey {
    static let defaultValue = YukiLinkHandler()
}

public extension EnvironmentValues {
    var yukiLinkHandler: YukiLinkHandler {
        get { self[YukiLinkHandlerKey.self] }
        set { self[YukiLinkHandlerKey.self] = newValue }
    }
}

/// Handles links tapped inside the modified view by presenting from that view, so a profile or
/// invite opened from a link in a sheet appears on top of that sheet instead of behind it.
struct LinkPresentationModifier: ViewModifier {
    let store: AppStore
    /// Set by the chat screen, which handles channel and message links itself. Elsewhere, links
    /// close the current sheet and pass navigation up to the screen that presented it.
    var openChannel: (@MainActor (_ channelId: String, _ messageId: String?) -> Void)?

    @Environment(\.yukiLinkHandler) private var parent
    @Environment(\.dismiss) private var dismiss
    @State private var profileUserId: String?
    @State private var inviteCode: String?
    @State private var showDiscover = false

    func body(content: Content) -> some View {
        content
            .environment(\.yukiLinkHandler, handler)
            .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
                UserProfileSheet(store: store, userId: item.value, serverId: store.selectedChannelId.flatMap { store.store.channels[$0]?.server })
            }
            .sheet(item: Binding(get: { inviteCode.map(IdentifiedString.init) }, set: { inviteCode = $0?.value })) { item in
                JoinOrCreateServerSheet(store: store, initialInviteCode: item.value)
            }
            .sheet(isPresented: $showDiscover) {
                DiscoverView(store: store)
            }
    }

    private var handler: YukiLinkHandler {
        YukiLinkHandler(
            openUser: { profileUserId = $0 },
            openChannel: { navigate(to: $0, messageId: nil) },
            openExternal: { url in
                switch StoatLink.parse(url) {
                case .invite(let code):
                    inviteCode = code
                    return .handled
                case .channel(let id, let messageId):
                    navigate(to: id, messageId: messageId)
                    return .handled
                case .discover:
                    showDiscover = true
                    return .handled
                case .user(let id):
                    profileUserId = id
                    return .handled
                case nil:
                    // Relative links that aren't app routes can't be opened in a browser either.
                    return url.host == nil ? .discarded : .systemAction
                }
            },
            navigate: { navigate(to: $0, messageId: $1) }
        )
    }

    private func navigate(to channelId: String, messageId: String?) {
        if let openChannel {
            openChannel(channelId, messageId)
            return
        }
        dismiss()
        if let upward = parent.navigate {
            upward(channelId, messageId)
        } else {
            store.open(.channel(channelId, messageId: messageId))
        }
    }
}

extension View {
    func presentsLinks(store: AppStore, openChannel: (@MainActor (_ channelId: String, _ messageId: String?) -> Void)? = nil) -> some View {
        modifier(LinkPresentationModifier(store: store, openChannel: openChannel))
    }
}

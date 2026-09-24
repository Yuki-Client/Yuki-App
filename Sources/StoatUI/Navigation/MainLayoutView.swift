import SwiftUI
import StoatCore
import StoatState
import StoatVoice

public struct MainLayoutView: View {
    @State private var store = AppStore()
    @State private var voice = VoiceCallController()
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
    @State private var inviteCode: String?
    @State private var showDiscover = false
    @State private var profileUserId: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true

    public init() {}

    public var body: some View {
        Group {
            switch store.phase {
            case .launching:
                LaunchView()
            case .loggedOut, .awaitingMFA, .onboarding:
                LoginView(store: store)
            case .loggedIn:
                mainContent
            }
        }
        .tint(YukiTheme.accent)
        .overlay(alignment: .top) {
            FeedbackOverlay(store: store)
        }
        .modifier(CallHandling(store: store, voice: voice))
        .onAppear {
            YukiAppearance.shared.applyToWindows()
        }
        .task {
            await store.restoreSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                YukiAppearance.shared.applyToWindows()
            }
            store.setAppActive(phase == .active)
        }
        .onOpenURL { url in
            handle(url)
        }
        .sheet(item: Binding(get: { inviteCode.map(IdentifiedString.init) }, set: { inviteCode = $0?.value })) { item in
            JoinOrCreateServerSheet(store: store, initialInviteCode: item.value)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverView(store: store)
        }
        .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
            UserProfileSheet(store: store, userId: item.value, serverId: store.selectedChannelId.flatMap { store.store.channels[$0]?.server })
        }
        .sheet(isPresented: Binding(get: { !store.pendingPolicyChanges.isEmpty && store.isLoggedIn }, set: { _ in })) {
            PolicyChangesSheet(store: store)
                .interactiveDismissDisabled()
        }
        // Last, so sheets and overlays attached above also get these: a view only passes the
        // environment to what it contains, and each modifier here contains the ones before it.
        .environment(store)
        .environment(voice)
        // Text follows the system size, stopping short of the largest accessibility sizes, which
        // leave no room for a chat with avatars, names and times on one line.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var mainContent: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            HStack(spacing: 0) {
                ServerSidebarView(store: store)
                ChannelListView(store: store)
            }
            // Swiping right to left goes back into the last channel opened in this server.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onChanged { _ in
                    YukiSwipeGuard.noteSwiping()
                }.onEnded { value in
                    guard horizontalSizeClass == .compact else { return }
                    let horizontal = value.translation.width
                    let swipedLeft = horizontal < -60 || value.predictedEndTranslation.width < -160
                    guard swipedLeft, abs(value.translation.height) < abs(horizontal) * 0.6 else { return }
                    if store.openLastChannel() {
                        YukiHaptics.selection()
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 420)
            // If the channel list comes back without the column changing here (e.g. the system back
            // gesture), record it, so opening a channel always changes the column and navigates.
            .onAppear {
                if horizontalSizeClass == .compact, preferredColumn != .sidebar {
                    preferredColumn = .sidebar
                }
            }
        } detail: {
            NavigationStack {
                detailContent
            }
        }
        .onChange(of: store.channelOpenCount) { _, _ in
            preferredColumn = .detail
        }
        .onChange(of: store.channelListRequestCount) { _, _ in
            guard horizontalSizeClass == .compact else { return }
            withAnimation { preferredColumn = .sidebar }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let channelId = store.selectedChannelId, let channel = store.store.channels[channelId] {
            Group {
                if channel.channelType == .voiceChannel {
                    VoiceChannelView(store: store, channelId: channelId)
                } else {
                    ChatFeedView(store: store, channelId: channelId)
                }
            }
            .id(channelId)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 18)),
                removal: .opacity.combined(with: .offset(x: -18))
            ))
            .animation(YukiMotion.transition(reduceMotion: reduceMotion, enabled: animationsEnabled), value: channelId)
        } else {
            ContentUnavailableView {
                Label("No Channel Selected", systemImage: "snowflake")
            } description: {
                Text("Choose a conversation from the sidebar.")
            }
            .background(YukiTheme.systemBackground)
        }
    }

    private func handle(_ url: URL) {
        switch StoatLink.parse(url) {
        case .invite(let code):
            inviteCode = code
        case .discover:
            showDiscover = true
        case .user(let id):
            profileUserId = id
        case .some(let link):
            store.open(link)
        case nil:
            break
        }
    }
}

/// Keeps calls in step with the session: leaves on logout, rings for incoming calls, and
/// offers to move a call from another device.
private struct CallHandling: ViewModifier {
    @Bindable var store: AppStore
    @Bindable var voice: VoiceCallController

    func body(content: Content) -> some View {
        content
            .onChange(of: store.phase) { _, phase in
                if phase != .loggedIn { voice.leave() }
            }
            .onAppear {
                store.ringsOnSystemCallScreen = voice.usesSystemCallScreen
            }
            .onChange(of: store.incomingCall) { _, call in
                if let call {
                    voice.ring(call, store: store)
                } else {
                    voice.stopRinging()
                }
            }
            .alert("Already in a Call", isPresented: isAskingToMove) {
                Button("Move Here") {
                    if let channelId = voice.pendingMoveChannelId {
                        voice.join(channelId, store: store, moveFromOtherDevice: true)
                    }
                    voice.pendingMoveChannelId = nil
                }
                Button("Cancel", role: .cancel) {
                    voice.pendingMoveChannelId = nil
                }
            } message: {
                Text("You're in a call on another device. Move it to this one? You'll be disconnected there.")
            }
            .overlay(alignment: .top) {
                if store.isLoggedIn, let call = store.incomingCall, voice.bannerCallChannelId == call.channelId {
                    IncomingCallBanner(call: call, store: store)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.bannerCallChannelId)
    }

    private var isAskingToMove: Binding<Bool> {
        Binding(get: { voice.pendingMoveChannelId != nil }, set: { if !$0 { voice.pendingMoveChannelId = nil } })
    }
}

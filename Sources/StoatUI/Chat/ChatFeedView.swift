import SwiftUI
import StoatCore
import StoatState
import StoatVoice

public struct ChatFeedView: View {
    @Bindable var store: AppStore
    public let channelId: String

    @State private var composerText = ""
    @State private var feedWidth: CGFloat = 0
    @Environment(VoiceCallController.self) private var voice
    @State private var showMemberList = false
    @AppStorage(ChatSwipeAction.storageKey) private var swipeAction: ChatSwipeAction = .reply
    @State private var showSearch = false
    @State private var showPins = false
    @State private var showChannelDetails = false
    @State private var highlightedMessageId: String?
    @State private var pendingJumpMessageId: String?
    @State private var profileUserId: String?
    @State private var reactionTarget: Message?
    @State private var actionsTarget: Message?
    @State private var reactionsTarget: ReactionsTarget?

    private struct ReactionsTarget: Identifiable {
        let messageId: String
        let emoji: String?
        var id: String { messageId }
    }
    /// An action picked in the actions sheet, run once the sheet has gone so it can present its own UI.
    @State private var deferredAction: (message: Message, action: MessageAction)?
    @State private var reportTarget: Message?
    @State private var deleteTarget: Message?
    @State private var isAtBottom = true
    /// Within a few screens of the newest message, close enough for the jump to animate smoothly.
    @State private var isNearBottom = true
    @State private var scrollAnchorId: String?
    @State private var isJumping = false
    /// Read marker captured when the channel opened, used for the "New" divider.
    @State private var unreadMarkerId: String?
    @State private var nsfwConfirmed = false

    public init(store: AppStore, channelId: String) {
        self.store = store
        self.channelId = channelId
    }

    private var channel: Channel? { store.store.channels[channelId] }
    private var timeline: ChannelTimeline { store.store.timeline(for: channelId) }
    private var permissions: Permission {
        channel.map { store.store.permissions(in: $0) } ?? []
    }

    private var channelTitle: String {
        channel?.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId) ?? "Channel"
    }

    public var body: some View {
        Group {
            if channel?.nsfw == true, !nsfwConfirmed, !store.confirmedNSFWChannels.contains(channelId) {
                NSFWGateView(channelName: channelTitle) {
                    store.confirmedNSFWChannels.insert(channelId)
                    nsfwConfirmed = true
                }
            } else {
                content
            }
        }
        .background(YukiTheme.systemBackground)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { feedWidth = $0 }
        .navigationTitle(channelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YukiTheme.systemBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showMemberList) {
            if let channel {
                MemberListSheet(store: store, channel: channel)
            }
        }
        .sheet(isPresented: $showSearch) {
            ChannelSearchView(channelId: channelId, channelName: channelTitle) { targetId in
                pendingJumpMessageId = targetId
            }
        }
        .sheet(isPresented: $showPins) {
            PinnedMessagesSheet(channelId: channelId, channelName: channelTitle) { targetId in
                pendingJumpMessageId = targetId
            }
        }
        .sheet(isPresented: $showChannelDetails) {
            ChannelDetailsSheet(store: store, channelId: channelId)
        }
        .sheet(item: Binding(get: { profileUserId.map(IdentifiedString.init) }, set: { profileUserId = $0?.value })) { item in
            UserProfileSheet(store: store, userId: item.value, serverId: channel?.server)
        }
        .sheet(item: $actionsTarget, onDismiss: {
            if let deferred = deferredAction {
                deferredAction = nil
                handle(deferred.action, for: deferred.message)
            }
        }) { message in
            MessageActionsSheet(message: message, serverId: channel?.server, permissions: permissions) { action in
                switch action {
                case .react, .togglePin, .markUnread:
                    handle(action, for: message)
                default:
                    deferredAction = (message, action)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(YukiTheme.groupedBackground)
        }
        .sheet(item: $reactionTarget) { message in
            EmojiPickerSheet(sections: store.store.emojiSections(for: channel), title: "Add Reaction") { emoji in
                react(with: emoji, to: message)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $reactionsTarget) { target in
            ReactionsSheet(store: store, channelId: channelId, messageId: target.messageId, serverId: channel?.server, initialEmoji: target.emoji)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(YukiTheme.groupedBackground)
        }
        .sheet(item: $reportTarget) { message in
            ReportSheet(store: store, target: .message(id: message.id), subject: "message")
        }
        .alert("Delete this message?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let message = deleteTarget {
                    Task { await store.deleteMessage(messageId: message.id, in: channelId) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .presentsLinks(store: store) { id, messageId in
            if id == channelId, let messageId {
                pendingJumpMessageId = messageId
            } else {
                store.open(.channel(id, messageId: messageId))
            }
        }
        .onAppear { store.viewingChannelId = channelId }
        .onDisappear {
            if store.viewingChannelId == channelId {
                store.viewingChannelId = nil
            }
        }
        .task(id: channelId) {
            captureUnreadMarker()
            // The channel is already selected by whatever opened it. Selecting it here again would
            // undo a newer choice while this screen is still animating away.
            if store.editingMessage == nil {
                composerText = store.draft(for: channelId)
            }
            if let messageId = store.takePendingJump(for: channelId) {
                // Loading the latest page here would replace the history the jump loads.
                pendingJumpMessageId = messageId
            } else if !timeline.isSynced {
                await store.loadLatestMessages(channelId: channelId)
            }
            store.markChannelAsRead(channelId)
        }
        .onChange(of: store.pendingJump) { _, _ in
            if let messageId = store.takePendingJump(for: channelId) {
                pendingJumpMessageId = messageId
            }
        }
        .onChange(of: store.editingMessage) { _, editing in
            // Editing borrows the composer; the draft comes back afterwards.
            if let editing {
                composerText = editing.content ?? ""
            } else {
                composerText = store.draft(for: channelId)
            }
        }
        .onChange(of: composerText) { _, text in
            if store.editingMessage == nil {
                store.setDraft(text, for: channelId)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ConnectionBannerView()

            if let channel, channel.supportsCalls,
               voice.channelId == channelId || !store.callParticipants(in: channelId).isEmpty {
                VoiceCallPanel(channel: channel, store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
                Group {
                    // Flipped so it starts at the newest message and older history loading above doesn't move
                    // what's on screen.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .frame(height: 8)
                                .id("bottom")
                                .modifier(LegacyBottomSentinel(isAtBottom: $isAtBottom))

                            ForEach(timeline.pending.reversed()) { pending in
                                PendingMessageRow(pending: pending, serverId: channel?.server, isContinuation: pendingIsContinuation(pending)) {
                                    store.retryPendingMessage(pending.id, in: channelId)
                                } onDiscard: {
                                    store.discardPendingMessage(pending.id, in: channelId)
                                }
                                .flippedForChat()
                                .id("pending-\(pending.id)")
                            }

                            ForEach(feedItems.reversed()) { item in
                                feedRow(item)
                                    .flippedForChat()
                                    .id(item.id)
                            }

                            historyHeader
                                .flippedForChat()
                                .id("history-header")
                        }
                        .scrollTargetLayout()
                    }
                    .flippedForChat()
                    .hidingScrollEdgeEffects()
                    .modifier(BottomDistanceTracking(isAtBottom: $isAtBottom, isNearBottom: $isNearBottom))
                    .scrollPosition(id: $scrollAnchorId)
                    .scrollIndicators(.hidden)
                    // Interactive dismissal tracks the finger in the flipped scroll view's coordinates and
                    // never fires, so any scroll puts the keyboard away instead. A tap on the messages does too.
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                    .simultaneousGesture(membersSwipe, including: canSwipeToMembers ? .all : .subviews)
                    .simultaneousGesture(backSwipe)
                    .onChange(of: timeline.messages.last?.id) { _, _ in
                        if timeline.messages.last?.author == store.store.currentUserId {
                            scrollToBottom(proxy, animated: true)
                        }
                        if isAtBottom && store.isAppActive {
                            store.markChannelAsRead(channelId)
                        }
                    }
                    .onChange(of: timeline.pending.count) { oldCount, newCount in
                        if newCount > oldCount {
                            if timeline.isViewingHistory {
                                jumpToPresent(proxy)
                            } else {
                                scrollToBottom(proxy, animated: true)
                            }
                        }
                    }
                    .onChange(of: isAtBottom) { _, atBottom in
                        guard !isJumping else { return }
                        if atBottom && timeline.isViewingHistory {
                            loadNewerKeepingPosition()
                        }
                        if atBottom && store.isAppActive {
                            store.markChannelAsRead(channelId)
                        }
                    }
                    .onChange(of: pendingJumpMessageId) { _, targetId in
                        guard let targetId else { return }
                        pendingJumpMessageId = nil
                        Task { await jump(to: targetId, proxy: proxy) }
                    }

                }
                .overlay(alignment: .bottomTrailing) {
                    // Animated on its own so showing or hiding it never animates the message list.
                    ZStack {
                        if !isAtBottom || timeline.isViewingHistory {
                            JumpToLatestButton(isViewingHistory: timeline.isViewingHistory) {
                                if timeline.isViewingHistory {
                                    jumpToPresent(proxy)
                                } else {
                                    scrollToBottom(proxy, animated: true)
                                }
                            }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: !isAtBottom || timeline.isViewingHistory)
                }
            }

            TypingIndicatorBar(store: store, channelId: channelId, serverId: channel?.server)
            ReplyingBanner(store: store, serverId: channel?.server)
            EditingBanner(store: store)
            if let channel {
                ChatComposerArea(store: store, channel: channel, permissions: permissions, text: $composerText)
            }
        }
    }

    @ViewBuilder
    private var historyHeader: some View {
        if timeline.hasMoreBefore && !timeline.messages.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 16)
            .onAppear {
                Task { await loadOlderPreservingPosition() }
            }
        } else if !timeline.hasMoreBefore || (timeline.isSynced && timeline.messages.isEmpty) {
            ChannelIntroView(channel: channel, title: channelTitle, canReadHistory: permissions.contains(.readMessageHistory))
        } else if timeline.isLoadingLatest {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 40)
        } else if let error = timeline.loadError, timeline.messages.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load messages", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await store.loadLatestMessages(channelId: channelId) }
                }
            }
            .padding(.top, 60)
        }
    }

    private var feedItems: [FeedItem] {
        FeedItem.build(
            from: timeline.messages,
            unreadMarkerId: unreadMarkerId,
            currentUserId: store.store.currentUserId,
            isBlocked: { store.store.users[$0]?.relationship == .blocked }
        )
    }

    /// Whether a pending message joins the group above it, as `FeedItem` groups sent ones.
    private func pendingIsContinuation(_ pending: PendingMessage) -> Bool {
        guard pending.replies.isEmpty, let me = store.store.currentUserId else { return false }
        guard let index = timeline.pending.firstIndex(where: { $0.id == pending.id }) else { return false }
        let previousDate: Date
        if index > 0 {
            previousDate = timeline.pending[index - 1].createdAt
        } else if let last = timeline.messages.last, last.author == me, last.system == nil, last.masquerade == nil, last.webhook == nil {
            previousDate = last.timestamp
        } else {
            return false
        }
        return Calendar.current.isDate(previousDate, inSameDayAs: pending.createdAt)
            && pending.createdAt.timeIntervalSince(previousDate) < FeedItem.groupingWindow
    }

    @ViewBuilder
    private func feedRow(_ item: FeedItem) -> some View {
        switch item {
        case .dateSeparator(let date):
            DateSeparatorRow(date: date)
        case .unreadDivider:
            UnreadDividerRow()
        case .message(let message, let isContinuation):
            MessageRowView(
                message: message,
                serverId: channel?.server,
                isContinuation: isContinuation,
                isHighlighted: highlightedMessageId == message.id,
                permissions: permissions
            ) { action in
                handle(action, for: message)
            }
        }
    }

    /// Adds or removes a reaction, remembering added ones for the quick reactions.
    private func react(with emoji: String, to message: Message) {
        let current = store.store.existingTimeline(for: channelId)?.message(id: message.id) ?? message
        if let userId = store.store.currentUserId, current.reactions[emoji]?.contains(userId) != true {
            ReactionHistory().record(emoji)
        }
        Task { await store.toggleReaction(messageId: message.id, emoji: emoji, in: channelId) }
    }

    private func handle(_ action: MessageAction, for message: Message) {
        switch action {
        case .reply:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                store.addReply(to: message)
            }
        case .react(let emoji):
            YukiHaptics.selection()
            react(with: emoji, to: message)
        case .openEmojiPicker:
            reactionTarget = message
        case .edit:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                store.replyingTo = []
                store.editingMessage = message
            }
        case .delete:
            deleteTarget = message
        case .togglePin:
            Task { await store.setPinned(message.pinned != true, messageId: message.id, in: channelId) }
        case .report:
            reportTarget = message
        case .jumpTo(let id):
            pendingJumpMessageId = id
        case .openUser(let userId):
            // A tap that arrives as part of a swipe across the chat isn't meant to open anyone.
            guard YukiSwipeGuard.acceptsTaps else { return }
            profileUserId = userId
        case .showActions:
            actionsTarget = message
        case .showReactions(let emoji):
            reactionsTarget = ReactionsTarget(messageId: message.id, emoji: emoji)
        case .markUnread:
            unreadMarkerId = nil
            Task { await store.markUnread(fromMessage: message.id, in: channelId) }
        }
    }

    private var canSwipeToMembers: Bool {
        swipeAction == .members && (channel?.server != nil || channel?.channelType == .group)
    }

    /// Swiping left to right anywhere goes back to the channel list, like Discord. The system's
    /// own back swipe only starts near the left side.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 30).onChanged { _ in
            YukiSwipeGuard.noteSwiping()
        }.onEnded { value in
            let horizontal = value.translation.width
            let swipedRight = horizontal > 90 || value.predictedEndTranslation.width > 220
            guard swipedRight, abs(value.translation.height) < abs(horizontal) * 0.5 else { return }
            dismissKeyboard()
            store.showChannelList()
        }
    }

    private var membersSwipe: some Gesture {
        DragGesture(minimumDistance: 30).onChanged { _ in
            YukiSwipeGuard.noteSwiping()
        }.onEnded { value in
            let horizontal = value.translation.width
            let swipedLeft = horizontal < -80 || value.predictedEndTranslation.width < -200
            guard swipedLeft, abs(value.translation.height) < abs(horizontal) * 0.6 else { return }
            YukiHaptics.selection()
            showMemberList = true
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func captureUnreadMarker() {
        guard let channel, store.store.isUnread(channel: channel) else {
            unreadMarkerId = nil
            return
        }
        unreadMarkerId = store.store.unreads[channelId]?.lastId ?? "0"
    }

    private func loadOlderPreservingPosition() async {
        guard timeline.hasMoreBefore, !timeline.isLoadingBefore else { return }
        await store.loadOlderMessages(channelId: channelId)
    }

    private func jumpToPresent(_ proxy: ScrollViewProxy) {
        Task {
            await store.loadLatestMessages(channelId: channelId)
            scrollToBottom(proxy, animated: false)
        }
    }

    /// Reaching the end of older history loads the next page, keeping the last message read in place.
    private func loadNewerKeepingPosition() {
        guard !timeline.isLoadingAfter else { return }
        let anchor = timeline.historyEndId
        Task {
            await store.loadNewerMessages(channelId: channelId)
            if let anchor, timeline.message(id: anchor) != nil {
                scrollAnchorId = anchor
            }
            // Still at the end of what's loaded, so nothing else will ask for the next page.
            if isAtBottom, timeline.isViewingHistory, !isJumping {
                try? await Task.sleep(for: .milliseconds(300))
                if isAtBottom, timeline.isViewingHistory {
                    loadNewerKeepingPosition()
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        // ScrollViewProxy fights `scrollPosition(id:)` and can land short, so go through the binding.
        // Long animated scrolls stutter while lazy rows are measured, so far jumps are instant.
        guard scrollAnchorId != "bottom" else {
            proxy.scrollTo("bottom", anchor: .top)
            return
        }
        if animated && isNearBottom {
            withAnimation(.easeOut(duration: 0.25)) {
                scrollAnchorId = "bottom"
            }
        } else {
            scrollAnchorId = "bottom"
        }
    }

    private func jump(to messageId: String, proxy: ScrollViewProxy) async {
        // While jumping, landing near the end of freshly loaded history must not count as reaching
        // the bottom: that loaded newer messages and moved the list again mid-jump.
        isJumping = true
        defer {
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                isJumping = false
                // If the jump settled at the newest loaded message, continue loading newer ones now.
                if isAtBottom && timeline.isViewingHistory {
                    loadNewerKeepingPosition()
                }
            }
        }
        let wasLoaded = timeline.message(id: messageId) != nil
        let available = await store.loadMessageContext(channelId: channelId, messageId: messageId)
        guard available else { return }
        // Let go of the scroll position binding: it otherwise pulls the list back to where it was
        // before, leaving the jump short of the message.
        scrollAnchorId = nil
        try? await Task.sleep(for: .milliseconds(100))
        if wasLoaded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                proxy.scrollTo(messageId, anchor: .center)
                highlightedMessageId = messageId
            }
        } else {
            // The history was just replaced, so rows aren't laid out yet: an animated scroll lands
            // short and then corrects. Go straight there instead.
            proxy.scrollTo(messageId, anchor: .center)
            withAnimation(.easeOut(duration: 0.2)) {
                highlightedMessageId = messageId
            }
        }
        // Rows in a lazy list are measured as they appear, so the first scroll can still land short.
        // Nudging it while it settles costs nothing once it's already there.
        for delay in [80, 150, 250, 350] {
            try? await Task.sleep(for: .milliseconds(delay))
            guard timeline.message(id: messageId) != nil else { break }
            proxy.scrollTo(messageId, anchor: .center)
        }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.easeOut(duration: 0.4)) {
            if highlightedMessageId == messageId {
                highlightedMessageId = nil
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                showChannelDetails = true
            } label: {
                ChatTitleView(store: store, channel: channel, title: channelTitle)
                    // A long topic would otherwise make this as wide as its text and push the title off screen.
                    .frame(maxWidth: feedWidth > 0 ? max(140, feedWidth - 180) : 220)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(channelTitle), channel details")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if let channel, channel.supportsCalls, voice.channelId != channelId, store.callParticipants(in: channelId).isEmpty {
                Button {
                    YukiHaptics.impact(.medium)
                    voice.join(channelId, store: store)
                } label: {
                    Image(systemName: "phone")
                }
                .accessibilityLabel("Start Call")
            }
            Menu {
                Button {
                    showSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Button {
                    showPins = true
                } label: {
                    Label("Pinned Messages", systemImage: "pin")
                }
                if channel?.channelType == .textChannel || channel?.channelType == .group {
                    Button {
                        showMemberList = true
                    } label: {
                        Label("Members", systemImage: "person.2")
                    }
                }
                Button {
                    showChannelDetails = true
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Channel options")
        }
    }
}

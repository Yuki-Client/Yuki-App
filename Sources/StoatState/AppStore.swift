import Foundation
import Observation
import StoatCore

@Observable
@MainActor
public final class AppStore {
    public enum SessionPhase: Equatable, Sendable {
        case launching
        case loggedOut
        case awaitingMFA(ticket: String, methods: [MFAMethod])
        /// New account that must pick a username before using the API.
        case onboarding
        case loggedIn
    }

    public struct Toast: Identifiable, Equatable, Sendable {
        public enum Style: Sendable { case error, success, info }
        public let id = UUID()
        public let message: String
        public let style: Style
    }

    public struct IncomingNotification: Identifiable, Equatable, Sendable {
        public let id: String
        public let channelId: String
        public let title: String
        public let body: String
        public let authorId: String
    }

    public struct IncomingCall: Identifiable, Equatable, Sendable {
        public let channelId: String
        public let callerId: String

        public var id: String { channelId }
    }

    public let store = NormalizedStore()
    public let apiClient: DeltaAPIClient

    public private(set) var phase: SessionPhase = .launching
    public private(set) var isConnecting = false
    public private(set) var errorMessage: String?
    public private(set) var connectionState: GatewayClient.ConnectionState = .disconnected
    public private(set) var instanceConfiguration: InstanceConfiguration?
    public var toast: Toast?
    public var incomingNotification: IncomingNotification?
    public internal(set) var incomingCall: IncomingCall?
    var incomingCallTimeout: Task<Void, Never>?
    /// When unreads were last fetched, so coming back to the app doesn't refetch them constantly.
    var lastUnreadSync = Date.distantPast
    /// Whether incoming calls ring on the system call screen, so no notification is needed.
    public var ringsOnSystemCallScreen = false
    public var pendingPolicyChanges: [PolicyChange] = []

    public var selectedServerId: String?
    public var selectedChannelId: String?
    /// The channel whose messages are on screen right now. Unlike `selectedChannelId`, this is nil
    /// on the channel list, so new messages there aren't marked read unseen.
    public var viewingChannelId: String?
    /// The channel last opened in each server (keyed by server ID, or `homeKey` for DMs).
    public private(set) var lastChannelByServer: [String: String] = [:]
    public static let homeKey = "@home"
    /// Incremented whenever a channel is opened, so compact layouts can navigate to it.
    public private(set) var channelOpenCount = 0
    /// Incremented to go back to the channel list in compact layouts.
    public private(set) var channelListRequestCount = 0
    /// Mature channels the user has confirmed they want to view this session.
    public var confirmedNSFWChannels: Set<String> = []
    public var replyingTo: [ReplyDraft] = []
    public var editingMessage: Message?
    /// Set by `openMessage`; the channel screen scrolls to it once open.
    public var pendingJump: MessageJump?
    public var slowmodeUntil: [String: Date] = [:]
    public private(set) var isAppActive = true

    public var profiles: [String: UserProfile] = [:]

    /// Unsent composer text keyed by channel ID, persisted per account.
    public private(set) var drafts: [String: String] = [:]
    private var draftSaveTask: Task<Void, Never>?

    private var gatewayClient: GatewayClient?
    private var gatewayListenerTask: Task<Void, Never>?
    private var gatewayStateListenerTask: Task<Void, Never>?
    private var cacheSaveTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    var ackTasks: [String: Task<Void, Never>] = [:]
    /// Read receipts not yet confirmed by Stoat (channel ID to message ID), saved so they're
    /// retried after a failure or the app closing, and so a reconnect doesn't undo them.
    var pendingAcks: [String: String] = [:]
    /// Read receipts Stoat accepted recently. It applies them from a queue a little later, so an
    /// unread sync in the meantime still has the old position and would bring the channel back.
    var confirmedAcks: [String: (messageId: String, at: Date)] = [:]
    /// Mentioned messages deleted since connecting. Stoat keeps listing them as mentions.
    var deletedMentionIds: Set<String> = []
    /// A second unread sync shortly after reading mentions, to clear the ones Stoat adds late.
    var followUpUnreadSync: Task<Void, Never>?
    var periodicUnreadSync: Task<Void, Never>?
    var lastMessageRefreshTasks: [String: Task<Void, Never>] = [:]
    var deliveryTasks: [UUID: Task<Void, Never>] = [:]
    /// Local previews of attachments just uploaded (by Autumn ID), shown while the uploaded copy loads.
    public internal(set) var localAttachmentPreviews: [String: Data] = [:]
    public internal(set) var notificationItems: [NotificationItem] = []
    /// Items the user removed, so syncing unreads doesn't bring them back.
    var removedNotificationIds: Set<String> = []
    var notificationSaveTask: Task<Void, Never>?
    var localPreviewOrder: [String] = []
    var latestLoadTasks: [String: Task<Void, Never>] = [:]
    var typingTasks: [String: Task<Void, Never>] = [:]
    var lastTypingSent: [String: Date] = [:]
    var pendingUserFetches: Set<String> = []
    /// Users the server said don't exist, so mentions of them aren't fetched again.
    var unknownUserIds: Set<String> = []
    var userFetchTask: Task<Void, Never>?

    public struct ReplyDraft: Identifiable, Equatable, Sendable {
        public var id: String { message.id }
        public let message: Message
        public var mention: Bool
    }

    public var currentUser: User? {
        store.currentUserId.flatMap { store.users[$0] }
    }

    public var isLoggedIn: Bool { phase == .loggedIn }

    public init() {
        AudioSessionPolicy.prepareForSilentPlayback()
        let savedURL = UserDefaults.standard.string(forKey: Keys.apiURL).flatMap(URL.init(string:))
        let apiURL = savedURL ?? URL(string: StoatInstance.Endpoints.stoat.api)!
        self.apiClient = DeltaAPIClient(baseURL: apiURL)

        if let data = UserDefaults.standard.data(forKey: Keys.instanceConfiguration),
           let configuration = try? JSONDecoder().decode(InstanceConfiguration.self, from: data) {
            instanceConfiguration = configuration
            StoatInstance.apply(configuration: configuration, apiURL: apiURL)
        }

        NotificationManager.shared.onOpenChannel = { [weak self] channelId in
            self?.openChannel(channelId)
        }
    }

    enum Keys {
        static let apiURL = "yuki.apiURL"
        static let instanceConfiguration = "yuki.instanceConfiguration"
        static let sessionToken = "sessionToken"
    }

    // MARK: - Feedback

    public func showError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        DiagnosticsLog.shared.record(.error, "\(message) (\(error))")
        toast = Toast(message: message, style: .error)
    }

    public func showError(_ message: String) {
        DiagnosticsLog.shared.record(.error, message)
        toast = Toast(message: message, style: .error)
    }

    public func showSuccess(_ message: String) {
        toast = Toast(message: message, style: .success)
    }

    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Session

    /// Restores a saved session. Cached data is shown immediately; the network is only
    /// used to refresh, so launching offline keeps the user signed in.
    public func restoreSession() async {
        guard phase == .launching else { return }
        guard let token = await KeychainStore.shared.load(account: Keys.sessionToken) else {
            phase = .loggedOut
            return
        }

        await apiClient.setSessionToken(token)
        await loadCache()
        loadDrafts()
        loadLastChannels()
        loadPendingAcks()
        await loadNotifications()
        phase = .loggedIn

        await refreshSessionAndConnect(token: token)
    }

    private func refreshSessionAndConnect(token: String) async {
        do {
            let user = try await apiClient.fetchCurrentUser()
            store.upsert(users: [user])
            store.currentUserId = user.id
        } catch StoatAPIError.unauthorized {
            await handleSessionInvalidated()
            return
        } catch {
            DiagnosticsLog.shared.record(.network, "Couldn't refresh the account, using the cache: \(error)")
        }

        await refreshInstanceConfiguration()
        await connectGateway(token: token)
    }

    private func refreshInstanceConfiguration() async {
        do {
            let configuration = try await apiClient.fetchInstanceConfiguration()
            await applyInstanceConfiguration(configuration)
        } catch {
            DiagnosticsLog.shared.record(.network, "Couldn't fetch the instance configuration: \(error)")
        }
    }

    private func applyInstanceConfiguration(_ configuration: InstanceConfiguration) async {
        instanceConfiguration = configuration
        StoatInstance.apply(configuration: configuration, apiURL: await apiClient.baseURL)
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Keys.instanceConfiguration)
        }
    }

    public func configureInstance(apiURL raw: String) async -> Bool {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), url.host != nil else {
            errorMessage = StoatAPIError.invalidURL.errorDescription
            return false
        }

        let current = await apiClient.baseURL
        if current == url, instanceConfiguration != nil {
            return true
        }

        await apiClient.setBaseURL(url)
        do {
            let configuration = try await apiClient.fetchInstanceConfiguration()
            UserDefaults.standard.set(url.absoluteString, forKey: Keys.apiURL)
            instanceConfiguration = configuration
            StoatInstance.apply(configuration: configuration, apiURL: url)
            if let data = try? JSONEncoder().encode(configuration) {
                UserDefaults.standard.set(data, forKey: Keys.instanceConfiguration)
            }
            return true
        } catch {
            await apiClient.setBaseURL(current)
            errorMessage = "Couldn't reach a Stoat server at \(url.absoluteString)."
            return false
        }
    }

    public func login(email: String, password: String) async -> Bool {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let response = try await apiClient.login(request: LoginRequest(email: email, password: password))
            return await handleLoginResponse(response)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func submitMFA(_ response: MFAResponse) async -> Bool {
        guard case .awaitingMFA(let ticket, _) = phase else { return false }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let result = try await apiClient.login(mfa: MFALoginRequest(ticket: ticket, response: response))
            return await handleLoginResponse(result)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func cancelMFA() {
        phase = .loggedOut
        errorMessage = nil
    }

    private func handleLoginResponse(_ response: LoginResponse) async -> Bool {
        switch response {
        case .success(let session):
            return await finishLogin(token: session.token)
        case .mfa(let requirement):
            phase = .awaitingMFA(ticket: requirement.ticket, methods: requirement.allowedMethods)
            return false
        case .disabled:
            errorMessage = "This account has been disabled."
            phase = .loggedOut
            return false
        }
    }

    private func finishLogin(token: String) async -> Bool {
        await apiClient.setSessionToken(token)
        await KeychainStore.shared.save(token: token, for: Keys.sessionToken)

        do {
            if instanceConfiguration == nil {
                await applyInstanceConfiguration(try await apiClient.fetchInstanceConfiguration())
            }

            if try await apiClient.fetchOnboardingStatus().onboarding {
                phase = .onboarding
                return true
            }

            let user = try await apiClient.fetchCurrentUser()
            store.reset()
            store.upsert(users: [user])
            store.currentUserId = user.id
            loadDrafts()
            loadLastChannels()
            loadPendingAcks()
            await loadNotifications()
            phase = .loggedIn
            await connectGateway(token: token)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await KeychainStore.shared.delete(account: Keys.sessionToken)
            await apiClient.setSessionToken(nil)
            phase = .loggedOut
            return false
        }
    }

    public func completeOnboarding(username: String) async -> Bool {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            try await apiClient.completeOnboarding(username: username)
            guard let token = await apiClient.sessionToken else { return false }
            let user = try await apiClient.fetchCurrentUser()
            store.reset()
            store.upsert(users: [user])
            store.currentUserId = user.id
            phase = .loggedIn
            await connectGateway(token: token)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func logout() async {
        try? await apiClient.logout()
        await clearLocalSession()
    }

    func handleSessionInvalidated() async {
        await clearLocalSession()
        errorMessage = "Your session has expired. Please log in again."
    }

    private func clearLocalSession() async {
        gatewayListenerTask?.cancel()
        gatewayListenerTask = nil
        gatewayStateListenerTask?.cancel()
        gatewayStateListenerTask = nil
        subscribeTask?.cancel()
        subscribeTask = nil
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        for task in ackTasks.values { task.cancel() }
        ackTasks = [:]
        for task in lastMessageRefreshTasks.values { task.cancel() }
        lastMessageRefreshTasks = [:]
        for task in deliveryTasks.values { task.cancel() }
        deliveryTasks = [:]
        localAttachmentPreviews = [:]
        localPreviewOrder = []
        if let key = pendingAcksKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        pendingAcks = [:]
        confirmedAcks = [:]
        deletedMentionIds = []
        followUpUnreadSync?.cancel()
        periodicUnreadSync?.cancel()
        dismissIncomingCall()
        await clearNotifications()
        await gatewayClient?.shutdown()
        gatewayClient = nil
        connectionState = .disconnected

        await KeychainStore.shared.delete(account: Keys.sessionToken)
        await apiClient.setSessionToken(nil)
        await DiskCacheStore.shared.clear()

        if let key = draftsKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        draftSaveTask?.cancel()
        drafts = [:]
        if let key = lastChannelsKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        lastChannelByServer = [:]
        viewingChannelId = nil
        store.reset()
        profiles = [:]
        selectedServerId = nil
        selectedChannelId = nil
        replyingTo = []
        editingMessage = nil
        pendingPolicyChanges = []
        NotificationManager.shared.updateBadgeCount(0)
        phase = .loggedOut
    }

    public func acknowledgePolicyChanges() async {
        do {
            try await apiClient.acknowledgePolicyChanges()
            pendingPolicyChanges = []
        } catch {
            showError(error)
        }
    }

    // MARK: - Connection

    private func connectGateway(token: String) async {
        gatewayListenerTask?.cancel()
        gatewayStateListenerTask?.cancel()
        await gatewayClient?.shutdown()

        let wsString = instanceConfiguration?.ws ?? "wss://events.stoat.chat"
        guard let wsURL = URL(string: wsString) else { return }

        let gateway = GatewayClient(wsURL: wsURL, token: token)
        gatewayClient = gateway

        gatewayListenerTask = Task { [weak self] in
            for await event in gateway.events {
                guard let self else { break }
                await self.handleGatewayEvent(event)
            }
        }

        gatewayStateListenerTask = Task { [weak self] in
            for await state in gateway.connectionStates {
                guard let self else { break }
                if self.connectionState != state {
                    DiagnosticsLog.shared.record(.gateway, "\(state)")
                }
                self.connectionState = state
            }
        }

        await gateway.connect()
    }

    public func reconnectGateway() async {
        await gatewayClient?.reconnect()
    }

    func sendGatewayCommand(_ command: GatewayCommand) {
        guard let gatewayClient else { return }
        Task { await gatewayClient.send(command: command) }
    }

    public func setAppActive(_ active: Bool) {
        if isAppActive != active {
            DiagnosticsLog.shared.record(.app, active ? "Came to the foreground" : "Went to the background")
        }
        guard active != isAppActive else { return }
        isAppActive = active
        if active {
            if let gatewayClient {
                Task { await gatewayClient.resumeFromBackground() }
            }
            if let channelId = viewingChannelId {
                markChannelAsRead(channelId)
            }
            // Catch up on what was read elsewhere, and clear any mentions Stoat left behind.
            if Date().timeIntervalSince(lastUnreadSync) > 30 {
                Task { await syncUnreads() }
            }
            startPeriodicUnreadSync()
        } else {
            periodicUnreadSync?.cancel()
            periodicUnreadSync = nil
            flushPendingAcks()
            saveCacheNow()
        }
    }

    // MARK: - Navigation

    public func selectServer(_ serverId: String?) {
        selectedServerId = serverId
        if let serverId {
            subscribe(toServer: serverId)
            let channels = store.channels(forServer: serverId)
            if let current = selectedChannelId, channels.contains(where: { $0.id == current }) {
                return
            }
            selectedChannelId = nil
        } else {
            subscribeTask?.cancel()
            if let current = selectedChannelId, store.channels[current]?.isPrivate == true {
                return
            }
            selectedChannelId = nil
        }
    }

    public func selectChannel(_ channelId: String) {
        if selectedChannelId != channelId {
            channelOpenCount += 1
            replyingTo = []
            editingMessage = nil
            if let previous = selectedChannelId {
                store.existingTimeline(for: previous)?.trim(keepingLast: 150)
            }
        }
        selectedChannelId = channelId
        if let channel = store.channels[channelId] {
            rememberLastChannel(channel)
            if let serverId = channel.server, selectedServerId != serverId {
                selectedServerId = serverId
                subscribe(toServer: serverId)
            } else if channel.isPrivate {
                selectedServerId = nil
            }
        }
        if incomingNotification?.channelId == channelId {
            incomingNotification = nil
        }
        NotificationManager.shared.removeNotifications(forChannel: channelId)
    }

    /// Opens a channel from a list, notification or link, navigating to it even if it was already selected.
    public func openChannel(_ channelId: String) {
        guard store.channels[channelId] != nil else { return }
        if selectedChannelId == channelId {
            channelOpenCount += 1
        }
        selectChannel(channelId)
    }

    public func lastChannel(forServer serverId: String?) -> String? {
        guard let id = lastChannelByServer[serverId ?? Self.homeKey], let channel = store.channels[id] else { return nil }
        if let serverId {
            guard channel.server == serverId, store.hasPermission(.viewChannel, in: channel) else { return nil }
        } else {
            guard channel.isPrivate else { return nil }
        }
        return id
    }

    public func showChannelList() {
        channelListRequestCount += 1
    }

    @discardableResult
    public func openLastChannel() -> Bool {
        guard let channelId = lastChannel(forServer: selectedServerId) else { return false }
        openChannel(channelId)
        return true
    }

    private var lastChannelsKey: String? {
        store.currentUserId.map { "yuki.lastChannels.\($0)" }
    }

    private func rememberLastChannel(_ channel: Channel) {
        guard channel.channelType != .voiceChannel else { return }
        let key = channel.server ?? Self.homeKey
        guard lastChannelByServer[key] != channel.id else { return }
        lastChannelByServer[key] = channel.id
        if let storageKey = lastChannelsKey {
            UserDefaults.standard.set(lastChannelByServer, forKey: storageKey)
        }
    }

    func loadLastChannels() {
        guard let key = lastChannelsKey else { return }
        lastChannelByServer = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// Server member events are only delivered for recently viewed servers; refresh the subscription periodically.
    private func subscribe(toServer serverId: String) {
        subscribeTask?.cancel()
        subscribeTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sendGatewayCommand(.subscribe(serverId: serverId))
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    // MARK: - Drafts

    private var draftsKey: String? {
        store.currentUserId.map { "yuki.drafts.\($0)" }
    }

    public func draft(for channelId: String) -> String {
        drafts[channelId] ?? ""
    }

    public func setDraft(_ text: String, for channelId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard drafts.removeValue(forKey: channelId) != nil else { return }
        } else {
            guard drafts[channelId] != text else { return }
            drafts[channelId] = text
        }

        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, let key = self.draftsKey else { return }
            UserDefaults.standard.set(self.drafts, forKey: key)
        }
    }

    func loadDrafts() {
        guard let key = draftsKey else { return }
        drafts = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    // MARK: - Cache

    private struct CacheSnapshot: Codable, Sendable {
        static let currentVersion = 2

        var version: Int
        var userId: String
        var users: [String: User]
        var servers: [String: Server]
        var channels: [String: Channel]
        var members: [String: [String: ServerMember]]
        var emojis: [String: Emoji]
        var unreads: [String: ChannelUnread]
        var messages: [String: [Message]]
        var serverOrder: [String]
        var serverSidebar: [String]?
        var serverFolders: [ServerFolder]?
        var notificationOptions: NotificationOptions
    }

    private func loadCache() async {
        guard let snapshot: CacheSnapshot = await DiskCacheStore.shared.load(),
              snapshot.version == CacheSnapshot.currentVersion else { return }
        store.currentUserId = snapshot.userId
        store.users = snapshot.users
        store.servers = snapshot.servers
        store.channels = snapshot.channels
        store.members = snapshot.members
        store.emojis = snapshot.emojis
        store.unreads = snapshot.unreads
        store.unreadsLoaded = true
        store.serverOrder = snapshot.serverOrder
        store.serverSidebar = snapshot.serverSidebar
        store.serverFolders = snapshot.serverFolders ?? []
        store.notificationOptions = snapshot.notificationOptions
        for (channelId, messages) in snapshot.messages {
            let timeline = store.timeline(for: channelId)
            timeline.merge(messages)
            timeline.isSynced = false
        }
    }

    func scheduleCacheSave() {
        guard cacheSaveTask == nil else { return }
        cacheSaveTask = Task { [weak self] in
            // Busy servers change something every few seconds, and each save rewrites the whole
            // snapshot; leaving the app saves straight away, so waiting longer loses nothing.
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.cacheSaveTask = nil
            self.saveCacheNow()
        }
    }

    func saveCacheNow() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        guard phase == .loggedIn, let userId = store.currentUserId else { return }

        var messages: [String: [Message]] = [:]
        for (channelId, timeline) in store.timelines where !timeline.messages.isEmpty {
            messages[channelId] = Array(timeline.messages.suffix(50))
        }

        let snapshot = CacheSnapshot(
            version: CacheSnapshot.currentVersion,
            userId: userId,
            users: store.users,
            servers: store.servers,
            channels: store.channels,
            members: store.members,
            emojis: store.emojis,
            unreads: store.unreads,
            messages: messages,
            serverOrder: store.serverOrder,
            serverSidebar: store.serverSidebar,
            serverFolders: store.serverFolders,
            notificationOptions: store.notificationOptions
        )

        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(Self.trimmed(snapshot)) else { return }
            await DiskCacheStore.shared.save(data: data)
        }
    }

    /// Saving tens of thousands of members made every save and launch slow, so only the people the
    /// cached messages, DMs and friends list need are kept.
    nonisolated private static func trimmed(_ snapshot: CacheSnapshot) -> CacheSnapshot {
        let memberLimit = 1500
        let userLimit = 5000
        guard snapshot.users.count > userLimit || snapshot.members.values.contains(where: { $0.count > memberLimit }) else {
            return snapshot
        }

        var needed: Set<String> = [snapshot.userId]
        for channel in snapshot.channels.values {
            needed.formUnion(channel.recipients ?? [])
        }
        for messages in snapshot.messages.values {
            for message in messages {
                needed.insert(message.author)
                needed.formUnion(message.mentions ?? [])
            }
        }
        for user in snapshot.users.values where user.relationship != .none {
            needed.insert(user.id)
        }

        var result = snapshot
        for (serverId, members) in snapshot.members where members.count > memberLimit {
            result.members[serverId] = members.filter { needed.contains($0.key) }
        }
        if snapshot.users.count > userLimit {
            for members in result.members.values {
                needed.formUnion(members.keys)
            }
            result.users = snapshot.users.filter { needed.contains($0.key) }
        }
        return result
    }

    func updateBadge() {
        NotificationManager.shared.updateBadgeCount(store.badgeCount)
    }
}

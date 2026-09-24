import Foundation

/// Routes follow stoatchat/crates/delta/src/routes.
public actor DeltaAPIClient {
    public private(set) var baseURL: URL
    public private(set) var sessionToken: String?
    private let urlSession: URLSession

    public init(
        baseURL: URL = URL(string: StoatInstance.Endpoints.stoat.api)!,
        sessionToken: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.urlSession = urlSession
    }

    public func setSessionToken(_ token: String?) {
        self.sessionToken = token
    }

    public func setBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // MARK: - Instance & Auth

    public func fetchInstanceConfiguration() async throws -> InstanceConfiguration {
        try await request(.get, "")
    }

    public func login(request body: LoginRequest) async throws -> LoginResponse {
        try await request(.post, "auth/session/login", body: body, authenticated: false)
    }

    public func login(mfa body: MFALoginRequest) async throws -> LoginResponse {
        try await request(.post, "auth/session/login", body: body, authenticated: false)
    }

    public func logout() async throws {
        try await requestVoid(.post, "auth/session/logout")
    }

    public func fetchSessions() async throws -> [SessionInfo] {
        try await request(.get, "auth/session/all")
    }

    /// Exchanges a password or code for a short-lived ticket required by sensitive account actions.
    public func createMFATicket(_ response: MFAResponse) async throws -> String {
        struct Ticket: Decodable { let token: String }
        let ticket: Ticket = try await request(.put, "auth/mfa/ticket", body: response)
        return ticket.token
    }

    public func revokeSession(id: String, mfaTicket: String) async throws {
        try await requestVoid(.delete, "auth/session/\(id)", headers: ["X-MFA-Ticket": mfaTicket])
    }

    public func revokeOtherSessions(mfaTicket: String) async throws {
        try await requestVoid(
            .delete,
            "auth/session/all",
            query: [URLQueryItem(name: "revoke_self", value: "false")],
            headers: ["X-MFA-Ticket": mfaTicket]
        )
    }

    // MARK: Account security

    public func fetchAccount() async throws -> AccountInfo {
        try await request(.get, "auth/account/")
    }

    public func changePassword(_ newPassword: String, currentPassword: String) async throws {
        struct Payload: Encodable {
            let password: String
            let current_password: String
        }
        try await requestVoid(.patch, "auth/account/change/password", body: Payload(password: newPassword, current_password: currentPassword))
    }

    /// Sends a confirmation link to the new address; the change applies once it's opened.
    public func changeEmail(_ email: String, currentPassword: String) async throws {
        struct Payload: Encodable {
            let email: String
            let current_password: String
        }
        try await requestVoid(.patch, "auth/account/change/email", body: Payload(email: email, current_password: currentPassword))
    }

    public func fetchMFAStatus() async throws -> MultiFactorStatus {
        try await request(.get, "auth/mfa/")
    }

    public func fetchRecoveryCodes(mfaTicket: String) async throws -> [String] {
        try await request(.post, "auth/mfa/recovery", headers: ["X-MFA-Ticket": mfaTicket])
    }

    public func generateRecoveryCodes(mfaTicket: String) async throws -> [String] {
        try await request(.patch, "auth/mfa/recovery", headers: ["X-MFA-Ticket": mfaTicket])
    }

    public func generateTOTPSecret(mfaTicket: String) async throws -> String {
        struct Secret: Decodable { let secret: String }
        let response: Secret = try await request(.post, "auth/mfa/totp", headers: ["X-MFA-Ticket": mfaTicket])
        return response.secret
    }

    public func enableTOTP(code: String) async throws {
        try await requestVoid(.put, "auth/mfa/totp", body: MFAResponse.totp(code))
    }

    public func disableTOTP(mfaTicket: String) async throws {
        try await requestVoid(.delete, "auth/mfa/totp", headers: ["X-MFA-Ticket": mfaTicket])
    }

    public func disableAccount(mfaTicket: String) async throws {
        try await requestVoid(.post, "auth/account/disable", headers: ["X-MFA-Ticket": mfaTicket])
    }

    /// Requests deletion; Stoat emails a confirmation link before the account is removed.
    public func deleteAccount(mfaTicket: String) async throws {
        try await requestVoid(.post, "auth/account/delete", headers: ["X-MFA-Ticket": mfaTicket])
    }

    public func fetchOnboardingStatus() async throws -> OnboardingStatus {
        try await request(.get, "onboard/hello")
    }

    public func completeOnboarding(username: String) async throws {
        try await requestVoid(.post, "onboard/complete", body: ["username": username])
    }

    public func acknowledgePolicyChanges() async throws {
        try await requestVoid(.post, "policy/acknowledge")
    }

    // MARK: - Users

    public func fetchCurrentUser() async throws -> User {
        try await request(.get, "users/@me")
    }

    public func fetchUser(id: String) async throws -> User {
        try await request(.get, "users/\(id)")
    }

    public func fetchUserProfile(id: String) async throws -> UserProfile {
        try await request(.get, "users/\(id)/profile")
    }

    public func fetchMutuals(userId: String) async throws -> MutualConnections {
        try await request(.get, "users/\(userId)/mutual")
    }

    public struct EditUserPayload: Encodable, Sendable {
        public var displayName: String?
        public var pronouns: String?
        public var avatar: String?
        public var status: UserStatus?
        public var profile: ProfilePayload?
        public var remove: [String]?

        public struct ProfilePayload: Encodable, Sendable {
            public var content: String?
            public var background: String?

            public init(content: String? = nil, background: String? = nil) {
                self.content = content
                self.background = background
            }
        }

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case pronouns, avatar, status, profile, remove
        }

        public init(
            displayName: String? = nil,
            pronouns: String? = nil,
            avatar: String? = nil,
            status: UserStatus? = nil,
            profile: ProfilePayload? = nil,
            remove: [String]? = nil
        ) {
            self.displayName = displayName
            self.pronouns = pronouns
            self.avatar = avatar
            self.status = status
            self.profile = profile
            self.remove = remove
        }
    }

    /// Edits the current user. Fields listed in `remove` (e.g. `StatusText`, `Avatar`) are cleared.
    public func editCurrentUser(_ payload: EditUserPayload) async throws -> User {
        try await request(.patch, "users/@me", body: payload)
    }

    /// Edits a bot's user account (display name, avatar, profile), which its owner may change.
    public func editBotUser(botId: String, _ payload: EditUserPayload) async throws -> User {
        try await request(.patch, "users/\(botId)", body: payload)
    }

    // MARK: - Bots

    public func fetchOwnedBots() async throws -> OwnedBotsResponse {
        try await request(.get, "bots/@me")
    }

    public func createBot(name: String) async throws -> BotWithUser {
        struct Payload: Encodable { let name: String }
        return try await request(.post, "bots/create", body: Payload(name: name))
    }

    public struct EditBotPayload: Encodable, Sendable {
        public var name: String?
        public var isPublic: Bool?
        public var analytics: Bool?
        public var interactionsURL: String?
        public var remove: [String]?

        enum CodingKeys: String, CodingKey {
            case name, analytics, remove
            case isPublic = "public"
            case interactionsURL = "interactions_url"
        }

        public init(name: String? = nil, isPublic: Bool? = nil, analytics: Bool? = nil, interactionsURL: String? = nil, remove: [String]? = nil) {
            self.name = name
            self.isPublic = isPublic
            self.analytics = analytics
            self.interactionsURL = interactionsURL
            self.remove = remove
        }
    }

    /// Edits a bot. `remove: ["Token"]` issues a new token.
    public func editBot(id: String, _ payload: EditBotPayload) async throws -> BotWithUser {
        try await request(.patch, "bots/\(id)", body: payload)
    }

    public func deleteBot(id: String) async throws {
        try await requestVoid(.delete, "bots/\(id)")
    }

    public func fetchPublicBot(id: String) async throws -> PublicBot {
        try await request(.get, "bots/\(id)/invite")
    }

    public enum BotDestination: Sendable {
        case server(String)
        case group(String)
    }

    public func inviteBot(id: String, to destination: BotDestination) async throws {
        switch destination {
        case .server(let server):
            try await requestVoid(.post, "bots/\(id)/invite", body: ["server": server])
        case .group(let group):
            try await requestVoid(.post, "bots/\(id)/invite", body: ["group": group])
        }
    }

    public func changeUsername(_ username: String, password: String) async throws -> User {
        try await request(.patch, "users/@me/username", body: ["username": username, "password": password])
    }

    public func fetchDirectMessageChannels() async throws -> [Channel] {
        try await request(.get, "users/dms")
    }

    public func openDirectMessage(with userId: String) async throws -> Channel {
        try await request(.get, "users/\(userId)/dm")
    }

    public func sendFriendRequest(username: String) async throws -> User {
        try await request(.post, "users/friend", body: ["username": username])
    }

    public func acceptFriendRequest(userId: String) async throws -> User {
        try await request(.put, "users/\(userId)/friend")
    }

    /// Removes a friend, or denies / cancels a pending request.
    public func removeFriend(userId: String) async throws -> User {
        try await request(.delete, "users/\(userId)/friend")
    }

    public func blockUser(userId: String) async throws -> User {
        try await request(.put, "users/\(userId)/block")
    }

    public func unblockUser(userId: String) async throws -> User {
        try await request(.delete, "users/\(userId)/block")
    }

    // MARK: - Channels

    public func fetchChannel(id: String) async throws -> Channel {
        try await request(.get, "channels/\(id)")
    }

    public struct CreateGroupPayload: Encodable, Sendable {
        public let name: String
        public let description: String?
        public let users: [String]
    }

    public func createGroup(name: String, description: String? = nil, users: [String]) async throws -> Channel {
        try await request(.post, "channels/create", body: CreateGroupPayload(name: name, description: description, users: users))
    }

    public func addGroupMember(channelId: String, userId: String) async throws {
        try await requestVoid(.put, "channels/\(channelId)/recipients/\(userId)")
    }

    public func removeGroupMember(channelId: String, userId: String) async throws {
        try await requestVoid(.delete, "channels/\(channelId)/recipients/\(userId)")
    }

    public struct EditChannelPayload: Encodable, Sendable {
        public var name: String?
        public var description: String?
        public var icon: String?
        public var nsfw: Bool?
        public var slowmode: Int?
        public var remove: [String]?

        public init(name: String? = nil, description: String? = nil, icon: String? = nil, nsfw: Bool? = nil, slowmode: Int? = nil, remove: [String]? = nil) {
            self.name = name
            self.description = description
            self.icon = icon
            self.nsfw = nsfw
            self.slowmode = slowmode
            self.remove = remove
        }
    }

    public func editChannel(channelId: String, _ payload: EditChannelPayload) async throws -> Channel {
        try await request(.patch, "channels/\(channelId)", body: payload)
    }

    // MARK: Webhooks

    public func fetchWebhooks(channelId: String) async throws -> [Webhook] {
        try await request(.get, "channels/\(channelId)/webhooks")
    }

    public func createWebhook(channelId: String, name: String, avatar: String? = nil) async throws -> Webhook {
        struct Payload: Encodable { let name: String; let avatar: String? }
        return try await request(.post, "channels/\(channelId)/webhooks", body: Payload(name: name, avatar: avatar))
    }

    public func editWebhook(id: String, name: String?, avatar: String?, removeAvatar: Bool) async throws -> Webhook {
        struct Payload: Encodable { let name: String?; let avatar: String?; let remove: [String]? }
        return try await request(.patch, "webhooks/\(id)", body: Payload(name: name, avatar: avatar, remove: removeAvatar ? ["Avatar"] : nil))
    }

    public func deleteWebhook(id: String) async throws {
        try await requestVoid(.delete, "webhooks/\(id)")
    }

    /// Deletes a server channel, closes a DM, or leaves a group.
    public func deleteChannel(channelId: String, leaveSilently: Bool = false) async throws {
        let query = leaveSilently ? [URLQueryItem(name: "leave_silently", value: "true")] : []
        try await requestVoid(.delete, "channels/\(channelId)", query: query)
    }

    public func acknowledge(channelId: String, messageId: String) async throws {
        try await requestVoid(.put, "channels/\(channelId)/ack/\(messageId)")
    }

    public func fetchUnreads() async throws -> [ChannelUnread] {
        try await request(.get, "sync/unreads")
    }

    public func createInvite(channelId: String) async throws -> Invite {
        try await request(.post, "channels/\(channelId)/invites")
    }

    // MARK: - Messages

    public struct MessagesPage: Decodable, Sendable {
        public let messages: [Message]
        public let users: [User]
        public let members: [ServerMember]

        public init(messages: [Message], users: [User] = [], members: [ServerMember] = []) {
            self.messages = messages
            self.users = users
            self.members = members
        }

        private enum CodingKeys: String, CodingKey {
            case messages, users, members
        }

        public init(from decoder: Decoder) throws {
            // The server returns a bare array unless `include_users` is set.
            if let list = try? decoder.singleValueContainer().decode(LossyArray<Message>.self) {
                self.init(messages: list.elements)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                messages: try c.decodeLossyArray(Message.self, forKey: .messages) ?? [],
                users: try c.decodeLossyArray(User.self, forKey: .users) ?? [],
                members: try c.decodeLossyArray(ServerMember.self, forKey: .members) ?? []
            )
        }
    }

    public enum MessageSort: String, Sendable {
        case relevance = "Relevance"
        case latest = "Latest"
        case oldest = "Oldest"
    }

    /// Fetches message history. Results are newest-first unless `sort` is `.oldest`.
    public func fetchMessages(
        channelId: String,
        limit: Int = 50,
        before: String? = nil,
        after: String? = nil,
        nearby: String? = nil,
        sort: MessageSort? = nil
    ) async throws -> MessagesPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "include_users", value: "true")
        ]
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        if let after { query.append(URLQueryItem(name: "after", value: after)) }
        if let nearby { query.append(URLQueryItem(name: "nearby", value: nearby)) }
        if let sort { query.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        return try await request(.get, "channels/\(channelId)/messages", query: query)
    }

    // MARK: - Creating and recovering accounts

    private struct CreateAccountPayload: Encodable, Sendable {
        let email: String
        let password: String
        let invite: String?
        let captcha: String?
    }

    private struct EmailCaptchaPayload: Encodable, Sendable {
        let email: String
        let captcha: String?
    }

    private struct ResetPasswordPayload: Encodable, Sendable {
        let token: String
        let password: String
        let removeSessions: Bool

        enum CodingKeys: String, CodingKey {
            case token, password
            case removeSessions = "remove_sessions"
        }
    }

    /// Creates an account. Stoat then emails a verification code.
    public func createAccount(email: String, password: String, invite: String?, captcha: String?) async throws {
        try await requestVoid(.post, "auth/account/create", body: CreateAccountPayload(
            email: email,
            password: password,
            invite: invite?.isEmpty == false ? invite : nil,
            captcha: captcha
        ), authenticated: false)
    }

    public func verifyAccount(code: String) async throws {
        try await requestVoid(.post, "auth/account/verify/\(code)", authenticated: false)
    }

    public func resendVerification(email: String, captcha: String?) async throws {
        try await requestVoid(.post, "auth/account/reverify", body: EmailCaptchaPayload(email: email, captcha: captcha), authenticated: false)
    }

    public func sendPasswordReset(email: String, captcha: String?) async throws {
        try await requestVoid(.post, "auth/account/reset_password", body: EmailCaptchaPayload(email: email, captcha: captcha), authenticated: false)
    }

    public func resetPassword(token: String, password: String, removeSessions: Bool) async throws {
        try await requestVoid(.patch, "auth/account/reset_password", body: ResetPasswordPayload(
            token: token,
            password: password,
            removeSessions: removeSessions
        ), authenticated: false)
    }

    public struct VoiceCredentials: Decodable, Sendable {
        public let token: String
        public let url: String
    }

    private struct JoinCallPayload: Encodable, Sendable {
        let node: String?
        let forceDisconnect: Bool?
        let recipients: [String]?

        enum CodingKeys: String, CodingKey {
            case node, recipients
            case forceDisconnect = "force_disconnect"
        }
    }

    /// Joins a voice call. `node` is only used when the call hasn't started yet; `forceDisconnect`
    /// ends a call the user is in elsewhere; `recipients` are notified if this starts the call.
    public func joinCall(channelId: String, node: String?, forceDisconnect: Bool = false, recipients: [String]? = nil) async throws -> VoiceCredentials {
        try await request(.post, "channels/\(channelId)/join_call", body: JoinCallPayload(
            node: node,
            forceDisconnect: forceDisconnect ? true : nil,
            recipients: recipients
        ))
    }

    public enum DiscoverKind: String, Sendable {
        case server = "servers"
        case bot = "bots"
    }

    /// The request to list a server or bot on Discover. Stoat answers NotFound if there isn't one.
    public func fetchDiscoverRequest(_ kind: DiscoverKind, id: String) async throws -> DiscoverRequest {
        try await request(.get, "\(kind.rawValue)/\(id)/discover")
    }

    public func requestDiscoverListing(_ kind: DiscoverKind, id: String) async throws {
        try await requestVoid(.put, "\(kind.rawValue)/\(id)/discover")
    }

    public func cancelDiscoverRequest(_ kind: DiscoverKind, id: String) async throws {
        try await requestVoid(.delete, "\(kind.rawValue)/\(id)/discover")
    }

    public func fetchMessage(channelId: String, messageId: String) async throws -> Message {
        try await request(.get, "channels/\(channelId)/messages/\(messageId)")
    }

    public struct ReplyIntent: Encodable, Sendable, Hashable {
        public let id: String
        public let mention: Bool

        public init(id: String, mention: Bool) {
            self.id = id
            self.mention = mention
        }
    }

    public struct SendMessagePayload: Encodable, Sendable {
        public let content: String?
        public let attachments: [String]?
        public let replies: [ReplyIntent]?

        public init(content: String?, attachments: [String]?, replies: [ReplyIntent]?) {
            self.content = content
            self.attachments = attachments
            self.replies = replies
        }
    }

    /// The nonce only goes in the `Idempotency-Key` header: the server records the key before
    /// reading the body, so also sending the old body `nonce` gets rejected as a duplicate.
    public func sendMessage(channelId: String, nonce: String, payload: SendMessagePayload) async throws -> Message {
        try await request(.post, "channels/\(channelId)/messages", body: payload, headers: ["Idempotency-Key": nonce])
    }

    public func editMessage(channelId: String, messageId: String, content: String) async throws -> Message {
        try await request(.patch, "channels/\(channelId)/messages/\(messageId)", body: ["content": content])
    }

    public func deleteMessage(channelId: String, messageId: String) async throws {
        try await requestVoid(.delete, "channels/\(channelId)/messages/\(messageId)")
    }

    public func addReaction(channelId: String, messageId: String, emoji: String) async throws {
        try await requestVoid(.put, "channels/\(channelId)/messages/\(messageId)/reactions/\(emoji)")
    }

    public func removeReaction(channelId: String, messageId: String, emoji: String) async throws {
        try await requestVoid(.delete, "channels/\(channelId)/messages/\(messageId)/reactions/\(emoji)")
    }

    private struct SearchPayload: Encodable {
        let query: String?
        let pinned: Bool?
        let limit: Int
        let sort: String
        let includeUsers: Bool

        enum CodingKeys: String, CodingKey {
            case query, pinned, limit, sort
            case includeUsers = "include_users"
        }
    }

    public func searchMessages(channelId: String, query: String, limit: Int = 50) async throws -> MessagesPage {
        try await request(
            .post,
            "channels/\(channelId)/search",
            body: SearchPayload(query: query, pinned: nil, limit: limit, sort: MessageSort.latest.rawValue, includeUsers: true)
        )
    }

    /// Pinned messages are fetched through search with `pinned: true`.
    public func fetchPinnedMessages(channelId: String) async throws -> MessagesPage {
        try await request(
            .post,
            "channels/\(channelId)/search",
            body: SearchPayload(query: nil, pinned: true, limit: 100, sort: MessageSort.latest.rawValue, includeUsers: true)
        )
    }

    public func pinMessage(channelId: String, messageId: String) async throws {
        try await requestVoid(.post, "channels/\(channelId)/messages/\(messageId)/pin")
    }

    public func unpinMessage(channelId: String, messageId: String) async throws {
        try await requestVoid(.delete, "channels/\(channelId)/messages/\(messageId)/pin")
    }

    // MARK: - Servers

    public struct JoinResponse: Decodable, Sendable {
        public let type: String
        public let server: Server?
        public let channels: [Channel]
        public let channel: Channel?

        enum CodingKeys: String, CodingKey {
            case type, server, channels, channel
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "Server"
            server = try c.decodeIfPresent(Server.self, forKey: .server)
            channels = try c.decodeLossyArray(Channel.self, forKey: .channels) ?? []
            channel = try c.decodeIfPresent(Channel.self, forKey: .channel)
        }
    }

    public func fetchInvite(code: String) async throws -> InvitePreview {
        try await request(.get, "invites/\(code)", authenticated: sessionToken != nil)
    }

    public func joinInvite(code: String) async throws -> JoinResponse {
        try await request(.post, "invites/\(code)")
    }

    public func deleteInvite(code: String) async throws {
        try await requestVoid(.delete, "invites/\(code)")
    }

    public func createServer(name: String, description: String? = nil) async throws -> JoinResponse {
        struct Payload: Encodable { let name: String; let description: String? }
        return try await request(.post, "servers/create", body: Payload(name: name, description: description))
    }

    public func fetchServer(id: String) async throws -> Server {
        try await request(.get, "servers/\(id)")
    }

    public struct EditServerPayload: Encodable, Sendable {
        public var name: String?
        public var description: String?
        public var icon: String?
        public var banner: String?
        public var categories: [ServerCategory]?
        public var systemMessages: SystemMessageChannels?
        public var remove: [String]?

        enum CodingKeys: String, CodingKey {
            case name, description, icon, banner, categories, remove
            case systemMessages = "system_messages"
        }

        public init(name: String? = nil, description: String? = nil, icon: String? = nil, banner: String? = nil, categories: [ServerCategory]? = nil, systemMessages: SystemMessageChannels? = nil, remove: [String]? = nil) {
            self.name = name
            self.description = description
            self.icon = icon
            self.banner = banner
            self.categories = categories
            self.systemMessages = systemMessages
            self.remove = remove
        }
    }

    public func editServer(serverId: String, _ payload: EditServerPayload) async throws -> Server {
        try await request(.patch, "servers/\(serverId)", body: payload)
    }

    // MARK: Roles and permissions

    public struct NewRoleResponse: Decodable, Sendable {
        public let id: String
        public let role: Role
    }

    public func createRole(serverId: String, name: String) async throws -> NewRoleResponse {
        struct Payload: Encodable { let name: String }
        return try await request(.post, "servers/\(serverId)/roles", body: Payload(name: name))
    }

    public struct EditRolePayload: Encodable, Sendable {
        public var name: String?
        public var colour: String?
        public var hoist: Bool?
        public var remove: [String]?

        public init(name: String? = nil, colour: String? = nil, hoist: Bool? = nil, remove: [String]? = nil) {
            self.name = name
            self.colour = colour
            self.hoist = hoist
            self.remove = remove
        }
    }

    public func editRole(serverId: String, roleId: String, _ payload: EditRolePayload) async throws -> Role {
        try await request(.patch, "servers/\(serverId)/roles/\(roleId)", body: payload)
    }

    public func deleteRole(serverId: String, roleId: String) async throws {
        try await requestVoid(.delete, "servers/\(serverId)/roles/\(roleId)")
    }

    /// Sets the order of every role on the server, most important first.
    public func editRoleRanks(serverId: String, ranks: [String]) async throws -> Server {
        struct Payload: Encodable { let ranks: [String] }
        return try await request(.patch, "servers/\(serverId)/roles/ranks", body: Payload(ranks: ranks))
    }

    public struct PermissionOverridePayload: Encodable, Sendable {
        public let allow: Int64
        public let deny: Int64

        public init(allow: Int64, deny: Int64) {
            self.allow = allow
            self.deny = deny
        }
    }

    private struct OverrideBody: Encodable { let permissions: PermissionOverridePayload }
    private struct ValueBody: Encodable { let permissions: Int64 }

    public func setServerRolePermissions(serverId: String, roleId: String, _ value: PermissionOverridePayload) async throws -> Server {
        try await request(.put, "servers/\(serverId)/permissions/\(roleId)", body: OverrideBody(permissions: value))
    }

    public func setServerDefaultPermissions(serverId: String, permissions: Int64) async throws -> Server {
        try await request(.put, "servers/\(serverId)/permissions/default", body: ValueBody(permissions: permissions))
    }

    public func setChannelRolePermissions(channelId: String, roleId: String, _ value: PermissionOverridePayload) async throws -> Channel {
        try await request(.put, "channels/\(channelId)/permissions/\(roleId)", body: OverrideBody(permissions: value))
    }

    public func setChannelDefaultPermissions(channelId: String, _ value: PermissionOverridePayload) async throws -> Channel {
        try await request(.put, "channels/\(channelId)/permissions/default", body: OverrideBody(permissions: value))
    }

    /// Permissions for members of a group, which take a plain value rather than an override.
    public func setGroupPermissions(channelId: String, permissions: Int64) async throws -> Channel {
        try await request(.put, "channels/\(channelId)/permissions/default", body: ValueBody(permissions: permissions))
    }

    /// Leaves a server; if the current user owns it, the server is deleted.
    public func leaveOrDeleteServer(serverId: String, leaveSilently: Bool = false) async throws {
        let query = leaveSilently ? [URLQueryItem(name: "leave_silently", value: "true")] : []
        try await requestVoid(.delete, "servers/\(serverId)", query: query)
    }

    /// Audit log entries, newest first. `types` filters by action type (e.g. `BanCreate`).
    public func fetchAuditLogs(serverId: String, before: String? = nil, types: [String] = [], limit: Int = 50) async throws -> AuditLogPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        query += types.map { URLQueryItem(name: "type", value: $0) }
        return try await request(.get, "servers/\(serverId)/audit_logs", query: query)
    }

    public func acknowledgeServer(serverId: String) async throws {
        try await requestVoid(.put, "servers/\(serverId)/ack")
    }

    public func createChannel(serverId: String, name: String, type: ChannelType, description: String? = nil) async throws -> Channel {
        struct Payload: Encodable { let type: String; let name: String; let description: String? }
        let legacyType = type == .voiceChannel ? "Voice" : "Text"
        return try await request(.post, "servers/\(serverId)/channels", body: Payload(type: legacyType, name: name, description: description))
    }

    public func fetchServerInvites(serverId: String) async throws -> [Invite] {
        try await request(.get, "servers/\(serverId)/invites")
    }

    public struct ServerMembersResponse: Decodable, Sendable {
        public let members: [ServerMember]
        public let users: [User]

        enum CodingKeys: String, CodingKey { case members, users }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            members = try c.decodeLossyArray(ServerMember.self, forKey: .members) ?? []
            users = try c.decodeLossyArray(User.self, forKey: .users) ?? []
        }
    }

    public func fetchServerMembers(serverId: String, excludeOffline: Bool = false) async throws -> ServerMembersResponse {
        let query = excludeOffline ? [URLQueryItem(name: "exclude_offline", value: "true")] : []
        return try await request(.get, "servers/\(serverId)/members", query: query)
    }

    /// Up to 10 members whose nickname or username contains `query` (case-sensitive), without
    /// downloading the whole member list.
    public func queryServerMembers(serverId: String, query: String) async throws -> ServerMembersResponse {
        try await request(.get, "servers/\(serverId)/members_experimental_query", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "experimental_api", value: "true")
        ])
    }

    public func fetchMember(serverId: String, userId: String) async throws -> ServerMember {
        try await request(.get, "servers/\(serverId)/members/\(userId)")
    }

    public struct EditMemberPayload: Encodable, Sendable {
        public var nickname: String?
        public var avatar: String?
        public var roles: [String]?
        public var timeout: String?
        public var remove: [String]?

        public init(nickname: String? = nil, avatar: String? = nil, roles: [String]? = nil, timeout: String? = nil, remove: [String]? = nil) {
            self.nickname = nickname
            self.avatar = avatar
            self.roles = roles
            self.timeout = timeout
            self.remove = remove
        }
    }

    public func editMember(serverId: String, userId: String, _ payload: EditMemberPayload) async throws -> ServerMember {
        try await request(.patch, "servers/\(serverId)/members/\(userId)", body: payload)
    }

    public func kickMember(serverId: String, userId: String) async throws {
        try await requestVoid(.delete, "servers/\(serverId)/members/\(userId)")
    }

    /// `deleteMessageSeconds` removes what they sent in the server over that many seconds, up to a week.
    public func banMember(serverId: String, userId: String, reason: String?, deleteMessageSeconds: Int = 0) async throws {
        struct Payload: Encodable {
            let reason: String?
            let delete_message_seconds: Int?
        }
        let payload = Payload(reason: reason, delete_message_seconds: deleteMessageSeconds > 0 ? min(deleteMessageSeconds, 604_800) : nil)
        try await requestVoid(.put, "servers/\(serverId)/bans/\(userId)", body: payload)
    }

    public func unbanMember(serverId: String, userId: String) async throws {
        try await requestVoid(.delete, "servers/\(serverId)/bans/\(userId)")
    }

    public func fetchBans(serverId: String) async throws -> ServerBansResponse {
        try await request(.get, "servers/\(serverId)/bans")
    }

    // MARK: - Custom Emojis

    public struct CreateEmojiPayload: Encodable, Sendable {
        public let name: String
        public let parent: EmojiParent
        public let nsfw: Bool

        public init(name: String, parent: EmojiParent, nsfw: Bool = false) {
            self.name = name
            self.parent = parent
            self.nsfw = nsfw
        }
    }

    public func fetchEmoji(emojiId: String) async throws -> Emoji {
        try await request(.get, "custom/emoji/\(emojiId)")
    }

    /// Registers an emoji using an Autumn upload ID from the `emojis` tag.
    public func createEmoji(uploadId: String, payload: CreateEmojiPayload) async throws -> Emoji {
        try await request(.put, "custom/emoji/\(uploadId)", body: payload)
    }

    public func deleteEmoji(emojiId: String) async throws {
        try await requestVoid(.delete, "custom/emoji/\(emojiId)")
    }

    // MARK: - Safety

    public enum ReportTarget: Sendable {
        case message(id: String)
        case server(id: String)
        case user(id: String, messageId: String?)
    }

    public func report(_ target: ReportTarget, reason: String, additionalContext: String) async throws {
        struct Content: Encodable {
            let type: String
            let id: String
            let reportReason: String
            let messageId: String?

            enum CodingKeys: String, CodingKey {
                case type, id
                case reportReason = "report_reason"
                case messageId = "message_id"
            }
        }
        struct Payload: Encodable {
            let content: Content
            let additionalContext: String

            enum CodingKeys: String, CodingKey {
                case content
                case additionalContext = "additional_context"
            }
        }

        let content: Content
        switch target {
        case .message(let id):
            content = Content(type: "Message", id: id, reportReason: reason, messageId: nil)
        case .server(let id):
            content = Content(type: "Server", id: id, reportReason: reason, messageId: nil)
        case .user(let id, let messageId):
            content = Content(type: "User", id: id, reportReason: reason, messageId: messageId)
        }
        try await requestVoid(.post, "safety/report", body: Payload(content: content, additionalContext: additionalContext))
    }

    // MARK: - Settings sync

    /// Fetches synced settings. Each value is `[updatedAt, jsonString]`.
    public func fetchSettings(keys: [String]) async throws -> [String: SyncedSetting] {
        try await request(.post, "sync/settings/fetch", body: ["keys": keys])
    }

    public func setSettings(_ values: [String: String]) async throws {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        try await requestVoid(.post, "sync/settings/set", query: [URLQueryItem(name: "timestamp", value: timestamp)], body: values)
    }

    // MARK: - HTTP

    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private struct NoBody: Encodable {}

    private func makeURL(_ path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw StoatAPIError.invalidURL
        }
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        if !path.isEmpty {
            let encodedPath = path
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { segment in
                    segment.addingPercentEncoding(withAllowedCharacters: .stoatPathSegmentAllowed) ?? String(segment)
                }
                .joined(separator: "/")
            components.percentEncodedPath = basePath + "/" + encodedPath
        } else {
            components.percentEncodedPath = basePath + "/"
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw StoatAPIError.invalidURL }
        return url
    }

    private func request<T: Decodable, B: Encodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: B? = nil as NoBody?,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, headers: headers, authenticated: authenticated)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[Delta] Failed to decode \(T.self) from \(method.rawValue) \(path): \(error)")
            #endif
            throw StoatAPIError.decodingError(String(describing: error))
        }
    }

    private func requestVoid<B: Encodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: B? = nil as NoBody?,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws {
        _ = try await perform(method, path, query: query, body: body, headers: headers, authenticated: authenticated)
    }

    private func perform<B: Encodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        body: B?,
        headers: [String: String],
        authenticated: Bool,
        attempt: Int = 0
    ) async throws -> Data {
        var urlRequest = URLRequest(url: try makeURL(path, query: query))
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("Yuki-iOS/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let sessionToken {
            urlRequest.setValue(sessionToken, forHTTPHeaderField: "X-Session-Token")
        }
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw StoatAPIError.network(Self.describe(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoatAPIError.unknown
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            // Login failures are also 401s, but carry a specific type such as InvalidCredentials.
            let type = try? JSONDecoder().decode(ServerErrorBody.self, from: data).type
            if let type, type != "InvalidSession" {
                throw StoatAPIError.server(statusCode: 401, type: type)
            }
            throw StoatAPIError.unauthorized
        case 429:
            let resetMs = Double(httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset-After") ?? "") ?? 1000
            let retryAfter = max(0.25, resetMs / 1000)
            // Wait out short limits once rather than surfacing an error.
            if attempt == 0, retryAfter <= 5 {
                try await Task.sleep(for: .seconds(retryAfter))
                return try await perform(method, path, query: query, body: body, headers: headers, authenticated: authenticated, attempt: 1)
            }
            throw StoatAPIError.rateLimited(retryAfter: retryAfter)
        default:
            let type = try? JSONDecoder().decode(ServerErrorBody.self, from: data).type
            // The path only: never the body, which holds message text and other people's details.
            // Verification codes travel in the path, so that part is left out too.
            let loggedPath = path.hasPrefix("auth/account/verify/") ? "auth/account/verify/…" : path
            DiagnosticsLog.log(.network, "\(method.rawValue) \(loggedPath) → \(httpResponse.statusCode) \(type ?? "")")
            if type == "InvalidSession" {
                throw StoatAPIError.unauthorized
            }
            throw StoatAPIError.server(statusCode: httpResponse.statusCode, type: type)
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You're offline. Check your connection and try again."
        case .timedOut:
            return "Stoat took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Couldn't reach the server."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return "Couldn't establish a secure connection to the server."
        default:
            return error.localizedDescription
        }
    }
}

private struct ServerErrorBody: Decodable {
    let type: String?
}

public struct SyncedSetting: Decodable, Sendable {
    public let updatedAt: Int64
    public let value: String

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        updatedAt = try c.decode(Int64.self)
        value = try c.decode(String.self)
    }
}

extension CharacterSet {
    /// Path segment characters left unescaped; everything else (including emoji) is percent-encoded once.
    static let stoatPathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@"
    )
}

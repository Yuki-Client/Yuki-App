import Foundation
import StoatCore

extension AppStore {
    func handleGatewayEvent(_ event: GatewayEvent) async {
        switch event {
        case .bulk(let events):
            for item in events {
                await handleGatewayEvent(item)
            }

        case .authenticated, .pong, .unknown:
            break

        case .logout:
            await handleSessionInvalidated()

        case .error(let type):
            if type == "InvalidSession" || type == "NotAuthenticated" {
                await handleSessionInvalidated()
            } else {
                DiagnosticsLog.shared.record(.gateway, "Error from Stoat: \(type)")
            }

        case .ready(let ready):
            await handleReady(ready)

        case .message(let message):
            handleIncomingMessage(message)

        case .messageUpdate(let id, let channelId, let data, let clear):
            store.existingTimeline(for: channelId)?.update(id: id) { message in
                if let content = data.content { message.content = content }
                if let edited = data.edited { message.edited = edited }
                if let pinned = data.pinned { message.pinned = pinned }
                if let embeds = data.embeds { message.embeds = embeds }
                if let reactions = data.reactions { message.reactions = reactions }
                if clear.contains("Pinned") { message.pinned = nil }
            }
            updateNotification(id: id) { message in
                if let content = data.content { message.content = content }
                if let edited = data.edited { message.edited = edited }
                if let embeds = data.embeds { message.embeds = embeds }
            }

        case .messageAppend(let id, let channelId, let embeds):
            store.existingTimeline(for: channelId)?.update(id: id) { message in
                message.embeds = (message.embeds ?? []) + embeds
            }

        case .messageDelete(let id, let channelId):
            forgetMentions([id], in: channelId)
            store.existingTimeline(for: channelId)?.remove(id: id)
            replyingTo.removeAll { $0.message.id == id }
            if editingMessage?.id == id { editingMessage = nil }
            removeNotifications(ids: [id])
            correctLastMessageAfterDelete(channelId: channelId, deletedIds: [id])

        case .bulkMessageDelete(let channelId, let ids):
            forgetMentions(Set(ids), in: channelId)
            store.existingTimeline(for: channelId)?.remove(ids: Set(ids))
            removeNotifications(ids: Set(ids))
            correctLastMessageAfterDelete(channelId: channelId, deletedIds: Set(ids))

        case .messageReact(let id, let channelId, let userId, let emoji):
            store.existingTimeline(for: channelId)?.update(id: id) { message in
                var users = message.reactions[emoji] ?? []
                if !users.contains(userId) {
                    users.append(userId)
                    message.reactions[emoji] = users
                }
            }

        case .messageUnreact(let id, let channelId, let userId, let emoji):
            store.existingTimeline(for: channelId)?.update(id: id) { message in
                guard var users = message.reactions[emoji] else { return }
                users.removeAll { $0 == userId }
                let isRestricted = message.interactions?.reactions?.contains(emoji) == true
                if users.isEmpty && !isRestricted {
                    message.reactions.removeValue(forKey: emoji)
                } else {
                    message.reactions[emoji] = users
                }
            }

        case .messageRemoveReaction(let id, let channelId, let emoji):
            store.existingTimeline(for: channelId)?.update(id: id) { message in
                message.reactions.removeValue(forKey: emoji)
            }

        case .channelCreate(let channel):
            store.channels[channel.id] = channel
            if let serverId = channel.server, var server = store.servers[serverId], !server.channels.contains(channel.id) {
                server.channels.append(channel.id)
                store.servers[serverId] = server
            }
            scheduleCacheSave()

        case .channelUpdate(let id, let data, let clear):
            guard var channel = store.channels[id] else { break }
            if let name = data.name { channel.name = name }
            if let owner = data.owner { channel.owner = owner }
            if let description = data.description { channel.description = description }
            if let icon = data.icon { channel.icon = icon }
            if let nsfw = data.nsfw { channel.nsfw = nsfw }
            if let active = data.active { channel.active = active }
            if let permissions = data.permissions { channel.permissions = permissions }
            if let rolePermissions = data.rolePermissions { channel.rolePermissions = rolePermissions }
            if let defaultPermissions = data.defaultPermissions { channel.defaultPermissions = defaultPermissions }
            if let lastMessageId = data.lastMessageId { channel.lastMessageId = lastMessageId }
            if let voice = data.voice { channel.voice = voice }
            if let slowmode = data.slowmode { channel.slowmode = slowmode }
            for field in clear {
                switch field {
                case "Description": channel.description = nil
                case "Icon": channel.icon = nil
                case "DefaultPermissions": channel.defaultPermissions = nil
                case "Voice": channel.voice = nil
                case "Slowmode": channel.slowmode = nil
                default: break
                }
            }
            store.channels[id] = channel
            scheduleCacheSave()

        case .channelDelete(let channelId):
            removeChannelLocally(channelId)

        case .channelGroupJoin(let channelId, let userId):
            guard var channel = store.channels[channelId] else { break }
            var recipients = channel.recipients ?? []
            if !recipients.contains(userId) {
                recipients.append(userId)
                channel.recipients = recipients
                store.channels[channelId] = channel
            }
            queueUserFetch([userId])

        case .channelGroupLeave(let channelId, let userId):
            if userId == store.currentUserId {
                removeChannelLocally(channelId)
            } else if var channel = store.channels[channelId] {
                channel.recipients?.removeAll { $0 == userId }
                store.channels[channelId] = channel
            }

        case .channelStartTyping(let channelId, let userId):
            guard userId != store.currentUserId else { break }
            store.typingUsers[channelId, default: []].insert(userId)
            queueUserFetch([userId])
            let key = "\(channelId):\(userId)"
            typingTasks[key]?.cancel()
            typingTasks[key] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                self.store.typingUsers[channelId]?.remove(userId)
                self.typingTasks[key] = nil
            }

        case .channelStopTyping(let channelId, let userId):
            store.typingUsers[channelId]?.remove(userId)
            typingTasks["\(channelId):\(userId)"]?.cancel()

        case .channelAck(let channelId, let userId, let messageId):
            guard userId == store.currentUserId else { break }
            store.markRead(channelId: channelId, messageId: messageId)
            if let pending = pendingAcks[channelId], pending <= messageId {
                setPendingAck(nil, for: channelId)
            }
            NotificationManager.shared.removeNotifications(forChannel: channelId)
            updateBadge()

        case .serverCreate(let server, let channels, let emojis):
            store.servers[server.id] = server
            for channel in channels {
                store.channels[channel.id] = channel
            }
            for emoji in emojis {
                store.emojis[emoji.id] = emoji
            }
            scheduleCacheSave()

        case .serverUpdate(let id, let data, let clear):
            guard var server = store.servers[id] else { break }
            if let owner = data.owner { server.owner = owner }
            if let name = data.name { server.name = name }
            if let description = data.description { server.description = description }
            if let channels = data.channels { server.channels = channels }
            if let categories = data.categories { server.categories = categories }
            if let systemMessages = data.systemMessages { server.systemMessages = systemMessages }
            if let roles = data.roles { server.roles = roles }
            if let defaultPermissions = data.defaultPermissions { server.defaultPermissions = defaultPermissions }
            if let icon = data.icon { server.icon = icon }
            if let banner = data.banner { server.banner = banner }
            if let flags = data.flags { server.flags = flags }
            if let nsfw = data.nsfw { server.nsfw = nsfw }
            if let discoverable = data.discoverable { server.discoverable = discoverable }
            for field in clear {
                switch field {
                case "Description": server.description = nil
                case "Categories": server.categories = nil
                case "SystemMessages": server.systemMessages = nil
                case "Icon": server.icon = nil
                case "Banner": server.banner = nil
                default: break
                }
            }
            store.servers[id] = server
            scheduleCacheSave()

        case .serverDelete(let id):
            removeServerLocally(id)

        case .serverMemberJoin(let serverId, let userId, let member):
            let resolved = member ?? ServerMember(key: ServerMemberId(server: serverId, user: userId), joinedAt: StoatDate.string(from: Date()))
            store.upsert(members: [resolved])
            queueUserFetch([userId])

        case .serverMemberUpdate(let key, let data, let clear):
            guard var member = store.members[key.server]?[key.user] else { break }
            if let joinedAt = data.joinedAt { member.joinedAt = joinedAt }
            if let nickname = data.nickname { member.nickname = nickname }
            if let pronouns = data.pronouns { member.pronouns = pronouns }
            if let avatar = data.avatar { member.avatar = avatar }
            if let roles = data.roles { member.roles = roles }
            if let timeout = data.timeout { member.timeout = timeout }
            if let canPublish = data.canPublish { member.canPublish = canPublish }
            if let canReceive = data.canReceive { member.canReceive = canReceive }
            for field in clear {
                switch field {
                case "Nickname": member.nickname = nil
                case "Pronouns": member.pronouns = nil
                case "Avatar": member.avatar = nil
                case "Roles": member.roles = []
                case "Timeout": member.timeout = nil
                default: break
                }
            }
            store.members[key.server, default: [:]][key.user] = member

        case .serverMemberLeave(let serverId, let userId):
            if userId == store.currentUserId {
                removeServerLocally(serverId)
            } else {
                store.members[serverId]?.removeValue(forKey: userId)
            }

        case .serverRoleUpdate(let serverId, let roleId, let data, let clear):
            guard var server = store.servers[serverId] else { break }
            var role = server.roles[roleId] ?? Role(name: data.name ?? "New Role")
            if let name = data.name { role.name = name }
            if let permissions = data.permissions { role.permissions = permissions }
            if let colour = data.colour { role.colour = colour }
            if let hoist = data.hoist { role.hoist = hoist }
            if let rank = data.rank { role.rank = rank }
            if let icon = data.icon { role.icon = icon }
            if clear.contains("Colour") { role.colour = nil }
            if clear.contains("Icon") { role.icon = nil }
            server.roles[roleId] = role
            store.servers[serverId] = server

        case .serverRoleDelete(let serverId, let roleId):
            store.servers[serverId]?.roles.removeValue(forKey: roleId)

        case .serverRoleRanksUpdate(let serverId, let ranks):
            guard var server = store.servers[serverId] else { break }
            for (index, roleId) in ranks.enumerated() {
                server.roles[roleId]?.rank = Int64(index)
            }
            store.servers[serverId] = server

        case .userSlowmodes(let slowmodes):
            for slowmode in slowmodes {
                slowmodeUntil[slowmode.channelId] = Date().addingTimeInterval(TimeInterval(slowmode.retryAfter))
            }

        case .userUpdate(let id, let data, let clear):
            guard var user = store.users[id] else { break }
            if let username = data.username { user.username = username }
            if let discriminator = data.discriminator { user.discriminator = discriminator }
            if let displayName = data.displayName { user.displayName = displayName }
            if let pronouns = data.pronouns { user.pronouns = pronouns }
            if let avatar = data.avatar { user.avatar = avatar }
            if let badges = data.badges { user.badges = badges }
            if let status = data.status {
                var merged = user.status ?? UserStatus()
                if let text = status.text { merged.text = text }
                if let presence = status.presence { merged.presence = presence }
                user.status = merged
            }
            if let flags = data.flags { user.flags = flags }
            if let privileged = data.privileged { user.privileged = privileged }
            if let bot = data.bot { user.bot = bot }
            if let relationship = data.relationship { user.relationship = relationship }
            if let online = data.online { user.online = online }
            for field in clear {
                switch field {
                case "Avatar": user.avatar = nil
                case "StatusText": user.status?.text = nil
                case "StatusPresence": user.status?.presence = nil
                case "DisplayName": user.displayName = nil
                case "Pronouns": user.pronouns = nil
                case "ProfileContent", "ProfileBackground": profiles.removeValue(forKey: id)
                default: break
                }
            }
            store.users[id] = user

        case .userRelationship(let user):
            var merged = store.users[user.id] ?? user
            merged.relationship = user.relationship
            store.users[user.id] = merged

        case .userSettingsUpdate(let update):
            applySyncedSettings(update)

        case .userPlatformWipe(let userId, let flags):
            for timeline in store.timelines.values {
                timeline.removeAll { $0.author == userId }
            }
            if var user = store.users[userId] {
                user.username = "Deleted User"
                user.displayName = nil
                user.avatar = nil
                user.status = nil
                user.online = false
                user.badges = 0
                user.flags = flags
                user.relationship = .none
                store.users[userId] = user
            }

        case .emojiCreate(let emoji):
            store.emojis[emoji.id] = emoji

        case .emojiUpdate(let id, let name):
            if let name {
                store.emojis[id]?.name = name
            }

        case .emojiDelete(let id):
            store.emojis.removeValue(forKey: id)

        case .voiceChannelJoin(let channelId, let state):
            store.voiceStates[channelId, default: [:]][state.id] = state
            // Answered, here or on another device.
            if state.id == store.currentUserId, incomingCall?.channelId == channelId {
                dismissIncomingCall()
            }

        case .voiceCallUpdate(let initiatorId, let channelId, let ended):
            if ended {
                if incomingCall?.channelId == channelId {
                    dismissIncomingCall()
                }
            } else {
                receiveIncomingCall(channelId: channelId, callerId: initiatorId)
            }

        case .voiceChannelLeave(let channelId, let userId):
            store.voiceStates[channelId]?.removeValue(forKey: userId)

        case .voiceChannelMove(let userId, let from, let to, let state):
            store.voiceStates[from]?.removeValue(forKey: userId)
            store.voiceStates[to, default: [:]][userId] = state

        case .userVoiceStateUpdate(let userId, let channelId, let data):
            guard var state = store.voiceStates[channelId]?[userId] else { break }
            if let value = data.isReceiving { state.isReceiving = value }
            if let value = data.isPublishing { state.isPublishing = value }
            if let value = data.screensharing { state.screensharing = value }
            if let value = data.camera { state.camera = value }
            store.voiceStates[channelId]?[userId] = state
        }
    }

    // MARK: - Ready

    private func handleReady(_ ready: ReadyPayload) async {
        store.ingest(ready: ready)

        if let current = selectedChannelId, store.channels[current] == nil {
            selectedChannelId = nil
        }
        if let server = selectedServerId, store.servers[server] == nil {
            selectedServerId = nil
        }

        // Anything could have been missed while disconnected.
        for timeline in store.timelines.values {
            timeline.isSynced = false
        }
        async let unreads: Void = syncUnreads()
        async let settings: Void = syncSettings()
        if let channelId = selectedChannelId {
            await loadLatestMessages(channelId: channelId)
        }
        if let serverId = selectedServerId {
            sendGatewayCommand(.subscribe(serverId: serverId))
        }

        if !ready.policyChanges.isEmpty {
            pendingPolicyChanges = ready.policyChanges
        }

        await unreads
        if isAppActive, periodicUnreadSync == nil {
            startPeriodicUnreadSync()
        }
        await settings
        scheduleCacheSave()
        await fetchMissedNotifications()
    }

    public func syncUnreads() async {
        do {
            let unreads = try await apiClient.fetchUnreads()
            var merged = Dictionary(unreads.map { ($0.id.channel, $0) }, uniquingKeysWith: { _, new in new })
            let now = Date()
            confirmedAcks = confirmedAcks.filter { now.timeIntervalSince($0.value.at) < 120 }
            // Reads Stoat hasn't applied yet would otherwise come back as unread.
            var readAhead = confirmedAcks.mapValues(\.messageId)
            readAhead.merge(pendingAcks) { max($0, $1) }
            if let userId = store.currentUserId {
                for (channelId, messageId) in readAhead {
                    var entry = merged[channelId] ?? ChannelUnread(channel: channelId, user: userId)
                    guard (entry.lastId ?? "0") < messageId else {
                        // Stoat is already there, possibly further on from another device. Sending
                        // this now would move it back, since Stoat takes whatever it's given.
                        if pendingAcks[channelId] == messageId {
                            setPendingAck(nil, for: channelId)
                        }
                        continue
                    }
                    entry.lastId = messageId
                    entry.mentions = entry.mentions.filter { $0 > messageId }
                    merged[channelId] = entry
                }
            }
            if !deletedMentionIds.isEmpty {
                for (channelId, entry) in merged where entry.mentions.contains(where: deletedMentionIds.contains) {
                    merged[channelId]?.mentions.removeAll(where: deletedMentionIds.contains)
                }
            }
            store.unreads = merged
            store.unreadsLoaded = true
            lastUnreadSync = Date()
            updateBadge()
            flushPendingAcks()
            clearStaleMentions()
        } catch {
            DiagnosticsLog.shared.record(.network, "Couldn't sync unreads: \(error)")
        }
    }

    func syncSettings() async {
        do {
            let settings = try await apiClient.fetchSettings(keys: ["ordering", "server-folders", "notifications"])
            applySyncedSettings(settings)
        } catch {
            DiagnosticsLog.shared.record(.network, "Couldn't sync settings: \(error)")
        }
    }

    private func applySyncedSettings(_ settings: [String: SyncedSetting]) {
        if let ordering = settings["ordering"],
           let parsed = try? JSONDecoder().decode(ServerOrderingSetting.self, from: Data(ordering.value.utf8)) {
            store.serverOrder = parsed.servers
            // A client without folders writes only `servers`, which puts folders back where their
            // first server is, the same as Stoat for Web does.
            store.serverSidebar = parsed.serverSidebar
        }
        if let folders = settings["server-folders"],
           let parsed = try? JSONDecoder().decode(ServerFoldersSetting.self, from: Data(folders.value.utf8)) {
            store.serverFolders = ServerFolder.cleaned(parsed.folders)
        }
        if let notifications = settings["notifications"],
           let parsed = try? JSONDecoder().decode(NotificationOptions.self, from: Data(notifications.value.utf8)) {
            store.notificationOptions = parsed
            updateBadge()
        }
    }

    // MARK: - Messages

    /// If a channel's newest message was deleted, finds the real newest one. Otherwise a message
    /// removed moments after it was sent (e.g. by AutoMod) leaves the channel unread with nothing new.
    private func correctLastMessageAfterDelete(channelId: String, deletedIds: Set<String>) {
        guard let channel = store.channels[channelId], let last = channel.lastMessageId, deletedIds.contains(last) else { return }
        // Only worth checking when the deleted message is what makes the channel look unread.
        guard (store.unreads[channelId]?.lastId ?? "0") < last else { return }

        if let timeline = store.existingTimeline(for: channelId), timeline.isSynced, !timeline.isViewingHistory {
            setLastMessageId(timeline.newestMessageId, for: channelId, replacing: last)
            return
        }
        lastMessageRefreshTasks[channelId]?.cancel()
        lastMessageRefreshTasks[channelId] = Task { [weak self] in
            // Deletions often come in bursts.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.lastMessageRefreshTasks[channelId] = nil
            guard let page = try? await self.apiClient.fetchMessages(channelId: channelId, limit: 1) else { return }
            self.setLastMessageId(page.messages.map(\.id).max(), for: channelId, replacing: last)
        }
    }

    private func setLastMessageId(_ newest: String?, for channelId: String, replacing deleted: String) {
        guard var channel = store.channels[channelId], channel.lastMessageId == deleted else { return }
        channel.lastMessageId = newest
        store.channels[channelId] = channel
        updateBadge()
        scheduleCacheSave()
    }

    private func handleIncomingMessage(_ message: Message) {
        if let user = message.user {
            store.upsert(users: [user])
        }
        if let member = message.member {
            store.upsert(members: [member])
        }

        // Stoat sends every visible channel's messages; only keep them for channels already loaded,
        // and cap background ones.
        let timeline = store.existingTimeline(for: message.channel)
            ?? (message.channel == selectedChannelId ? store.timeline(for: message.channel) : nil)
        if let timeline {
            guard timeline.upsert(message) else { return }
            if message.channel != selectedChannelId, timeline.messages.count > 200 {
                timeline.trim(keepingLast: 150)
            }
        }

        if var channel = store.channels[message.channel] {
            channel.lastMessageId = message.id
            if channel.channelType == .directMessage, channel.active == false {
                channel.active = true
            }
            store.channels[message.channel] = channel
        }

        if store.users[message.author] == nil, message.webhook == nil, message.system == nil {
            queueUserFetch([message.author])
        }
        if let referenced = message.system?.referencedUserIds {
            queueUserFetch(referenced.filter { store.users[$0] == nil })
        }
        store.typingUsers[message.channel]?.remove(message.author)
        recordNotification(for: message)

        let isOwnMessage = message.author == store.currentUserId
        let isViewing = isAppActive && viewingChannelId == message.channel

        if isOwnMessage || isViewing {
            if isOwnMessage {
                store.markRead(channelId: message.channel, messageId: message.id)
                // Stoat doesn't count your own message as read, so without this the channel
                // comes back unread at the next sync, and on every other client.
                if isAppActive {
                    acknowledge(message.id, in: message.channel)
                }
            } else {
                markChannelAsRead(message.channel)
                if store.mentionsMe(message) {
                    scheduleFollowUpUnreadSync()
                }
            }
        } else {
            if let userId = store.currentUserId, store.mentionsMe(message) {
                var unread = store.unreads[message.channel] ?? ChannelUnread(channel: message.channel, user: userId)
                if !unread.mentions.contains(message.id) {
                    unread.mentions.append(message.id)
                }
                store.unreads[message.channel] = unread
            }
            notifyIfNeeded(for: message)
        }

        updateBadge()
        scheduleCacheSave()
    }

    private func notifyIfNeeded(for message: Message) {
        guard let channel = store.channels[message.channel],
              let userId = store.currentUserId,
              !message.suppressesNotifications,
              message.system == nil,
              !store.isMuted(channel: channel) else { return }

        if let author = store.users[message.author], author.relationship == .blocked {
            return
        }

        let mentionsMe = message.mentions?.contains(userId) == true
        let roleMentioned: Bool = {
            guard let serverId = channel.server, let roleMentions = message.roleMentions else { return false }
            let myRoles = Set(store.member(userId: userId, in: serverId)?.roles ?? [])
            return roleMentions.contains { myRoles.contains($0) }
        }()
        let level = store.notificationOptions.level(for: channel)
        let shouldNotify: Bool
        switch level {
        case .all: shouldNotify = true
        case .mention: shouldNotify = mentionsMe || roleMentioned || message.mentionsEveryone
        case .none: shouldNotify = false
        }
        guard shouldNotify else { return }

        let authorName = message.masquerade?.name
            ?? message.webhook?.name
            ?? store.displayName(userId: message.author, serverId: channel.server)
        let title: String
        switch channel.channelType {
        case .directMessage:
            title = authorName
        case .group:
            title = "\(authorName) in \(channel.displayName(withUsers: store.users, currentUserId: userId))"
        default:
            let serverName = channel.server.flatMap { store.servers[$0]?.name } ?? ""
            title = "\(authorName) in #\(channel.name ?? "channel")" + (serverName.isEmpty ? "" : " • \(serverName)")
        }
        if isAppActive {
            incomingNotification = IncomingNotification(
                id: message.id,
                channelId: message.channel,
                title: title,
                body: notificationBody(for: message, serverId: channel.server, keepingEmoji: true),
                authorId: message.author
            )
        } else {
            let body = notificationBody(for: message, serverId: channel.server, keepingEmoji: false)
            NotificationManager.shared.postMessageNotification(title: title, body: body, channelId: message.channel, messageId: message.id)
        }
    }

    /// System notifications can't draw custom emoji, so they get `:name:` instead.
    func notificationBody(for message: Message, serverId: String?, keepingEmoji: Bool) -> String {
        if let content = message.content, !content.isEmpty {
            let preview = MentionFormatter.previewText(content, store: store, serverId: serverId)
            return keepingEmoji ? preview : MentionFormatter.plainText(preview, store: store, serverId: serverId)
        }
        if let count = message.attachments?.count, count > 0 {
            return count == 1 ? "Sent an attachment" : "Sent \(count) attachments"
        }
        return "Sent a message"
    }

    // MARK: - Local removal

    func removeChannelLocally(_ channelId: String) {
        let serverId = store.channels[channelId]?.server
        store.channels.removeValue(forKey: channelId)
        store.removeTimeline(for: channelId)
        store.unreads.removeValue(forKey: channelId)
        if let serverId, var server = store.servers[serverId] {
            server.channels.removeAll { $0 == channelId }
            store.servers[serverId] = server
        }
        if selectedChannelId == channelId {
            selectedChannelId = nil
        }
        updateBadge()
        scheduleCacheSave()
    }

    func removeServerLocally(_ serverId: String) {
        let channelIds = store.channels.values.filter { $0.server == serverId }.map(\.id)
        for channelId in channelIds {
            store.channels.removeValue(forKey: channelId)
            store.removeTimeline(for: channelId)
            store.unreads.removeValue(forKey: channelId)
        }
        store.servers.removeValue(forKey: serverId)
        store.members.removeValue(forKey: serverId)
        store.emojis = store.emojis.filter { $0.value.parent.serverId != serverId }
        if selectedServerId == serverId {
            selectedServerId = nil
            selectedChannelId = nil
        }
        updateBadge()
        scheduleCacheSave()
    }

    // MARK: - User resolution

    public func queueUserFetch(_ ids: [String]) {
        let missing = ids.filter { store.users[$0] == nil && !unknownUserIds.contains($0) && $0 != "00000000000000000000000000" }
        guard !missing.isEmpty else { return }
        pendingUserFetches.formUnion(missing)
        guard userFetchTask == nil else { return }
        userFetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            let batch = Array(self.pendingUserFetches.prefix(25))
            self.pendingUserFetches.subtract(batch)
            await withTaskGroup(of: (String, User?, Bool).self) { group in
                for id in batch {
                    group.addTask {
                        do {
                            return (id, try await self.apiClient.fetchUser(id: id), false)
                        } catch let error as StoatAPIError {
                            if case .server(404, _) = error { return (id, nil, true) }
                            return (id, nil, error.serverType == "NotFound")
                        } catch {
                            return (id, nil, false)
                        }
                    }
                }
                var fetched: [User] = []
                for await (id, user, notFound) in group {
                    if let user { fetched.append(user) }
                    if notFound { self.unknownUserIds.insert(id) }
                }
                self.store.upsert(users: fetched)
            }
            self.userFetchTask = nil
            // Anything past the batch limit, or queued while fetching, goes in the next round.
            if !self.pendingUserFetches.isEmpty {
                self.queueUserFetch(Array(self.pendingUserFetches))
            }
        }
    }
}

// MARK: - Stale mentions

extension AppStore {
    /// Stoat keeps listing deleted messages as mentions, so they're remembered here.
    func forgetMentions(_ ids: Set<String>, in channelId: String) {
        guard let mentions = store.unreads[channelId]?.mentions, mentions.contains(where: ids.contains) else { return }
        deletedMentionIds.formUnion(ids.filter(mentions.contains))
        store.unreads[channelId]?.mentions.removeAll(where: ids.contains)
        updateBadge()
    }

    /// Stoat adds role and @everyone mentions from a queue, sometimes after they've been read.
    /// Checking again shortly afterwards clears those before they show up anywhere.
    func scheduleFollowUpUnreadSync() {
        followUpUnreadSync?.cancel()
        followUpUnreadSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self else { return }
            self.followUpUnreadSync = nil
            await self.syncUnreads()
        }
    }

    /// A safety net for anything the connection missed.
    func startPeriodicUnreadSync() {
        periodicUnreadSync?.cancel()
        periodicUnreadSync = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                if self.isAppActive, Date().timeIntervalSince(self.lastUnreadSync) >= 240 {
                    await self.syncUnreads()
                }
            }
        }
    }

    /// Stoat adds role and @everyone mentions a moment after the message, so one can land in a
    /// channel that was read in between. Acknowledging again clears it for every client.
    func clearStaleMentions() {
        let stale = store.channelsWithStaleMentions
        guard !stale.isEmpty else { return }
        DiagnosticsLog.shared.record(.app, "Clearing \(stale.count) mention\(stale.count == 1 ? "" : "s") Stoat still lists for channels already read")
        for (channelId, lastRead) in stale {
            store.unreads[channelId]?.mentions = []
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.apiClient.acknowledge(channelId: channelId, messageId: lastRead)
                    self.confirmedAcks[channelId] = (lastRead, Date())
                } catch {
                    DiagnosticsLog.log(.network, "Couldn't clear a stale mention in \(channelId): \(error)")
                }
            }
        }
        updateBadge()
    }
}

// MARK: - Incoming calls

extension AppStore {
    private static let ringDuration: Duration = .seconds(45)

    func receiveIncomingCall(channelId: String, callerId: String) {
        guard let userId = store.currentUserId,
              callerId != userId,
              let channel = store.channels[channelId],
              !store.isMuted(channel: channel),
              store.users[callerId]?.relationship != .blocked,
              store.voiceStates[channelId]?[userId] == nil else { return }

        incomingCall = IncomingCall(channelId: channelId, callerId: callerId)
        incomingCallTimeout?.cancel()
        incomingCallTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.ringDuration)
            guard !Task.isCancelled else { return }
            self?.dismissIncomingCall()
        }

        if !isAppActive, !ringsOnSystemCallScreen {
            let caller = store.displayName(userId: callerId, serverId: nil)
            let title = channel.channelType == .group
                ? "\(caller) in \(channel.displayName(withUsers: store.users, currentUserId: userId))"
                : caller
            NotificationManager.shared.postMessageNotification(title: title, body: "Incoming call", channelId: channelId, messageId: "call-\(channelId)")
        }
    }

    public func dismissIncomingCall() {
        incomingCallTimeout?.cancel()
        incomingCallTimeout = nil
        incomingCall = nil
    }
}

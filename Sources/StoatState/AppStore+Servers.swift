import Foundation
import StoatCore

extension AppStore {
    // MARK: - Joining & creating

    public static func inviteCode(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let index = parts.firstIndex(of: "invite"), index + 1 < parts.count {
                return parts[index + 1]
            }
            if let last = parts.last {
                return last
            }
        }
        return trimmed.components(separatedBy: "/").last ?? trimmed
    }

    public func previewInvite(_ input: String) async throws -> InvitePreview {
        try await apiClient.fetchInvite(code: Self.inviteCode(from: input))
    }

    public func joinServer(inviteCode input: String) async -> Bool {
        do {
            let response = try await apiClient.joinInvite(code: Self.inviteCode(from: input))
            for channel in response.channels {
                store.channels[channel.id] = channel
            }
            if let channel = response.channel {
                store.channels[channel.id] = channel
                selectChannel(channel.id)
            }
            if let server = response.server {
                store.servers[server.id] = server
                selectServer(server.id)
                if let first = store.channels(forServer: server.id).first(where: \.isTextBased) {
                    selectChannel(first.id)
                }
            }
            scheduleCacheSave()
            return true
        } catch StoatAPIError.server(_, "AlreadyInServer") {
            showError("You're already in that server.")
            return false
        } catch {
            showError(error)
            return false
        }
    }

    public func createServer(name: String, description: String? = nil) async -> Server? {
        do {
            let response = try await apiClient.createServer(name: name, description: description)
            for channel in response.channels {
                store.channels[channel.id] = channel
            }
            guard let server = response.server else { return nil }
            store.servers[server.id] = server
            selectServer(server.id)
            if let first = response.channels.first {
                selectChannel(first.id)
            }
            scheduleCacheSave()
            return server
        } catch {
            showError(error)
            return nil
        }
    }

    public func leaveServer(_ serverId: String, silently: Bool = false) async -> Bool {
        do {
            try await apiClient.leaveOrDeleteServer(serverId: serverId, leaveSilently: silently)
            removeServerLocally(serverId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Server settings

    public func updateServer(serverId: String, name: String?, description: String?, iconData: Data?, bannerData: Data?, removeIcon: Bool = false, removeBanner: Bool = false) async -> Bool {
        do {
            var payload = DeltaAPIClient.EditServerPayload()
            payload.name = name
            if let description {
                if description.isEmpty {
                    payload.remove = (payload.remove ?? []) + ["Description"]
                } else {
                    payload.description = description
                }
            }
            if let iconData {
                payload.icon = try await upload(iconData, filename: "icon.png", tag: .icons)
            } else if removeIcon {
                payload.remove = (payload.remove ?? []) + ["Icon"]
            }
            if let bannerData {
                payload.banner = try await upload(bannerData, filename: "banner.png", tag: .banners)
            } else if removeBanner {
                payload.remove = (payload.remove ?? []) + ["Banner"]
            }
            let updated = try await apiClient.editServer(serverId: serverId, payload)
            store.servers[updated.id] = updated
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    /// Sets which channels get join, leave, kick and ban notices. Empty turns them all off.
    public func updateSystemMessages(serverId: String, channels: SystemMessageChannels) async -> Bool {
        do {
            let payload = channels.isEmpty
                ? DeltaAPIClient.EditServerPayload(remove: ["SystemMessages"])
                : DeltaAPIClient.EditServerPayload(systemMessages: channels)
            store.servers[serverId] = try await apiClient.editServer(serverId: serverId, payload)
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Audit log

    public func fetchAuditLogs(serverId: String, before: String? = nil, types: [String] = []) async -> [AuditLogEntry]? {
        do {
            let page = try await apiClient.fetchAuditLogs(serverId: serverId, before: before, types: types)
            store.upsert(users: page.users)
            store.upsert(members: page.members)
            return page.auditLogs
        } catch {
            showError(error)
            return nil
        }
    }

    // MARK: - Webhooks

    public func fetchWebhooks(channelId: String) async -> [Webhook]? {
        do {
            return try await apiClient.fetchWebhooks(channelId: channelId)
        } catch {
            showError(error)
            return nil
        }
    }

    public func createWebhook(channelId: String, name: String, avatarData: Data?) async -> Webhook? {
        do {
            let avatar = if let avatarData { try await upload(avatarData, filename: "avatar.png", tag: .avatars) } else { String?.none }
            return try await apiClient.createWebhook(channelId: channelId, name: name, avatar: avatar)
        } catch {
            showError(error)
            return nil
        }
    }

    public func editWebhook(id: String, name: String?, avatarData: Data?, removeAvatar: Bool) async -> Webhook? {
        do {
            let avatar = if let avatarData { try await upload(avatarData, filename: "avatar.png", tag: .avatars) } else { String?.none }
            return try await apiClient.editWebhook(id: id, name: name, avatar: avatar, removeAvatar: removeAvatar && avatarData == nil)
        } catch {
            showError(error)
            return nil
        }
    }

    public func deleteWebhook(id: String) async -> Bool {
        do {
            try await apiClient.deleteWebhook(id: id)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func updateCategories(serverId: String, categories: [ServerCategory]) async -> Bool {
        do {
            let cleaned = Self.sanitizedCategories(categories, serverChannels: store.servers[serverId]?.channels ?? [])
            let updated = try await apiClient.editServer(serverId: serverId, DeltaAPIClient.EditServerPayload(categories: cleaned))
            store.servers[updated.id] = updated
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func upload(_ data: Data, filename: String, tag: AutumnClient.Tag) async throws -> String {
        let token = await apiClient.sessionToken
        let limit = instanceConfiguration?.features.limits?.default?.fileUploadSizeLimits?[tag.rawValue]
        return try await AutumnClient.shared.upload(data: data, filename: filename, tag: tag, token: token, sizeLimit: limit)
    }

    // MARK: - Channels

    public func createChannel(serverId: String, name: String, type: ChannelType, description: String? = nil) async -> Channel? {
        do {
            let channel = try await apiClient.createChannel(serverId: serverId, name: name, type: type, description: description)
            store.channels[channel.id] = channel
            if var server = store.servers[serverId], !server.channels.contains(channel.id) {
                server.channels.append(channel.id)
                store.servers[serverId] = server
            }
            selectChannel(channel.id)
            return channel
        } catch {
            showError(error)
            return nil
        }
    }

    /// `slowmode: 0` turns slowmode off.
    public func updateChannel(
        channelId: String,
        name: String?,
        description: String?,
        nsfw: Bool? = nil,
        slowmode: Int? = nil,
        iconData: Data? = nil,
        removeIcon: Bool = false
    ) async -> Bool {
        do {
            var payload = DeltaAPIClient.EditChannelPayload(name: name, nsfw: nsfw)
            var remove: [String] = []
            if let description {
                if description.isEmpty {
                    remove.append("Description")
                } else {
                    payload.description = description
                }
            }
            if let slowmode {
                if slowmode > 0 {
                    payload.slowmode = min(slowmode, 21_600)
                } else {
                    remove.append("Slowmode")
                }
            }
            if let iconData {
                payload.icon = try await upload(iconData, filename: "icon.png", tag: .icons)
            } else if removeIcon {
                remove.append("Icon")
            }
            if !remove.isEmpty {
                payload.remove = remove
            }
            let updated = try await apiClient.editChannel(channelId: channelId, payload)
            store.channels[updated.id] = updated
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func deleteChannel(channelId: String) async -> Bool {
        do {
            try await apiClient.deleteChannel(channelId: channelId)
            removeChannelLocally(channelId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Invites

    public func createInvite(channelId: String) async -> String? {
        do {
            let invite = try await apiClient.createInvite(channelId: channelId)
            return "\(StoatInstance.appURL)/invite/\(invite.code)"
        } catch {
            showError(error)
            return nil
        }
    }

    public func fetchServerInvites(serverId: String) async -> [Invite] {
        do {
            return try await apiClient.fetchServerInvites(serverId: serverId)
        } catch {
            showError(error)
            return []
        }
    }

    public func deleteInvite(code: String) async -> Bool {
        do {
            try await apiClient.deleteInvite(code: code)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Members & moderation

    /// Loads a server's members. With `onlineOnly`, merges in just the online ones; otherwise
    /// replaces the member list with the full one. Returns how many members came back.
    @discardableResult
    public func fetchServerMembers(serverId: String, onlineOnly: Bool = false) async -> Int? {
        do {
            let response = try await apiClient.fetchServerMembers(serverId: serverId, excludeOffline: onlineOnly)
            store.upsert(users: response.users)
            if onlineOnly {
                store.upsert(members: response.members)
            } else {
                var dict: [String: ServerMember] = [:]
                for member in response.members {
                    dict[member.key.user] = member
                }
                store.members[serverId] = dict
            }
            return response.members.count
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { showError(error) }
            return nil
        }
    }

    /// For servers too large to load in full.
    public func searchServerMembers(serverId: String, query: String) async -> [String] {
        // Stoat's search is case-sensitive, so also try the lowercase and capitalised forms.
        let variants = Array(Set([query, query.lowercased(), query.capitalized]))
        var ids: [String] = []
        await withTaskGroup(of: DeltaAPIClient.ServerMembersResponse?.self) { group in
            for variant in variants {
                group.addTask { [apiClient] in
                    try? await apiClient.queryServerMembers(serverId: serverId, query: variant)
                }
            }
            for await response in group {
                guard let response else { continue }
                store.upsert(users: response.users)
                store.upsert(members: response.members)
                ids.append(contentsOf: response.members.map(\.key.user))
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    public func setNickname(_ nickname: String?, userId: String, serverId: String) async -> Bool {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payload = trimmed.isEmpty
            ? DeltaAPIClient.EditMemberPayload(remove: ["Nickname"])
            : DeltaAPIClient.EditMemberPayload(nickname: trimmed)
        return await editMember(serverId: serverId, userId: userId, payload)
    }

    public func setServerAvatar(_ data: Data?, serverId: String) async -> Bool {
        guard let userId = store.currentUserId else { return false }
        do {
            if let data {
                let id = try await upload(data, filename: "avatar.png", tag: .avatars)
                return await editMember(serverId: serverId, userId: userId, DeltaAPIClient.EditMemberPayload(avatar: id))
            }
            return await editMember(serverId: serverId, userId: userId, DeltaAPIClient.EditMemberPayload(remove: ["Avatar"]))
        } catch {
            showError(error)
            return false
        }
    }

    public func setRoles(_ roles: [String], userId: String, serverId: String) async -> Bool {
        let payload = roles.isEmpty
            ? DeltaAPIClient.EditMemberPayload(remove: ["Roles"])
            : DeltaAPIClient.EditMemberPayload(roles: roles)
        return await editMember(serverId: serverId, userId: userId, payload)
    }

    public func setTimeout(until: Date?, userId: String, serverId: String) async -> Bool {
        let payload = until.map { DeltaAPIClient.EditMemberPayload(timeout: StoatDate.string(from: $0)) }
            ?? DeltaAPIClient.EditMemberPayload(remove: ["Timeout"])
        return await editMember(serverId: serverId, userId: userId, payload)
    }

    private func editMember(serverId: String, userId: String, _ payload: DeltaAPIClient.EditMemberPayload) async -> Bool {
        do {
            let member = try await apiClient.editMember(serverId: serverId, userId: userId, payload)
            store.upsert(members: [member])
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func kickMember(userId: String, serverId: String) async -> Bool {
        do {
            try await apiClient.kickMember(serverId: serverId, userId: userId)
            store.members[serverId]?.removeValue(forKey: userId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func banMember(userId: String, serverId: String, reason: String?, deleteMessageSeconds: Int = 0) async -> Bool {
        do {
            let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            try await apiClient.banMember(
                serverId: serverId,
                userId: userId,
                reason: trimmed?.isEmpty == true ? nil : trimmed,
                deleteMessageSeconds: deleteMessageSeconds
            )
            store.members[serverId]?.removeValue(forKey: userId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func fetchBans(serverId: String) async -> ServerBansResponse? {
        do {
            return try await apiClient.fetchBans(serverId: serverId)
        } catch {
            showError(error)
            return nil
        }
    }

    public func unban(userId: String, serverId: String) async -> Bool {
        do {
            try await apiClient.unbanMember(serverId: serverId, userId: userId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Emojis

    public func createCustomEmoji(name: String, serverId: String, imageData: Data, filename: String = "emoji.png") async -> Bool {
        do {
            let uploadId = try await upload(imageData, filename: filename, tag: .emojis)
            let emoji = try await apiClient.createEmoji(
                uploadId: uploadId,
                payload: DeltaAPIClient.CreateEmojiPayload(name: name, parent: .server(id: serverId))
            )
            store.emojis[emoji.id] = emoji
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func deleteCustomEmoji(emojiId: String) async -> Bool {
        do {
            try await apiClient.deleteEmoji(emojiId: emojiId)
            store.emojis.removeValue(forKey: emojiId)
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Notification preferences

    public func setServerMuted(_ muted: Bool, serverId: String) async {
        var options = store.notificationOptions
        if muted {
            options.serverMutes[serverId] = NotificationOptions.MuteState()
        } else {
            options.serverMutes.removeValue(forKey: serverId)
        }
        await saveNotificationOptions(options)
    }

    public func setChannelMuted(_ muted: Bool, channelId: String) async {
        var options = store.notificationOptions
        if muted {
            options.channelMutes[channelId] = NotificationOptions.MuteState()
        } else {
            options.channelMutes.removeValue(forKey: channelId)
        }
        await saveNotificationOptions(options)
    }

    public func setNotificationLevel(_ level: NotificationOptions.Level?, serverId: String) async {
        var options = store.notificationOptions
        options.server[serverId] = level
        await saveNotificationOptions(options)
    }

    public func setNotificationLevel(_ level: NotificationOptions.Level?, channelId: String) async {
        var options = store.notificationOptions
        options.channel[channelId] = level
        await saveNotificationOptions(options)
    }

    private func saveNotificationOptions(_ options: NotificationOptions) async {
        let previous = store.notificationOptions
        store.notificationOptions = options
        updateBadge()
        do {
            let json = String(decoding: try JSONEncoder().encode(options), as: UTF8.self)
            try await apiClient.setSettings(["notifications": json])
            scheduleCacheSave()
        } catch {
            store.notificationOptions = previous
            updateBadge()
            showError(error)
        }
    }

    // MARK: - Server list and folders

    /// Reorders the top of the server list, where folders count as one entry.
    public func moveSidebarEntries(from source: IndexSet, to destination: Int) async {
        await saveSidebar(store.sidebarLayout.movingTopLevel(from: source, to: destination, servers: store.servers))
    }

    public func moveServersInFolder(_ folderId: String, from source: IndexSet, to destination: Int) async {
        await saveSidebar(store.sidebarLayout.movingInFolder(folderId, from: source, to: destination, servers: store.servers))
    }

    @discardableResult
    public func moveSidebarItem(_ id: String, onto targetId: String) async -> Bool {
        guard let layout = store.sidebarLayout.moving(id, onto: targetId, servers: store.servers) else { return false }
        await saveSidebar(layout)
        return true
    }

    public func createFolder(named name: String, with serverIds: [String]) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await saveSidebar(store.sidebarLayout.creatingFolder(id: ServerFolder.newId(), name: trimmed, serverIds: serverIds, servers: store.servers))
    }

    public func addServer(_ serverId: String, toFolder folderId: String) async {
        await saveSidebar(store.sidebarLayout.addingServer(serverId, toFolder: folderId, servers: store.servers))
    }

    public func removeServerFromFolder(_ serverId: String) async {
        await saveSidebar(store.sidebarLayout.removingServerFromFolder(serverId, servers: store.servers))
    }

    public func deleteFolder(_ folderId: String) async {
        await saveSidebar(store.sidebarLayout.deletingFolder(folderId, servers: store.servers))
    }

    public func renameFolder(_ folderId: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await saveSidebar(store.sidebarLayout.editingFolder(folderId) { $0.name = trimmed }, orderChanged: false)
    }

    /// `colour` is any CSS colour, or nil for the default.
    public func setFolderColour(_ folderId: String, to colour: String?) async {
        await saveSidebar(store.sidebarLayout.editingFolder(folderId) { $0.colour = colour }, orderChanged: false)
    }

    /// Opens or closes a folder. Synced like Stoat for Web does, so it stays that way everywhere.
    public func toggleFolder(_ folderId: String) async {
        await saveSidebar(store.sidebarLayout.editingFolder(folderId) { $0.collapsed = $0.isCollapsed ? nil : true }, orderChanged: false)
    }

    /// Shows the new layout at once, then saves it to Stoat. The flat `servers` list is kept up to
    /// date too, so clients without folders still get the order.
    private func saveSidebar(_ layout: ServerSidebarLayout, orderChanged: Bool = true) async {
        let previous = (order: store.serverOrder, sidebar: store.serverSidebar, folders: store.serverFolders)
        store.serverFolders = layout.folders
        var values: [String: String] = [:]
        do {
            if orderChanged {
                let flat = layout.flatServerIds(servers: store.servers)
                store.serverOrder = flat
                store.serverSidebar = layout.order
                let ordering = ServerOrderingSetting(servers: flat, serverSidebar: layout.order)
                values["ordering"] = String(decoding: try JSONEncoder().encode(ordering), as: UTF8.self)
            }
            values["server-folders"] = String(decoding: try JSONEncoder().encode(ServerFoldersSetting(folders: layout.folders)), as: UTF8.self)
            scheduleCacheSave()
            try await apiClient.setSettings(values)
        } catch {
            store.serverOrder = previous.order
            store.serverSidebar = previous.sidebar
            store.serverFolders = previous.folders
            showError(error)
        }
    }
}

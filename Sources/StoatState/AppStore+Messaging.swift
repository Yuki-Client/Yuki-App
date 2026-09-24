import Foundation
import StoatCore

extension AppStore {
    static let pageSize = 50

    // MARK: - History

    /// Runs in its own task, so a screen disappearing (and cancelling its `.task`) doesn't cancel
    /// the load, and concurrent callers share the request.
    public func loadLatestMessages(channelId: String) async {
        if let running = latestLoadTasks[channelId] {
            await running.value
            return
        }
        let task = Task { await performLoadLatest(channelId: channelId) }
        latestLoadTasks[channelId] = task
        await task.value
        latestLoadTasks[channelId] = nil
    }

    private func performLoadLatest(channelId: String) async {
        let timeline = store.timeline(for: channelId)
        if let channel = store.channels[channelId], !store.hasPermission(.readMessageHistory, in: channel) {
            timeline.hasMoreBefore = false
            timeline.isSynced = true
            return
        }

        timeline.isLoadingLatest = true
        timeline.loadError = nil
        defer { timeline.isLoadingLatest = false }

        do {
            let page = try await apiClient.fetchMessages(channelId: channelId, limit: Self.pageSize)
            ingest(page: page)

            let oldestFetchedId = page.messages.map(\.id).min()
            let overlaps = oldestFetchedId.map { timeline.message(id: $0) != nil } ?? true
            if !timeline.messages.isEmpty, page.messages.count == Self.pageSize, !overlaps || timeline.isViewingHistory {
                // What's loaded doesn't connect to this page (older history, or a stale cache);
                // drop it rather than show a silent gap.
                timeline.replace(with: page.messages)
                timeline.hasMoreBefore = true
            } else {
                timeline.merge(page.messages)
            }
            timeline.isViewingHistory = false
            timeline.historyEndId = nil
            // A short page means the channel's full history is loaded, unless older cached messages exist.
            if page.messages.count < Self.pageSize, timeline.oldestMessageId == oldestFetchedId {
                timeline.hasMoreBefore = false
            }
            timeline.isSynced = true
            timeline.loadError = nil

            if let newest = timeline.newestMessageId, var channel = store.channels[channelId] {
                if (channel.lastMessageId ?? "") < newest {
                    channel.lastMessageId = newest
                    store.channels[channelId] = channel
                }
            }
            scheduleCacheSave()
        } catch is CancellationError {
            return
        } catch {
            timeline.loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadOlderMessages(channelId: String) async {
        let timeline = store.timeline(for: channelId)
        guard timeline.hasMoreBefore, !timeline.isLoadingBefore, let oldest = timeline.oldestMessageId else { return }

        timeline.isLoadingBefore = true
        let task = Task { () -> Void in
            defer { timeline.isLoadingBefore = false }
            do {
                let page = try await apiClient.fetchMessages(channelId: channelId, limit: Self.pageSize, before: oldest)
                ingest(page: page)
                timeline.merge(page.messages)
                timeline.hasMoreBefore = page.messages.count == Self.pageSize
            } catch is CancellationError {
                return
            } catch {
                showError(error)
            }
        }
        await task.value
    }

    public func loadNewerMessages(channelId: String) async {
        let timeline = store.timeline(for: channelId)
        guard timeline.isViewingHistory, !timeline.isLoadingAfter, let after = timeline.historyEndId else { return }
        timeline.isLoadingAfter = true
        defer { timeline.isLoadingAfter = false }
        do {
            let page = try await apiClient.fetchMessages(channelId: channelId, limit: Self.pageSize, after: after, sort: .oldest)
            ingest(page: page)
            timeline.merge(page.messages)
            let newest = page.messages.map(\.id).max() ?? after
            // A full page that ends at the newest message is also the present.
            if page.messages.count < Self.pageSize || newest >= (store.channels[channelId]?.lastMessageId ?? "") {
                timeline.isViewingHistory = false
                timeline.historyEndId = nil
                timeline.isSynced = true
            } else {
                timeline.historyEndId = page.messages.map(\.id).max()
            }
        } catch is CancellationError {
            return
        } catch {
            showError(error)
        }
    }

    public func loadMessageContext(channelId: String, messageId: String) async -> Bool {
        let timeline = store.timeline(for: channelId)
        if timeline.message(id: messageId) != nil { return true }
        do {
            let page = try await apiClient.fetchMessages(channelId: channelId, limit: Self.pageSize, nearby: messageId)
            ingest(page: page)
            timeline.replace(with: page.messages)
            timeline.hasMoreBefore = true
            timeline.isSynced = false
            let newestLoaded = page.messages.map(\.id).max() ?? messageId
            let latest = store.channels[channelId]?.lastMessageId ?? ""
            // Fewer messages after the target than asked for means there are no newer ones, even
            // when Stoat still points the channel at a newer message that has been deleted.
            let newerCount = page.messages.filter { $0.id > messageId }.count
            timeline.isViewingHistory = newestLoaded < latest && newerCount >= Self.pageSize / 2
            timeline.historyEndId = timeline.isViewingHistory ? newestLoaded : nil
            return timeline.message(id: messageId) != nil
        } catch is CancellationError {
            return false
        } catch {
            showError(error)
            return false
        }
    }

    public func fetchReferencedMessage(channelId: String, messageId: String) async -> Message? {
        if let message = store.findMessage(id: messageId, in: channelId) { return message }
        guard let message = try? await apiClient.fetchMessage(channelId: channelId, messageId: messageId) else { return nil }
        queueUserFetch([message.author])
        return message
    }

    func ingest(page: DeltaAPIClient.MessagesPage) {
        store.upsert(users: page.users)
        store.upsert(members: page.members)
        let missing = page.messages
            .flatMap { [$0.author] + ($0.system?.referencedUserIds ?? []) }
            .filter { store.users[$0] == nil }
        queueUserFetch(missing)
    }

    // MARK: - Sending

    /// Failed sends stay in the timeline so they can be retried.
    public func sendMessage(content: String, in channelId: String, attachments: [OutgoingAttachment] = []) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let limit = instanceConfiguration?.features.limits?.default?.messageLength ?? 2000
        guard trimmed.count <= limit else {
            showError("Messages can be at most \(limit) characters.")
            return
        }

        let replies = replyingTo.map { DeltaAPIClient.ReplyIntent(id: $0.message.id, mention: $0.mention) }
        let pending = PendingMessage(
            nonce: Self.makeNonce(),
            channelId: channelId,
            content: trimmed,
            attachments: attachments,
            replies: replies,
            state: .sending,
            createdAt: Date()
        )
        replyingTo = []
        store.timeline(for: channelId).pending.append(pending)
        endTyping(in: channelId)

        startDelivery(pending)
    }

    public func retryPendingMessage(_ id: UUID, in channelId: String) {
        let timeline = store.timeline(for: channelId)
        guard let index = timeline.pending.firstIndex(where: { $0.id == id }) else { return }
        timeline.pending[index].state = .sending
        startDelivery(timeline.pending[index])
    }

    public func discardPendingMessage(_ id: UUID, in channelId: String) {
        deliveryTasks.removeValue(forKey: id)?.cancel()
        store.timeline(for: channelId).pending.removeAll { $0.id == id }
    }

    private func startDelivery(_ pending: PendingMessage) {
        deliveryTasks[pending.id]?.cancel()
        deliveryTasks[pending.id] = Task { [weak self] in
            await self?.deliver(pending)
            self?.deliveryTasks[pending.id] = nil
        }
    }

    private func deliver(_ pending: PendingMessage) async {
        let timeline = store.timeline(for: pending.channelId)
        do {
            var attachmentIds: [String] = []
            if !pending.attachments.isEmpty {
                let token = await apiClient.sessionToken
                let limit = instanceConfiguration?.features.limits?.default?.fileUploadSizeLimits?["attachments"]
                for attachment in pending.attachments {
                    if let uploaded = timeline.pending.first(where: { $0.id == pending.id })?.uploadedAttachmentIds[attachment.id] {
                        attachmentIds.append(uploaded)
                        continue
                    }
                    let pendingId = pending.id
                    let id = try await AutumnClient.shared.upload(
                        data: attachment.data,
                        filename: attachment.filename,
                        contentType: attachment.contentType,
                        tag: .attachments,
                        token: token,
                        sizeLimit: limit,
                        progress: { fraction in
                            Task { @MainActor [weak self] in
                                self?.setUploadProgress(fraction, attachment: attachment.id, pending: pendingId, in: timeline)
                            }
                        }
                    )
                    try Task.checkCancellation()
                    attachmentIds.append(id)
                    if let index = timeline.pending.firstIndex(where: { $0.id == pending.id }) {
                        timeline.pending[index].uploadedAttachmentIds[attachment.id] = id
                        timeline.pending[index].uploadProgress[attachment.id] = 1
                    }
                    if let preview = attachment.preview {
                        rememberLocalPreview(preview, forAttachment: id)
                    }
                }
            }
            try Task.checkCancellation()

            let message = try await apiClient.sendMessage(
                channelId: pending.channelId,
                nonce: pending.nonce,
                payload: DeltaAPIClient.SendMessagePayload(
                    content: pending.content.isEmpty ? nil : pending.content,
                    attachments: attachmentIds.isEmpty ? nil : attachmentIds,
                    replies: pending.replies.isEmpty ? nil : pending.replies
                )
            )
            timeline.pending.removeAll { $0.id == pending.id }
            timeline.upsert(message)
            if var channel = store.channels[pending.channelId], (channel.lastMessageId ?? "") < message.id {
                channel.lastMessageId = message.id
                if channel.channelType == .directMessage { channel.active = true }
                store.channels[pending.channelId] = channel
            }
            store.markRead(channelId: pending.channelId, messageId: message.id)
            startSlowmode(channelId: pending.channelId)
            updateBadge()
            scheduleCacheSave()
        } catch StoatAPIError.server(_, "DuplicateNonce") {
            // An earlier attempt with this key reached the server; the gateway delivers the message.
            timeline.pending.removeAll { $0.id == pending.id }
        } catch is CancellationError {
            return
        } catch {
            if case StoatAPIError.server(_, "InSlowmode") = error {
                startSlowmode(channelId: pending.channelId)
            }
            guard let index = timeline.pending.firstIndex(where: { $0.id == pending.id }) else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            timeline.pending[index].state = .failed(message)
            // If the server answered, the key has been used; a retry needs a fresh one. Network
            // failures keep the key so a request that did arrive can't be posted twice.
            if let apiError = error as? StoatAPIError, !apiError.isConnectivityError {
                timeline.pending[index].nonce = Self.makeNonce()
            }
        }
    }

    private func setUploadProgress(_ fraction: Double, attachment: UUID, pending pendingId: UUID, in timeline: ChannelTimeline) {
        guard let index = timeline.pending.firstIndex(where: { $0.id == pendingId }) else { return }
        let current = timeline.pending[index].uploadProgress[attachment] ?? 0
        // Updating for every chunk would redraw the chat far more than the eye can see.
        guard fraction - current >= 0.02 || fraction >= 1 else { return }
        timeline.pending[index].uploadProgress[attachment] = fraction
    }

    private func rememberLocalPreview(_ preview: Data, forAttachment attachmentId: String) {
        localAttachmentPreviews[attachmentId] = preview
        localPreviewOrder.append(attachmentId)
        while localPreviewOrder.count > 40 {
            localAttachmentPreviews.removeValue(forKey: localPreviewOrder.removeFirst())
        }
    }

    public func slowmodeRemaining(channelId: String, now: Date = Date()) -> Int {
        guard let until = slowmodeUntil[channelId] else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    /// Starts the local countdown after sending, unless the user can bypass slowmode.
    func startSlowmode(channelId: String, seconds: Int? = nil) {
        guard let channel = store.channels[channelId], !store.hasPermission(.bypassSlowmode, in: channel) else { return }
        let delay = seconds ?? channel.slowmode ?? 0
        guard delay > 0 else { return }
        let until = Date().addingTimeInterval(TimeInterval(delay))
        if (slowmodeUntil[channelId] ?? .distantPast) < until {
            slowmodeUntil[channelId] = until
        }
    }

    static func makeNonce() -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var time = UInt64(Date().timeIntervalSince1970 * 1000)
        var timePart: [Character] = []
        for _ in 0..<10 {
            timePart.append(alphabet[Int(time % 32)])
            time /= 32
        }
        let randomPart = (0..<16).map { _ in alphabet[Int.random(in: 0..<32)] }
        return String(timePart.reversed()) + String(randomPart)
    }

    public func editMessage(messageId: String, content: String, in channelId: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("Edited messages can't be empty.")
            return
        }
        let timeline = store.timeline(for: channelId)
        let original = timeline.message(id: messageId)
        timeline.update(id: messageId) { message in
            message.content = trimmed
            message.edited = StoatDate.string(from: Date())
        }
        editingMessage = nil

        do {
            let updated = try await apiClient.editMessage(channelId: channelId, messageId: messageId, content: trimmed)
            timeline.upsert(updated)
        } catch {
            if let original {
                timeline.upsert(original)
            }
            showError(error)
        }
    }

    public func deleteMessage(messageId: String, in channelId: String) async {
        let timeline = store.timeline(for: channelId)
        let original = timeline.message(id: messageId)
        timeline.remove(id: messageId)
        do {
            try await apiClient.deleteMessage(channelId: channelId, messageId: messageId)
        } catch {
            if let original {
                timeline.upsert(original)
            }
            showError(error)
        }
    }

    // MARK: - Reactions & pins

    public func toggleReaction(messageId: String, emoji: String, in channelId: String) async {
        guard let myId = store.currentUserId else { return }
        let timeline = store.timeline(for: channelId)
        guard let message = timeline.message(id: messageId) else { return }
        let hadReacted = message.reactions[emoji]?.contains(myId) == true

        timeline.update(id: messageId) { message in
            var users = message.reactions[emoji] ?? []
            if hadReacted {
                users.removeAll { $0 == myId }
            } else if !users.contains(myId) {
                users.append(myId)
            }
            if users.isEmpty {
                message.reactions.removeValue(forKey: emoji)
            } else {
                message.reactions[emoji] = users
            }
        }

        do {
            if hadReacted {
                try await apiClient.removeReaction(channelId: channelId, messageId: messageId, emoji: emoji)
            } else {
                try await apiClient.addReaction(channelId: channelId, messageId: messageId, emoji: emoji)
            }
        } catch {
            timeline.update(id: messageId) { current in
                current.reactions = message.reactions
            }
            showError(error)
        }
    }

    public func setPinned(_ pinned: Bool, messageId: String, in channelId: String) async {
        do {
            if pinned {
                try await apiClient.pinMessage(channelId: channelId, messageId: messageId)
            } else {
                try await apiClient.unpinMessage(channelId: channelId, messageId: messageId)
            }
            store.existingTimeline(for: channelId)?.update(id: messageId) { $0.pinned = pinned ? true : nil }
        } catch {
            showError(error)
        }
    }

    public func fetchPinnedMessages(channelId: String) async throws -> [Message] {
        let page = try await apiClient.fetchPinnedMessages(channelId: channelId)
        ingest(page: page)
        return page.messages.sorted { $0.id > $1.id }
    }

    public func searchMessages(channelId: String, query: String) async throws -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let page = try await apiClient.searchMessages(channelId: channelId, query: String(trimmed.prefix(64)))
        ingest(page: page)
        return page.messages.sorted { $0.id > $1.id }
    }

    // MARK: - Replies

    public func addReply(to message: Message) {
        guard !replyingTo.contains(where: { $0.message.id == message.id }) else { return }
        let maxReplies = instanceConfiguration?.features.limits?.global?.messageReplies ?? 5
        guard replyingTo.count < maxReplies else { return }
        editingMessage = nil
        replyingTo.append(ReplyDraft(message: message, mention: message.author != store.currentUserId))
    }

    public func toggleReplyMention(_ messageId: String) {
        guard let index = replyingTo.firstIndex(where: { $0.message.id == messageId }) else { return }
        replyingTo[index].mention.toggle()
    }

    public func removeReply(_ messageId: String) {
        replyingTo.removeAll { $0.message.id == messageId }
    }

    // MARK: - Typing

    /// Sends `BeginTyping` at most every 2.5 seconds, with `EndTyping` after a pause.
    public func noteTyping(in channelId: String) {
        let now = Date()
        if let last = lastTypingSent[channelId], now.timeIntervalSince(last) < 2.5 {
        } else {
            lastTypingSent[channelId] = now
            sendGatewayCommand(.beginTyping(channelId: channelId))
        }

        typingTasks["self:\(channelId)"]?.cancel()
        typingTasks["self:\(channelId)"] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.endTyping(in: channelId)
        }
    }

    public func endTyping(in channelId: String) {
        typingTasks["self:\(channelId)"]?.cancel()
        typingTasks["self:\(channelId)"] = nil
        guard lastTypingSent.removeValue(forKey: channelId) != nil else { return }
        sendGatewayCommand(.endTyping(channelId: channelId))
    }

    // MARK: - Read state

    /// Marks a channel read locally at once and acknowledges it on the server after a short debounce.
    public func markChannelAsRead(_ channelId: String) {
        guard let channel = store.channels[channelId] else { return }
        let messageId = [channel.lastMessageId, store.existingTimeline(for: channelId)?.newestMessageId]
            .compactMap { $0 }
            .max()
        guard let messageId else { return }

        let hadMentions = store.mentionCount(channelId: channelId) > 0
        let wasUnread = store.isUnread(channel: channel) || hadMentions
        store.markRead(channelId: channelId, messageId: messageId)
        updateBadge()
        guard wasUnread else { return }

        acknowledge(messageId, in: channelId)
        if hadMentions {
            scheduleFollowUpUnreadSync()
        }
    }

    func acknowledge(_ messageId: String, in channelId: String) {
        setPendingAck(messageId, for: channelId)
        ackTasks[channelId]?.cancel()
        ackTasks[channelId] = Task { [weak self] in
            // Batches quick successive reads; flushed early if the app goes to the background.
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            self.ackTasks[channelId] = nil
            await self.sendPendingAck(channelId: channelId)
        }
        scheduleCacheSave()
    }

    // MARK: - Read receipts

    var pendingAcksKey: String? {
        store.currentUserId.map { "yuki.pendingAcks.\($0)" }
    }

    func loadPendingAcks() {
        guard let key = pendingAcksKey else { return }
        pendingAcks = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func setPendingAck(_ messageId: String?, for channelId: String) {
        if let messageId {
            guard pendingAcks[channelId] != messageId else { return }
            pendingAcks[channelId] = messageId
        } else {
            guard pendingAcks.removeValue(forKey: channelId) != nil else { return }
        }
        if let key = pendingAcksKey {
            UserDefaults.standard.set(pendingAcks, forKey: key)
        }
    }

    func sendPendingAck(channelId: String) async {
        guard let messageId = pendingAcks[channelId] else { return }
        do {
            try await apiClient.acknowledge(channelId: channelId, messageId: messageId)
            confirmedAcks[channelId] = (messageId, Date())
            if pendingAcks[channelId] == messageId {
                setPendingAck(nil, for: channelId)
            }
        } catch let error as StoatAPIError where Self.isPermanentAckFailure(error) {
            // The server refused it (e.g. the channel is gone), so retrying won't help.
            if pendingAcks[channelId] == messageId {
                setPendingAck(nil, for: channelId)
            }
        } catch {
            DiagnosticsLog.shared.record(.network, "Read receipt failed, retrying later: \(error)")
        }
    }

    private static func isPermanentAckFailure(_ error: StoatAPIError) -> Bool {
        switch error {
        case .server(let status, _):
            // Rate limits and server errors are worth retrying.
            return (400..<500).contains(status) && status != 429
        case .unauthorized:
            return true
        default:
            return false
        }
    }

    func flushPendingAcks() {
        for channelId in pendingAcks.keys {
            ackTasks[channelId]?.cancel()
            ackTasks[channelId] = Task { [weak self] in
                await self?.sendPendingAck(channelId: channelId)
                self?.ackTasks[channelId] = nil
            }
        }
    }

    public func markUnread(fromMessage messageId: String, in channelId: String) async {
        guard let userId = store.currentUserId else { return }
        let messages = store.timeline(for: channelId).messages
        guard let index = messages.firstIndex(where: { $0.id == messageId }), index > 0 else {
            showError("Load earlier messages to mark this one as unread.")
            return
        }
        let previousId = messages[index - 1].id
        var unread = store.unreads[channelId] ?? ChannelUnread(channel: channelId, user: userId)
        unread.lastId = previousId
        store.unreads[channelId] = unread
        ackTasks[channelId]?.cancel()
        setPendingAck(nil, for: channelId)
        // Otherwise the next unread sync would treat the newer read as still on its way and undo this.
        confirmedAcks.removeValue(forKey: channelId)
        updateBadge()
        do {
            try await apiClient.acknowledge(channelId: channelId, messageId: previousId)
        } catch {
            showError(error)
        }
    }

    /// For when Stoat leaves unreads or mentions that won't clear on their own.
    public func markEverythingRead() async {
        for serverId in store.servers.keys {
            await markServerAsRead(serverId)
        }
        for channel in store.directChannels where channel.channelType != .savedMessages {
            markChannelAsRead(channel.id)
        }
        flushPendingAcks()
        updateBadge()
    }

    public func markServerAsRead(_ serverId: String) async {
        for channel in store.channels(forServer: serverId) {
            if let last = channel.lastMessageId {
                store.markRead(channelId: channel.id, messageId: last)
            }
        }
        updateBadge()
        do {
            try await apiClient.acknowledgeServer(serverId: serverId)
        } catch {
            showError(error)
        }
    }
}

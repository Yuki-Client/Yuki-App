import Foundation
import StoatCore

extension AppStore {
    public var friends: [User] {
        store.users.values.filter { $0.relationship == .friend }.sortedByName()
    }

    public var incomingFriendRequests: [User] {
        store.users.values.filter { $0.relationship == .incoming }.sortedByName()
    }

    public var outgoingFriendRequests: [User] {
        store.users.values.filter { $0.relationship == .outgoing }.sortedByName()
    }

    public var blockedUsers: [User] {
        store.users.values.filter { $0.relationship == .blocked }.sortedByName()
    }

    public func sendFriendRequest(username: String) async -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let user = try await apiClient.sendFriendRequest(username: trimmed)
            store.upsert(users: [user])
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func acceptFriend(userId: String) async {
        await updateRelationship { try await self.apiClient.acceptFriendRequest(userId: userId) }
    }

    /// Removes a friend, or declines / cancels a pending request.
    public func removeFriend(userId: String) async {
        await updateRelationship { try await self.apiClient.removeFriend(userId: userId) }
    }

    public func blockUser(userId: String) async {
        await updateRelationship { try await self.apiClient.blockUser(userId: userId) }
    }

    public func unblockUser(userId: String) async {
        await updateRelationship { try await self.apiClient.unblockUser(userId: userId) }
    }

    private func updateRelationship(_ operation: @escaping () async throws -> User) async {
        do {
            let user = try await operation()
            var merged = store.users[user.id] ?? user
            merged.relationship = user.relationship
            store.users[user.id] = merged
        } catch {
            showError(error)
        }
    }

    public func openDirectMessage(with userId: String) async {
        if userId == store.currentUserId,
           let saved = store.channels.values.first(where: { $0.channelType == .savedMessages }) {
            selectChannel(saved.id)
            return
        }
        if let existing = store.channels.values.first(where: {
            $0.channelType == .directMessage && $0.recipients?.contains(userId) == true
        }) {
            if existing.active == false {
                store.channels[existing.id]?.active = true
            }
            selectChannel(existing.id)
            return
        }
        do {
            let channel = try await apiClient.openDirectMessage(with: userId)
            store.channels[channel.id] = channel
            selectChannel(channel.id)
            scheduleCacheSave()
        } catch {
            showError(error)
        }
    }

    public func createGroup(name: String, users: [String]) async -> Channel? {
        do {
            let channel = try await apiClient.createGroup(name: name, users: users)
            store.channels[channel.id] = channel
            selectChannel(channel.id)
            scheduleCacheSave()
            return channel
        } catch {
            showError(error)
            return nil
        }
    }

    public func addGroupMember(channelId: String, userId: String) async -> Bool {
        do {
            try await apiClient.addGroupMember(channelId: channelId, userId: userId)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func removeGroupMember(channelId: String, userId: String) async {
        do {
            try await apiClient.removeGroupMember(channelId: channelId, userId: userId)
        } catch {
            showError(error)
        }
    }

    public func closeConversation(channelId: String, silently: Bool = false) async {
        do {
            try await apiClient.deleteChannel(channelId: channelId, leaveSilently: silently)
            if store.channels[channelId]?.channelType == .directMessage {
                store.channels[channelId]?.active = false
                if selectedChannelId == channelId {
                    selectedChannelId = nil
                }
            } else {
                removeChannelLocally(channelId)
            }
        } catch {
            showError(error)
        }
    }

    public func loadProfile(userId: String) async -> UserProfile? {
        if let cached = profiles[userId] { return cached }
        do {
            let profile = try await apiClient.fetchUserProfile(id: userId)
            profiles[userId] = profile
            return profile
        } catch {
            return nil
        }
    }

    public func loadUser(userId: String) async -> User? {
        if let cached = store.users[userId] { return cached }
        guard let user = try? await apiClient.fetchUser(id: userId) else { return nil }
        store.upsert(users: [user])
        return user
    }

    public func loadMutuals(userId: String) async -> MutualConnections? {
        guard userId != store.currentUserId else { return nil }
        return try? await apiClient.fetchMutuals(userId: userId)
    }

    public static let contentReportReasons: [(value: String, label: String)] = [
        ("NoneSpecified", "No reason specified"),
        ("Illegal", "Illegal content"),
        ("IllegalGoods", "Illegal goods or services"),
        ("IllegalExtortion", "Extortion or blackmail"),
        ("IllegalPornography", "Illegal pornography"),
        ("IllegalHacking", "Hacking or illegal access"),
        ("ExtremeViolence", "Extreme violence or gore"),
        ("PromotesHarm", "Promotes harm to self or others"),
        ("UnsolicitedSpam", "Unsolicited spam"),
        ("Raid", "Raid or spam attack"),
        ("SpamAbuse", "Spam or platform abuse"),
        ("ScamsFraud", "Scams or fraud"),
        ("Malware", "Malware or malicious links"),
        ("Harassment", "Harassment or abuse")
    ]

    public static let userReportReasons: [(value: String, label: String)] = [
        ("NoneSpecified", "No reason specified"),
        ("UnsolicitedSpam", "Unsolicited spam"),
        ("SpamAbuse", "Spam or platform abuse"),
        ("InappropriateProfile", "Inappropriate profile"),
        ("Impersonation", "Impersonation"),
        ("BanEvasion", "Ban evasion"),
        ("Underage", "Underage user")
    ]

    public func report(_ target: DeltaAPIClient.ReportTarget, reason: String, context: String) async -> Bool {
        do {
            try await apiClient.report(target, reason: reason, additionalContext: context)
            showSuccess("Report sent. Thank you for helping keep Stoat safe.")
            return true
        } catch {
            showError(error)
            return false
        }
    }
}

extension Array where Element == User {
    func sortedByName() -> [User] {
        sorted { $0.visibleName.localizedCaseInsensitiveCompare($1.visibleName) == .orderedAscending }
    }
}

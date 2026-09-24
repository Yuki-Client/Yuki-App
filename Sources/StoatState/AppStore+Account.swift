import Foundation
import StoatCore

extension AppStore {
    /// An empty `text` clears the custom status.
    public func updateStatus(text: String?, presence: Presence?) async {
        var payload = DeltaAPIClient.EditUserPayload()
        var status = UserStatus()
        var remove: [String] = []

        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                remove.append("StatusText")
            } else {
                status.text = String(trimmed.prefix(128))
            }
        }
        if let presence {
            status.presence = presence
        }
        if status.text != nil || status.presence != nil {
            payload.status = status
        }
        if !remove.isEmpty {
            payload.remove = remove
        }

        await editCurrentUser(payload)
    }

    public struct ProfileChanges: Sendable {
        public var displayName: String?
        public var pronouns: String?
        public var bio: String?
        public var avatarData: Data?
        public var removeAvatar = false
        public var backgroundData: Data?
        public var removeBackground = false

        public init() {}
    }

    public func updateProfile(_ changes: ProfileChanges, botId: String? = nil) async -> Bool {
        do {
            var payload = DeltaAPIClient.EditUserPayload()
            var remove: [String] = []

            if let displayName = changes.displayName {
                let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { remove.append("DisplayName") } else { payload.displayName = trimmed }
            }
            if let pronouns = changes.pronouns {
                let trimmed = pronouns.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { remove.append("Pronouns") } else { payload.pronouns = trimmed }
            }

            var profile = DeltaAPIClient.EditUserPayload.ProfilePayload()
            if let bio = changes.bio {
                if bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    remove.append("ProfileContent")
                } else {
                    profile.content = bio
                }
            }
            if let backgroundData = changes.backgroundData {
                profile.background = try await upload(backgroundData, filename: "background.png", tag: .backgrounds)
            } else if changes.removeBackground {
                remove.append("ProfileBackground")
            }
            if profile.content != nil || profile.background != nil {
                payload.profile = profile
            }

            if let avatarData = changes.avatarData {
                payload.avatar = try await upload(avatarData, filename: "avatar.png", tag: .avatars)
            } else if changes.removeAvatar {
                remove.append("Avatar")
            }

            if !remove.isEmpty {
                payload.remove = remove
            }

            let updated = if let botId {
                try await apiClient.editBotUser(botId: botId, payload)
            } else {
                try await apiClient.editCurrentUser(payload)
            }
            store.upsert(users: [updated])
            profiles.removeValue(forKey: updated.id)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    private func editCurrentUser(_ payload: DeltaAPIClient.EditUserPayload) async {
        do {
            let updated = try await apiClient.editCurrentUser(payload)
            store.upsert(users: [updated])
            scheduleCacheSave()
        } catch {
            showError(error)
        }
    }

    public func changeUsername(_ username: String, password: String) async -> Bool {
        do {
            let updated = try await apiClient.changeUsername(username, password: password)
            store.upsert(users: [updated])
            showSuccess("Username updated.")
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Sessions

    public func fetchSessions() async -> [SessionInfo] {
        do {
            return try await apiClient.fetchSessions()
        } catch {
            showError(error)
            return []
        }
    }

    public func revokeSession(id: String, ticket: String) async -> Bool {
        do {
            try await apiClient.revokeSession(id: id, mfaTicket: ticket)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func revokeOtherSessions(ticket: String) async -> Bool {
        do {
            try await apiClient.revokeOtherSessions(mfaTicket: ticket)
            showSuccess("Signed out of all other sessions.")
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: - Account security

    public func fetchAccountInfo() async -> AccountInfo? {
        do {
            return try await apiClient.fetchAccount()
        } catch {
            showError(error)
            return nil
        }
    }

    public func fetchMFAStatus() async -> MultiFactorStatus? {
        do {
            return try await apiClient.fetchMFAStatus()
        } catch {
            showError(error)
            return nil
        }
    }

    /// Tickets are single use.
    public func createMFATicket(_ response: MFAResponse) async -> String? {
        do {
            return try await apiClient.createMFATicket(response)
        } catch {
            showError(error)
            return nil
        }
    }

    public func changePassword(current: String, new: String) async -> Bool {
        do {
            try await apiClient.changePassword(new, currentPassword: current)
            showSuccess("Password changed.")
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func changeEmail(_ email: String, currentPassword: String) async -> Bool {
        do {
            try await apiClient.changeEmail(email, currentPassword: currentPassword)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    /// Regenerating invalidates the old codes.
    public func recoveryCodes(ticket: String, regenerate: Bool) async -> [String]? {
        do {
            return regenerate
                ? try await apiClient.generateRecoveryCodes(mfaTicket: ticket)
                : try await apiClient.fetchRecoveryCodes(mfaTicket: ticket)
        } catch {
            showError(error)
            return nil
        }
    }

    public func generateTOTPSecret(ticket: String) async -> String? {
        do {
            return try await apiClient.generateTOTPSecret(mfaTicket: ticket)
        } catch {
            showError(error)
            return nil
        }
    }

    public func enableTOTP(code: String) async -> Bool {
        do {
            try await apiClient.enableTOTP(code: code.filter(\.isNumber))
            showSuccess("Authenticator app enabled.")
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func disableTOTP(ticket: String) async -> Bool {
        do {
            try await apiClient.disableTOTP(mfaTicket: ticket)
            showSuccess("Authenticator app removed.")
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func disableAccount(ticket: String) async -> Bool {
        do {
            try await apiClient.disableAccount(mfaTicket: ticket)
            await logout()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    /// Stoat emails a confirmation link before anything is deleted.
    public func deleteAccount(ticket: String) async -> Bool {
        do {
            try await apiClient.deleteAccount(mfaTicket: ticket)
            await logout()
            return true
        } catch {
            showError(error)
            return false
        }
    }
}

extension AppStore {
    public var captchaKey: String? {
        guard let captcha = instanceConfiguration?.features.captcha, captcha.enabled else { return nil }
        return captcha.key
    }

    public var requiresInvite: Bool {
        instanceConfiguration?.features.inviteOnly == true
    }

    public func createAccount(email: String, password: String, invite: String?, captcha: String?) async -> Bool {
        do {
            try await apiClient.createAccount(email: email, password: password, invite: invite, captcha: captcha)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func verifyAccount(code: String) async -> Bool {
        do {
            try await apiClient.verifyAccount(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func resendVerification(email: String, captcha: String?) async -> Bool {
        do {
            try await apiClient.resendVerification(email: email, captcha: captcha)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func sendPasswordReset(email: String, captcha: String?) async -> Bool {
        do {
            try await apiClient.sendPasswordReset(email: email, captcha: captcha)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func resetPassword(token: String, newPassword: String, signOutEverywhere: Bool) async -> Bool {
        do {
            try await apiClient.resetPassword(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                password: newPassword,
                removeSessions: signOutEverywhere
            )
            return true
        } catch {
            showError(error)
            return false
        }
    }
}

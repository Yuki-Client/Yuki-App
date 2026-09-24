import Foundation
import StoatCore

extension AppStore {
    public func fetchOwnedBots() async -> [Bot]? {
        do {
            let response = try await apiClient.fetchOwnedBots()
            store.upsert(users: response.users)
            return response.bots
        } catch {
            showError(error)
            return nil
        }
    }

    public func createBot(name: String) async -> Bot? {
        do {
            let response = try await apiClient.createBot(name: name.trimmingCharacters(in: .whitespaces))
            store.upsert(users: [response.user])
            return response.bot
        } catch {
            showError(error)
            return nil
        }
    }

    public func editBot(id: String, name: String? = nil, isPublic: Bool? = nil, resetToken: Bool = false) async -> Bot? {
        do {
            let payload = DeltaAPIClient.EditBotPayload(name: name, isPublic: isPublic, remove: resetToken ? ["Token"] : nil)
            let response = try await apiClient.editBot(id: id, payload)
            store.upsert(users: [response.user])
            return response.bot
        } catch {
            showError(error)
            return nil
        }
    }

    public func deleteBot(id: String) async -> Bool {
        do {
            try await apiClient.deleteBot(id: id)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func fetchPublicBot(id: String) async -> PublicBot? {
        try? await apiClient.fetchPublicBot(id: id)
    }

    public func addBot(id: String, to destination: DeltaAPIClient.BotDestination) async -> Bool {
        do {
            try await apiClient.inviteBot(id: id, to: destination)
            showSuccess("Bot added.")
            return true
        } catch {
            showError(error)
            return false
        }
    }
}

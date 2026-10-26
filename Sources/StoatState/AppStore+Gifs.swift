import Foundation
import StoatCore

extension AppStore {
    /// Empty if they couldn't be loaded; the picker shows trending GIFs instead of an error.
    public func gifCategories() async -> [GifboxClient.Category] {
        let token = await apiClient.sessionToken
        return (try? await GifboxClient.shared.categories(token: token)) ?? []
    }

    /// Trending GIFs when `query` is empty, otherwise search results. Pass `position` to load the next page.
    public func gifs(matching query: String, position: String? = nil) async -> GifboxClient.Page? {
        let token = await apiClient.sessionToken
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                return try await GifboxClient.shared.trending(token: token, position: position)
            }
            return try await GifboxClient.shared.search(trimmed, token: token, position: position)
        } catch is CancellationError {
            return nil
        } catch {
            showError(error)
            return nil
        }
    }
}

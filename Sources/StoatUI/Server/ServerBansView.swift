import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct ServerBansView: View {
    @Bindable var store: AppStore
    let serverId: String

    @State private var bans: [ServerBan] = []
    @State private var users: [String: BannedUser] = [:]
    @State private var isLoading = true

    var body: some View {
        List {
            if bans.isEmpty && !isLoading {
                ContentUnavailableView("No Bans", systemImage: "hammer", description: Text("Banned users appear here."))
            }
            ForEach(bans) { ban in
                let user = users[ban.key.user]
                HStack(spacing: 12) {
                    AvatarView(avatar: user?.avatar, fallbackText: user?.username ?? "?", size: 36, userId: ban.key.user)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user?.username ?? ban.key.user)
                        if let reason = ban.reason, !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Unban") {
                        Task {
                            if await store.unban(userId: ban.key.user, serverId: serverId) {
                                bans.removeAll { $0.id == ban.id }
                            }
                        }
                    }
                    .tint(.green)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Bans")
        .task {
            if let response = await store.fetchBans(serverId: serverId) {
                bans = response.bans
                users = Dictionary(response.users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            }
            isLoading = false
        }
    }
}

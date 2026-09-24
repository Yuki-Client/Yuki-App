import SwiftUI
import StoatState

struct BlockedUsersView: View {
    @Bindable var store: AppStore

    var body: some View {
        List {
            if store.blockedUsers.isEmpty {
                ContentUnavailableView("No Blocked Users", systemImage: "hand.raised", description: Text("People you block will appear here."))
            }
            ForEach(store.blockedUsers) { user in
                HStack(spacing: 12) {
                    AvatarView(avatar: user.avatar, fallbackText: user.visibleName, size: 36, userId: user.id)
                    VStack(alignment: .leading) {
                        Text(user.visibleName)
                        Text(user.fullHandle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Unblock") {
                        Task { await store.unblockUser(userId: user.id) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Blocked Users")
    }
}

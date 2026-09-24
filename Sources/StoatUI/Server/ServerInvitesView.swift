import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct ServerInvitesView: View {
    @Bindable var store: AppStore
    let serverId: String

    @State private var invites: [Invite] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if invites.isEmpty && !isLoading {
                ContentUnavailableView("No Invites", systemImage: "link", description: Text("Invites created for this server appear here."))
            }
            ForEach(invites) { invite in
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.code)
                        .font(.body.monospaced())
                    HStack(spacing: 6) {
                        Text("#\(store.store.channels[invite.channel]?.name ?? "unknown")")
                        Text("•")
                        Text("by \(store.store.displayName(userId: invite.creator, serverId: serverId))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Revoke", role: .destructive) {
                        Task {
                            if await store.deleteInvite(code: invite.code) {
                                invites.removeAll { $0.code == invite.code }
                            }
                        }
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(StoatInstance.appURL)/invite/\(invite.code)"
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Invites")
        .task {
            invites = await store.fetchServerInvites(serverId: serverId)
            store.queueUserFetch(invites.map(\.creator))
            isLoading = false
        }
    }
}

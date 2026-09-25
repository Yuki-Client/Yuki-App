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
                    if let limits = limitsLabel(invite) {
                        Text(limits)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            // Expired invites are only cleared out hourly, so they can still be listed.
            invites = await store.fetchServerInvites(serverId: serverId)
                .filter { ($0.expiryDate ?? .distantFuture) > Date() }
            store.queueUserFetch(invites.map(\.creator))
            isLoading = false
        }
    }

    private func limitsLabel(_ invite: Invite) -> String? {
        var parts: [String] = []
        if let maxUses = invite.maxUses {
            parts.append("\(invite.uses ?? 0)/\(maxUses) uses")
        } else if let uses = invite.uses, uses > 0 {
            parts.append(uses == 1 ? "1 use" : "\(uses) uses")
        }
        if let expiry = invite.expiryDate {
            parts.append("expires \(expiry.formatted(.relative(presentation: .named)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

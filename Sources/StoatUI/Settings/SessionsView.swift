import SwiftUI
import StoatCore
import StoatState

struct SessionsView: View {
    @Bindable var store: AppStore
    @State private var sessions: [SessionInfo] = []
    @State private var isLoading = true
    @State private var revokeTarget: RevokeTarget?

    private enum RevokeTarget: Identifiable {
        case session(SessionInfo)
        case others

        var id: String {
            switch self {
            case .session(let session): session.id
            case .others: "others"
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                        if let date = Message.date(fromULID: session.id) {
                            Text("Signed in \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Log Out", role: .destructive) {
                            revokeTarget = .session(session)
                        }
                    }
                }
            } footer: {
                Text("Swipe a session to sign it out. You'll be asked to confirm it's you.")
            }

            if sessions.count > 1 {
                Section {
                    Button("Log Out All Other Sessions", role: .destructive) {
                        revokeTarget = .others
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Sessions")
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $revokeTarget) { target in
            VerifyIdentitySheet(store: store, title: "Log Out") { ticket in
                Task {
                    let success: Bool
                    switch target {
                    case .session(let session):
                        success = await store.revokeSession(id: session.id, ticket: ticket)
                    case .others:
                        success = await store.revokeOtherSessions(ticket: ticket)
                    }
                    if success { await reload() }
                }
            }
        }
    }

    private func reload() async {
        sessions = await store.fetchSessions()
        isLoading = false
    }
}

import SwiftUI
import PhotosUI
import StoatCore
import StoatState

struct MyBotsView: View {
    @Bindable var store: AppStore

    @State private var bots: [Bot] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newName = ""
    @State private var isCreating = false
    @State private var openBot: Bot?

    var body: some View {
        List {
            if bots.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Bots", systemImage: "cpu")
                } description: {
                    Text("Bots are automated accounts you control with a token, using Stoat's API.")
                } actions: {
                    Button("Create a Bot") { showCreate = true }
                }
            }
            ForEach(bots) { bot in
                NavigationLink {
                    BotDetailView(store: store, bot: bot) { updated in
                        replace(bot.id, with: updated)
                    }
                } label: {
                    BotRow(store: store, bot: bot)
                }
            }
        }
        .overlay { if isLoading && bots.isEmpty { ProgressView() } }
        .navigationTitle("My Bots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Bot")
                .disabled(isCreating)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("New Bot", isPresented: $showCreate) {
            TextField("Username", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                isCreating = true
                Task {
                    if let bot = await store.createBot(name: newName) {
                        bots.append(bot)
                        openBot = bot
                    }
                    isCreating = false
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).count < 2)
        } message: {
            Text("Usernames can use letters, numbers, underscores, dots and dashes.")
        }
        .navigationDestination(item: $openBot) { bot in
            BotDetailView(store: store, bot: bot) { updated in
                replace(bot.id, with: updated)
            }
        }
    }

    private func reload() async {
        if let fetched = await store.fetchOwnedBots() {
            bots = fetched
        }
        isLoading = false
    }

    private func replace(_ id: String, with updated: Bot?) {
        if let updated, let index = bots.firstIndex(where: { $0.id == id }) {
            bots[index] = updated
        } else if updated == nil {
            bots.removeAll { $0.id == id }
        }
    }
}

private struct BotRow: View {
    @Bindable var store: AppStore
    let bot: Bot

    var body: some View {
        let user = store.store.users[bot.id]
        HStack(spacing: 12) {
            AvatarView(avatar: user?.avatar, fallbackText: user?.visibleName ?? "Bot", size: 40, userId: bot.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user?.visibleName ?? "Bot")
                    if bot.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(YukiTheme.accent)
                            .font(.caption)
                    }
                }
                Text(user.map { "@\($0.fullHandle)" } ?? bot.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bot.isPublic ? "Public" : "Private")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

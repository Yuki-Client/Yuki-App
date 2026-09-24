import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct BotDetailView: View {
    @Bindable var store: AppStore
    let onChange: (Bot?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bot: Bot
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var revealToken = false
    @State private var confirmResetToken = false
    @State private var confirmDelete = false
    @State private var showAddToServer = false

    init(store: AppStore, bot: Bot, onChange: @escaping (Bot?) -> Void) {
        self.store = store
        self.onChange = onChange
        _bot = State(initialValue: bot)
    }

    private var user: User? { store.store.users[bot.id] }

    private var hasProfileChanges: Bool {
        guard hasLoaded, let user else { return false }
        return username != user.username
            || displayName != (user.displayName ?? "")
            || bio != (store.profiles[bot.id]?.content ?? "")
            || avatarData != nil
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if let avatarData, let image = UIImage(data: avatarData) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        } else {
                            AvatarView(avatar: user?.avatar, fallbackText: user?.visibleName ?? "Bot", size: 64, userId: bot.id)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        PhotosPicker("Change Avatar", selection: $avatarItem, matching: .images)
                        Text(verbatim: bot.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Profile") {
                LabeledContent("Username") {
                    TextField("username", text: $username)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Display Name") {
                    TextField("Optional", text: $displayName)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Toggle("Public Bot", isOn: Binding(
                    get: { bot.isPublic },
                    set: { value in
                        Task {
                            if let updated = await store.editBot(id: bot.id, isPublic: value) {
                                bot = updated
                                onChange(updated)
                            }
                        }
                    }
                ))
            } footer: {
                Text(bot.isPublic ? "Anyone can add this bot to servers they manage." : "Only you can add this bot to servers.")
            }

            if bot.isPublic, StoatInstance.isOfficial {
                Section {
                    NavigationLink {
                        DiscoverListingView(store: store, kind: .bot, id: bot.id, name: user?.visibleName ?? "this bot", isListed: bot.discoverable)
                    } label: {
                        Label("Discover", systemImage: "safari")
                    }
                } footer: {
                    Text("Ask Stoat to list this bot on Discover.")
                }
            }

            Section {
                HStack {
                    Text(verbatim: revealToken ? bot.token : String(repeating: "•", count: 24))
                        .font(.caption.monospaced())
                        .lineLimit(revealToken ? nil : 1)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        revealToken.toggle()
                    } label: {
                        Image(systemName: revealToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(revealToken ? "Hide token" : "Show token")
                }
                Button {
                    UIPasteboard.general.string = bot.token
                    YukiHaptics.notification(.success)
                } label: {
                    Label("Copy Token", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    confirmResetToken = true
                } label: {
                    Label("Reset Token", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Token")
            } footer: {
                Text("Anyone with this token can control your bot. Reset it if it leaks.")
            }

            Section {
                Button {
                    showAddToServer = true
                } label: {
                    Label("Add to a Server or Group", systemImage: "plus.circle")
                }
                Button {
                    UIPasteboard.general.string = "\(StoatInstance.appURL)/bot/\(bot.id)"
                    YukiHaptics.notification(.success)
                } label: {
                    Label("Copy Invite Link", systemImage: "link")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Bot", systemImage: "trash")
                }
            }
        }
        .navigationTitle(user?.visibleName ?? "Bot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasProfileChanges {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: saveProfile)
                        .disabled(isSaving || username.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            _ = await store.loadProfile(userId: bot.id)
            username = user?.username ?? ""
            displayName = user?.displayName ?? ""
            bio = store.profiles[bot.id]?.content ?? ""
            hasLoaded = true
        }
        .onChange(of: avatarItem) { _, item in
            Task { avatarData = try? await item?.loadTransferable(type: Data.self) }
        }
        .alert("Reset this bot's token?", isPresented: $confirmResetToken) {
            Button("Reset Token", role: .destructive) {
                Task {
                    if let updated = await store.editBot(id: bot.id, resetToken: true) {
                        bot = updated
                        onChange(updated)
                        revealToken = true
                        store.showSuccess("New token issued. Update it wherever your bot runs.")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current token stops working immediately.")
        }
        .alert("Delete \(user?.visibleName ?? "this bot")?", isPresented: $confirmDelete) {
            Button("Delete Bot", role: .destructive) {
                Task {
                    if await store.deleteBot(id: bot.id) {
                        onChange(nil)
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The bot leaves every server and its token stops working. This can't be undone.")
        }
        .sheet(isPresented: $showAddToServer) {
            AddBotSheet(store: store, botId: bot.id, botName: user?.visibleName ?? "Bot")
        }
    }

    private func saveProfile() {
        guard let user else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let trimmedName = username.trimmingCharacters(in: .whitespaces)
            if trimmedName != user.username {
                guard let updated = await store.editBot(id: bot.id, name: trimmedName) else { return }
                bot = updated
                onChange(updated)
            }
            var changes = AppStore.ProfileChanges()
            if displayName != (user.displayName ?? "") { changes.displayName = displayName }
            if bio != (store.profiles[bot.id]?.content ?? "") { changes.bio = bio }
            changes.avatarData = avatarData
            if changes.displayName != nil || changes.bio != nil || changes.avatarData != nil {
                guard await store.updateProfile(changes, botId: bot.id) else { return }
                _ = await store.loadProfile(userId: bot.id)
            }
            avatarData = nil
            avatarItem = nil
            username = store.store.users[bot.id]?.username ?? trimmedName
            store.showSuccess("Bot updated.")
        }
    }
}

import SwiftUI
import PhotosUI
import StoatCore
import StoatState

struct WebhooksView: View {
    @Bindable var store: AppStore
    let channelId: String

    @State private var webhooks: [Webhook] = []
    @State private var isLoading = true
    @State private var showCreate = false

    var body: some View {
        List {
            if webhooks.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Webhooks", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Webhooks let other services, like GitHub or your own scripts, post messages here.")
                } actions: {
                    Button("Create Webhook") { showCreate = true }
                }
            }
            ForEach(webhooks) { webhook in
                NavigationLink {
                    WebhookDetailView(store: store, webhook: webhook) { updated in
                        if let updated, let index = webhooks.firstIndex(where: { $0.id == webhook.id }) {
                            webhooks[index] = updated
                        } else if updated == nil {
                            webhooks.removeAll { $0.id == webhook.id }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        WebhookAvatar(webhook: webhook, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(webhook.name)
                            Text("Created by \(store.store.displayName(userId: webhook.creatorId, serverId: store.store.channels[channelId]?.server))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if isLoading && webhooks.isEmpty { ProgressView() } }
        .navigationTitle("Webhooks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Webhook")
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showCreate) {
            WebhookEditorSheet(store: store, title: "New Webhook", initialName: "") { name, avatarData, _ in
                guard let webhook = await store.createWebhook(channelId: channelId, name: name, avatarData: avatarData) else { return false }
                webhooks.append(webhook)
                store.queueUserFetch([webhook.creatorId])
                return true
            }
        }
    }

    private func reload() async {
        if let fetched = await store.fetchWebhooks(channelId: channelId) {
            webhooks = fetched
            store.queueUserFetch(fetched.map(\.creatorId))
        }
        isLoading = false
    }
}

struct WebhookDetailView: View {
    @Bindable var store: AppStore
    let onChange: (Webhook?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var webhook: Webhook
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var revealURL = false

    init(store: AppStore, webhook: Webhook, onChange: @escaping (Webhook?) -> Void) {
        self.store = store
        self.onChange = onChange
        _webhook = State(initialValue: webhook)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    WebhookAvatar(webhook: webhook, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(webhook.name).font(.headline)
                        Text(verbatim: webhook.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showEdit = true
                } label: {
                    Label("Edit Name & Avatar", systemImage: "pencil")
                }
            }

            if let url = webhook.executeURL {
                Section {
                    Text(verbatim: revealURL ? url : String(url.prefix(url.count - (webhook.token?.count ?? 0))) + "••••••••")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .onTapGesture { revealURL.toggle() }
                    Button {
                        UIPasteboard.general.string = url
                        YukiHaptics.notification(.success)
                    } label: {
                        Label("Copy Webhook URL", systemImage: "doc.on.doc")
                    }
                    Button {
                        UIPasteboard.general.string = url + "/github"
                        YukiHaptics.notification(.success)
                    } label: {
                        Label("Copy GitHub URL", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("URL")
                } footer: {
                    Text("Anyone with this URL can post as the webhook. For GitHub, use the GitHub URL with the JSON content type.")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Webhook", systemImage: "trash")
                }
            }
        }
        .navigationTitle(webhook.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            WebhookEditorSheet(store: store, title: "Edit Webhook", initialName: webhook.name, currentAvatar: webhook.avatar) { name, avatarData, removeAvatar in
                guard let updated = await store.editWebhook(
                    id: webhook.id,
                    name: name == webhook.name ? nil : name,
                    avatarData: avatarData,
                    removeAvatar: removeAvatar
                ) else { return false }
                webhook = updated
                onChange(updated)
                return true
            }
        }
        .alert("Delete \(webhook.name)?", isPresented: $confirmDelete) {
            Button("Delete Webhook", role: .destructive) {
                Task {
                    if await store.deleteWebhook(id: webhook.id) {
                        onChange(nil)
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything using this webhook's URL will stop being able to post.")
        }
    }
}

private struct WebhookEditorSheet: View {
    @Bindable var store: AppStore
    let title: String
    let initialName: String
    var currentAvatar: Attachment?
    let onSave: (_ name: String, _ avatarData: Data?, _ removeAvatar: Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var removeAvatar = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let avatarData, let image = UIImage(data: avatarData) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else if let currentAvatar, !removeAvatar {
                                RemoteImage(url: currentAvatar.downloadURL(), maxPixelSize: 160) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { _ in YukiTheme.cardSurface }
                            } else {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(YukiTheme.cardSurface)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker("Choose Avatar", selection: $avatarItem, matching: .images)
                            if avatarData != nil || (currentAvatar != nil && !removeAvatar) {
                                Button("Remove Avatar", role: .destructive) {
                                    avatarData = nil
                                    avatarItem = nil
                                    removeAvatar = true
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Name") {
                    TextField("Webhook name", text: $name)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(32))
                            if await onSave(trimmed, avatarData, removeAvatar) {
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = initialName }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    avatarData = try? await item.loadTransferable(type: Data.self)
                    removeAvatar = false
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct WebhookAvatar: View {
    let webhook: Webhook
    let size: CGFloat

    var body: some View {
        if let avatar = webhook.avatar {
            RemoteImage(url: avatar.downloadURL(), maxPixelSize: 160) { image in
                image.resizable().scaledToFill()
            } placeholder: { _ in
                AvatarView(avatar: nil, fallbackText: webhook.name, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            AvatarView(avatar: nil, fallbackText: webhook.name, size: size)
        }
    }
}

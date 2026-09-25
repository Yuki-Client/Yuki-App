import SwiftUI
import PhotosUI
import StoatCore
import StoatState

public struct ChannelDetailsSheet: View {
    @Bindable var store: AppStore
    public let channelId: String

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var topic = ""
    @State private var nsfw = false
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var showMembers = false
    @State private var inviteChannelId: String?
    @State private var hasLoaded = false
    @State private var slowmode = 0
    @State private var iconItem: PhotosPickerItem?
    @State private var iconData: Data?
    @State private var removeIcon = false

    /// Slowmode choices in seconds, up to Stoat's six-hour limit.
    static let slowmodeOptions = [0, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 21_600]

    public init(store: AppStore, channelId: String) {
        self.store = store
        self.channelId = channelId
    }

    private var channel: Channel? { store.store.channels[channelId] }
    private var permissions: Permission { channel.map { store.store.permissions(in: $0) } ?? [] }
    private var canEdit: Bool {
        guard let channel else { return false }
        return (channel.channelType == .textChannel || channel.channelType == .voiceChannel || channel.channelType == .group)
            && permissions.contains(.manageChannel)
    }

    private var hasChanges: Bool {
        guard let channel else { return false }
        return name != (channel.name ?? "") || topic != (channel.description ?? "") || nsfw != channel.nsfw
            || slowmode != (channel.slowmode ?? 0) || iconData != nil || removeIcon
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let channel {
                    Section {
                        if canEdit {
                            TextField("Name", text: $name)
                            TextField("Topic", text: $topic, axis: .vertical)
                                .lineLimit(2...6)
                            if channel.channelType != .group {
                                Toggle("Mature Content (18+)", isOn: $nsfw)
                                Picker("Slowmode", selection: $slowmode) {
                                    ForEach(Self.slowmodeOptions, id: \.self) { seconds in
                                        Text(Channel.slowmodeLabel(seconds)).tag(seconds)
                                    }
                                }
                            }
                            HStack(spacing: 12) {
                                Group {
                                    if let iconData, let image = UIImage(data: iconData) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else if let icon = channel.icon, !removeIcon {
                                        RemoteImage(url: icon.downloadURL(), maxPixelSize: 120) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: { _ in YukiTheme.cardSurface }
                                    } else {
                                        Image(systemName: channel.channelType == .group ? "person.3.fill" : "number")
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(YukiTheme.cardSurface)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                PhotosPicker("Change Icon", selection: $iconItem, matching: .images)
                                Spacer()
                                if iconData != nil || (channel.icon != nil && !removeIcon) {
                                    Button("Remove", role: .destructive) {
                                        iconData = nil
                                        iconItem = nil
                                        removeIcon = true
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        } else {
                            LabeledContent("Name", value: channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId))
                            if let description = channel.description, !description.isEmpty {
                                YukiMarkdownView(description, serverId: channel.server)
                            }
                        }
                    } header: {
                        Text(channel.channelType == .group ? "Group" : "Channel")
                    }

                    if channel.channelType != .savedMessages {
                        Section("Notifications") {
                            Toggle("Mute", isOn: Binding(
                                get: { store.store.notificationOptions.isChannelMuted(channelId) },
                                set: { muted in Task { await store.setChannelMuted(muted, channelId: channelId) } }
                            ))
                            Picker("Notify Me", selection: Binding(
                                get: { store.store.notificationOptions.channel[channelId] },
                                set: { level in Task { await store.setNotificationLevel(level, channelId: channelId) } }
                            )) {
                                Text("Default").tag(NotificationOptions.Level?.none)
                                Text("All Messages").tag(NotificationOptions.Level?.some(.all))
                                Text("Mentions Only").tag(NotificationOptions.Level?.some(.mention))
                                Text("Nothing").tag(NotificationOptions.Level?.some(.none))
                            }
                        }
                    }

                    Section {
                        if channel.channelType == .group {
                            Button {
                                showMembers = true
                            } label: {
                                Label("Members (\(channel.recipients?.count ?? 0))", systemImage: "person.2")
                            }
                        }
                        if permissions.contains(.inviteOthers), channel.channelType == .textChannel || channel.channelType == .group {
                            Button {
                                inviteChannelId = channelId
                            } label: {
                                Label("Create Invite", systemImage: "person.badge.plus")
                            }
                        }
                        Button {
                            store.markChannelAsRead(channelId)
                        } label: {
                            Label("Mark as Read", systemImage: "checkmark.message")
                        }
                        Button {
                            UIPasteboard.general.string = channelId
                            YukiHaptics.notification(.success)
                        } label: {
                            Label("Copy Channel ID", systemImage: "number")
                        }
                    }

                    if channel.server != nil, permissions.contains(.managePermissions) || permissions.contains(.manageWebhooks) {
                        Section {
                            if permissions.contains(.managePermissions) {
                                NavigationLink {
                                    ChannelPermissionsView(store: store, channelId: channelId)
                                } label: {
                                    Label("Permissions", systemImage: "lock.shield")
                                }
                            }
                            if permissions.contains(.manageWebhooks), channel.channelType == .textChannel {
                                NavigationLink {
                                    WebhooksView(store: store, channelId: channelId)
                                } label: {
                                    Label("Webhooks", systemImage: "point.3.connected.trianglepath.dotted")
                                }
                            }
                        }
                    } else if channel.channelType == .group, channel.owner == store.store.currentUserId {
                        Section {
                            NavigationLink {
                                GroupPermissionsView(store: store, channelId: channelId)
                            } label: {
                                Label("Member Permissions", systemImage: "lock.shield")
                            }
                        }
                    }

                    if let date = Message.date(fromULID: channelId) {
                        Section {
                            LabeledContent("Created", value: date.formatted(date: .long, time: .shortened))
                        }
                    }

                    if channel.channelType == .group || (channel.server != nil && permissions.contains(.manageChannel)) {
                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label(channel.channelType == .group ? "Leave Group" : "Delete Channel", systemImage: channel.channelType == .group ? "rectangle.portrait.and.arrow.right" : "trash")
                            }
                        }
                    }
                }
            }
            .presentsLinks(store: store)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving…" : "Save") { save() }
                            .disabled(!hasChanges || isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                // Runs again when returning from a pushed screen; keep unsaved edits.
                guard !hasLoaded else { return }
                hasLoaded = true
                name = channel?.name ?? ""
                slowmode = channel?.slowmode ?? 0
                topic = channel?.description ?? ""
                nsfw = channel?.nsfw ?? false
            }
            .onChange(of: iconItem) { _, item in
                guard let item else { return }
                Task {
                    iconData = try? await item.loadTransferable(type: Data.self)
                    removeIcon = false
                }
            }
            .alert(channel?.channelType == .group ? "Leave this group?" : "Delete #\(channel?.name ?? "channel")?", isPresented: $showDeleteConfirm) {
                Button(channel?.channelType == .group ? "Leave" : "Delete", role: .destructive) {
                    Task {
                        if channel?.channelType == .group {
                            await store.closeConversation(channelId: channelId)
                            dismiss()
                        } else if await store.deleteChannel(channelId: channelId) {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(channel?.channelType == .group ? "You'll need to be added again to rejoin." : "All messages in this channel will be permanently deleted.")
            }
            .sheet(isPresented: $showMembers) {
                if let channel {
                    MemberListSheet(store: store, channel: channel)
                }
            }
            .sheet(item: Binding(get: { inviteChannelId.map(IdentifiedString.init) }, set: { inviteChannelId = $0?.value })) { item in
                InviteShareSheet(store: store, channelId: item.value)
                    .presentationDetents([.height(360)])
            }
        }
    }

    private func save() {
        guard let channel else { return }
        isSaving = true
        Task {
            let success = await store.updateChannel(
                channelId: channelId,
                name: name == channel.name ? nil : name,
                description: topic == (channel.description ?? "") ? nil : topic,
                nsfw: nsfw == channel.nsfw ? nil : nsfw,
                slowmode: slowmode == (channel.slowmode ?? 0) ? nil : slowmode,
                iconData: iconData,
                removeIcon: removeIcon
            )
            isSaving = false
            if success {
                YukiHaptics.notification(.success)
                dismiss()
            }
        }
    }
}

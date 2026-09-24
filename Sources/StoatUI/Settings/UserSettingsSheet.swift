import SwiftUI
import StoatCore
import StoatState

public struct UserSettingsSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var statusText = ""
    @State private var showLogoutConfirm = false
    @State private var showEditProfile = false
    @State private var notificationsAuthorized = NotificationManager.shared.isAuthorized
    @State private var apiURL = ""
    @AppStorage(YukiHaptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(ChatSwipeAction.storageKey) private var chatSwipeAction: ChatSwipeAction = .reply
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let user = store.currentUser {
                    Section {
                        Button {
                            showEditProfile = true
                        } label: {
                            HStack(spacing: 14) {
                                PresenceAvatarView(user: user, userId: user.id, size: 60)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(user.visibleName).font(.headline)
                                    Text(user.fullHandle).font(.subheadline).foregroundStyle(.secondary)
                                    Text("Edit Profile").font(.caption.weight(.semibold)).foregroundStyle(YukiTheme.accent)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Section("Status") {
                        Picker("Presence", selection: Binding(
                            get: { user.status?.presence ?? .online },
                            set: { presence in Task { await store.updateStatus(text: nil, presence: presence) } }
                        )) {
                            ForEach([Presence.online, .idle, .focus, .busy, .invisible], id: \.self) { presence in
                                HStack {
                                    StatusBadge(presence: presence, size: 10)
                                    Text(StatusBadge.label(for: presence))
                                }
                                .tag(presence)
                            }
                        }
                        HStack {
                            TextField("Custom status", text: $statusText)
                                .submitLabel(.done)
                                .onSubmit { saveStatus() }
                            if statusText != (user.status?.text ?? "") {
                                Button("Save", action: saveStatus)
                            } else if !statusText.isEmpty {
                                Button("Clear") {
                                    statusText = ""
                                    saveStatus()
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    Section("Account") {
                        NavigationLink {
                            AccountSecurityView(store: store)
                        } label: {
                            Label("Account & Security", systemImage: "lock.shield")
                        }
                        NavigationLink {
                            BlockedUsersView(store: store)
                        } label: {
                            Label("Blocked Users", systemImage: "hand.raised")
                        }
                        NavigationLink {
                            MyBotsView(store: store)
                        } label: {
                            Label("My Bots", systemImage: "cpu")
                        }
                    }
                }

                Section {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .onChange(of: hapticsEnabled) { _, enabled in
                        if enabled { YukiHaptics.selection() }
                    }
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    Toggle(isOn: $animationsEnabled) {
                        Label("Animations", systemImage: "wand.and.sparkles")
                    }
                    Picker(selection: $chatSwipeAction) {
                        ForEach(ChatSwipeAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    } label: {
                        Label("Swipe Left in Chat", systemImage: "hand.draw")
                    }
                } header: {
                    Text("App")
                } footer: {
                    Text("Animations slide and fade channels and servers as you move between them; iOS's Reduce Motion turns them off too. \(chatSwipeAction.explanation) On the channel list, swiping right to left goes back into the last channel you had open.")
                }

                Section {
                    if notificationsAuthorized {
                        Label("Notifications Enabled", systemImage: "bell.badge.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task {
                                notificationsAuthorized = await NotificationManager.shared.requestAuthorization()
                                if !notificationsAuthorized, let url = URL(string: UIApplication.openSettingsURLString) {
                                    await UIApplication.shared.open(url)
                                }
                            }
                        } label: {
                            Label("Enable Notifications", systemImage: "bell.badge")
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Stoat only sends push notifications to its official app, so Yuki alerts you while it's open or recently used, and keeps the app icon badge up to date.")
                }

                Section {
                    LabeledContent("Server", value: apiURL)
                    LabeledContent("Connection", value: connectionLabel)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("Yuki Version", value: version)
                    }
                    NavigationLink {
                        AboutYukiView()
                    } label: {
                        Label("About Yuki & Legal", systemImage: "info.circle")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Yuki is an unofficial client and isn't affiliated with Stoat.")
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Log out of Yuki?", isPresented: $showLogoutConfirm) {
                Button("Log Out", role: .destructive) {
                    Task { await store.logout() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet(store: store)
            }
            .task {
                statusText = store.currentUser?.status?.text ?? ""
                apiURL = await store.apiClient.baseURL.host ?? ""
                await NotificationManager.shared.refreshAuthorizationStatus()
                notificationsAuthorized = NotificationManager.shared.isAuthorized
            }
        }
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .authenticated: return "Connected"
        case .connected, .connecting: return "Connecting…"
        case .disconnected: return "Offline"
        }
    }

    private func saveStatus() {
        Task { await store.updateStatus(text: statusText, presence: nil) }
    }
}

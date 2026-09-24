import SwiftUI
import StoatCore
import StoatState

public struct JoinOrCreateServerSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public enum Mode: String, CaseIterable, Identifiable {
        case join = "Join"
        case create = "Create"
        public var id: String { rawValue }
    }

    @State private var mode: Mode = .join
    @State private var inviteInput = ""
    @State private var preview: InvitePreview?
    @State private var previewError: String?
    @State private var isLoadingPreview = false
    @State private var serverName = ""
    @State private var isWorking = false
    @State private var showDiscover = false

    private let initialInviteCode: String?

    public init(store: AppStore, initialInviteCode: String? = nil) {
        self.store = store
        self.initialInviteCode = initialInviteCode
    }

    public var body: some View {
        NavigationStack {
            Form {
                if initialInviteCode == nil {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                if mode == .join {
                    joinSection
                } else {
                    Section {
                        TextField("Server name", text: $serverName)
                    } footer: {
                        Text("You'll be the owner and can invite friends right away.")
                    }
                }
            }
            .navigationTitle(mode == .join ? "Join a Server" : "Create a Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .join ? "Join" : "Create") { submit() }
                        .disabled(isWorking || (mode == .join ? preview == nil : serverName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .task(id: inviteInput) {
                await loadPreview()
            }
            .onAppear {
                if let initialInviteCode {
                    inviteInput = initialInviteCode
                }
            }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section {
            TextField("Invite link or code", text: $inviteInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("For example \(StoatInstance.appURL)/invite/abc123 or abc123.")
        }

        if initialInviteCode == nil, StoatInstance.isOfficial {
            Section {
                Button {
                    showDiscover = true
                } label: {
                    Label("Find a Server on Discover", systemImage: "safari")
                }
            }
            .sheet(isPresented: $showDiscover) {
                DiscoverView(store: store)
            }
        }

        if isLoadingPreview {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else if let preview {
            Section {
                VStack(spacing: 10) {
                    AvatarView(avatar: preview.serverIcon ?? preview.userAvatar, fallbackText: preview.serverName ?? preview.channelName, size: 72, isRounded: preview.serverId == nil)
                    Text(preview.serverName ?? preview.channelName)
                        .font(.title3.bold())
                    if preview.serverId != nil {
                        Text("#\(preview.channelName)")
                            .foregroundStyle(.secondary)
                    }
                    if let count = preview.memberCount {
                        // A Label here spaces the icon out like a list row; keep them together.
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                            Text("\(count.formatted()) \(count == 1 ? "member" : "members")")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                    Text("Invited by \(preview.userName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let serverId = preview.serverId, store.store.servers[serverId] != nil {
                        Text("You're already a member.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(YukiTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        } else if let previewError {
            Section {
                Label(previewError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func loadPreview() async {
        let trimmed = inviteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = nil
        previewError = nil
        guard trimmed.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            preview = try await store.previewInvite(trimmed)
        } catch {
            guard !Task.isCancelled else { return }
            previewError = "That invite is invalid or has expired."
        }
    }

    private func submit() {
        isWorking = true
        Task {
            defer { isWorking = false }
            switch mode {
            case .join:
                if let serverId = preview?.serverId, store.store.servers[serverId] != nil {
                    store.selectServer(serverId)
                    if let channelId = preview?.channelId {
                        store.openChannel(channelId)
                    }
                    dismiss()
                } else if await store.joinServer(inviteCode: inviteInput) {
                    dismiss()
                }
            case .create:
                if await store.createServer(name: serverName.trimmingCharacters(in: .whitespaces)) != nil {
                    dismiss()
                }
            }
        }
    }
}

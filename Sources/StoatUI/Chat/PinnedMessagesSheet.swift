import SwiftUI
import StoatCore
import StoatState

public struct PinnedMessagesSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let channelId: String
    let channelName: String
    let onJumpToMessage: (String) -> Void

    @State private var pinned: [Message] = []
    @State private var isLoading = true
    @State private var errorText: String?

    public init(channelId: String, channelName: String, onJumpToMessage: @escaping (String) -> Void) {
        self.channelId = channelId
        self.channelName = channelName
        self.onJumpToMessage = onJumpToMessage
    }

    private var canManage: Bool {
        guard let channel = appStore.store.channels[channelId] else { return false }
        return appStore.store.hasPermission(.manageMessages, in: channel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    ContentUnavailableView("Couldn't load pins", systemImage: "pin.slash", description: Text(errorText))
                } else if pinned.isEmpty {
                    ContentUnavailableView("No Pinned Messages", systemImage: "pin", description: Text("Pinned messages in \(channelName) will show up here."))
                } else {
                    List(pinned) { message in
                        Button {
                            dismiss()
                            onJumpToMessage(message.id)
                        } label: {
                            MessageResultCard(message: message)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            if canManage {
                                Button {
                                    Task {
                                        await appStore.setPinned(false, messageId: message.id, in: channelId)
                                        pinned.removeAll { $0.id == message.id }
                                    }
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(YukiTheme.systemBackground)
            .navigationTitle("Pinned Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                do {
                    pinned = try await appStore.fetchPinnedMessages(channelId: channelId)
                } catch {
                    errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                isLoading = false
            }
        }
    }
}

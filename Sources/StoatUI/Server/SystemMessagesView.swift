import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct SystemMessagesView: View {
    @Bindable var store: AppStore
    let serverId: String

    @Environment(\.dismiss) private var dismiss
    @State private var channels = SystemMessageChannels()
    @State private var hasLoaded = false
    @State private var isSaving = false

    private var server: Server? { store.store.servers[serverId] }

    private var textChannels: [Channel] {
        (server?.channels ?? []).compactMap { store.store.channels[$0] }.filter { $0.channelType == .textChannel }
    }

    var body: some View {
        Form {
            Section {
                picker("Member Joined", selection: $channels.userJoined)
                picker("Member Left", selection: $channels.userLeft)
                picker("Member Kicked", selection: $channels.userKicked)
                picker("Member Banned", selection: $channels.userBanned)
            } footer: {
                Text("Stoat posts a short notice in the chosen channel. Choose None to turn a notice off.")
            }
        }
        .navigationTitle("System Messages")
        .toolbar {
            if hasLoaded, channels != (server?.systemMessages ?? SystemMessageChannels()) {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            if await store.updateSystemMessages(serverId: serverId, channels: channels) {
                                store.showSuccess("System messages updated.")
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            channels = server?.systemMessages ?? SystemMessageChannels()
            hasLoaded = true
        }
    }

    private func picker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(textChannels) { channel in
                Text("#\(channel.name ?? "channel")").tag(String?.some(channel.id))
            }
        }
    }
}

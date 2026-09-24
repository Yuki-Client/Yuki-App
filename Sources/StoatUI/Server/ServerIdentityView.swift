import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct ServerIdentityView: View {
    @Bindable var store: AppStore
    let serverId: String

    @State private var nickname = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var isSaving = false

    private var permissions: Permission {
        store.store.servers[serverId].map { store.store.permissions(in: $0) } ?? []
    }

    var body: some View {
        Form {
            if let userId = store.store.currentUserId {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(avatar: store.store.avatar(userId: userId, serverId: serverId), fallbackText: store.store.displayName(userId: userId, serverId: serverId), size: 80, userId: userId)
                        Spacer()
                    }
                    if permissions.contains(.changeAvatar) {
                        PhotosPicker("Change Server Avatar", selection: $avatarItem, matching: .images)
                        if store.store.member(userId: userId, in: serverId)?.avatar != nil {
                            Button("Remove Server Avatar", role: .destructive) {
                                Task { _ = await store.setServerAvatar(nil, serverId: serverId) }
                            }
                        }
                    }
                } footer: {
                    Text("Your server profile only changes how you appear in this server.")
                }

                if permissions.contains(.changeNickname) {
                    Section("Nickname") {
                        TextField(store.currentUser?.visibleName ?? "Nickname", text: $nickname)
                        Button(isSaving ? "Saving…" : "Save Nickname") {
                            isSaving = true
                            Task {
                                if await store.setNickname(nickname, userId: userId, serverId: serverId) {
                                    store.showSuccess("Nickname updated.")
                                }
                                isSaving = false
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .navigationTitle("Server Profile")
        .onAppear {
            if let userId = store.store.currentUserId {
                nickname = store.store.member(userId: userId, in: serverId)?.nickname ?? ""
            }
        }
        .onChange(of: avatarItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                if await store.setServerAvatar(data, serverId: serverId) {
                    store.showSuccess("Server avatar updated.")
                }
            }
        }
    }
}

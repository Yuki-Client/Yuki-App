import SwiftUI
import PhotosUI
import StoatCore
import StoatState

public struct EditProfileSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var pronouns = ""
    @State private var bio = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var removeAvatar = false
    @State private var backgroundItem: PhotosPickerItem?
    @State private var backgroundData: Data?
    @State private var removeBackground = false
    @State private var original: (displayName: String, pronouns: String, bio: String) = ("", "", "")
    @State private var profile: UserProfile?
    @State private var isSaving = false

    public init(store: AppStore) {
        self.store = store
    }

    private var hasChanges: Bool {
        displayName != original.displayName || pronouns != original.pronouns || bio != original.bio
            || avatarData != nil || removeAvatar || backgroundData != nil || removeBackground
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        Color.clear
                            .frame(height: 110)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                if let backgroundData, let image = UIImage(data: backgroundData) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else if let background = profile?.background, !removeBackground {
                                    RemoteImage(url: background.downloadURL(), maxPixelSize: 1000, animates: true) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: { _ in YukiTheme.cardSurface }
                                } else {
                                    LinearGradient(colors: [YukiTheme.accentDeep.opacity(0.8), YukiTheme.accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                            .clipped()

                        Group {
                            if let avatarData, let image = UIImage(data: avatarData) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                            } else {
                                AvatarView(avatar: removeAvatar ? nil : store.currentUser?.avatar, fallbackText: displayName, size: 72, userId: store.store.currentUserId)
                            }
                        }
                        .padding(3)
                        .background(Circle().fill(YukiTheme.systemBackground))
                        .offset(x: 12, y: 30)
                    }
                    .padding(.bottom, 30)
                    .listRowInsets(EdgeInsets())

                    PhotosPicker("Change Avatar", selection: $avatarItem, matching: .images)
                    if store.currentUser?.avatar != nil || avatarData != nil {
                        Button("Remove Avatar", role: .destructive) {
                            avatarData = nil
                            removeAvatar = true
                        }
                    }
                    PhotosPicker("Change Banner", selection: $backgroundItem, matching: .images)
                    if profile?.background != nil || backgroundData != nil {
                        Button("Remove Banner", role: .destructive) {
                            backgroundData = nil
                            removeBackground = true
                        }
                    }
                }

                Section("Display Name") {
                    TextField(store.currentUser?.username ?? "Display name", text: $displayName)
                }

                Section("Pronouns") {
                    TextField("e.g. they/them", text: $pronouns)
                }

                Section {
                    TextField("Tell people about yourself", text: $bio, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("About Me")
                } footer: {
                    Text("Supports markdown.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(!hasChanges || isSaving)
                }
            }
            .task {
                let user = store.currentUser
                displayName = user?.displayName ?? ""
                pronouns = user?.pronouns ?? ""
                if let id = user?.id {
                    profile = await store.loadProfile(userId: id)
                }
                bio = profile?.content ?? ""
                original = (displayName, pronouns, bio)
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    avatarData = try? await item?.loadTransferable(type: Data.self)
                    removeAvatar = false
                }
            }
            .onChange(of: backgroundItem) { _, item in
                Task {
                    backgroundData = try? await item?.loadTransferable(type: Data.self)
                    removeBackground = false
                }
            }
        }
    }

    private func save() {
        var changes = AppStore.ProfileChanges()
        if displayName != original.displayName { changes.displayName = displayName }
        if pronouns != original.pronouns { changes.pronouns = pronouns }
        if bio != original.bio { changes.bio = bio }
        changes.avatarData = avatarData
        changes.removeAvatar = removeAvatar
        changes.backgroundData = backgroundData
        changes.removeBackground = removeBackground

        isSaving = true
        Task {
            let success = await store.updateProfile(changes)
            isSaving = false
            if success {
                YukiHaptics.notification(.success)
                dismiss()
            }
        }
    }
}

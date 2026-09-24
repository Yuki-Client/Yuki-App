import SwiftUI
import PhotosUI
import StoatState

struct ServerEmojiView: View {
    @Bindable var store: AppStore
    let serverId: String

    @State private var showAdd = false
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isUploading = false

    private var limit: Int { 100 }

    var body: some View {
        let emojis = store.store.emojis(forServer: serverId)
        List {
            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Upload Emoji", systemImage: "plus.circle")
                }
                .disabled(emojis.count >= limit)
            } footer: {
                Text("\(emojis.count) of \(limit) slots used. Images must be under 500 KB. Names can use lowercase letters, numbers and underscores.")
            }

            Section {
                ForEach(emojis) { emoji in
                    HStack(spacing: 12) {
                        ReactionEmojiView(emoji: emoji.id, size: 32)
                        Text(":\(emoji.name):")
                        Spacer()
                        if let creator = emoji.creatorId {
                            Text(store.store.displayName(userId: creator, serverId: serverId))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { _ = await store.deleteCustomEmoji(emojiId: emoji.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Emoji")
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Spacer()
                            if let imageData, let image = UIImage(data: imageData) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                            } else {
                                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary).frame(width: 72, height: 72)
                            }
                            Spacer()
                        }
                        PhotosPicker("Choose Image", selection: $photoItem, matching: .images)
                    }
                    Section("Name") {
                        TextField("emoji_name", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: name) { _, value in
                                let cleaned = String(value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(32))
                                if cleaned != value { name = cleaned }
                            }
                    }
                }
                .navigationTitle("Upload Emoji")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { resetForm() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isUploading ? "Uploading…" : "Upload") {
                            guard let imageData else { return }
                            isUploading = true
                            Task {
                                if await store.createCustomEmoji(name: name, serverId: serverId, imageData: imageData) {
                                    resetForm()
                                }
                                isUploading = false
                            }
                        }
                        .disabled(isUploading || imageData == nil || name.count < 2)
                    }
                }
                .onChange(of: photoItem) { _, item in
                    Task { imageData = try? await item?.loadTransferable(type: Data.self) }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func resetForm() {
        showAdd = false
        name = ""
        imageData = nil
        photoItem = nil
    }
}

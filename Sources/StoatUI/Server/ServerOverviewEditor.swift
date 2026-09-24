import SwiftUI
import StoatCore
import PhotosUI
import StoatState

struct ServerOverviewEditor: View {
    @Bindable var store: AppStore
    let serverId: String

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var iconItem: PhotosPickerItem?
    @State private var iconData: Data?
    @State private var bannerItem: PhotosPickerItem?
    @State private var bannerData: Data?
    @State private var removeIcon = false
    @State private var removeBanner = false
    @State private var isSaving = false

    private var server: Server? { store.store.servers[serverId] }

    var body: some View {
        Form {
            Section("Icon") {
                HStack(spacing: 16) {
                    if let iconData, let image = UIImage(data: iconData) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        AvatarView(avatar: removeIcon ? nil : server?.icon, fallbackText: name, size: 64, isRounded: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker("Choose Image", selection: $iconItem, matching: .images)
                        if server?.icon != nil || iconData != nil {
                            Button("Remove", role: .destructive) {
                                iconData = nil
                                removeIcon = true
                            }
                        }
                    }
                }
            }

            Section("Banner") {
                if let bannerData, let image = UIImage(data: bannerData) {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 100).clipped()
                } else if let banner = server?.banner, !removeBanner {
                    RemoteImage(url: banner.downloadURL(), maxPixelSize: 800) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { _ in Color.secondary.opacity(0.2) }
                    .frame(height: 100)
                    .clipped()
                }
                PhotosPicker("Choose Banner", selection: $bannerItem, matching: .images)
                if server?.banner != nil || bannerData != nil {
                    Button("Remove Banner", role: .destructive) {
                        bannerData = nil
                        removeBanner = true
                    }
                }
            }

            Section("Name") {
                TextField("Server name", text: $name)
            }

            Section("Description") {
                TextField("What's this server about?", text: $description, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    isSaving = true
                    Task {
                        let success = await store.updateServer(
                            serverId: serverId,
                            name: name == server?.name ? nil : name,
                            description: description == (server?.description ?? "") ? nil : description,
                            iconData: iconData,
                            bannerData: bannerData,
                            removeIcon: removeIcon,
                            removeBanner: removeBanner
                        )
                        isSaving = false
                        if success {
                            store.showSuccess("Server updated.")
                            dismiss()
                        }
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            name = server?.name ?? ""
            description = server?.description ?? ""
        }
        .onChange(of: iconItem) { _, item in
            Task {
                iconData = try? await item?.loadTransferable(type: Data.self)
                removeIcon = false
            }
        }
        .onChange(of: bannerItem) { _, item in
            Task {
                bannerData = try? await item?.loadTransferable(type: Data.self)
                removeBanner = false
            }
        }
    }
}

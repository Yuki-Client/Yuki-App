import SwiftUI
import StoatCore
import StoatState

/// Changes are kept locally until Save so they go to the server as one update.
struct ServerCategoriesView: View {
    @Bindable var store: AppStore
    let serverId: String
    /// Shows a Done button when there are no changes, for when this is the root of a sheet.
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss
    @State private var categories: [ServerCategory] = []
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var editMode: EditMode = .inactive
    @State private var showNewCategory = false
    @State private var newTitle = ""
    @State private var renamingId: String?
    @State private var renameText = ""
    @State private var deletingId: String?

    private var server: Server? { store.store.servers[serverId] }

    private var hasChanges: Bool {
        hasLoaded && categories != (server?.categories ?? [])
    }

    private var uncategorized: [String] {
        let filed = Set(categories.flatMap(\.channels))
        return (server?.channels ?? []).filter { !filed.contains($0) && store.store.channels[$0] != nil }
    }

    var body: some View {
        List {
            Section {
                if uncategorized.isEmpty {
                    Text("Every channel is in a category.")
                        .foregroundStyle(.secondary)
                }
                ForEach(uncategorized, id: \.self) { channelId in
                    channelRow(channelId, in: nil)
                }
            } header: {
                Text("No Category")
            } footer: {
                Text("Channels without a category appear at the top of the channel list.")
            }

            ForEach(categories) { category in
                Section {
                    if category.channels.isEmpty {
                        Text("No channels")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(category.channels, id: \.self) { channelId in
                        channelRow(channelId, in: category.id)
                    }
                    .onMove { source, destination in
                        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
                        categories[index].channels = AppStore.reorder(categories[index].channels, from: source, to: destination)
                    }
                } header: {
                    categoryHeader(category)
                }
            }

            Section {
                Button {
                    newTitle = ""
                    showNewCategory = true
                } label: {
                    Label("New Category", systemImage: "folder.badge.plus")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving)
                }
            } else if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(editMode.isEditing ? "Done Reordering" : "Reorder Channels") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .disabled(categories.allSatisfy { $0.channels.count < 2 })
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            // Stoat can hold a channel in two categories, which the list can't show twice.
            categories = AppStore.sanitizedCategories(server?.categories ?? [], serverChannels: server?.channels ?? [])
            hasLoaded = true
        }
        .alert("New Category", isPresented: $showNewCategory) {
            TextField("Category name", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                categories.append(ServerCategory(id: AppStore.makeCategoryId(), title: String(title.prefix(32)), channels: []))
            }
        }
        .alert("Rename Category", isPresented: Binding(get: { renamingId != nil }, set: { if !$0 { renamingId = nil } })) {
            TextField("Category name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = categories.firstIndex(where: { $0.id == renamingId }), !title.isEmpty {
                    categories[index].title = String(title.prefix(32))
                }
            }
        }
        .alert(
            "Delete \(categories.first { $0.id == deletingId }?.title ?? "category")?",
            isPresented: Binding(get: { deletingId != nil }, set: { if !$0 { deletingId = nil } })
        ) {
            Button("Delete Category", role: .destructive) {
                categories.removeAll { $0.id == deletingId }
                deletingId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its channels move to No Category. Nothing is deleted until you save.")
        }
    }

    private func categoryHeader(_ category: ServerCategory) -> some View {
        let index = categories.firstIndex(where: { $0.id == category.id }) ?? 0
        return HStack {
            Text(category.title)
            Spacer()
            Menu {
                Button {
                    renameText = category.title
                    renamingId = category.id
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    categories.swapAt(index, index - 1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(index == 0)
                Button {
                    categories.swapAt(index, index + 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(index >= categories.count - 1)
                Button(role: .destructive) {
                    deletingId = category.id
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .frame(width: 44, height: 28, alignment: .trailing)
            }
            .accessibilityLabel("\(category.title) options")
        }
    }

    @ViewBuilder
    private func channelRow(_ channelId: String, in categoryId: String?) -> some View {
        let channel = store.store.channels[channelId]
        HStack(spacing: 10) {
            Image(systemName: channel?.channelType == .voiceChannel || channel?.voice != nil ? "speaker.wave.2" : "number")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(channel?.name ?? "Unknown channel")
                .lineLimit(1)
            Spacer()
            if !editMode.isEditing {
                Menu {
                    if categoryId != nil {
                        Button {
                            move(channelId, to: nil)
                        } label: {
                            Label("No Category", systemImage: "tray")
                        }
                    }
                    ForEach(categories.filter { $0.id != categoryId }) { category in
                        Button {
                            move(channelId, to: category.id)
                        } label: {
                            Label(category.title, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .frame(width: 44, height: 32, alignment: .trailing)
                }
                .disabled(categories.isEmpty)
                .accessibilityLabel("Move \(channel?.name ?? "channel")")
            }
        }
    }

    private func move(_ channelId: String, to categoryId: String?) {
        for index in categories.indices {
            categories[index].channels.removeAll { $0 == channelId }
        }
        if let categoryId, let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].channels.append(channelId)
        }
        YukiHaptics.selection()
    }

    private func save() {
        isSaving = true
        Task {
            if await store.updateCategories(serverId: serverId, categories: categories) {
                store.showSuccess("Categories saved.")
                categories = server?.categories ?? []
                dismiss()
            }
            isSaving = false
        }
    }
}

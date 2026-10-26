import SwiftUI
import StoatCore
import StoatState

public struct CreateChannelSheet: View {
    @Bindable var store: AppStore
    public let serverId: String
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: ChannelType = .textChannel
    @State private var description = ""
    @State private var isCreating = false
    @State private var categoryId: String?

    public init(store: AppStore, serverId: String, categoryId: String? = nil) {
        self.store = store
        self.serverId = serverId
        _categoryId = State(initialValue: categoryId == ServerCategory.defaultId ? nil : categoryId)
    }

    private var categories: [ServerCategory] {
        (store.store.servers[serverId]?.categories ?? []).filter { $0.id != ServerCategory.defaultId }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        Label("Text", systemImage: "number").tag(ChannelType.textChannel)
                        Label("Voice", systemImage: "speaker.wave.2").tag(ChannelType.voiceChannel)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Name") {
                    TextField("new-channel", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Topic") {
                    TextField("Optional", text: $description, axis: .vertical)
                }
                if !categories.isEmpty {
                    Section("Category") {
                        Picker("Category", selection: $categoryId) {
                            Text("No Category").tag(String?.none)
                            ForEach(categories) { category in
                                Text(category.title).tag(String?.some(category.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create") {
                        isCreating = true
                        Task {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            let topic = description.trimmingCharacters(in: .whitespaces)
                            if let channel = await store.createChannel(serverId: serverId, name: trimmed, type: type, description: topic.isEmpty ? nil : topic, categoryId: categoryId) {
                                // Same as web, and keeps it visible if the category is collapsed.
                                store.openChannel(channel.id)
                                dismiss()
                            }
                            isCreating = false
                        }
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

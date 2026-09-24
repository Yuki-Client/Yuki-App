import SwiftUI
import StoatState

struct PolicyChangesSheet: View {
    @Bindable var store: AppStore
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Stoat has updated its policies. Please review the changes below to continue.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.pendingPolicyChanges, id: \.url) { change in
                    Section {
                        Text(change.description)
                        if let url = URL(string: change.url) {
                            Link("Read more", destination: url)
                        }
                    }
                }
            }
            .navigationTitle("Policy Updates")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    isSubmitting = true
                    Task {
                        await store.acknowledgePolicyChanges()
                        isSubmitting = false
                    }
                } label: {
                    Text(isSubmitting ? "Saving…" : "I Understand")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)
                .padding()
            }
        }
    }
}

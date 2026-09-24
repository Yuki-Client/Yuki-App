import SwiftUI
import StoatCore
import StoatState

public struct ReportSheet: View {
    @Bindable var store: AppStore
    let target: DeltaAPIClient.ReportTarget
    let subject: String

    @Environment(\.dismiss) private var dismiss
    @State private var reason = "NoneSpecified"
    @State private var details = ""
    @State private var isSubmitting = false

    public init(store: AppStore, target: DeltaAPIClient.ReportTarget, subject: String) {
        self.store = store
        self.target = target
        self.subject = subject
    }

    private var reasons: [(value: String, label: String)] {
        if case .user = target { return AppStore.userReportReasons }
        return AppStore.contentReportReasons
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }
                } footer: {
                    Text("Reports go to the Stoat Trust & Safety team, not server moderators.")
                }
                Section("Details") {
                    TextField("Anything else we should know?", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Report \(subject.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        isSubmitting = true
                        Task {
                            if await store.report(target, reason: reason, context: String(details.prefix(1000))) {
                                dismiss()
                            }
                            isSubmitting = false
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

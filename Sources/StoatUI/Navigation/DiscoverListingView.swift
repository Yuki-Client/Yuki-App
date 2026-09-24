import SwiftUI
import StoatCore
import StoatState

struct DiscoverListingView: View {
    @Bindable var store: AppStore
    let kind: DeltaAPIClient.DiscoverKind
    let id: String
    let name: String
    let isListed: Bool

    @State private var status: DiscoverRequestStatus?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var loadError: String?

    private var noun: String { kind == .server ? "server" : "bot" }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stoat Discover", systemImage: "safari")
                        .font(.headline)
                    Text("Listing \(name) on Discover lets anyone on Stoat find it\(kind == .server ? " and join" : " and add it"). Stoat reviews every request first.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if isListed {
                    statusRow(title: "Listed on Discover", detail: "Contact Stoat support to remove this \(noun) from Discover.", systemImage: "checkmark.seal.fill", color: .green)
                } else if let loadError {
                    statusRow(title: "Couldn't Check", detail: loadError, systemImage: "exclamationmark.triangle", color: .orange)
                } else if let status {
                    statusContent(status)
                } else {
                    Button {
                        Task { await request() }
                    } label: {
                        Label("Request Listing", systemImage: "paperplane")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func statusContent(_ status: DiscoverRequestStatus) -> some View {
        switch status {
        case .pending, .underReview:
            statusRow(title: status == .pending ? "Waiting for Review" : "Under Review", detail: "Check back later to see whether your \(noun) was approved.", systemImage: "hourglass", color: .orange)
            Button("Cancel Request", role: .destructive) {
                Task { await cancel() }
            }
            .disabled(isWorking)
        case .approved(let reason):
            statusRow(title: "Approved", detail: reason ?? "Your \(noun) is on Discover. Contact Stoat support to remove it.", systemImage: "checkmark.seal.fill", color: .green)
        case .denied(let reason):
            statusRow(title: "Not Approved", detail: reason ?? "Stoat didn't approve this request.", systemImage: "xmark.octagon", color: .red)
        case .removed(let reason):
            statusRow(title: "Removed from Discover", detail: reason ?? "Contact Stoat support for more information.", systemImage: "minus.circle", color: .red)
        }
    }

    private func statusRow(title: String, detail: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard !isListed else { return }
        do {
            status = try await store.apiClient.fetchDiscoverRequest(kind, id: id).status
            loadError = nil
        } catch StoatAPIError.server(_, "NotFound"?) {
            status = nil
            loadError = nil
        } catch StoatAPIError.server(_, "NoEffect"?) {
            loadError = "Discover isn't available on this Stoat instance."
        } catch StoatAPIError.server(_, "Banned"?) {
            loadError = "This \(noun) can't be listed on Discover."
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func request() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.apiClient.requestDiscoverListing(kind, id: id)
            YukiHaptics.notification(.success)
            await load()
        } catch {
            store.showError(error)
        }
    }

    private func cancel() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.apiClient.cancelDiscoverRequest(kind, id: id)
            await load()
        } catch {
            store.showError(error)
        }
    }
}

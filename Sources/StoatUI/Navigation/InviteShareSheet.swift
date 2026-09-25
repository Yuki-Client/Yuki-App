import SwiftUI
import StoatCore
import StoatState

struct InviteShareSheet: View {
    @Bindable var store: AppStore
    let channelId: String

    @State private var invite: Invite?
    @State private var expiresAfter: TimeInterval?
    @State private var maxUses: Int?
    @State private var isCreating = false
    /// Once a link has been copied or shared it's left alone when the settings change.
    @State private var handedOut = false
    @State private var copied = false

    private static let expiryOptions: [(label: String, seconds: TimeInterval)] = [
        ("30 minutes", 1_800),
        ("1 hour", 3_600),
        ("6 hours", 21_600),
        ("12 hours", 43_200),
        ("1 day", 86_400),
        ("7 days", 604_800),
        ("30 days", 2_592_000)
    ]

    private static let useOptions = [1, 5, 10, 25, 50, 100]

    private var availableExpiryOptions: [(label: String, seconds: TimeInterval)] {
        guard let limit = store.maxInviteDuration else { return Self.expiryOptions }
        return Self.expiryOptions.filter { $0.seconds <= limit }
    }

    private var link: String? {
        invite.map { "\(StoatInstance.appURL)/invite/\($0.code)" }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite People")
                .font(.headline)
                .padding(.top, 20)
            Group {
                if let link {
                    Text(link)
                        .textSelection(.enabled)
                } else {
                    Text(isCreating ? "Creating link…" : "Couldn't create a link")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(YukiTheme.cardSurface))

            VStack(spacing: 0) {
                settingRow("Expire After") {
                    Picker("Expire After", selection: $expiresAfter) {
                        ForEach(availableExpiryOptions, id: \.seconds) { option in
                            Text(option.label).tag(TimeInterval?.some(option.seconds))
                        }
                        Text("Never").tag(TimeInterval?.none)
                    }
                }
                Divider().padding(.leading, 12)
                settingRow("Max Uses") {
                    Picker("Max Uses", selection: $maxUses) {
                        Text("No Limit").tag(Int?.none)
                        ForEach(Self.useOptions, id: \.self) { uses in
                            Text(uses == 1 ? "1 use" : "\(uses) uses").tag(Int?.some(uses))
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(YukiTheme.cardSurface))
            .disabled(isCreating)

            HStack(spacing: 12) {
                Button {
                    guard let link else { return }
                    UIPasteboard.general.string = link
                    copied = true
                    handedOut = true
                    YukiHaptics.notification(.success)
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(link == nil)
                if let url = link.flatMap(URL.init(string:)) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .simultaneousGesture(TapGesture().onEnded { handedOut = true })
                }
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 20)
        .task(id: "\(expiresAfter ?? 0)-\(maxUses ?? 0)") {
            await regenerate()
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder picker: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            picker()
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
    }

    private func regenerate() async {
        let previous = invite
        isCreating = true
        defer { isCreating = false }
        guard let created = await store.createInvite(channelId: channelId, maxUses: maxUses, expiresAfter: expiresAfter) else {
            return
        }
        invite = created
        copied = false
        if let previous, !handedOut {
            _ = await store.deleteInvite(code: previous.code)
        }
        handedOut = false
    }
}

import SwiftUI
import StoatCore

public struct AboutYukiView: View {
    public init() {}

    private static let stoatTerms = URL(string: "https://stoat.chat/legal/terms")!
    private static let stoatGuidelines = URL(string: "https://stoat.chat/legal/community-guidelines")!
    private static let stoatPrivacy = URL(string: "https://stoat.chat/legal/privacy")!
    private static let sourceCode = URL(string: "https://github.com/Yuki-Client/Yuki-App")!
    private static let licence = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                        .accessibilityHidden(true)
                    Text("Yuki")
                        .font(.title2.bold())
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Not Affiliated with Stoat") {
                Text("Yuki is an independent, unofficial app made by the community for using Stoat. It isn't made, endorsed, sponsored or supported by Stoat or the Stoat team.")
                Text("Stoat's name is used only to say what Yuki works with and belongs to its owners.")
            }

            Section {
                Text("Using Yuki means using Stoat, so Stoat's terms, guidelines and privacy policy still apply to your account and what you post.")
                Link(destination: Self.stoatTerms) {
                    Label("Stoat Terms of Service", systemImage: "doc.text")
                }
                Link(destination: Self.stoatGuidelines) {
                    Label("Stoat Community Guidelines", systemImage: "person.2")
                }
                Link(destination: Self.stoatPrivacy) {
                    Label("Stoat Privacy Policy", systemImage: "hand.raised")
                }
            } header: {
                Text("Your Stoat Account")
            } footer: {
                Text("Problems with Yuki itself should go to the Yuki team, not Stoat support.")
            }

            Section("Privacy") {
                Text("Yuki has no servers, accounts, ads or analytics of its own. It connects to your Stoat server (stoat.chat unless you choose another), to Gifbox, Stoat's GIF service, when you search for GIFs, and to stt.gg when you browse Discover.")
                Text("Images, videos and GIFs in messages can load from the sites that host them. Your login is kept in this device's Keychain, and recent messages are cached on this device.")
            }

            Section {
                Link(destination: Self.sourceCode) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.licence) {
                    Label("GNU Affero General Public License v3", systemImage: "doc.text")
                }
            } header: {
                Text("Licence")
            } footer: {
                Text("Yuki is free software: you can share and change it under the terms of the GNU AGPL, version 3. It comes with no warranty.")
            }
        }
        .font(.subheadline)
        .navigationTitle("About Yuki")
        .navigationBarTitleDisplayMode(.inline)
    }
}

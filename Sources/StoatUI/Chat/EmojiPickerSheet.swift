import SwiftUI
import StoatCore
import StoatState

/// Unicode emoji derived from the system's Unicode tables, grouped by code point block.
enum EmojiCatalog {
    struct Entry: Hashable {
        let emoji: String
        let name: String
    }

    struct Group: Identifiable {
        let id: String
        let symbol: String
        let entries: [Entry]
    }

    private static let blocks: [(title: String, symbol: String, ranges: [ClosedRange<UInt32>])] = [
        ("Smileys & People", "face.smiling", [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1F9D0...0x1F9DF, 0x1FAE0...0x1FAE8]),
        ("Gestures & Body", "hand.raised", [0x1F440...0x1F450, 0x1F466...0x1F487, 0x1F90C...0x1F90F, 0x1F930...0x1F93A, 0x1F9B0...0x1F9BF, 0x1FAF0...0x1FAF8]),
        ("Animals & Nature", "leaf", [0x1F300...0x1F320, 0x1F330...0x1F37F, 0x1F400...0x1F43F, 0x1F980...0x1F9AF, 0x1FAB0...0x1FABF]),
        ("Food & Drink", "fork.knife", [0x1F32D...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CF, 0x1FAD0...0x1FADB]),
        ("Activities", "sportscourt", [0x1F380...0x1F3FA, 0x1F93C...0x1F94F, 0x1F9E0...0x1F9FF, 0x1FA70...0x1FAAF]),
        ("Travel & Places", "airplane", [0x1F680...0x1F6FF]),
        ("Objects & Symbols", "lightbulb", [0x1F488...0x1F4FF, 0x1F500...0x1F5FF, 0x2600...0x27BF, 0x1F7E0...0x1F7EB])
    ]

    static let groups: [Group] = {
        var seen = Set<String>()
        return blocks.map { block in
            var entries: [Entry] = []
            for range in block.ranges {
                for value in range {
                    guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { continue }
                    let emoji = String(scalar)
                    guard seen.insert(emoji).inserted else { continue }
                    let name = (scalar.properties.name ?? "").lowercased().replacingOccurrences(of: " ", with: "_")
                    entries.append(Entry(emoji: emoji, name: name))
                }
            }
            return Group(id: block.title, symbol: block.symbol, entries: entries)
        } + [letters]
    }()

    /// Regional indicator letters, which Stoat for Web lists so people can spell things out.
    private static let letters: Group = {
        let entries = (0x1F1E6...0x1F1FF).compactMap { value -> Entry? in
            guard let scalar = Unicode.Scalar(UInt32(value)), let letter = UnicodeEmoji.letter(of: scalar) else { return nil }
            return Entry(emoji: String(scalar), name: "regional_indicator_\(letter.lowercased())")
        }
        return Group(id: "Letters", symbol: "textformat.abc", entries: entries)
    }()

    static let all: [Entry] = groups.flatMap(\.entries)

    static func search(_ query: String, limit: Int) -> [Entry] {
        guard limit > 0 else { return [] }
        let normalized = query.lowercased().replacingOccurrences(of: " ", with: "_")
        let prefix = all.filter { $0.name.hasPrefix(normalized) }
        let contains = all.filter { !$0.name.hasPrefix(normalized) && $0.name.contains(normalized) }
        return Array((prefix + contains).prefix(limit))
    }
}

public struct EmojiPickerSheet: View {
    public let sections: [NormalizedStore.EmojiServerSection]
    public var title: String
    public let onSelectEmoji: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @AppStorage("yuki.recentEmoji") private var recentStorage = ""

    public init(sections: [NormalizedStore.EmojiServerSection], title: String = "Emoji", onSelectEmoji: @escaping (String) -> Void) {
        self.sections = sections
        self.title = title
        self.onSelectEmoji = onSelectEmoji
    }

    private var customEmojis: [Emoji] {
        sections.flatMap(\.emojis)
    }

    /// Custom emoji only show up when they're in one of the sections, which leaves out servers
    /// the channel won't accept emoji from.
    private var recents: [String] {
        let usable = Set(customEmojis.map(\.id))
        return recentStorage.split(separator: " ").map(String.init)
            .filter { !Emoji.isCustomEmojiId($0) || usable.contains($0) }
    }

    private let columns = [GridItem(.adaptive(minimum: 42), spacing: 6)]

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        if query.isEmpty {
                            if !recents.isEmpty {
                                section(id: "recents", title: "Recently Used", items: recents)
                            }
                            ForEach(sections) { server in
                                section(id: server.id, title: server.name, icon: server.icon, items: server.emojis.map(\.id))
                            }
                            ForEach(EmojiCatalog.groups) { group in
                                section(id: group.id, title: group.id, items: group.entries.map(\.emoji))
                            }
                        } else {
                            let lowered = query.lowercased()
                            let custom = customEmojis.filter { $0.name.lowercased().contains(lowered) }.map(\.id)
                            let unicode = EmojiCatalog.search(query, limit: 120).map(\.emoji)
                            if custom.isEmpty && unicode.isEmpty {
                                ContentUnavailableView.search(text: query)
                            } else {
                                section(id: "results", title: "Results", items: custom + unicode)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if query.isEmpty {
                        jumpBar(proxy)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search emoji")
            .background(YukiTheme.systemBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func jumpBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !recents.isEmpty {
                    jumpButton(label: "Recently Used") {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                    } action: {
                        withAnimation { proxy.scrollTo("recents", anchor: .top) }
                    }
                }
                ForEach(sections) { server in
                    jumpButton(label: server.name) {
                        AvatarView(avatar: server.icon, fallbackText: server.name, size: 24, isRounded: false)
                    } action: {
                        withAnimation { proxy.scrollTo(server.id, anchor: .top) }
                    }
                }
                if !sections.isEmpty {
                    Divider().frame(height: 22)
                }
                ForEach(EmojiCatalog.groups) { group in
                    jumpButton(label: group.id) {
                        Image(systemName: group.symbol).foregroundStyle(.secondary)
                    } action: {
                        withAnimation { proxy.scrollTo(group.id, anchor: .top) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(YukiTheme.systemBackground)
    }

    private func jumpButton<Icon: View>(label: String, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func section(id: String, title: String, icon: Attachment? = nil, items: [String]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        ReactionEmojiView(emoji: item, size: 30)
                            .frame(width: 42, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(for: item))
                }
            }
            .padding(.horizontal, 12)
        } header: {
            HStack(spacing: 8) {
                if let icon {
                    AvatarView(avatar: icon, fallbackText: title, size: 18, isRounded: false)
                }
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(YukiTheme.systemBackground)
        }
        .id(id)
    }

    private func label(for item: String) -> String {
        if Emoji.isCustomEmojiId(item) {
            return customEmojis.first(where: { $0.id == item })?.name ?? "Custom emoji"
        }
        return item.unicodeScalars.first?.properties.name?.capitalized ?? item
    }

    private func select(_ item: String) {
        YukiHaptics.selection()
        var updated = recentStorage.split(separator: " ").map(String.init).filter { $0 != item }
        updated.insert(item, at: 0)
        recentStorage = updated.prefix(24).joined(separator: " ")
        onSelectEmoji(item)
        dismiss()
    }
}

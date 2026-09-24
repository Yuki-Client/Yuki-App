import SwiftUI
import StoatCore
import StoatState

struct GifPickerSheet: View {
    @Bindable var store: AppStore
    let onSelect: (GifboxClient.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    /// nil shows categories; an empty string shows trending GIFs.
    @State private var activeQuery: String?
    @State private var categories: [GifboxClient.Category] = []
    @State private var results: [GifboxClient.Result] = []
    @State private var nextPosition: String?
    @State private var isLoading = false

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if activeQuery == nil {
                    categoryGrid
                } else {
                    resultGrid
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(YukiTheme.groupedBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Gifbox")
            .onSubmit(of: .search) {
                activeQuery = searchText.trimmingCharacters(in: .whitespaces)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if activeQuery != nil {
                        Button {
                            searchText = ""
                            activeQuery = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back to categories")
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                if categories.isEmpty {
                    categories = await store.gifCategories()
                }
            }
            .task(id: searchText) {
                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    if activeQuery != "" { activeQuery = nil }
                    return
                }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                activeQuery = trimmed
            }
            .task(id: activeQuery) {
                guard let query = activeQuery else { return }
                results = []
                nextPosition = nil
                await loadPage(query: query, position: nil)
            }
        }
    }

    private var title: String {
        switch activeQuery {
        case nil: "GIFs"
        case "": "Trending"
        case let query?: query
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            Button {
                activeQuery = ""
            } label: {
                tile(title: "Trending", imageURL: nil, symbol: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)

            ForEach(categories, id: \.self) { category in
                Button {
                    searchText = category.title
                    activeQuery = category.title
                } label: {
                    tile(title: category.title, imageURL: URL(string: category.image), symbol: nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay {
            if categories.isEmpty {
                ProgressView().padding(.top, 120)
            }
        }
    }

    private func tile(title: String, imageURL: URL?, symbol: String?) -> some View {
        ZStack {
            if let imageURL {
                RemoteImage(url: imageURL, maxPixelSize: 256) { image in
                    image.resizable().scaledToFill()
                } placeholder: { _ in
                    YukiTheme.cardSurface
                }
            } else {
                LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Color.black.opacity(0.35)
            VStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.title3.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(8)
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var resultGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(results) { result in
                Button {
                    YukiHaptics.impact(.light)
                    onSelect(result)
                    dismiss()
                } label: {
                    ZStack {
                        YukiTheme.cardSurface
                        if let poster = result.posterURL {
                            RemoteImage(url: poster, maxPixelSize: 256) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { _ in
                                Color.clear
                            }
                        }
                        if !reduceMotion, let video = result.previewVideoURL {
                            LoopingVideoView(url: video)
                        } else if result.posterURL == nil {
                            Text("GIF").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send GIF")
                .onAppear {
                    if result.id == results.last?.id, let position = nextPosition, !isLoading, let query = activeQuery {
                        Task { await loadPage(query: query, position: position) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay {
            if results.isEmpty {
                if isLoading {
                    ProgressView().padding(.top, 120)
                } else {
                    ContentUnavailableView.search(text: activeQuery ?? "")
                        .padding(.top, 40)
                }
            }
        }
    }

    private func loadPage(query: String, position: String?) async {
        isLoading = true
        defer { isLoading = false }
        guard let page = await store.gifs(matching: query, position: position), activeQuery == query else { return }
        let known = Set(results.map(\.id))
        results.append(contentsOf: page.results.filter { !known.contains($0.id) })
        nextPosition = page.next
    }
}

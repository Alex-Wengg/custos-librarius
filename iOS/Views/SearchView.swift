import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoading {
                    loadingView
                } else if !hasSearched {
                    emptyStateView
                } else if results.isEmpty {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search your library...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    results = []
                    hasSearched = false
                }
            }
        }
    }

    // MARK: - Views

    var loadingView: some View {
        VStack(spacing: 16) {
            SwiftUI.ProgressView()
            Text("Loading library...")
                .foregroundStyle(.secondary)
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Search Your Library")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter keywords to search through your documents")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !Task { await appState.searchService.hasChunks }.result.map({ $0 }) ?? true {
                Text("No documents synced yet.\nAdd documents on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
        }
        .padding()
    }

    var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.bold)

            Text("Try different keywords")
                .foregroundStyle(.secondary)
        }
    }

    var resultsList: some View {
        List(results) { result in
            SearchResultRow(result: result)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true
        hasSearched = true

        Task {
            results = await appState.searchService.search(query: searchText, topK: 20)
            isSearching = false
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(result.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", result.score))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }

            // Text
            Text(result.text)
                .font(.body)
                .lineLimit(isExpanded ? nil : 3)

            // Expand button
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchView()
        .environmentObject(AppState())
}

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var hasSearched = false
    @State private var noDocumentsIndexed = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search your documents...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        appState.searchResults = []
                        hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty)
            }
            .padding()
            .background(.background)

            Divider()

            // Results
            if appState.isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if noDocumentsIndexed {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("No documents indexed")
                        .font(.headline)
                    Text("Add documents and run indexing from the Documents tab first.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if appState.searchResults.isEmpty && hasSearched {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                    Text("Try different keywords or check your documents.")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if appState.searchResults.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Enter a search query to find relevant passages")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.searchResults) { result in
                            SearchResultCard(result: result)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Search")
    }

    func performSearch() {
        guard !searchText.isEmpty else { return }

        Task { @MainActor in
            appState.isSearching = true
            noDocumentsIndexed = false

            do {
                // Ensure search service is loaded
                if !appState.embeddingModelLoaded {
                    try await appState.searchService?.loadEmbeddingModel()
                    appState.embeddingModelLoaded = true
                }

                let results = try await appState.searchService?.search(query: searchText, topK: 10) ?? []
                appState.searchResults = results

                // Check if no documents are indexed (empty results on first search)
                if results.isEmpty {
                    // Could be no matching results or no documents indexed
                    let chunksPath = appState.currentProject?.path.appendingPathComponent("data/chunks.json")
                    if let path = chunksPath, !FileManager.default.fileExists(atPath: path.path) {
                        noDocumentsIndexed = true
                    }
                }
            } catch {
                print("Search error: \(error)")
                appState.searchResults = []
            }

            hasSearched = true
            appState.isSearching = false
        }
    }
}

struct SearchResultCard: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)
                Text(result.source)
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", result.score * 100))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(result.text)
                .font(.body)
                .lineLimit(4)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray).opacity(0.1))
        .cornerRadius(12)
    }
}

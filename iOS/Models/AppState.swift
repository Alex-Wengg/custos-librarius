import SwiftUI

/// iOS App State - read-only consumer of macOS-generated content
@MainActor
class AppState: ObservableObject {
    // Navigation
    @Published var selectedTab: Tab = .search

    // Data
    @Published var chunks: [ChunkData] = []
    @Published var quizSets: [QuizSet] = []
    @Published var flashcardSets: [FlashcardSet] = []
    @Published var progress: StudyProgress = StudyProgress()

    // State
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Services
    let searchService = SearchService()

    // Data directory (will be iCloud container in production)
    var dataDirectory: URL {
        // For POC, use Documents directory
        // In production: FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.custoslibrarius")
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustosLibrarius")
    }

    init() {
        Task {
            await loadData()
        }
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

            // Load chunks for search
            try await searchService.loadChunks(from: dataDirectory)

            // Load quiz sets
            quizSets = try loadJSON(filename: "quizzes.json") ?? []

            // Load flashcard sets
            flashcardSets = try loadJSON(filename: "flashcards.json") ?? []

            // Load progress
            progress = try loadJSON(filename: "progress.json") ?? StudyProgress()

        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func saveProgress() {
        do {
            try saveJSON(progress, filename: "progress.json")
        } catch {
            print("Failed to save progress: \(error)")
        }
    }

    // MARK: - JSON Helpers

    private func loadJSON<T: Decodable>(filename: String) throws -> T? {
        let url = dataDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, filename: String) throws {
        let url = dataDirectory.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url)
    }
}

// MARK: - Tab

enum Tab: String, CaseIterable {
    case search = "Search"
    case quiz = "Quiz"
    case flashcards = "Flashcards"
    case progress = "Progress"

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .quiz: return "checkmark.circle"
        case .flashcards: return "rectangle.on.rectangle"
        case .progress: return "chart.bar"
        }
    }
}

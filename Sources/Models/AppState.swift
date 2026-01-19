import SwiftUI
import Combine

/// Main application state
@MainActor
class AppState: ObservableObject {
    // Navigation
    @Published var selectedTab: SidebarItem = .chat
    @Published var showNewProjectSheet = false
    @Published var showAddDocumentSheet = false

    // Project
    @Published var currentProject: Project?
    @Published var projects: [Project] = []

    // Documents
    @Published var documents: [Document] = []
    @Published var selectedDocument: Document?

    // Chat
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false

    // Search
    @Published var searchQuery = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false

    // Training
    @Published var trainingProgress: TrainingProgress?
    @Published var isTraining = false

    // Models
    @Published var modelLoaded = false
    @Published var modelLoadingProgress: Double = 0
    @Published var embeddingModelLoaded = false

    // Services
    var chatService: ChatService?
    var searchService: SearchService?
    var trainingService: TrainingService?

    init() {
        loadProjects()
        // Auto-open default project if exists (deferred to avoid publishing during init)
        let defaultProject = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("LibrarianProjects/MyLibrary")
        if FileManager.default.fileExists(atPath: defaultProject.appendingPathComponent("librarian.json").path) {
            Task { @MainActor in
                self.currentProject = Project(name: "MyLibrary", path: defaultProject)
                self.loadProjectData()
            }
        }
    }

    func loadProjects() {
        // Load projects from disk
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".librarian/projects")

        if FileManager.default.fileExists(atPath: projectsDir.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: projectsDir,
                    includingPropertiesForKeys: nil
                )
                projects = contents.compactMap { url -> Project? in
                    let configPath = url.appendingPathComponent("librarian.json")
                    guard FileManager.default.fileExists(atPath: configPath.path) else { return nil }
                    return Project(name: url.lastPathComponent, path: url)
                }
            } catch {
                print("Error loading projects: \(error)")
            }
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Librarian project folder"

        if panel.runModal() == .OK, let url = panel.url {
            let configPath = url.appendingPathComponent("librarian.json")
            if FileManager.default.fileExists(atPath: configPath.path) {
                currentProject = Project(name: url.lastPathComponent, path: url)
                loadProjectData()
            }
        }
    }

    func loadProjectData() {
        guard let project = currentProject else { return }

        // Load documents
        let docsDir = project.path.appendingPathComponent("documents")
        if FileManager.default.fileExists(atPath: docsDir.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: nil)
                documents = files.filter { ["pdf", "txt", "md", "epub"].contains($0.pathExtension.lowercased()) }
                    .map { Document(name: $0.lastPathComponent, path: $0) }
            } catch {
                print("Error loading documents: \(error)")
            }
        }

        // Initialize services
        Task {
            await initializeServices()
        }
    }

    func initializeServices() async {
        guard let project = currentProject else { return }

        chatService = ChatService(projectPath: project.path)
        searchService = SearchService(projectPath: project.path)
        trainingService = TrainingService(projectPath: project.path)

        // Load models
        await loadModels()
    }

    func loadModels() async {
        modelLoadingProgress = 0.1
        do {
            try await chatService?.loadModel()
            modelLoaded = true
            modelLoadingProgress = 0.6

            try await searchService?.loadEmbeddingModel()
            embeddingModelLoaded = true
            modelLoadingProgress = 1.0
        } catch {
            print("Error loading models: \(error)")
        }
    }
}

// MARK: - Models

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case search = "Search"
    case library = "Library"
    case flashcards = "Flashcards"
    case quiz = "Quiz"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .flashcards: return "rectangle.on.rectangle"
        case .quiz: return "checkmark.circle"
        case .settings: return "gear"
        }
    }
}

struct Project: Identifiable {
    let id = UUID()
    let name: String
    let path: URL
}

struct Document: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let text: String
    let source: String
    let score: Float
}

struct TrainingProgress {
    let iteration: Int
    let totalIterations: Int
    let trainingLoss: Float
    let validationLoss: Float?
    let bestLoss: Float
    let patienceCounter: Int
}

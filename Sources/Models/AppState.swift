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
    @Published var generationProgress: GenerationProgress?

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
    @Published var isLoadingModels = false
    @Published var adapterLoaded = false

    // Services
    var chatService: ChatService?
    var searchService: SearchService?
    var trainingService: TrainingService?

    // Persistence key for last project
    private static let lastProjectPathKey = "lastProjectPath"

    init() {
        loadProjects()
        // Auto-open last selected project (or default) on launch
        Task { @MainActor in
            await self.autoLoadLastProject()
        }
    }

    /// Auto-load the last selected project on app launch
    private func autoLoadLastProject() async {
        // Try last selected project first
        if let lastPath = UserDefaults.standard.string(forKey: Self.lastProjectPathKey) {
            let url = URL(fileURLWithPath: lastPath)
            let configPath = url.appendingPathComponent("librarian.json")
            if FileManager.default.fileExists(atPath: configPath.path) {
                self.currentProject = Project(name: url.lastPathComponent, path: url)
                self.loadProjectData()
                return
            }
        }

        // Fall back to default project
        let defaultProject = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("LibrarianProjects/MyLibrary")
        if FileManager.default.fileExists(atPath: defaultProject.appendingPathComponent("librarian.json").path) {
            self.currentProject = Project(name: "MyLibrary", path: defaultProject)
            self.loadProjectData()
        }
    }

    /// Save the current project path for auto-load on next launch
    private func saveLastProjectPath() {
        if let path = currentProject?.path.path {
            UserDefaults.standard.set(path, forKey: Self.lastProjectPathKey)
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
                saveLastProjectPath()
                loadProjectData()
            }
        }
    }

    /// Select a project programmatically
    func selectProject(_ project: Project) {
        currentProject = project
        saveLastProjectPath()
        loadProjectData()
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
        guard !isLoadingModels else { return }
        isLoadingModels = true
        modelLoadingProgress = 0.1

        do {
            print("Loading LLM model...")
            try await chatService?.loadModel()
            modelLoaded = true

            // Check if adapter was loaded
            if let hasAdapter = await chatService?.hasLoadedAdapter {
                adapterLoaded = hasAdapter
                print(hasAdapter ? "LoRA adapter loaded" : "No adapter (base model)")
            }

            modelLoadingProgress = 0.6
            print("LLM model loaded")

            print("Loading embedding model...")
            try await searchService?.loadEmbeddingModel()
            embeddingModelLoaded = true
            modelLoadingProgress = 1.0
            print("Embedding model loaded")
        } catch {
            print("Error loading models: \(error)")
        }

        isLoadingModels = false
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

// SearchResult is defined in SearchService.swift

struct TrainingProgress {
    let iteration: Int
    let totalIterations: Int
    let trainingLoss: Float
    let validationLoss: Float?
    let bestLoss: Float
    let patienceCounter: Int

    var percentComplete: Double {
        guard totalIterations > 0 else { return 0 }
        return Double(iteration) / Double(totalIterations) * 100
    }
}

struct GenerationProgress {
    let tokensGenerated: Int
    let tokensPerSecond: Double
    let elapsedTime: TimeInterval
    let stage: GenerationStage

    enum GenerationStage: String {
        case preparing = "Preparing..."
        case generating = "Generating"
        case finishing = "Finishing..."
    }

    var displayText: String {
        switch stage {
        case .preparing:
            return stage.rawValue
        case .generating:
            return "\(tokensGenerated) tokens • \(String(format: "%.1f", tokensPerSecond)) tok/s"
        case .finishing:
            return stage.rawValue
        }
    }
}

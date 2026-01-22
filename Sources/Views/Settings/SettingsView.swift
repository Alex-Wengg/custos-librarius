import SwiftUI

// MARK: - Model Definitions

struct MLXModel: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let description: String
    let category: ModelCategory

    enum ModelCategory: String, CaseIterable {
        case small = "Small (1-3B)"
        case medium = "Medium (7-8B)"
        case large = "Large (14B+)"
    }
}

let availableModels: [MLXModel] = [
    // Small
    MLXModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B", size: "~1GB", description: "Fast, low RAM", category: .small),
    MLXModel(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen 2.5 3B", size: "~2GB", description: "Balanced speed/quality", category: .small),
    MLXModel(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", size: "~2GB", description: "Meta, good reasoning", category: .small),

    // Medium
    MLXModel(id: "mlx-community/Qwen2.5-7B-Instruct-4bit", name: "Qwen 2.5 7B", size: "~4GB", description: "Recommended - best quality/speed", category: .medium),
    MLXModel(id: "mlx-community/Llama-3.1-8B-Instruct-4bit", name: "Llama 3.1 8B", size: "~4.5GB", description: "Meta, strong all-around", category: .medium),

    // Large
    MLXModel(id: "mlx-community/Qwen2.5-14B-Instruct-4bit", name: "Qwen 2.5 14B", size: "~8GB", description: "Excellent reasoning", category: .large),
    MLXModel(id: "mlx-community/Qwen2.5-32B-Instruct-4bit", name: "Qwen 2.5 32B", size: "~18GB", description: "Top tier (needs 32GB+ RAM)", category: .large),
]

let availableEmbeddingModels: [MLXModel] = [
    MLXModel(id: "mlx-community/bge-small-en-v1.5-quantized-4bit", name: "BGE Small", size: "~50MB", description: "Fast, English only", category: .small),
    MLXModel(id: "mlx-community/bge-base-en-v1.5-quantized-4bit", name: "BGE Base", size: "~100MB", description: "Better quality, English", category: .small),
    MLXModel(id: "mlx-community/bge-large-en-v1.5-quantized-4bit", name: "BGE Large", size: "~300MB", description: "Best quality, English", category: .medium),
    MLXModel(id: "mlx-community/bge-m3-4bit", name: "BGE M3", size: "~500MB", description: "Multilingual", category: .medium),
]

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("modelId") private var modelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    @AppStorage("embeddingModelId") private var embeddingModelId = "mlx-community/bge-small-en-v1.5-quantized-4bit"
    @AppStorage("maxTokens") private var maxTokens = 512
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("chunkSize") private var chunkSize = 400

    @State private var showLLMTests = false
    @State private var isReloadingModel = false
    @State private var customModelId = ""
    @State private var showCustomModel = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme:", selection: $appTheme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }

            Section {
                // LLM Model Picker
                Picker("LLM Model:", selection: $modelId) {
                    ForEach(MLXModel.ModelCategory.allCases, id: \.self) { category in
                        let models = availableModels.filter { $0.category == category }
                        if !models.isEmpty {
                            Section(header: Text(category.rawValue)) {
                                ForEach(models) { model in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(model.name)
                                            Text(model.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(model.size)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(model.id)
                                }
                            }
                        }
                    }
                }
                .pickerStyle(.menu)

                // Current model info
                if let currentModel = availableModels.first(where: { $0.id == modelId }) {
                    HStack {
                        Label(currentModel.description, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(currentModel.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Custom model option
                DisclosureGroup("Custom Model", isExpanded: $showCustomModel) {
                    HStack {
                        TextField("mlx-community/model-name", text: $customModelId)
                            .textFieldStyle(.roundedBorder)
                        Button("Use") {
                            if !customModelId.isEmpty {
                                modelId = customModelId
                            }
                        }
                        .disabled(customModelId.isEmpty)
                    }
                    Text("Enter any model ID from huggingface.co/mlx-community")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Reload button
                HStack {
                    Button {
                        reloadModel()
                    } label: {
                        if isReloadingModel {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Reload Model", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isReloadingModel || appState.currentProject == nil)

                    Spacer()

                    if appState.modelLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Not loaded", systemImage: "circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Language Model")
            } footer: {
                Text("Models are downloaded from HuggingFace on first use (~2-8 GB)")
                    .font(.caption)
            }

            Section("Embedding Model") {
                Picker("Model:", selection: $embeddingModelId) {
                    ForEach(availableEmbeddingModels) { model in
                        HStack {
                            Text(model.name)
                            Spacer()
                            Text(model.size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Generation") {
                HStack {
                    Text("Max Tokens:")
                    Slider(value: .init(get: { Double(maxTokens) }, set: { maxTokens = Int($0) }),
                           in: 128...2048, step: 128)
                    Text("\(maxTokens)")
                        .frame(width: 50)
                }

                HStack {
                    Text("Temperature:")
                    Slider(value: $temperature, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", temperature))
                        .frame(width: 50)
                }
            }

            Section {
                HStack {
                    Text("Chunk Size:")
                    Slider(value: .init(get: { Double(chunkSize) }, set: { chunkSize = Int($0) }),
                           in: 100...800, step: 50)
                    Text("\(chunkSize)")
                        .frame(width: 50)
                }
            } header: {
                Text("Document Processing")
            } footer: {
                Text("Target words per chunk. Smaller = more precise search, larger = more context")
                    .font(.caption)
            }

            Section("About") {
                HStack {
                    Text("Custos Librarius")
                        .fontWeight(.bold)
                    Spacer()
                    Text("v1.0.0")
                        .foregroundColor(.secondary)
                }

                Text("AI-powered document research assistant built with MLX Swift")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Developer") {
                Button("Run LLM Tests") {
                    showLLMTests = true
                }
                .disabled(appState.chatService == nil)

                if appState.chatService == nil {
                    Text("Open a project to enable LLM tests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 550, height: 600)
        .sheet(isPresented: $showLLMTests) {
            LLMTestView()
                .environmentObject(appState)
        }
    }

    func reloadModel() {
        isReloadingModel = true

        // Update project config
        if let project = appState.currentProject {
            let configPath = project.path.appendingPathComponent("librarian.json")
            let config = ProjectConfig(
                name: project.name,
                model: modelId,
                embeddingModel: embeddingModelId
            )
            if let data = try? JSONEncoder().encode(config) {
                try? data.write(to: configPath)
            }
        }

        // Reload
        Task {
            appState.modelLoaded = false
            appState.chatService = nil

            if let project = appState.currentProject {
                appState.chatService = ChatService(projectPath: project.path)
                try? await appState.chatService?.loadModel()
                appState.modelLoaded = true
            }

            await MainActor.run {
                isReloadingModel = false
            }
        }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var projectName = ""
    @State private var projectLocation = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Name")
                        .font(.headline)
                    TextField("Enter project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.headline)
                    HStack {
                        Text(projectLocation.path)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
                            selectLocation()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create Project") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectName.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    func selectLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            projectLocation = url
        }
    }

    func createProject() {
        let projectDir = projectLocation.appendingPathComponent(projectName)

        do {
            // Create directories
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectDir.appendingPathComponent("documents"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectDir.appendingPathComponent("data"), withIntermediateDirectories: true)

            // Create config
            let config = ProjectConfig(
                name: projectName,
                model: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                embeddingModel: "mlx-community/bge-small-en-v1.5-quantized-4bit"
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: projectDir.appendingPathComponent("librarian.json"))

            // Set as current project
            appState.currentProject = Project(name: projectName, path: projectDir)
            appState.loadProjectData()

            dismiss()
        } catch {
            print("Error creating project: \(error)")
        }
    }
}

struct ProjectConfig: Codable {
    let name: String
    let model: String
    let embeddingModel: String
}

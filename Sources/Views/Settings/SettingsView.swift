import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("modelId") private var modelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    @AppStorage("embeddingModelId") private var embeddingModelId = "mlx-community/bge-small-en-v1.5-quantized-4bit"
    @AppStorage("maxTokens") private var maxTokens = 512
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("appTheme") private var appTheme = "dark"

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme:", selection: $appTheme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }

            Section("Models") {
                TextField("LLM Model:", text: $modelId)
                    .textFieldStyle(.roundedBorder)

                TextField("Embedding Model:", text: $embeddingModelId)
                    .textFieldStyle(.roundedBorder)

                Text("Models are downloaded from HuggingFace on first use")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

            Section("About") {
                HStack {
                    Text("Librarian")
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
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showLLMTests) {
            LLMTestView()
                .environmentObject(appState)
        }
    }

    @State private var showLLMTests = false
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

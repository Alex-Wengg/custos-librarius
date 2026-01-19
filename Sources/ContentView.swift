import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.currentProject != nil {
                DetailView()
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $appState.showNewProjectSheet) {
            NewProjectSheet()
        }
        .sheet(isPresented: $appState.showAddDocumentSheet) {
            AddDocumentSheet()
        }
        .onAppear {
            // Ensure the window can receive keyboard events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.keyWindow ?? NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(window.contentView)
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedTab) {
            if appState.currentProject != nil {
                Section("Project") {
                    ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }

            Section("Recent Projects") {
                ForEach(appState.projects) { project in
                    Button {
                        appState.currentProject = project
                        appState.loadProjectData()
                    } label: {
                        Label(project.name, systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Custos Librarius")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.showNewProjectSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct DetailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedTab {
            case .chat:
                ChatView()
            case .search:
                SearchView()
            case .library:
                LibraryView()
            case .flashcards:
                FlashcardsView()
            case .quiz:
                QuizView()
            case .settings:
                SettingsView()
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectName = ""
    @State private var showCreateForm = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Custos Librarius")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your personal AI guardian of knowledge")
                .font(.title3)
                .foregroundColor(.secondary)

            if showCreateForm {
                VStack(spacing: 12) {
                    TextField("Project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .focused($isTextFieldFocused)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                        .onSubmit {
                            if !projectName.isEmpty {
                                createProject()
                            }
                        }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showCreateForm = false
                            projectName = ""
                        }

                        Button("Create") {
                            createProject()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(projectName.isEmpty)
                    }
                }
                .padding(.top)
            } else {
                HStack(spacing: 16) {
                    Button {
                        showCreateForm = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                            .frame(width: 140)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        appState.openProject()
                    } label: {
                        Label("Open Project", systemImage: "folder")
                            .frame(width: 140)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top)
            }
        }
        .padding(40)
    }

    func createProject() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let projectDir = homeDir.appendingPathComponent("LibrarianProjects/\(projectName)")

        do {
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectDir.appendingPathComponent("documents"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectDir.appendingPathComponent("data"), withIntermediateDirectories: true)

            let config = ProjectConfig(
                name: projectName,
                model: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                embeddingModel: "mlx-community/bge-small-en-v1.5-quantized-4bit"
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: projectDir.appendingPathComponent("librarian.json"))

            appState.currentProject = Project(name: projectName, path: projectDir)
            appState.loadProjectData()

            showCreateForm = false
            projectName = ""
        } catch {
            print("Error: \(error)")
        }
    }
}

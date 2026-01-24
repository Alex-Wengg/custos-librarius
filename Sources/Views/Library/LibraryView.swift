import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                Text("Documents").tag(0)
                Text("Training").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            if selectedSection == 0 {
                DocumentsSection()
            } else {
                TrainingSection()
            }
        }
        .navigationTitle("Library")
    }
}

// MARK: - Documents Section

struct DocumentsSection: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("chunkSize") private var chunkSize = 400
    @State private var isDropTargeted = false
    @State private var isIndexing = false
    @State private var indexingStatus = ""
    @State private var showChunkInspector = false
    @State private var processingStats: ProcessingStats?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(appState.documents.count) documents")
                    .foregroundColor(.secondary)

                Spacer()

                // Inspect chunks button
                Button {
                    showChunkInspector = true
                } label: {
                    Label("Inspect Chunks", systemImage: "magnifyingglass")
                }
                .disabled(appState.currentProject == nil)

                if !appState.documents.isEmpty {
                    // Fast processing (heuristics only)
                    Button {
                        indexDocuments(useAI: false)
                    } label: {
                        if isIndexing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Processing...")
                            }
                        } else {
                            Label("Process Fast", systemImage: "bolt")
                        }
                    }
                    .disabled(isIndexing)
                    .help("Fast processing using heuristics (recommended)")

                    // AI processing (slower but more accurate)
                    Button {
                        indexDocuments(useAI: true)
                    } label: {
                        Label("Process with AI", systemImage: "brain")
                    }
                    .disabled(isIndexing)
                    .help("Slower but more accurate AI-based classification")

                    // Delete selected document
                    if let selected = appState.selectedDocument {
                        Button(role: .destructive) {
                            removeDocument(selected)
                            appState.selectedDocument = nil
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }

                Button {
                    appState.showAddDocumentSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            if !indexingStatus.isEmpty {
                Text(indexingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            Divider()

            // Document list or drop zone
            if appState.documents.isEmpty {
                LibraryDropZone(isTargeted: $isDropTargeted) { urls in
                    addDocuments(urls)
                }
            } else {
                List(appState.documents, selection: $appState.selectedDocument) { doc in
                    LibraryDocumentRow(document: doc) {
                        removeDocument(doc)
                    }
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(doc.path.path, inFileViewerRootedAtPath: "")
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            removeDocument(doc)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showChunkInspector) {
            ChunkInspectorView()
                .environmentObject(appState)
        }
    }

    func addDocuments(_ urls: [URL]) {
        guard let project = appState.currentProject else { return }
        let docsDir = project.path.appendingPathComponent("documents")

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["pdf", "txt", "md", "epub"].contains(ext) else { continue }

            let dest = docsDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)

            appState.documents.append(Document(name: url.lastPathComponent, path: dest))
        }
    }

    func removeDocument(_ doc: Document) {
        // Remove the file
        try? FileManager.default.removeItem(at: doc.path)
        appState.documents.removeAll { $0.id == doc.id }

        // Remove associated chunks from processed data
        guard let project = appState.currentProject else { return }
        let dataDir = project.path.appendingPathComponent("data")

        let chunksPath = dataDir.appendingPathComponent("chunks_v2.json")
        if let data = try? Data(contentsOf: chunksPath),
           var chunks = try? JSONDecoder().decode([SemanticChunk].self, from: data) {
            let beforeCount = chunks.count
            chunks.removeAll { $0.source == doc.name }
            if chunks.count != beforeCount {
                if let newData = try? JSONEncoder().encode(chunks) {
                    try? newData.write(to: chunksPath)
                }
                indexingStatus = "Removed \(beforeCount - chunks.count) chunks for \(doc.name)"
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        addDocuments([url])
                    }
                }
            }
        }
        return true
    }

    func indexDocuments(useAI: Bool = false) {
        guard let project = appState.currentProject else { return }
        isIndexing = true
        indexingStatus = useAI ? "Loading AI model..." : "Starting fast processing..."

        Task {
            do {
                let service: DocumentProcessingService

                if useAI {
                    // Load model if needed for AI classification
                    if appState.chatService == nil {
                        appState.chatService = ChatService(projectPath: project.path)
                        try await appState.chatService?.loadModel()
                    }
                    service = DocumentProcessingService(
                        projectPath: project.path,
                        chatService: appState.chatService,
                        enableAIClassification: true,
                        chunkSize: chunkSize
                    )
                } else {
                    // Fast heuristic-based processing (no LLM)
                    service = DocumentProcessingService(
                        projectPath: project.path,
                        chatService: nil,
                        enableAIClassification: false,
                        chunkSize: chunkSize
                    )
                }

                let result = try await service.processAllDocuments { status in
                    Task { @MainActor in
                        indexingStatus = status
                    }
                }

                await MainActor.run {
                    processingStats = result.stats
                    var statusMsg = "Processed \(result.chunks.count) chunks from \(result.stats.totalDocuments) documents"
                    statusMsg += " (avg \(Int(result.stats.avgChunkLength)) words/chunk)"
                    if result.stats.chunksFiltered > 0 {
                        statusMsg += " - \(result.stats.chunksFiltered) filtered"
                    }
                    let midSentenceFixes = result.stats.chunksMergedContext + result.stats.chunksMarkedContinuation
                    if midSentenceFixes > 0 {
                        statusMsg += " - \(midSentenceFixes) mid-sentence fixed"
                    }
                    indexingStatus = statusMsg
                    isIndexing = false
                }
            } catch {
                await MainActor.run {
                    indexingStatus = "Error: \(error.localizedDescription)"
                    isIndexing = false
                }
            }
        }
    }
}

struct LibraryDocumentRow: View {
    let document: Document
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconForExtension(document.path.pathExtension))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(document.name)
                    .fontWeight(.medium)

                if let size = fileSize(document.path) {
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Remove document")
        }
        .padding(.vertical, 4)
    }

    func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.fill"
        case "epub": return "book.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc"
        }
    }

    func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct LibraryDropZone: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text("Drop PDF, EPUB, TXT, or MD files here")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("or click Add above")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
        )
        .padding()
    }
}

// MARK: - Training Section

struct TrainingSection: View {
    @EnvironmentObject var appState: AppState
    @State private var status = ""
    @State private var pipelineProgress: PipelineProgress?
    @State private var isRunning = false
    @State private var existingExampleCount = 0
    @State private var hasAdapter = false
    @State private var targetExamples = 250
    @State private var chunkCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("LoRA Fine-Tuning")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Train the AI to become an expert on your documents using LOCAL Qwen model")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Status indicators
                HStack(spacing: 16) {
                    StatusBadge(
                        icon: "doc.text",
                        label: "Documents",
                        value: "\(appState.documents.count)",
                        isGood: !appState.documents.isEmpty
                    )
                    StatusBadge(
                        icon: "square.stack.3d.up",
                        label: "Chunks",
                        value: "\(chunkCount)",
                        isGood: chunkCount > 0
                    )
                    StatusBadge(
                        icon: "list.bullet.rectangle",
                        label: "Examples",
                        value: "\(existingExampleCount)",
                        isGood: existingExampleCount > 0
                    )
                    StatusBadge(
                        icon: "cpu",
                        label: "Adapter",
                        value: hasAdapter ? "Ready" : "None",
                        isGood: hasAdapter
                    )
                }

                // Warning if documents exist but not processed
                if !appState.documents.isEmpty && chunkCount == 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Documents need to be processed first. Go to Documents tab and click 'Process Fast'.")
                            .font(.callout)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Model status
                GroupBox("Local Model") {
                    VStack(alignment: .leading, spacing: 12) {
                        if appState.modelLoaded {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Qwen model loaded and ready")
                                Spacer()
                            }

                            // Show adapter status
                            if appState.adapterLoaded {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                        .foregroundColor(.purple)
                                    Text("Fine-tuned adapter active")
                                        .foregroundColor(.purple)
                                    Spacer()
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("Model will be loaded when training starts")
                                Spacer()
                            }
                        }

                        Text("Training data is generated using your local Qwen model - no API key needed!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Progress
                if let progress = pipelineProgress {
                    GroupBox(progress.phase.rawValue) {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: Double(progress.percentComplete), total: 100) {
                                HStack {
                                    Text(progress.detail)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(progress.percentComplete)%")
                                }
                                .font(.caption)
                            }

                            if let trainingProgress = progress.trainingProgress {
                                HStack(spacing: 24) {
                                    LossIndicator(label: "Train", value: trainingProgress.trainingLoss)
                                    if let validLoss = trainingProgress.validationLoss {
                                        LossIndicator(label: "Valid", value: validLoss)
                                    }
                                    LossIndicator(label: "Best", value: trainingProgress.bestLoss, highlight: true)
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                // Status message
                if !status.isEmpty && pipelineProgress == nil {
                    GroupBox {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(status)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                }

                // Actions
                VStack(spacing: 12) {
                    if isRunning {
                        Button("Stop") {
                            stopPipeline()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        // Full pipeline button
                        Button {
                            runFullPipeline()
                        } label: {
                            Label("Generate & Train", systemImage: "sparkles")
                                .frame(width: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canRunPipeline)

                        // Individual actions
                        HStack(spacing: 12) {
                            Button {
                                generateDataOnly()
                            } label: {
                                Label("Generate Data Only", systemImage: "doc.badge.plus")
                            }
                            .disabled(!canGenerateData)

                            Button {
                                trainFromExisting()
                            } label: {
                                Label("Train from Existing", systemImage: "cpu")
                            }
                            .disabled(existingExampleCount == 0)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Settings
                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Target examples:")
                            Picker("", selection: $targetExamples) {
                                Text("50").tag(50)
                                Text("100").tag(100)
                                Text("200").tag(200)
                                Text("250").tag(250)
                            }
                            .frame(width: 80)
                            Text("(more = better quality but slower)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle")
                            .font(.headline)

                        Text("1. Local Qwen model generates Q&A from your documents")
                        Text("2. Data is formatted for Qwen and split 80/20 train/valid")
                        Text("3. LoRA adapter trains with early stopping")
                        Text("4. Adapter is saved and used for improved quiz generation")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            refreshStatus()
        }
    }

    // MARK: - Computed Properties

    var canRunPipeline: Bool {
        chunkCount > 0
    }

    var canGenerateData: Bool {
        chunkCount > 0
    }

    // MARK: - Actions

    func refreshStatus() {
        guard let project = appState.currentProject else { return }

        Task {
            let pipeline = TrainingPipeline(projectPath: project.path)
            existingExampleCount = await pipeline.getExistingExampleCount()
            hasAdapter = pipeline.hasTrainedAdapter()

            // Load chunk count
            let chunksPath = project.path.appendingPathComponent("data/chunks_v2.json")
            if let data = try? Data(contentsOf: chunksPath),
               let chunks = try? JSONDecoder().decode([SemanticChunk].self, from: data) {
                await MainActor.run {
                    chunkCount = chunks.count
                }
            } else {
                await MainActor.run {
                    chunkCount = 0
                }
            }
        }
    }

    func runFullPipeline() {
        guard let project = appState.currentProject else { return }

        isRunning = true
        status = ""

        Task { @MainActor in
            let pipeline = TrainingPipeline(projectPath: project.path)

            do {
                let result = try await pipeline.runFullPipeline(
                    targetExamples: targetExamples,
                    trainingIterations: 200,
                    patience: 5,
                    learningRate: 1e-5,
                    loraLayers: 4
                ) { progress in
                    Task { @MainActor in
                        pipelineProgress = progress
                    }
                }

                status = "Complete! Generated \(result.examplesGenerated) examples, best loss: \(String(format: "%.4f", result.bestLoss))"
                pipelineProgress = nil
                refreshStatus()
            } catch {
                status = "Error: \(error.localizedDescription)"
                pipelineProgress = nil
            }

            isRunning = false
        }
    }

    func generateDataOnly() {
        guard let project = appState.currentProject else { return }

        isRunning = true
        status = "Loading model and generating training data..."

        Task { @MainActor in
            let pipeline = TrainingPipeline(projectPath: project.path)

            do {
                let result = try await pipeline.generateTrainingDataOnly(
                    targetExamples: targetExamples
                ) { progress in
                    Task { @MainActor in
                        status = progress.currentStatus
                    }
                }

                status = "Generated \(result.examples.count) examples (saved for training)"
                refreshStatus()
            } catch {
                status = "Error: \(error.localizedDescription)"
            }

            isRunning = false
        }
    }

    func trainFromExisting() {
        guard let project = appState.currentProject else { return }

        isRunning = true
        appState.isTraining = true

        Task { @MainActor in
            let pipeline = TrainingPipeline(projectPath: project.path)

            do {
                try await pipeline.trainFromExistingExamples(
                    iterations: 200,
                    patience: 5,
                    learningRate: 1e-5,
                    loraLayers: 4
                ) { progress in
                    Task { @MainActor in
                        appState.trainingProgress = progress
                        pipelineProgress = PipelineProgress(
                            phase: .training,
                            detail: "Iteration \(progress.iteration)/\(progress.totalIterations)",
                            percentComplete: Int(progress.percentComplete),
                            trainingProgress: progress
                        )
                    }
                }

                status = "Training complete!"
                pipelineProgress = nil
                refreshStatus()
            } catch {
                status = "Error: \(error.localizedDescription)"
                pipelineProgress = nil
            }

            isRunning = false
            appState.isTraining = false
        }
    }

    func stopPipeline() {
        guard let project = appState.currentProject else { return }
        let pipeline = TrainingPipeline(projectPath: project.path)

        Task {
            await pipeline.stopTraining()
        }

        isRunning = false
        appState.isTraining = false
        pipelineProgress = nil
        status = "Stopped"
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let icon: String
    let label: String
    let value: String
    let isGood: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(isGood ? .green : .secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LossIndicator: View {
    let label: String
    let value: Float
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.4f", value))
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(highlight ? .green : .primary)
        }
    }
}

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
    @State private var isDropTargeted = false
    @State private var isIndexing = false
    @State private var indexingStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(appState.documents.count) documents")
                    .foregroundColor(.secondary)

                Spacer()

                if !appState.documents.isEmpty {
                    Button {
                        indexDocuments()
                    } label: {
                        if isIndexing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Indexing...")
                            }
                        } else {
                            Label("Index All", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isIndexing)
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
                    LibraryDocumentRow(document: doc)
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
        try? FileManager.default.removeItem(at: doc.path)
        appState.documents.removeAll { $0.id == doc.id }
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

    func indexDocuments() {
        guard let project = appState.currentProject else { return }
        isIndexing = true
        indexingStatus = "Starting..."

        Task {
            do {
                let docsDir = project.path.appendingPathComponent("documents")
                let dataDir = project.path.appendingPathComponent("data")

                // Create data directory if needed
                try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

                var allChunks: [[String: Any]] = []
                let files = try FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: nil)

                for (index, file) in files.enumerated() {
                    await MainActor.run {
                        indexingStatus = "Processing \(file.lastPathComponent)... (\(index + 1)/\(files.count))"
                    }

                    let ext = file.pathExtension.lowercased()
                    guard ["txt", "md"].contains(ext) else { continue }

                    // Read text file
                    let content = try String(contentsOf: file, encoding: .utf8)
                    let chunks = chunkText(content, source: file.lastPathComponent)

                    for (i, chunk) in chunks.enumerated() {
                        allChunks.append([
                            "id": "\(file.deletingPathExtension().lastPathComponent)_\(i)",
                            "text": chunk,
                            "source": file.lastPathComponent,
                            "title": file.deletingPathExtension().lastPathComponent,
                            "author": "Unknown",
                            "index": i
                        ])
                    }
                }

                // Save chunks
                let chunksData = try JSONSerialization.data(withJSONObject: allChunks, options: .prettyPrinted)
                try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

                await MainActor.run {
                    indexingStatus = "Indexed \(allChunks.count) chunks from \(files.count) files"
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

    func chunkText(_ text: String, source: String, chunkSize: Int = 500, overlap: Int = 50) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var chunks: [String] = []
        var i = 0

        while i < words.count {
            let end = min(i + chunkSize, words.count)
            let chunk = words[i..<end].joined(separator: " ")
            chunks.append(chunk)
            i += chunkSize - overlap
        }

        return chunks
    }
}

struct LibraryDocumentRow: View {
    let document: Document

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
    @State private var isGeneratingData = false
    @State private var qaCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Train on Your Library")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Fine-tune the AI to become an expert on your documents")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Status
                if !status.isEmpty {
                    GroupBox {
                        HStack {
                            if isGeneratingData || appState.isTraining {
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

                // Progress
                if appState.isTraining, let progress = appState.trainingProgress {
                    GroupBox("Training Progress") {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: Double(progress.iteration), total: Double(progress.totalIterations)) {
                                HStack {
                                    Text("Iteration \(progress.iteration)/\(progress.totalIterations)")
                                    Spacer()
                                    Text("\(Int(Double(progress.iteration) / Double(progress.totalIterations) * 100))%")
                                }
                            }

                            HStack(spacing: 24) {
                                VStack(alignment: .leading) {
                                    Text("Training Loss")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.4f", progress.trainingLoss))
                                        .font(.title3)
                                        .fontWeight(.medium)
                                }

                                if let validLoss = progress.validationLoss {
                                    VStack(alignment: .leading) {
                                        Text("Validation Loss")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.4f", validLoss))
                                            .font(.title3)
                                            .fontWeight(.medium)
                                    }
                                }

                                VStack(alignment: .leading) {
                                    Text("Best Loss")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.4f", progress.bestLoss))
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                // Actions
                if appState.isTraining {
                    Button("Stop Training") {
                        appState.trainingService?.stopTraining()
                        appState.isTraining = false
                        status = "Training stopped"
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        trainOnLibrary()
                    } label: {
                        Label("Train on Library", systemImage: "sparkles")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGeneratingData || appState.documents.isEmpty)
                }

                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle")
                            .font(.headline)

                        Text("1. AI reads your documents and generates Q&A pairs")
                        Text("2. Data is split into training (80%) and validation (20%)")
                        Text("3. Model trains with early stopping to prevent overfitting")
                        Text("4. Your custom AI expert is ready to use!")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
    }

    func trainOnLibrary() {
        guard let project = appState.currentProject else { return }

        isGeneratingData = true
        status = "Generating Q&A pairs from your documents..."

        Task { @MainActor in
            do {
                let dataDir = project.path.appendingPathComponent("data")
                let chunksPath = dataDir.appendingPathComponent("chunks.json")

                // Load chunks
                guard FileManager.default.fileExists(atPath: chunksPath.path) else {
                    status = "No indexed documents. Please index your documents first."
                    isGeneratingData = false
                    return
                }

                let chunksData = try Data(contentsOf: chunksPath)
                let chunks = try JSONDecoder().decode([ChunkData].self, from: chunksData)

                guard !chunks.isEmpty else {
                    status = "No content found in documents."
                    isGeneratingData = false
                    return
                }

                // Generate Q&A pairs using the LLM
                status = "Generating Q&A pairs... (this may take a few minutes)"

                var qaPairs: [(String, String)] = []
                let selectedChunks = chunks.shuffled().prefix(min(20, chunks.count))

                for (i, chunk) in selectedChunks.enumerated() {
                    status = "Generating Q&A from chunk \(i + 1)/\(selectedChunks.count)..."

                    if let pair = try await generateQAPair(from: chunk.text) {
                        qaPairs.append(pair)
                    }
                }

                qaCount = qaPairs.count
                status = "Generated \(qaCount) Q&A pairs. Preparing training data..."

                // Shuffle and split 80/20
                let shuffled = qaPairs.shuffled()
                let splitIndex = Int(Double(shuffled.count) * 0.8)
                let trainPairs = Array(shuffled.prefix(splitIndex))
                let validPairs = Array(shuffled.suffix(from: splitIndex))

                // Write JSONL files
                let trainPath = dataDir.appendingPathComponent("train.jsonl")
                let validPath = dataDir.appendingPathComponent("valid.jsonl")

                try writeQAPairs(trainPairs, to: trainPath)
                try writeQAPairs(validPairs, to: validPath)

                isGeneratingData = false
                status = "Starting training with \(trainPairs.count) train / \(validPairs.count) validation pairs..."

                // Start training
                appState.isTraining = true

                try await appState.trainingService?.train(
                    trainFile: trainPath,
                    validFile: validPath,
                    iterations: 200,
                    patience: 5,
                    learningRate: 1e-5,
                    loraLayers: 4
                ) { progress in
                    appState.trainingProgress = progress
                }

                appState.isTraining = false
                status = "Training complete! Your AI is now an expert on your documents."

            } catch {
                status = "Error: \(error.localizedDescription)"
                isGeneratingData = false
                appState.isTraining = false
            }
        }
    }

    func generateQAPair(from text: String) async throws -> (String, String)? {
        guard let chatService = appState.chatService else { return nil }

        let response = try await chatService.generate(
            query: """
            Based on this text, create ONE question and answer pair.
            Format: Q: [question]\\nA: [answer]
            Keep both concise.

            Text: \(text.prefix(1000))
            """,
            context: []
        )

        // Parse Q&A
        let lines = response.components(separatedBy: "\n")
        var question: String?
        var answer: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Q:") {
                question = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("A:") {
                answer = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }

        if let q = question, let a = answer, !q.isEmpty, !a.isEmpty {
            return (q, a)
        }
        return nil
    }

    func writeQAPairs(_ pairs: [(String, String)], to url: URL) throws {
        var lines: [String] = []
        for (q, a) in pairs {
            let text = "Question: \(q)\nAnswer: \(a)"
            let json = try JSONEncoder().encode(["text": text])
            lines.append(String(data: json, encoding: .utf8)!)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

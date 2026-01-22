import SwiftUI
import PDFKit

struct ChunkInspectorView: View {
    @EnvironmentObject var appState: AppState
    @State private var chunks: [SemanticChunk] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var stats: ProcessingStats?
    @State private var filterSource: String?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isExporting = false

    private var filteredChunks: [SemanticChunk] {
        var result = chunks

        if let source = filterSource {
            result = result.filter { $0.source == source }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    private var sources: [String] {
        Array(Set(chunks.map { $0.source })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            if let stats = stats {
                statsHeader(stats)
            }

            Divider()

            // Filters
            HStack {
                // Source filter
                Picker("Source", selection: $filterSource) {
                    Text("All Sources").tag(nil as String?)
                    ForEach(sources, id: \.self) { source in
                        Text(source).tag(source as String?)
                    }
                }
                .frame(width: 200)

                // Search
                TextField("Search chunks...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Spacer()

                // Navigation
                Text("Chunk \(currentIndex + 1) of \(filteredChunks.count)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button(action: { currentIndex = max(0, currentIndex - 1) }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)

                Button(action: { currentIndex = min(filteredChunks.count - 1, currentIndex + 1) }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= filteredChunks.count - 1)

                Divider()
                    .frame(height: 20)

                // Export buttons
                Menu {
                    Button("Export as JSON") {
                        exportAsJSON()
                    }
                    Button("Export as PDF") {
                        exportAsPDF()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(chunks.isEmpty || isExporting)
            }
            .padding()

            Divider()

            // Chunk display
            if isLoading {
                ProgressView("Loading chunks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Error loading chunks")
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredChunks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No chunks found")
                        .font(.headline)
                    Text("Process documents in Library to create chunks")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chunkDetail(filteredChunks[currentIndex])
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadChunks()
        }
    }

    // MARK: - Stats Header

    @ViewBuilder
    func statsHeader(_ stats: ProcessingStats) -> some View {
        HStack(spacing: 24) {
            statItem("Documents", value: "\(stats.totalDocuments)")
            Divider().frame(height: 30)
            statItem("Chunks", value: "\(stats.totalChunks)")
            if stats.chunksFiltered > 0 {
                Divider().frame(height: 30)
                statItem("AI Filtered", value: "\(stats.chunksFiltered)", highlight: true)
            }
            Divider().frame(height: 30)
            statItem("Avg Length", value: "\(Int(stats.avgChunkLength)) words")
            Divider().frame(height: 30)
            statItem("With Section", value: "\(percent(stats.chunksWithSection, of: stats.totalChunks))%")
            Divider().frame(height: 30)
            statItem("With Page", value: "\(percent(stats.chunksWithPage, of: stats.totalChunks))%")
            Divider().frame(height: 30)
            statItem("Sentences Split", value: "\(stats.sentencesSplit)", highlight: stats.sentencesSplit > 0)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    @ViewBuilder
    func statItem(_ label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(highlight ? .red : .primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(Double(value) / Double(total) * 100)
    }

    // MARK: - Chunk Detail

    @ViewBuilder
    func chunkDetail(_ chunk: SemanticChunk) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata card
                GroupBox("Metadata") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        metadataItem("ID", chunk.id)
                        metadataItem("Source", chunk.source)
                        metadataItem("Page", chunk.page.map { "\($0)" } ?? "—")
                        metadataItem("Chapter", chunk.chapter ?? "—")
                        metadataItem("Section", chunk.section ?? "—")
                        metadataItem("Words", "\(chunk.wordCount)")
                        metadataItem("Sentences", "\(chunk.sentenceCount)")
                        metadataItem("Index", "\(chunk.startIndex)")
                    }
                    .padding(8)
                }

                // Preceding context
                if let context = chunk.precedingContext, !context.isEmpty {
                    GroupBox("Preceding Context (overlap)") {
                        Text(context)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Main text
                GroupBox("Chunk Text") {
                    Text(chunk.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Following context
                if let context = chunk.followingContext, !context.isEmpty {
                    GroupBox("Following Context (overlap)") {
                        Text(context)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Quality indicators
                GroupBox("Quality Check") {
                    VStack(alignment: .leading, spacing: 8) {
                        qualityRow("Has section metadata", chunk.section != nil)
                        qualityRow("Has page number", chunk.page != nil)
                        qualityRow("Reasonable length (100-800 words)", chunk.wordCount >= 100 && chunk.wordCount <= 800)
                        qualityRow("Has context overlap", chunk.precedingContext != nil || chunk.followingContext != nil)
                        qualityRow("Ends with complete sentence", endsWithCompleteSentence(chunk.text))
                    }
                    .padding(8)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    func metadataItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func qualityRow(_ label: String, _ passed: Bool) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
            Text(label)
            Spacer()
        }
    }

    func endsWithCompleteSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return [".", "!", "?", "\"", "'", ")"].contains(last)
    }

    // MARK: - Data Loading

    func loadChunks() {
        guard let project = appState.currentProject else {
            isLoading = false
            return
        }

        Task {
            do {
                let service = DocumentProcessingService(projectPath: project.path)
                let loaded = try await service.loadChunks()

                await MainActor.run {
                    chunks = loaded
                    currentIndex = 0

                    // Calculate stats
                    var s = ProcessingStats()
                    s.totalChunks = loaded.count
                    s.totalDocuments = Set(loaded.map { $0.source }).count
                    s.totalWords = loaded.reduce(0) { $0 + $1.wordCount }
                    s.avgChunkLength = loaded.isEmpty ? 0 : Double(s.totalWords) / Double(s.totalChunks)
                    s.chunksWithSection = loaded.filter { $0.section != nil }.count
                    s.chunksWithPage = loaded.filter { $0.page != nil }.count
                    stats = s

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Export Functions

    func exportAsJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "chunks_export.json"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(filteredChunks)
                try data.write(to: url)

                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } catch {
                print("Export error: \(error)")
            }
        }
    }

    func exportAsPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "chunks_export.pdf"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            isExporting = true

            DispatchQueue.global(qos: .userInitiated).async {
                let pdfData = generatePDFData()

                DispatchQueue.main.async {
                    do {
                        try pdfData.write(to: url)
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    } catch {
                        print("PDF export error: \(error)")
                    }
                    isExporting = false
                }
            }
        }
    }

    func generatePDFData() -> Data {
        let pageWidth: CGFloat = 612  // Letter size
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let chunksToExport = filteredChunks
        var currentY: CGFloat = pageHeight - margin

        func startNewPage() {
            if currentY < pageHeight - margin {
                context.endPage()
            }
            context.beginPage(mediaBox: &mediaBox)
            currentY = pageHeight - margin
        }

        func drawText(_ text: String, fontSize: CGFloat, bold: Bool = false, color: NSColor = .black) -> CGFloat {
            let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]

            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

            let constraintSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), nil, constraintSize, nil)

            let textHeight = suggestedSize.height + 4

            if currentY - textHeight < margin {
                startNewPage()
            }

            let textRect = CGRect(x: margin, y: currentY - textHeight, width: contentWidth, height: textHeight)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

            context.saveGState()
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.restoreGState()

            currentY -= textHeight
            return textHeight
        }

        // Title page
        startNewPage()
        _ = drawText("Chunk Export Report", fontSize: 24, bold: true)
        currentY -= 20
        _ = drawText("Total Chunks: \(chunksToExport.count)", fontSize: 14)
        _ = drawText("Sources: \(Set(chunksToExport.map { $0.source }).count)", fontSize: 14)

        if let stats = stats {
            _ = drawText("Average Length: \(Int(stats.avgChunkLength)) words", fontSize: 14)
        }

        _ = drawText("Generated: \(Date().formatted())", fontSize: 12, color: .gray)
        currentY -= 40

        // Each chunk
        for (index, chunk) in chunksToExport.enumerated() {
            if currentY < margin + 200 {
                startNewPage()
            }

            // Chunk header
            _ = drawText("Chunk \(index + 1): \(chunk.id)", fontSize: 14, bold: true, color: .blue)
            currentY -= 8

            // Metadata
            var metaText = "Source: \(chunk.source)"
            if let page = chunk.page { metaText += " | Page: \(page)" }
            if let section = chunk.section { metaText += " | Section: \(section)" }
            metaText += " | Words: \(chunk.wordCount)"
            _ = drawText(metaText, fontSize: 10, color: .gray)
            currentY -= 8

            // Text content
            _ = drawText(chunk.text, fontSize: 11)
            currentY -= 20
        }

        context.endPage()
        context.closePDF()

        return pdfData as Data
    }
}

// MARK: - Preview

#Preview {
    ChunkInspectorView()
}

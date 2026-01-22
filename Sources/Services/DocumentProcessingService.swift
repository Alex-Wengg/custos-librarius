import Foundation
import PDFKit
import NaturalLanguage

// MARK: - Data Models

/// Rich chunk with full metadata
struct SemanticChunk: Codable, Identifiable {
    let id: String
    let text: String
    let source: String
    let page: Int?
    let section: String?
    let chapter: String?
    let startIndex: Int
    let endIndex: Int
    let sentenceCount: Int
    let wordCount: Int
    let precedingContext: String?
    let followingContext: String?

    // NL-extracted entities (fast mode)
    let people: [String]?
    let places: [String]?
    let organizations: [String]?
    let keyTerms: [String]?

    var metadata: [String: String] {
        var meta: [String: String] = ["source": source]
        if let page = page { meta["page"] = String(page) }
        if let section = section { meta["section"] = section }
        if let chapter = chapter { meta["chapter"] = chapter }
        return meta
    }

    // Convenience init without entities (backwards compatible)
    init(id: String, text: String, source: String, page: Int?, section: String?, chapter: String?,
         startIndex: Int, endIndex: Int, sentenceCount: Int, wordCount: Int,
         precedingContext: String?, followingContext: String?) {
        self.id = id
        self.text = text
        self.source = source
        self.page = page
        self.section = section
        self.chapter = chapter
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.sentenceCount = sentenceCount
        self.wordCount = wordCount
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.people = nil
        self.places = nil
        self.organizations = nil
        self.keyTerms = nil
    }

    // Full init with entities
    init(id: String, text: String, source: String, page: Int?, section: String?, chapter: String?,
         startIndex: Int, endIndex: Int, sentenceCount: Int, wordCount: Int,
         precedingContext: String?, followingContext: String?,
         people: [String]?, places: [String]?, organizations: [String]?, keyTerms: [String]?) {
        self.id = id
        self.text = text
        self.source = source
        self.page = page
        self.section = section
        self.chapter = chapter
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.sentenceCount = sentenceCount
        self.wordCount = wordCount
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.people = people
        self.places = places
        self.organizations = organizations
        self.keyTerms = keyTerms
    }
}

/// Document structure element
struct DocumentElement {
    enum ElementType {
        case title
        case chapter
        case section
        case subsection
        case paragraph
        case listItem
        case table
        case figure
    }

    let type: ElementType
    let text: String
    let page: Int?
    let level: Int  // Heading level (1-6) or 0 for body
}

/// Processing statistics
struct ProcessingStats {
    var totalDocuments: Int = 0
    var totalPages: Int = 0
    var totalChunks: Int = 0
    var totalWords: Int = 0
    var totalSentences: Int = 0
    var avgChunkLength: Double = 0
    var chunksWithSection: Int = 0
    var chunksWithPage: Int = 0
    var sentencesSplit: Int = 0  // Should be 0
    var chunksFiltered: Int = 0  // Removed by AI classification
    var chunksMergedContext: Int = 0  // Mid-sentence chunks fixed by merging context
    var chunksMarkedContinuation: Int = 0  // Chunks marked with [...] prefix
}

/// AI classification result for a chunk
struct ChunkClassification: Codable {
    let contentType: ContentType
    let chapter: String?
    let section: String?
    let quality: Double  // 0-1 score

    enum ContentType: String, Codable {
        case content      // Main body content - keep
        case toc          // Table of contents - remove
        case frontMatter  // Copyright, ISBN, preface - remove
        case citation     // Footnote, bibliography - remove
        case index        // Index entries - remove
    }
}

// MARK: - Document Processing Service

actor DocumentProcessingService {
    private let projectPath: URL
    private let chatService: ChatService?

    // Configuration
    private let targetChunkSize: Int
    private let minChunkSize: Int
    private let maxChunkSize: Int
    private let overlapSentences: Int = 2   // Sentences to overlap
    private let enableAIClassification: Bool

    init(projectPath: URL, chatService: ChatService? = nil, enableAIClassification: Bool = true, chunkSize: Int = 400) {
        self.projectPath = projectPath
        self.chatService = chatService
        self.enableAIClassification = enableAIClassification && chatService != nil
        self.targetChunkSize = chunkSize
        self.minChunkSize = max(50, chunkSize / 4)  // Min is 1/4 of target (min 50)
        self.maxChunkSize = chunkSize * 2           // Max is 2x target
    }

    // MARK: - Main Processing Pipeline

    func processAllDocuments(onProgress: ((String) -> Void)? = nil) async throws -> (chunks: [SemanticChunk], stats: ProcessingStats) {
        let docsDir = projectPath.appendingPathComponent("documents")
        let files = try FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: nil)

        var allChunks: [SemanticChunk] = []
        var stats = ProcessingStats()
        stats.totalDocuments = files.count

        for (index, file) in files.enumerated() {
            onProgress?("Processing \(file.lastPathComponent)... (\(index + 1)/\(files.count))")

            let ext = file.pathExtension.lowercased()
            let elements: [DocumentElement]

            switch ext {
            case "pdf":
                elements = try await extractFromPDF(file)
            case "txt", "md":
                elements = try await extractFromText(file)
            case "epub":
                elements = try await extractFromEPUB(file)
            default:
                continue
            }

            let chunks = createSemanticChunks(from: elements, source: file.lastPathComponent)
            allChunks.append(contentsOf: chunks)

            stats.totalPages += elements.compactMap { $0.page }.max() ?? 1
        }

        // Step 1: Merge small chunks into larger ones for better summarization
        onProgress?("Merging chunks for processing...")
        var mergedChunks = mergeSmallChunks(allChunks)

        // Step 2: Process chunks (AI summarization or heuristic filtering)
        let beforeCount = mergedChunks.count
        if enableAIClassification, let chat = chatService {
            // AI mode: Summarize chunks with Qwen for clean, self-contained text
            onProgress?("Summarizing chunks with AI...")
            mergedChunks = try await summarizeChunks(mergedChunks, chatService: chat, onProgress: onProgress)
        } else {
            // Fast mode: Heuristic filtering + NL enhancements
            onProgress?("Filtering non-content chunks...")
            mergedChunks = heuristicFilterChunks(mergedChunks)

            // Add context overlap for fast mode
            mergedChunks = addContextOverlap(to: mergedChunks)

            // Fix mid-sentence chunks (only needed for fast mode)
            onProgress?("Fixing mid-sentence chunks...")
            let midSentenceResult = fixMidSentenceChunks(mergedChunks)
            mergedChunks = midSentenceResult.chunks
            stats.chunksMergedContext = midSentenceResult.merged
            stats.chunksMarkedContinuation = midSentenceResult.marked

            // Extract entities using NLTagger (fast, no ML model needed)
            onProgress?("Extracting entities with NLTagger...")
            mergedChunks = extractEntitiesFromChunks(mergedChunks)
        }
        stats.chunksFiltered = beforeCount - mergedChunks.count

        // Calculate stats
        stats.totalChunks = mergedChunks.count
        stats.totalWords = mergedChunks.reduce(0) { $0 + $1.wordCount }
        stats.totalSentences = mergedChunks.reduce(0) { $0 + $1.sentenceCount }
        stats.avgChunkLength = mergedChunks.isEmpty ? 0 : Double(stats.totalWords) / Double(stats.totalChunks)
        stats.chunksWithSection = mergedChunks.filter { $0.section != nil }.count
        stats.chunksWithPage = mergedChunks.filter { $0.page != nil }.count

        // Save chunks
        try await saveChunks(mergedChunks)

        return (mergedChunks, stats)
    }

    // MARK: - PDF Extraction

    private func extractFromPDF(_ url: URL) async throws -> [DocumentElement] {
        guard let document = PDFDocument(url: url) else {
            throw ProcessingError.cannotOpenDocument
        }

        var elements: [DocumentElement] = []
        var currentChapter: String?
        var currentSection: String?

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let text = page.string else { continue }

            let pageNumber = pageIndex + 1

            // Use NLTokenizer to detect proper paragraph boundaries
            let paragraphs = extractParagraphsNL(from: text)

            for paragraph in paragraphs {
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                // Check if this looks like a header (short, title case or all caps)
                let wordCount = trimmed.split(separator: " ").count
                let isShort = wordCount <= 10

                if isShort {
                    // Could be a header - use line classification
                    let element = classifyLine(trimmed, page: pageNumber, currentChapter: &currentChapter, currentSection: &currentSection)
                    elements.append(element)
                } else {
                    // Regular paragraph - keep as-is
                    elements.append(DocumentElement(type: .paragraph, text: trimmed, page: pageNumber, level: 0))
                }
            }
        }

        return elements
    }

    /// Extract paragraphs using Apple's NLTokenizer
    private func extractParagraphsNL(from text: String) -> [String] {
        // First, normalize the text - join lines that are part of the same paragraph
        // PDF often has hard line breaks within paragraphs
        let normalized = normalizePDFText(text)

        let tokenizer = NLTokenizer(unit: .paragraph)
        tokenizer.string = normalized

        var paragraphs: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let paragraph = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                paragraphs.append(paragraph)
            }
            return true
        }

        // If NLTokenizer didn't find paragraphs, fall back to double-newline split
        if paragraphs.isEmpty || paragraphs.count == 1 {
            paragraphs = normalized.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return paragraphs
    }

    /// Normalize PDF text by joining lines that are part of the same paragraph
    private func normalizePDFText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var currentParagraph = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line = paragraph break
            if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    result.append(currentParagraph)
                    currentParagraph = ""
                }
                continue
            }

            // Check if this line starts a new paragraph
            let startsNewParagraph = isNewParagraphStart(trimmed, previousText: currentParagraph)

            if startsNewParagraph && !currentParagraph.isEmpty {
                result.append(currentParagraph)
                currentParagraph = trimmed
            } else if currentParagraph.isEmpty {
                currentParagraph = trimmed
            } else {
                // Join with previous line
                // Add space unless previous ends with hyphen (word continuation)
                if currentParagraph.hasSuffix("-") {
                    currentParagraph = String(currentParagraph.dropLast()) + trimmed
                } else {
                    currentParagraph += " " + trimmed
                }
            }
        }

        // Don't forget last paragraph
        if !currentParagraph.isEmpty {
            result.append(currentParagraph)
        }

        return result.joined(separator: "\n\n")
    }

    /// Detect if a line starts a new paragraph
    private func isNewParagraphStart(_ line: String, previousText: String) -> Bool {
        // Empty previous = definitely new paragraph
        if previousText.isEmpty { return true }

        // Previous ends with sentence-ending punctuation
        let prevTrimmed = previousText.trimmingCharacters(in: .whitespaces)
        if let last = prevTrimmed.last {
            let sentenceEnders: Set<Character> = [".", "!", "?", ":", ";"]
            if sentenceEnders.contains(last) {
                // And current starts with uppercase = new paragraph
                if let first = line.first, first.isUppercase {
                    return true
                }
            }
        }

        // Line starts with bullet, number, or special character
        if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") {
            return true
        }
        if let first = line.first, first.isNumber {
            // "1." or "1)" pattern
            if line.contains(".") || line.contains(")") {
                let prefix = line.prefix(4)
                if prefix.contains(".") || prefix.contains(")") {
                    return true
                }
            }
        }

        // Line is all caps (likely header)
        if line == line.uppercased() && line.count > 3 && line.contains(" ") {
            return true
        }

        return false
    }

    // MARK: - Text Extraction

    private func extractFromText(_ url: URL) async throws -> [DocumentElement] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var elements: [DocumentElement] = []

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Markdown heading detection
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)

                let type: DocumentElement.ElementType
                switch level {
                case 1:
                    type = .chapter
                case 2:
                    type = .section
                case 3...:
                    type = .subsection
                default:
                    type = .paragraph
                }

                elements.append(DocumentElement(type: type, text: text, page: nil, level: level))
            } else {
                elements.append(DocumentElement(type: .paragraph, text: trimmed, page: nil, level: 0))
            }
        }

        return elements
    }

    // MARK: - EPUB Extraction (basic)

    private func extractFromEPUB(_ url: URL) async throws -> [DocumentElement] {
        // For now, treat as text - can enhance with proper EPUB parsing later
        // EPUB is just a ZIP with XHTML files
        return try await extractFromText(url)
    }

    // MARK: - Line Classification

    private func classifyLine(_ text: String, page: Int, currentChapter: inout String?, currentSection: inout String?) -> DocumentElement {
        let upperText = text.uppercased()
        let wordCount = text.split(separator: " ").count
        let charCount = text.count

        // Skip single characters and very short text as headers
        guard charCount >= 3 else {
            return DocumentElement(type: .paragraph, text: text, page: page, level: 0)
        }

        // Skip page numbers and numeric-only lines
        let trimmedDigits = text.trimmingCharacters(in: .decimalDigits.union(.whitespaces).union(CharacterSet(charactersIn: "–-")))
        if trimmedDigits.isEmpty || trimmedDigits.count <= 2 {
            return DocumentElement(type: .paragraph, text: text, page: page, level: 0)
        }

        // Chapter detection: ALL CAPS, short, often starts with "CHAPTER" or number
        if text == upperText && wordCount <= 10 && wordCount >= 2 && charCount >= 5 {
            if text.contains("CHAPTER") || (text.first?.isNumber == true && text.contains(" ")) {
                currentChapter = text.capitalized
                currentSection = nil
                return DocumentElement(type: .chapter, text: text, page: page, level: 1)
            }
            // Could be a section header - must be at least 5 chars
            if charCount >= 5 {
                currentSection = text.capitalized
                return DocumentElement(type: .section, text: text, page: page, level: 2)
            }
        }

        // Section detection: Title Case, short lines, meaningful length
        if wordCount <= 12 && wordCount >= 2 && charCount >= 8 && isTitleCase(text) {
            currentSection = text
            return DocumentElement(type: .section, text: text, page: page, level: 2)
        }

        // List item detection
        if text.hasPrefix("•") || text.hasPrefix("-") || text.hasPrefix("*") ||
           (text.first?.isNumber == true && text.contains(".")) {
            return DocumentElement(type: .listItem, text: text, page: page, level: 0)
        }

        // Default: paragraph
        return DocumentElement(type: .paragraph, text: text, page: page, level: 0)
    }

    private func isTitleCase(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        let titleCaseWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
        // At least 60% of words should start with uppercase
        return Double(titleCaseWords.count) / Double(words.count) >= 0.6
    }

    // MARK: - Semantic Chunking

    func createSemanticChunks(from elements: [DocumentElement], source: String) -> [SemanticChunk] {
        var chunks: [SemanticChunk] = []
        var currentText = ""
        var currentSection: String?
        var currentChapter: String?
        var currentPage: Int?
        var startIndex = 0
        var chunkIndex = 0

        for element in elements {
            // Update context based on element type
            switch element.type {
            case .chapter:
                // Flush current chunk before new chapter
                if !currentText.isEmpty {
                    let chunk = finalizeChunk(
                        text: currentText,
                        source: source,
                        section: currentSection,
                        chapter: currentChapter,
                        page: currentPage,
                        index: chunkIndex,
                        startIndex: startIndex
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                    currentText = ""
                }
                currentChapter = element.text
                currentSection = nil
                currentPage = element.page
                startIndex = chunkIndex

            case .section, .subsection:
                // Flush current chunk before new section
                if !currentText.isEmpty && wordCount(currentText) >= minChunkSize {
                    let chunk = finalizeChunk(
                        text: currentText,
                        source: source,
                        section: currentSection,
                        chapter: currentChapter,
                        page: currentPage,
                        index: chunkIndex,
                        startIndex: startIndex
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                    currentText = ""
                    startIndex = chunkIndex
                }
                currentSection = element.text
                if element.page != nil { currentPage = element.page }

            case .paragraph, .listItem:
                if element.page != nil && currentPage == nil {
                    currentPage = element.page
                }

                // Add text with proper spacing
                if !currentText.isEmpty {
                    currentText += "\n\n"
                }
                currentText += element.text

                // Check if we should split
                let words = wordCount(currentText)
                if words >= targetChunkSize {
                    // Try to split at sentence boundary
                    let splitResult = splitAtSentenceBoundary(currentText, targetWords: targetChunkSize)

                    let chunk = finalizeChunk(
                        text: splitResult.chunk,
                        source: source,
                        section: currentSection,
                        chapter: currentChapter,
                        page: currentPage,
                        index: chunkIndex,
                        startIndex: startIndex
                    )
                    chunks.append(chunk)
                    chunkIndex += 1

                    currentText = splitResult.remainder
                    startIndex = chunkIndex
                }

            case .title, .table, .figure:
                // Include as-is
                if !currentText.isEmpty {
                    currentText += "\n\n"
                }
                currentText += element.text
            }
        }

        // Don't forget the last chunk
        if !currentText.isEmpty && wordCount(currentText) >= minChunkSize / 2 {
            let chunk = finalizeChunk(
                text: currentText,
                source: source,
                section: currentSection,
                chapter: currentChapter,
                page: currentPage,
                index: chunkIndex,
                startIndex: startIndex
            )
            chunks.append(chunk)
        }

        // Add context overlap
        chunks = addContextOverlap(to: chunks)

        return chunks
    }

    private func finalizeChunk(text: String, source: String, section: String?, chapter: String?, page: Int?, index: Int, startIndex: Int) -> SemanticChunk {
        let sentences = countSentences(text)
        let words = wordCount(text)

        return SemanticChunk(
            id: "\(source.replacingOccurrences(of: " ", with: "_"))_\(index)",
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            page: page,
            section: section,
            chapter: chapter,
            startIndex: startIndex,
            endIndex: index,
            sentenceCount: sentences,
            wordCount: words,
            precedingContext: nil,
            followingContext: nil
        )
    }

    private func splitAtSentenceBoundary(_ text: String, targetWords: Int) -> (chunk: String, remainder: String) {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }

        var chunkSentences: [String] = []
        var currentWords = 0
        var splitIndex = 0

        for (index, sentence) in sentences.enumerated() {
            let sentenceWords = sentence.split(separator: " ").count
            if currentWords + sentenceWords > targetWords && currentWords >= minChunkSize {
                break
            }
            chunkSentences.append(sentence)
            currentWords += sentenceWords
            splitIndex = index + 1
        }

        let chunk = chunkSentences.joined()
        let remainder = sentences[splitIndex...].joined()

        return (chunk, remainder)
    }

    // MARK: - Paragraph Extraction (using Apple NLP)

    /// Extract paragraphs using Apple's NaturalLanguage framework
    private func extractParagraphs(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .paragraph)
        tokenizer.string = text

        var paragraphs: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let paragraph = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                paragraphs.append(paragraph)
            }
            return true
        }

        return paragraphs
    }

    /// Create chunks respecting paragraph boundaries
    func createParagraphChunks(from text: String, source: String, page: Int?) -> [SemanticChunk] {
        let paragraphs = extractParagraphs(text)
        var chunks: [SemanticChunk] = []
        var currentText = ""
        var chunkIndex = 0

        for paragraph in paragraphs {
            let paragraphWords = paragraph.split(separator: " ").count

            // If adding this paragraph exceeds max size, finalize current chunk
            if wordCount(currentText) + paragraphWords > maxChunkSize && !currentText.isEmpty {
                chunks.append(finalizeChunk(
                    text: currentText,
                    source: source,
                    section: nil,
                    chapter: nil,
                    page: page,
                    index: chunkIndex,
                    startIndex: chunkIndex
                ))
                chunkIndex += 1
                currentText = ""
            }

            // Add paragraph to current chunk
            if currentText.isEmpty {
                currentText = paragraph
            } else {
                currentText += "\n\n" + paragraph
            }

            // If current chunk is at target size, finalize it
            if wordCount(currentText) >= targetChunkSize {
                chunks.append(finalizeChunk(
                    text: currentText,
                    source: source,
                    section: nil,
                    chapter: nil,
                    page: page,
                    index: chunkIndex,
                    startIndex: chunkIndex
                ))
                chunkIndex += 1
                currentText = ""
            }
        }

        // Don't forget the last chunk
        if !currentText.isEmpty && wordCount(currentText) >= minChunkSize {
            chunks.append(finalizeChunk(
                text: currentText,
                source: source,
                section: nil,
                chapter: nil,
                page: page,
                index: chunkIndex,
                startIndex: chunkIndex
            ))
        }

        return chunks
    }

    private func addContextOverlap(to chunks: [SemanticChunk]) -> [SemanticChunk] {
        guard chunks.count > 1 else { return chunks }

        var result: [SemanticChunk] = []

        for (index, chunk) in chunks.enumerated() {
            var newChunk = chunk

            // Get last 2 sentences from previous chunk
            if index > 0 {
                let prevText = chunks[index - 1].text
                let lastSentences = getLastSentences(prevText, count: overlapSentences)
                newChunk = SemanticChunk(
                    id: chunk.id,
                    text: chunk.text,
                    source: chunk.source,
                    page: chunk.page,
                    section: chunk.section,
                    chapter: chunk.chapter,
                    startIndex: chunk.startIndex,
                    endIndex: chunk.endIndex,
                    sentenceCount: chunk.sentenceCount,
                    wordCount: chunk.wordCount,
                    precedingContext: lastSentences,
                    followingContext: chunk.followingContext
                )
            }

            // Get first 2 sentences from next chunk
            if index < chunks.count - 1 {
                let nextText = chunks[index + 1].text
                let firstSentences = getFirstSentences(nextText, count: overlapSentences)
                newChunk = SemanticChunk(
                    id: newChunk.id,
                    text: newChunk.text,
                    source: newChunk.source,
                    page: newChunk.page,
                    section: newChunk.section,
                    chapter: newChunk.chapter,
                    startIndex: newChunk.startIndex,
                    endIndex: newChunk.endIndex,
                    sentenceCount: newChunk.sentenceCount,
                    wordCount: newChunk.wordCount,
                    precedingContext: newChunk.precedingContext,
                    followingContext: firstSentences
                )
            }

            result.append(newChunk)
        }

        return result
    }

    // MARK: - Mid-Sentence Fix

    /// Fix chunks that start mid-sentence by merging preceding context
    /// Uses Apple's NLTokenizer for accurate sentence boundary detection
    /// Returns: (fixedChunks, mergedCount, markedCount)
    private func fixMidSentenceChunks(_ chunks: [SemanticChunk]) -> (chunks: [SemanticChunk], merged: Int, marked: Int) {
        var result: [SemanticChunk] = []
        var mergedCount = 0
        var markedCount = 0

        for chunk in chunks {
            var text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var needsFix = startsMidSentence(text)

            // Step 1: If starts mid-sentence and has preceding context that ends mid-sentence, merge
            if needsFix, let preceding = chunk.precedingContext?.trimmingCharacters(in: .whitespacesAndNewlines), !preceding.isEmpty {
                // Only merge if preceding context ends mid-sentence (incomplete)
                // This connects split sentences properly
                if endsMidSentence(preceding) {
                    text = preceding + " " + text
                } else {
                    // Preceding ends with complete sentence - just prepend for context
                    text = preceding + " " + text
                }
                // Normalize whitespace
                text = text.replacingOccurrences(of: "  ", with: " ")
                text = text.replacingOccurrences(of: "\n ", with: "\n")
                mergedCount += 1
                needsFix = startsMidSentence(text)
            }

            // Step 2: If still starts mid-sentence, add [...] marker
            if needsFix {
                text = "[...] " + text
                markedCount += 1
            }

            // Recalculate sentence count with NLTokenizer
            let newSentenceCount = countSentences(text)

            // Create updated chunk
            let updatedChunk = SemanticChunk(
                id: chunk.id,
                text: text,
                source: chunk.source,
                page: chunk.page,
                section: chunk.section,
                chapter: chunk.chapter,
                startIndex: chunk.startIndex,
                endIndex: chunk.endIndex,
                sentenceCount: newSentenceCount,
                wordCount: text.split(separator: " ").count,
                precedingContext: chunk.precedingContext,
                followingContext: chunk.followingContext
            )
            result.append(updatedChunk)
        }

        if mergedCount > 0 || markedCount > 0 {
            print("Mid-sentence fix (NLTokenizer): merged \(mergedCount) chunks, marked \(markedCount) with [...]")
        }

        return (result, mergedCount, markedCount)
    }

    /// Check if text starts mid-sentence using Apple's NLTokenizer
    private func startsMidSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Quick check: starts with lowercase letter (definite mid-sentence)
        if let first = trimmed.first, first.isLowercase {
            return true
        }

        // Use NLTokenizer to check if text starts at a sentence boundary
        // If the first sentence doesn't start at index 0, we're mid-sentence
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var firstSentenceStart: String.Index?
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            firstSentenceStart = range.lowerBound
            return false // Stop after first sentence
        }

        // If no sentence found or first sentence doesn't start at beginning
        guard let start = firstSentenceStart else { return true }

        // Check if there's significant content before the first detected sentence
        if start != trimmed.startIndex {
            let prefix = String(trimmed[trimmed.startIndex..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty && prefix.count > 2 {
                return true
            }
        }

        return false
    }

    /// Check if text ends mid-sentence (doesn't end with sentence-ending punctuation)
    private func endsMidSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Check last character for sentence-ending punctuation
        let sentenceEnders = ".!?\"\'"
        let curlyQuotes = "\u{201C}\u{201D}\u{2018}\u{2019}" // ""''
        let allEnders = sentenceEnders + curlyQuotes

        if let last = trimmed.last, allEnders.contains(last) {
            return false
        }

        // Use NLTokenizer to verify - check if last sentence ends at text end
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var lastSentenceEnd: String.Index?
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            lastSentenceEnd = range.upperBound
            return true // Continue to get last sentence
        }

        // If last sentence doesn't end at text end, we're mid-sentence
        if let end = lastSentenceEnd {
            return end != trimmed.endIndex
        }

        return true
    }

    // MARK: - Chunk Merging

    private func mergeSmallChunks(_ chunks: [SemanticChunk]) -> [SemanticChunk] {
        guard chunks.count > 1 else { return chunks }

        var result: [SemanticChunk] = []
        var pendingChunk: SemanticChunk?

        for chunk in chunks {
            if let pending = pendingChunk {
                // If current chunk is small, merge with pending
                if chunk.wordCount < minChunkSize {
                    let mergedText = pending.text + "\n\n" + chunk.text
                    pendingChunk = SemanticChunk(
                        id: pending.id,
                        text: mergedText,
                        source: pending.source,
                        page: pending.page,
                        section: pending.section ?? chunk.section,
                        chapter: pending.chapter ?? chunk.chapter,
                        startIndex: pending.startIndex,
                        endIndex: chunk.endIndex,
                        sentenceCount: pending.sentenceCount + chunk.sentenceCount,
                        wordCount: wordCount(mergedText),
                        precedingContext: pending.precedingContext,
                        followingContext: chunk.followingContext
                    )
                } else {
                    // Current chunk is big enough, flush pending
                    if pending.wordCount >= minChunkSize / 2 {
                        result.append(pending)
                    }
                    pendingChunk = chunk
                }
            } else {
                pendingChunk = chunk
            }
        }

        // Don't forget the last pending chunk
        if let pending = pendingChunk, pending.wordCount >= minChunkSize / 2 {
            result.append(pending)
        }

        return result
    }

    // MARK: - Heuristic Filtering (Fast, no LLM)

    private func heuristicFilterChunks(_ chunks: [SemanticChunk]) -> [SemanticChunk] {
        return chunks.filter { chunk in
            let text = chunk.text

            // Skip very short chunks
            if chunk.wordCount < 30 {
                return false
            }

            // Detect TOC patterns (lines with dots/dashes followed by numbers)
            let tocPattern = #"\.{3,}|\s{3,}\d+$|—{2,}"#
            let tocLineCount = text.components(separatedBy: .newlines)
                .filter { $0.range(of: tocPattern, options: .regularExpression) != nil }
                .count
            if tocLineCount > 3 {
                return false
            }

            // Detect front matter (copyright, ISBN, publisher)
            let frontMatterKeywords = [
                "copyright ©", "all rights reserved", "isbn", "printed in",
                "library of congress", "cataloging-in-publication",
                "first published", "penguin", "random house", "harpercollins"
            ]
            let lowerText = text.lowercased()
            let frontMatterHits = frontMatterKeywords.filter { lowerText.contains($0) }.count
            if frontMatterHits >= 2 {
                return false
            }

            // Detect index entries (alphabetical with page numbers)
            let indexPattern = #"^[A-Z][a-z]+,\s*\d+(-\d+)?(,\s*\d+(-\d+)?)*$"#
            let indexLines = text.components(separatedBy: .newlines)
                .filter { $0.range(of: indexPattern, options: .regularExpression) != nil }
                .count
            if indexLines > 5 {
                return false
            }

            // Detect citation/bibliography patterns
            let citationPatterns = [
                #"\(\d{4}\)"#,  // (2023)
                #"pp?\.\s*\d+"#,  // p. 123 or pp. 123-456
                #"vol\.\s*\d+"#,  // vol. 5
                #"https?://"#  // URLs
            ]
            var citationHits = 0
            for pattern in citationPatterns {
                if text.range(of: pattern, options: .regularExpression) != nil {
                    citationHits += 1
                }
            }
            // Only filter if chunk is dominated by citations (many patterns, short text)
            if citationHits >= 3 && chunk.wordCount < 100 {
                return false
            }

            // Detect "contents" or "table of contents" headers
            if lowerText.hasPrefix("contents") || lowerText.contains("table of contents") {
                return false
            }

            return true
        }
    }

    // MARK: - AI Summarization

    /// Summarize chunks using Qwen for clean, self-contained text
    /// This replaces broken sentences, removes noise, and creates quiz-ready content
    private func summarizeChunks(_ chunks: [SemanticChunk], chatService: ChatService, onProgress: ((String) -> Void)?) async throws -> [SemanticChunk] {
        var summarizedChunks: [SemanticChunk] = []
        var debugLog: [String] = []

        for (index, chunk) in chunks.enumerated() {
            onProgress?("Summarizing chunk \(index + 1)/\(chunks.count)...")

            // Quick heuristic pre-filter (skip obvious non-content)
            if isObviouslyNonContent(chunk.text) {
                debugLog.append("[\(index)] SKIPPED (non-content): \(chunk.id)")
                continue
            }

            // Skip very short chunks
            if chunk.wordCount < 50 {
                debugLog.append("[\(index)] SKIPPED (too short): \(chunk.id)")
                continue
            }

            // Summarize with Qwen
            let result = try await summarizeChunk(chunk, chatService: chatService)

            // Skip if AI determined it's not useful content
            if result.summary.isEmpty || result.contentType != "content" {
                debugLog.append("[\(index)] FILTERED by AI: \(chunk.id) (type: \(result.contentType))")
                continue
            }

            // Create new chunk with summarized text
            let summarizedChunk = SemanticChunk(
                id: chunk.id,
                text: result.summary,
                source: chunk.source,
                page: chunk.page,
                section: result.section ?? chunk.section,
                chapter: result.chapter ?? chunk.chapter,
                startIndex: chunk.startIndex,
                endIndex: chunk.endIndex,
                sentenceCount: countSentences(result.summary),
                wordCount: result.summary.split(separator: " ").count,
                precedingContext: nil,  // Not needed for summaries
                followingContext: nil
            )
            summarizedChunks.append(summarizedChunk)
            debugLog.append("[\(index)] SUMMARIZED: \(chunk.id) (\(chunk.wordCount) → \(summarizedChunk.wordCount) words)")
        }

        // Print debug log
        print("=== CHUNK SUMMARIZATION DEBUG ===")
        for line in debugLog.suffix(20) {  // Last 20 entries
            print(line)
        }
        print("=== END DEBUG (\(summarizedChunks.count)/\(chunks.count) kept) ===")

        // Save debug log
        let debugText = debugLog.joined(separator: "\n")
        let debugPath = projectPath.appendingPathComponent("data/summarization_debug.txt")
        try? debugText.write(to: debugPath, atomically: true, encoding: .utf8)

        return summarizedChunks
    }

    /// Result from summarizing a single chunk
    private struct SummarizationResult {
        let summary: String
        let contentType: String
        let chapter: String?
        let section: String?
    }

    /// Summarize a single chunk using Qwen
    private func summarizeChunk(_ chunk: SemanticChunk, chatService: ChatService) async throws -> SummarizationResult {
        let prompt = """
        Analyze and summarize this text from a book. Respond with ONLY valid JSON.

        Text:
        \(String(chunk.text.prefix(1500)))

        Instructions:
        1. If this is table of contents, index, copyright, or bibliography, set type to that category
        2. If this is main content, summarize it in 2-3 paragraphs with complete sentences
        3. Keep all key facts, names, dates, concepts, and arguments
        4. Write clear, self-contained text that doesn't start mid-sentence
        5. Extract chapter and section names if visible

        Respond with this exact JSON format:
        {"type": "content|toc|index|copyright|bibliography", "summary": "your summary here or empty if not content", "chapter": "chapter name or null", "section": "section name or null"}

        JSON:
        """

        let response = try await chatService.generate(query: prompt, context: [])
        return parseSummarizationResponse(response, fallbackChunk: chunk)
    }

    /// Parse the JSON response from summarization
    private func parseSummarizationResponse(_ response: String, fallbackChunk: SemanticChunk) -> SummarizationResult {
        // Clean up response
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            // Fallback: return original text
            return SummarizationResult(
                summary: fallbackChunk.text,
                contentType: "content",
                chapter: fallbackChunk.chapter,
                section: fallbackChunk.section
            )
        }

        let jsonString = String(cleaned[start...end])

        guard let data = jsonString.data(using: .utf8) else {
            return SummarizationResult(
                summary: fallbackChunk.text,
                contentType: "content",
                chapter: fallbackChunk.chapter,
                section: fallbackChunk.section
            )
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            let contentType = json?["type"] as? String ?? "content"
            let summary = json?["summary"] as? String ?? ""
            let chapter = json?["chapter"] as? String
            let section = json?["section"] as? String

            return SummarizationResult(
                summary: summary.isEmpty ? fallbackChunk.text : summary,
                contentType: contentType.lowercased(),
                chapter: chapter != "null" ? chapter : nil,
                section: section != "null" ? section : nil
            )
        } catch {
            return SummarizationResult(
                summary: fallbackChunk.text,
                contentType: "content",
                chapter: fallbackChunk.chapter,
                section: fallbackChunk.section
            )
        }
    }

    // MARK: - AI Classification (Legacy)

    private func classifyAndFilterChunks(_ chunks: [SemanticChunk], chatService: ChatService, onProgress: ((String) -> Void)?) async throws -> [SemanticChunk] {
        var filteredChunks: [SemanticChunk] = []
        var debugLog: [String] = []

        for (index, chunk) in chunks.enumerated() {
            onProgress?("Classifying chunk \(index + 1)/\(chunks.count)...")

            // Quick heuristic pre-filter (skip only very obvious non-content)
            if isObviouslyNonContent(chunk.text) {
                debugLog.append("[\(index)] HEURISTIC FILTER: \(chunk.id) - \(String(chunk.text.prefix(50)))...")
                continue
            }

            // AI classification for ambiguous chunks
            let classification = try await classifyChunk(chunk, chatService: chatService)

            // Lowered threshold from 0.5 to 0.3 - keep more content
            let dominated = classification.contentType == .content && classification.quality >= 0.3

            if dominated {
                // Update chunk with AI-extracted metadata OR text analysis fallback
                var finalChapter = classification.chapter
                var finalSection = classification.section

                // Text analysis fallback if AI returned nil
                if finalChapter == nil || isNumericOnly(finalChapter ?? "") {
                    finalChapter = extractChapterFromText(chunk.text) ?? chunk.chapter
                }
                if finalSection == nil || isBadSection(finalSection ?? "") {
                    finalSection = extractSectionFromText(chunk.text) ?? chunk.section
                }

                // Clean up bad metadata
                finalChapter = cleanMetadata(finalChapter)
                finalSection = cleanMetadata(finalSection)

                let updatedChunk = SemanticChunk(
                    id: chunk.id,
                    text: chunk.text,
                    source: chunk.source,
                    page: chunk.page,
                    section: finalSection,
                    chapter: finalChapter,
                    startIndex: chunk.startIndex,
                    endIndex: chunk.endIndex,
                    sentenceCount: chunk.sentenceCount,
                    wordCount: chunk.wordCount,
                    precedingContext: chunk.precedingContext,
                    followingContext: chunk.followingContext
                )
                filteredChunks.append(updatedChunk)
                debugLog.append("[\(index)] KEPT: \(chunk.id) (quality: \(classification.quality), type: \(classification.contentType))")
            } else {
                debugLog.append("[\(index)] AI FILTER: \(chunk.id) (quality: \(classification.quality), type: \(classification.contentType)) - \(String(chunk.text.prefix(50)))...")
            }
        }

        // Print debug log
        print("=== CHUNK CLASSIFICATION DEBUG ===")
        for line in debugLog {
            print(line)
        }
        print("=== END DEBUG (\(filteredChunks.count)/\(chunks.count) kept) ===")

        // Also save to file for easy access
        let debugText = debugLog.joined(separator: "\n")
        let debugPath = projectPath.appendingPathComponent("data/classification_debug.txt")
        try? debugText.write(to: debugPath, atomically: true, encoding: .utf8)

        return filteredChunks
    }

    private func isObviouslyNonContent(_ text: String) -> Bool {
        let lower = text.lowercased()

        // Only filter very obvious cases - be conservative
        // TOC patterns: must have "contents" AND "page" AND many short lines with numbers
        if lower.contains("table of contents") || (lower.contains("contents") && lower.hasPrefix("contents")) {
            let lines = text.split(separator: "\n")
            let pageNumLines = lines.filter { $0.contains(where: { $0.isNumber }) && $0.count < 60 }
            if Double(pageNumLines.count) / Double(max(1, lines.count)) > 0.8 {
                return true
            }
        }

        // ISBN/Copyright - only if it's the main content
        if (lower.contains("isbn") || lower.contains("library of congress")) && text.count < 500 {
            return true
        }

        return false
    }

    private func isNumericOnly(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.allSatisfy { $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == "." }
    }

    private func isBadSection(_ text: String) -> Bool {
        // Section names that are actually citations or page artifacts
        let bad = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if bad.isEmpty { return true }
        if bad.last?.isNumber == true && bad.count > 3 { return true }  // Ends with footnote number
        if bad.contains("Press,") || bad.contains("Review,") { return true }  // Citation
        if isNumericOnly(bad) { return true }
        return false
    }

    // MARK: - Text Analysis Fallback

    private func extractChapterFromText(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        for line in lines.prefix(5) {
            // "Chapter 1: Introduction" or "CHAPTER ONE"
            if line.lowercased().hasPrefix("chapter") {
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
                return line
            }

            // "1 Introduction" or "1. Introduction"
            let pattern = #"^(\d+)[\.\s]+([A-Z][a-zA-Z\s]+)$"#
            if let match = line.range(of: pattern, options: .regularExpression) {
                let title = line[match].components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ". "))).last ?? ""
                if !title.isEmpty {
                    return title.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private func extractSectionFromText(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        for line in lines.prefix(3) {
            // Skip empty or very short
            guard line.count > 5 && line.count < 80 else { continue }

            // "1.2 Section Title" pattern
            let pattern = #"^(\d+\.\d+)\s+([A-Z][a-zA-Z\s]+)$"#
            if let match = line.range(of: pattern, options: .regularExpression) {
                return String(line[match])
            }

            // Title Case short line (likely a section header)
            if isTitleCase(line) && line.split(separator: " ").count <= 8 {
                return line
            }
        }
        return nil
    }

    private func cleanMetadata(_ text: String?) -> String? {
        guard var cleaned = text else { return nil }

        // Remove trailing footnote numbers
        while let last = cleaned.last, last.isNumber {
            cleaned.removeLast()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Remove if it's just a number now
        if isNumericOnly(cleaned) { return nil }

        // Remove if it looks like a citation
        if cleaned.contains("Press,") || cleaned.contains("University") && cleaned.contains(",") {
            return nil
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    private func classifyChunk(_ chunk: SemanticChunk, chatService: ChatService) async throws -> ChunkClassification {
        let prompt = """
        Classify this text chunk from a book. Respond with ONLY valid JSON, no other text.

        Text (first 500 chars):
        \(String(chunk.text.prefix(500)))

        Respond with this exact JSON format:
        {"type": "content|toc|frontMatter|citation|index", "chapter": "chapter name or null", "section": "section name or null", "quality": 0.0-1.0}

        Where:
        - type: "content" for main book content, "toc" for table of contents, "frontMatter" for copyright/ISBN/preface, "citation" for footnotes/bibliography, "index" for book index
        - chapter: Extract the chapter name if identifiable, otherwise null
        - section: Extract the section name if identifiable, otherwise null
        - quality: How useful this chunk is for learning (1.0 = very useful, 0.0 = not useful)

        JSON:
        """

        let response = try await chatService.generate(query: prompt, context: [])

        // Parse the JSON response
        return parseClassificationResponse(response, fallbackChunk: chunk)
    }

    private func parseClassificationResponse(_ response: String, fallbackChunk: SemanticChunk) -> ChunkClassification {
        // Try to extract JSON from response
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            // Default to content if parsing fails
            return ChunkClassification(contentType: .content, chapter: fallbackChunk.chapter, section: fallbackChunk.section, quality: 0.7)
        }

        let jsonString = String(cleaned[start...end])

        guard let data = jsonString.data(using: .utf8) else {
            return ChunkClassification(contentType: .content, chapter: fallbackChunk.chapter, section: fallbackChunk.section, quality: 0.7)
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            let typeStr = json?["type"] as? String ?? "content"
            let contentType: ChunkClassification.ContentType
            switch typeStr.lowercased() {
            case "toc": contentType = .toc
            case "frontmatter", "front_matter": contentType = .frontMatter
            case "citation": contentType = .citation
            case "index": contentType = .index
            default: contentType = .content
            }

            let chapter = json?["chapter"] as? String
            let section = json?["section"] as? String
            let quality = json?["quality"] as? Double ?? 0.7

            return ChunkClassification(
                contentType: contentType,
                chapter: chapter != "null" ? chapter : nil,
                section: section != "null" ? section : nil,
                quality: quality
            )
        } catch {
            return ChunkClassification(contentType: .content, chapter: fallbackChunk.chapter, section: fallbackChunk.section, quality: 0.7)
        }
    }

    // MARK: - NL Entity Extraction (Fast Mode)

    /// Extract entities from chunks using Apple's NLTagger
    private func extractEntitiesFromChunks(_ chunks: [SemanticChunk]) -> [SemanticChunk] {
        return chunks.map { chunk in
            let entities = extractEntities(from: chunk.text)
            let keyTerms = extractKeyTerms(from: chunk.text)

            return SemanticChunk(
                id: chunk.id,
                text: chunk.text,
                source: chunk.source,
                page: chunk.page,
                section: chunk.section,
                chapter: chunk.chapter,
                startIndex: chunk.startIndex,
                endIndex: chunk.endIndex,
                sentenceCount: chunk.sentenceCount,
                wordCount: chunk.wordCount,
                precedingContext: chunk.precedingContext,
                followingContext: chunk.followingContext,
                people: entities.people.isEmpty ? nil : entities.people,
                places: entities.places.isEmpty ? nil : entities.places,
                organizations: entities.organizations.isEmpty ? nil : entities.organizations,
                keyTerms: keyTerms.isEmpty ? nil : keyTerms
            )
        }
    }

    /// Extract named entities (people, places, organizations) using NLTagger
    private func extractEntities(from text: String) -> (people: [String], places: [String], organizations: [String]) {
        var people: Set<String> = []
        var places: Set<String> = []
        var organizations: Set<String> = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag = tag else { return true }

            let entity = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard entity.count > 1 else { return true }  // Skip single chars

            switch tag {
            case .personalName:
                people.insert(entity)
            case .placeName:
                places.insert(entity)
            case .organizationName:
                organizations.insert(entity)
            default:
                break
            }
            return true
        }

        return (Array(people), Array(places), Array(organizations))
    }

    /// Extract key terms (nouns) using NLTagger
    private func extractKeyTerms(from text: String, maxTerms: Int = 10) -> [String] {
        var termCounts: [String: Int] = [:]

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            guard let tag = tag else { return true }

            // Only keep nouns (key concepts)
            if tag == .noun {
                let term = String(text[tokenRange]).lowercased()
                // Filter out very short or common words
                if term.count > 3 && !commonWords.contains(term) {
                    termCounts[term, default: 0] += 1
                }
            }
            return true
        }

        // Return top terms by frequency
        return termCounts
            .sorted { $0.value > $1.value }
            .prefix(maxTerms)
            .map { $0.key }
    }

    /// Common words to filter out from key terms
    private let commonWords: Set<String> = [
        "that", "this", "these", "those", "which", "what", "where", "when", "while",
        "their", "there", "they", "them", "then", "than", "have", "been", "being",
        "would", "could", "should", "other", "some", "many", "more", "most", "such",
        "only", "also", "well", "just", "even", "much", "each", "very", "same",
        "case", "part", "time", "year", "years", "way", "ways", "thing", "things",
        "people", "work", "fact", "point", "number", "place", "example", "state"
    ]

    // MARK: - Helpers

    private func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }

    private func countSentences(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func getLastSentences(_ text: String, count: Int) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences.suffix(count).joined()
    }

    private func getFirstSentences(_ text: String, count: Int) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences.prefix(count).joined()
    }

    // MARK: - Persistence

    private func saveChunks(_ chunks: [SemanticChunk]) async throws {
        let dataDir = projectPath.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Save new format
        let data = try encoder.encode(chunks)
        try data.write(to: dataDir.appendingPathComponent("chunks_v2.json"))

        // Also save legacy format for compatibility
        let legacyChunks = chunks.map { chunk -> [String: Any] in
            [
                "id": chunk.id,
                "text": chunk.text,
                "source": chunk.source,
                "title": chunk.section ?? chunk.source,
                "author": "Unknown",
                "index": chunk.startIndex
            ]
        }
        let legacyData = try JSONSerialization.data(withJSONObject: legacyChunks, options: .prettyPrinted)
        try legacyData.write(to: dataDir.appendingPathComponent("chunks.json"))
    }

    func loadChunks() async throws -> [SemanticChunk] {
        let dataDir = projectPath.appendingPathComponent("data")
        let v2Path = dataDir.appendingPathComponent("chunks_v2.json")

        if FileManager.default.fileExists(atPath: v2Path.path) {
            let data = try Data(contentsOf: v2Path)
            return try JSONDecoder().decode([SemanticChunk].self, from: data)
        }

        // Fall back to legacy format
        let legacyPath = dataDir.appendingPathComponent("chunks.json")
        let data = try Data(contentsOf: legacyPath)
        let legacy = try JSONDecoder().decode([LegacyChunk].self, from: data)

        return legacy.enumerated().map { index, chunk in
            SemanticChunk(
                id: chunk.id,
                text: chunk.text,
                source: chunk.source,
                page: nil,
                section: chunk.title,
                chapter: nil,
                startIndex: index,
                endIndex: index,
                sentenceCount: 0,
                wordCount: chunk.text.split(separator: " ").count,
                precedingContext: nil,
                followingContext: nil
            )
        }
    }
}

// MARK: - Legacy Support

private struct LegacyChunk: Codable {
    let id: String
    let text: String
    let source: String
    let title: String
    let author: String
    let index: Int
}

// MARK: - Errors

enum ProcessingError: Error, LocalizedError {
    case cannotOpenDocument
    case noTextContent
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: return "Cannot open document"
        case .noTextContent: return "Document contains no text"
        case .invalidFormat: return "Invalid document format"
        }
    }
}

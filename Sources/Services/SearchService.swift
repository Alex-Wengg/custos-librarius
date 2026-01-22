import Foundation

/// Hybrid search service combining BM25 + embedding similarity
actor SearchService {
    private let projectPath: URL
    private var chunks: [SemanticChunk] = []
    private var isLoaded = false

    // Embedding service for semantic search
    private var embeddingService: EmbeddingService?

    // Hybrid search weight (0 = pure BM25, 1 = pure embeddings)
    private let embeddingWeight: Float = 0.5

    init(projectPath: URL) {
        self.projectPath = projectPath
        self.embeddingService = EmbeddingService(projectPath: projectPath)
    }

    // MARK: - Loading

    func loadEmbeddingModel(modelId: String = "BAAI/bge-small-en-v1.5") async throws {
        // Load chunks
        try await loadIndex()

        // Load embedding model
        try await embeddingService?.loadModel(modelId: modelId)

        // Load cached embeddings if available
        try await embeddingService?.loadIndex()

        isLoaded = true
    }

    private func loadIndex() async throws {
        let chunksPath = projectPath.appendingPathComponent("data/chunks_v2.json")
        guard FileManager.default.fileExists(atPath: chunksPath.path) else { return }

        let data = try Data(contentsOf: chunksPath)
        chunks = try JSONDecoder().decode([SemanticChunk].self, from: data)
    }

    // MARK: - Embedding Index

    /// Build embedding index for all chunks
    func buildEmbeddingIndex(onProgress: ((String) -> Void)? = nil) async throws {
        guard !chunks.isEmpty else {
            onProgress?("No chunks to embed")
            return
        }

        try await embeddingService?.buildIndex(chunks: chunks, onProgress: onProgress)
    }

    var hasEmbeddings: Bool {
        get async {
            await embeddingService?.hasEmbeddings ?? false
        }
    }

    // MARK: - Search

    /// Hybrid search combining BM25 and embedding similarity
    func search(query: String, topK: Int = 5, useHybrid: Bool = true) async throws -> [SearchResult] {
        if !isLoaded {
            try await loadIndex()
            isLoaded = true
        }

        let documents = chunks.map { $0.text }
        guard !documents.isEmpty else { return [] }

        // BM25 scores
        let bm25Scores = bm25Search(query: query, documents: documents)

        // Embedding scores (if available) - use searchAll for efficiency
        var embeddingScores: [Float] = Array(repeating: 0, count: documents.count)
        if useHybrid, let embedService = embeddingService, await embedService.hasEmbeddings {
            let semanticScores = try await embedService.searchAll(query: query)
            for (id, score) in semanticScores {
                if let index = getChunkIndex(id: id) {
                    embeddingScores[index] = score
                }
            }
        }

        // Normalize scores to 0-1 range
        let normalizedBM25 = normalizeScores(bm25Scores)
        let normalizedEmb = normalizeScores(embeddingScores)

        // Combine scores
        var hybridScores: [(index: Int, score: Float)] = []
        for i in 0..<documents.count {
            let bm25 = normalizedBM25[i]
            let emb = normalizedEmb[i]
            let hybrid = (1 - embeddingWeight) * bm25 + embeddingWeight * emb
            hybridScores.append((i, hybrid))
        }

        // Sort and take top K
        hybridScores.sort { $0.score > $1.score }
        let topResults = hybridScores.prefix(topK)

        return topResults.map { item in
            let chunk = chunks[item.index]
            return SearchResult(
                text: chunk.text,
                source: chunk.source,
                score: item.score,
                metadata: SearchMetadata(
                    page: chunk.page,
                    section: chunk.section,
                    chapter: chunk.chapter
                )
            )
        }
    }

    /// BM25-only search
    func searchBM25(query: String, topK: Int = 5) async throws -> [SearchResult] {
        return try await search(query: query, topK: topK, useHybrid: false)
    }

    private func getChunkIndex(id: String) -> Int? {
        return chunks.firstIndex { $0.id == id }
    }

    // MARK: - BM25

    private func bm25Search(query: String, documents: [String], k1: Float = 1.5, b: Float = 0.75) -> [Float] {
        let queryTerms = tokenize(query)
        let docTerms = documents.map { tokenize($0) }

        let avgDocLen = Float(docTerms.map { $0.count }.reduce(0, +)) / Float(max(1, docTerms.count))

        // Document frequencies
        var df: [String: Int] = [:]
        for terms in docTerms {
            for term in Set(terms) {
                df[term, default: 0] += 1
            }
        }

        let N = Float(documents.count)

        return docTerms.map { terms in
            var score: Float = 0
            let docLen = Float(terms.count)

            for qterm in queryTerms {
                let tf = Float(terms.filter { $0 == qterm }.count)
                let docFreq = Float(df[qterm] ?? 0)
                let idf = log((N - docFreq + 0.5) / (docFreq + 0.5) + 1)
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLen / avgDocLen))
                score += idf * tfNorm
            }

            return score
        }
    }

    private func tokenize(_ text: String) -> [String] {
        // Simple tokenization - lowercase, split on whitespace/punctuation
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
    }

    private func normalizeScores(_ scores: [Float]) -> [Float] {
        guard !scores.isEmpty else { return [] }
        let maxScore = scores.max() ?? 1
        let minScore = scores.min() ?? 0
        let range = maxScore - minScore

        if range == 0 { return scores.map { _ in 0.5 } }
        return scores.map { ($0 - minScore) / range }
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id = UUID()
    let text: String
    let source: String
    let score: Float
    let metadata: SearchMetadata?

    init(text: String, source: String, score: Float, metadata: SearchMetadata? = nil) {
        self.text = text
        self.source = source
        self.score = score
        self.metadata = metadata
    }
}

struct SearchMetadata {
    let page: Int?
    let section: String?
    let chapter: String?
}

// MARK: - Reranking Service

/// Reranks search results using cross-encoder style scoring
actor RerankingService {

    /// Rerank results using enhanced relevance heuristics
    func rerank(query: String, results: [SearchResult], topK: Int = 5) async -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        let queryTerms = tokenize(query)
        let queryTermSet = Set(queryTerms)
        let queryBigrams = generateBigrams(queryTerms)

        // Score each result based on query-document relevance
        var scored = results.map { result -> (result: SearchResult, score: Float) in
            let docTerms = tokenize(result.text)
            let docTermSet = Set(docTerms)
            let docBigrams = generateBigrams(docTerms)

            // 1. Term overlap (Jaccard-like)
            let overlap = Float(queryTermSet.intersection(docTermSet).count)
            let overlapScore = overlap / Float(max(1, queryTermSet.count))

            // 2. Bigram overlap (phrase matching)
            let bigramOverlap = Float(queryBigrams.intersection(docBigrams).count)
            let bigramScore = bigramOverlap / Float(max(1, queryBigrams.count))

            // 3. Term density (how concentrated are query terms)
            let words = result.text.lowercased().components(separatedBy: .whitespaces)
            var termPositions: [Int] = []
            for (i, word) in words.enumerated() {
                let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
                if queryTermSet.contains(cleanWord) {
                    termPositions.append(i)
                }
            }

            let densityScore: Float
            if termPositions.count >= 2 {
                let span = Float(termPositions.last! - termPositions.first! + 1)
                densityScore = Float(termPositions.count) / span
            } else {
                densityScore = termPositions.isEmpty ? 0 : 0.5
            }

            // 4. Position bonus (prefer matches early in document)
            let positionScore: Float
            if let firstPos = termPositions.first {
                positionScore = 1.0 / (1.0 + Float(firstPos) / 50.0)
            } else {
                positionScore = 0
            }

            // 5. Coverage score (what fraction of query terms appear)
            let coverageScore = overlap / Float(queryTermSet.count)

            // 6. Length normalization (prefer concise relevant passages)
            let lengthPenalty = 1.0 / (1.0 + Float(docTerms.count) / 500.0)

            // Combine scores with weights
            let finalScore = result.score * 0.30 +     // Original retrieval score
                            overlapScore * 0.20 +       // Term overlap
                            bigramScore * 0.15 +        // Phrase matching
                            densityScore * 0.15 +       // Term clustering
                            coverageScore * 0.10 +      // Query coverage
                            positionScore * 0.05 +      // Position
                            lengthPenalty * 0.05        // Length

            return (result, finalScore)
        }

        scored.sort { $0.score > $1.score }

        return scored.prefix(topK).map {
            SearchResult(
                text: $0.result.text,
                source: $0.result.source,
                score: $0.score,
                metadata: $0.result.metadata
            )
        }
    }

    /// Generate bigrams from token list
    private func generateBigrams(_ tokens: [String]) -> Set<String> {
        guard tokens.count >= 2 else { return [] }
        var bigrams = Set<String>()
        for i in 0..<(tokens.count - 1) {
            bigrams.insert("\(tokens[i])_\(tokens[i+1])")
        }
        return bigrams
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
    }
}

// MARK: - Query Expansion

/// Expands queries with synonyms and related terms
struct QueryExpander {

    /// Expand query with related terms
    static func expand(query: String) -> String {
        let words = query.lowercased().split(separator: " ").map(String.init)
        var expanded = words

        // Add common synonyms and related terms
        for word in words {
            if let synonyms = synonymMap[word] {
                expanded.append(contentsOf: synonyms)
            }
        }

        return expanded.joined(separator: " ")
    }

    /// Generate multiple query variants for better recall
    static func generateVariants(query: String) -> [String] {
        var variants = [query]

        // Add expanded version
        let expandedQuery = expand(query: query)
        if expandedQuery != query {
            variants.append(expandedQuery)
        }

        // Add question form variants
        let lowerQuery = query.lowercased()
        if !lowerQuery.hasPrefix("what") && !lowerQuery.hasPrefix("how") &&
           !lowerQuery.hasPrefix("why") && !lowerQuery.hasPrefix("when") {
            variants.append("what is \(query)")
            variants.append("how does \(query)")
        }

        return variants
    }

    // Common synonyms for query expansion
    private static let synonymMap: [String: [String]] = [
        "create": ["make", "build", "generate"],
        "delete": ["remove", "erase", "drop"],
        "update": ["modify", "change", "edit"],
        "find": ["search", "locate", "get"],
        "show": ["display", "list", "view"],
        "error": ["bug", "issue", "problem", "exception"],
        "fast": ["quick", "rapid", "efficient"],
        "slow": ["sluggish", "delayed", "lag"],
        "big": ["large", "huge", "massive"],
        "small": ["tiny", "little", "compact"],
        "important": ["significant", "key", "critical"],
        "example": ["sample", "instance", "demonstration"],
        "function": ["method", "procedure", "routine"],
        "class": ["type", "object", "structure"],
        "variable": ["property", "field", "attribute"],
        "api": ["interface", "endpoint", "service"],
    ]
}

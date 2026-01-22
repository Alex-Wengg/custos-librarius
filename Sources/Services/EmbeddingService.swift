import Foundation
import MLX
import MLXEmbedders
import Tokenizers

/// Service for generating and searching text embeddings using MLX
actor EmbeddingService {
    private let projectPath: URL
    private var isLoaded = false

    // Embedding model container
    private var modelContainer: MLXEmbedders.ModelContainer?

    // Cached embeddings
    private var chunkEmbeddings: [[Float]] = []
    private var chunkTexts: [String] = []
    private var chunkIds: [String] = []

    // Embedding dimensions (set after model loads)
    private var embeddingDimension: Int = 384  // Default for bge-small

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    // MARK: - Model Loading

    func loadModel(modelId: String = "BAAI/bge-small-en-v1.5") async throws {
        // Note: Use non-quantized model IDs like "BAAI/bge-small-en-v1.5"
        // The mlx-community quantized versions may not be compatible
        print("Loading embedding model: \(modelId)")

        let configuration = MLXEmbedders.ModelConfiguration(id: modelId)
        modelContainer = try await MLXEmbedders.loadModelContainer(configuration: configuration) { progress in
            if progress.fractionCompleted < 1.0 {
                print("Downloading: \(Int(progress.fractionCompleted * 100))%")
            }
        }

        isLoaded = true
        print("Embedding model loaded successfully")
    }

    // MARK: - Embedding Generation

    /// Generate embedding for a single text
    func embed(text: String) async throws -> [Float] {
        guard let container = modelContainer else {
            throw EmbeddingError.modelNotLoaded
        }

        let embedding: [Float] = try await container.perform { model, tokenizer, pooler in
            // Tokenize
            let tokens = tokenizer.encode(text: text)
            let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)

            // Create attention mask (all 1s for valid tokens)
            let attentionMask = MLXArray.ones([1, tokens.count])

            // Run model
            let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: attentionMask)

            // Pool the output (normalized for similarity search)
            let pooled = pooler(output, mask: attentionMask, normalize: true)

            // Evaluate and extract
            eval(pooled)
            return pooled.asArray(Float.self)
        }

        return embedding
    }

    /// Generate embeddings for multiple texts (batched)
    func embedBatch(texts: [String], onProgress: ((Int, Int) -> Void)? = nil) async throws -> [[Float]] {
        guard let container = modelContainer else {
            throw EmbeddingError.modelNotLoaded
        }

        var embeddings: [[Float]] = []

        // Process one at a time to avoid memory issues
        for (index, text) in texts.enumerated() {
            let emb: [Float] = try await container.perform { model, tokenizer, pooler in
                // Tokenize
                let tokens = tokenizer.encode(text: text)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let attentionMask = MLXArray.ones([1, tokens.count])

                // Run model
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: attentionMask)

                // Pool the output (normalized)
                let pooled = pooler(output, mask: attentionMask, normalize: true)

                // Evaluate and extract
                eval(pooled)
                return pooled.asArray(Float.self)
            }
            embeddings.append(emb)

            onProgress?(index + 1, texts.count)
        }

        return embeddings
    }

    // MARK: - Index Management

    /// Build embeddings index from chunks
    func buildIndex(chunks: [SemanticChunk], onProgress: ((String) -> Void)? = nil) async throws {
        guard isLoaded else {
            throw EmbeddingError.modelNotLoaded
        }

        onProgress?("Generating embeddings for \(chunks.count) chunks...")

        // Store chunk info
        chunkTexts = chunks.map { $0.text }
        chunkIds = chunks.map { $0.id }

        // Generate embeddings with progress
        chunkEmbeddings = try await embedBatch(texts: chunkTexts) { completed, total in
            onProgress?("Embedding chunk \(completed)/\(total)")
        }

        // Update dimension
        if let first = chunkEmbeddings.first {
            embeddingDimension = first.count
        }

        // Save to disk
        try await saveIndex()

        onProgress?("Embedding index built: \(chunkEmbeddings.count) embeddings (\(embeddingDimension) dimensions)")
    }

    /// Load embeddings from disk
    func loadIndex() async throws {
        let embeddingsPath = projectPath.appendingPathComponent("data/embeddings.json")

        guard FileManager.default.fileExists(atPath: embeddingsPath.path) else {
            print("No cached embeddings found")
            return
        }

        let data = try Data(contentsOf: embeddingsPath)
        let saved = try JSONDecoder().decode(SavedEmbeddings.self, from: data)

        chunkIds = saved.ids
        chunkTexts = saved.texts
        chunkEmbeddings = saved.embeddings

        if let first = chunkEmbeddings.first {
            embeddingDimension = first.count
        }

        print("Loaded \(chunkEmbeddings.count) cached embeddings (\(embeddingDimension) dimensions)")
    }

    /// Save embeddings to disk
    private func saveIndex() async throws {
        let dataDir = projectPath.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let saved = SavedEmbeddings(
            ids: chunkIds,
            texts: chunkTexts,
            embeddings: chunkEmbeddings
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(saved)
        try data.write(to: dataDir.appendingPathComponent("embeddings.json"))

        print("Saved embeddings to disk")
    }

    // MARK: - Similarity Search

    /// Search for similar chunks using cosine similarity
    func search(query: String, topK: Int = 5) async throws -> [(id: String, text: String, score: Float)] {
        guard !chunkEmbeddings.isEmpty else {
            return []
        }

        guard isLoaded else {
            throw EmbeddingError.modelNotLoaded
        }

        // Generate query embedding
        let queryEmbedding = try await embed(text: query)

        // Calculate similarities
        var similarities: [(index: Int, score: Float)] = []

        for (index, docEmbedding) in chunkEmbeddings.enumerated() {
            let score = cosineSimilarity(queryEmbedding, docEmbedding)
            similarities.append((index, score))
        }

        // Sort by score descending
        similarities.sort { $0.score > $1.score }

        // Return top K
        return similarities.prefix(topK).map { item in
            (id: chunkIds[item.index], text: chunkTexts[item.index], score: item.score)
        }
    }

    /// Search and return scores for all documents (for hybrid search)
    func searchAll(query: String) async throws -> [String: Float] {
        guard !chunkEmbeddings.isEmpty, isLoaded else {
            return [:]
        }

        let queryEmbedding = try await embed(text: query)

        var scores: [String: Float] = [:]
        for (index, docEmbedding) in chunkEmbeddings.enumerated() {
            let score = cosineSimilarity(queryEmbedding, docEmbedding)
            scores[chunkIds[index]] = score
        }

        return scores
    }

    // MARK: - Similarity Metrics

    /// Cosine similarity between two vectors (embeddings should already be normalized)
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        // Since embeddings are normalized, cosine similarity is just dot product
        var dotProduct: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
        }

        return dotProduct
    }

    // MARK: - State

    var hasEmbeddings: Bool {
        !chunkEmbeddings.isEmpty
    }

    var embeddingCount: Int {
        chunkEmbeddings.count
    }

    var dimensions: Int {
        embeddingDimension
    }
}

// MARK: - Data Structures

private struct SavedEmbeddings: Codable {
    let ids: [String]
    let texts: [String]
    let embeddings: [[Float]]
}

enum EmbeddingError: Error, LocalizedError {
    case modelNotLoaded
    case embeddingFailed
    case dimensionMismatch

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Embedding model not loaded"
        case .embeddingFailed: return "Failed to generate embedding"
        case .dimensionMismatch: return "Embedding dimension mismatch"
        }
    }
}

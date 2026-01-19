import Foundation

/// Service for BM25 keyword search
actor SearchService {
    private let projectPath: URL
    private var chunks: [ChunkData] = []
    private var isLoaded = false

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    func loadEmbeddingModel() async throws {
        // Load chunks for BM25 search
        try loadIndex()
        isLoaded = true
    }

    private func loadIndex() throws {
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")

        if FileManager.default.fileExists(atPath: chunksPath.path) {
            let data = try Data(contentsOf: chunksPath)
            chunks = try JSONDecoder().decode([ChunkData].self, from: data)
        }
    }

    func search(query: String, topK: Int = 5) async throws -> [SearchResult] {
        if !isLoaded {
            try loadIndex()
            isLoaded = true
        }

        guard !chunks.isEmpty else { return [] }

        // Use BM25 search
        let bm25Scores = bm25Search(query: query, documents: chunks.map { $0.text })
        var scores: [(index: Int, score: Float)] = bm25Scores.enumerated().map { ($0.offset, $0.element) }

        // Sort and take top K
        scores.sort { $0.score > $1.score }
        let topResults = scores.prefix(topK)

        return topResults.map { item in
            SearchResult(
                text: chunks[item.index].text,
                source: chunks[item.index].source,
                score: item.score
            )
        }
    }

    private func bm25Search(query: String, documents: [String], k1: Float = 1.5, b: Float = 0.75) -> [Float] {
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        let docTerms = documents.map { $0.lowercased().split(separator: " ").map(String.init) }

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
}

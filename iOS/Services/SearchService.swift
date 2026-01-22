import Foundation

/// BM25 keyword search service (no ML required)
actor SearchService {
    private var chunks: [ChunkData] = []
    private var isLoaded = false

    func loadChunks(from url: URL) async throws {
        let chunksPath = url.appendingPathComponent("chunks.json")

        guard FileManager.default.fileExists(atPath: chunksPath.path) else {
            chunks = []
            isLoaded = true
            return
        }

        let data = try Data(contentsOf: chunksPath)
        chunks = try JSONDecoder().decode([ChunkData].self, from: data)
        isLoaded = true
    }

    var hasChunks: Bool {
        !chunks.isEmpty
    }

    var chunkCount: Int {
        chunks.count
    }

    func getAvailableSources() -> [String] {
        Array(Set(chunks.map { $0.source })).sorted()
    }

    func search(query: String, topK: Int = 10) async -> [SearchResult] {
        guard !chunks.isEmpty, !query.isEmpty else { return [] }

        // BM25 search
        let bm25Scores = bm25Search(query: query, documents: chunks.map { $0.text })
        var scores: [(index: Int, score: Float)] = bm25Scores.enumerated().map { ($0.offset, $0.element) }

        // Filter zero scores and sort
        scores = scores.filter { $0.score > 0 }
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
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
    }
}

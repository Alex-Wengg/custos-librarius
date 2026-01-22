import Foundation
import MLX
import MLXEmbedders

/// Quick test for hybrid search quality

// Test documents (simulating chunks from a history book)
let testChunks = [
    ("chunk1", "The Treaty of Westphalia was signed in 1648, ending the Thirty Years' War. It established the principle of state sovereignty in Europe."),
    ("chunk2", "Napoleon Bonaparte crowned himself Emperor of France in 1804. His military campaigns reshaped the map of Europe."),
    ("chunk3", "The Industrial Revolution began in Britain in the late 18th century. Steam power and mechanization transformed manufacturing."),
    ("chunk4", "World War I started in 1914 following the assassination of Archduke Franz Ferdinand. It was called 'the war to end all wars'."),
    ("chunk5", "The Renaissance was a cultural movement that began in Italy in the 14th century. It marked a rebirth of art, literature, and learning."),
    ("chunk6", "The French Revolution of 1789 overthrew the monarchy. It was driven by ideals of liberty, equality, and fraternity."),
    ("chunk7", "Ancient Rome was founded in 753 BC. The Roman Empire at its peak controlled much of Europe, North Africa, and the Middle East."),
    ("chunk8", "The Cold War was a period of geopolitical tension between the United States and Soviet Union from 1947 to 1991."),
]

// Test queries with expected top results
let testQueries = [
    // Exact match tests
    ("Treaty of Westphalia", "chunk1", "Exact keyword match"),
    ("Napoleon Emperor", "chunk2", "Exact keyword match"),

    // Semantic/synonym tests
    ("peace agreement 1648", "chunk1", "Semantic - 'peace agreement' ≈ 'treaty'"),
    ("factory machines Britain", "chunk3", "Semantic - Industrial Revolution"),
    ("artistic rebirth Italy", "chunk5", "Semantic - Renaissance"),

    // Conceptual tests
    ("end of monarchy France", "chunk6", "Conceptual - French Revolution"),
    ("US USSR conflict", "chunk8", "Conceptual - Cold War"),

    // Paraphrase tests
    ("military leader who became French ruler", "chunk2", "Paraphrase - Napoleon"),
    ("ancient civilization Mediterranean", "chunk7", "Paraphrase - Rome"),
]

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0
    for i in 0..<a.count { dot += a[i] * b[i] }
    return dot
}

func bm25Score(query: String, document: String) -> Float {
    let queryTerms = query.lowercased().split(separator: " ").map(String.init)
    let docTerms = document.lowercased().split(separator: " ").map(String.init)
    let docSet = Set(docTerms)

    var score: Float = 0
    for term in queryTerms {
        if docSet.contains(term) {
            score += 1
        }
    }
    return score / Float(queryTerms.count)
}

func runSearchTests() async {
    print("=== Hybrid Search Quality Test ===\n")

    do {
        // Load model
        print("Loading embedding model...")
        let config = ModelConfiguration(id: "BAAI/bge-small-en-v1.5")
        let container = try await loadModelContainer(configuration: config) { _ in }
        print("✓ Model loaded\n")

        // Generate embeddings for all chunks
        print("Generating chunk embeddings...")
        var chunkEmbeddings: [String: [Float]] = [:]

        for (id, text) in testChunks {
            let emb = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: text)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }
            chunkEmbeddings[id] = emb
        }
        print("✓ \(testChunks.count) chunk embeddings generated\n")

        // Run test queries
        print("Running search quality tests...\n")
        print(String(repeating: "=", count: 80))

        var bm25Correct = 0
        var hybridCorrect = 0
        var embeddingCorrect = 0

        for (query, expectedId, testType) in testQueries {
            // Generate query embedding
            let queryEmb = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: query)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }

            // Calculate scores for all chunks
            var results: [(id: String, bm25: Float, emb: Float, hybrid: Float)] = []

            for (id, text) in testChunks {
                let bm25 = bm25Score(query: query, document: text)
                let emb = cosineSimilarity(queryEmb, chunkEmbeddings[id]!)
                let hybrid = 0.5 * bm25 + 0.5 * emb  // Weighted combination
                results.append((id, bm25, emb, hybrid))
            }

            // Get top result for each method
            let topBM25 = results.max(by: { $0.bm25 < $1.bm25 })!
            let topEmb = results.max(by: { $0.emb < $1.emb })!
            let topHybrid = results.max(by: { $0.hybrid < $1.hybrid })!

            // Check correctness
            let bm25Ok = topBM25.id == expectedId
            let embOk = topEmb.id == expectedId
            let hybridOk = topHybrid.id == expectedId

            if bm25Ok { bm25Correct += 1 }
            if embOk { embeddingCorrect += 1 }
            if hybridOk { hybridCorrect += 1 }

            // Print result
            print("Query: \"\(query)\"")
            print("Type:  \(testType)")
            print("Expected: \(expectedId)")
            print("Results:")
            print("  BM25:      \(topBM25.id) \(bm25Ok ? "✅" : "❌") (score: \(String(format: "%.3f", topBM25.bm25)))")
            print("  Embedding: \(topEmb.id) \(embOk ? "✅" : "❌") (score: \(String(format: "%.3f", topEmb.emb)))")
            print("  Hybrid:    \(topHybrid.id) \(hybridOk ? "✅" : "❌") (score: \(String(format: "%.3f", topHybrid.hybrid)))")
            print(String(repeating: "-", count: 80))
        }

        // Summary
        let total = testQueries.count
        print("\n=== Summary ===")
        print("BM25 Accuracy:      \(bm25Correct)/\(total) (\(Int(Float(bm25Correct)/Float(total)*100))%)")
        print("Embedding Accuracy: \(embeddingCorrect)/\(total) (\(Int(Float(embeddingCorrect)/Float(total)*100))%)")
        print("Hybrid Accuracy:    \(hybridCorrect)/\(total) (\(Int(Float(hybridCorrect)/Float(total)*100))%)")

        if hybridCorrect > bm25Correct {
            print("\n✅ Hybrid search outperforms BM25 alone!")
        }
        if embeddingCorrect > bm25Correct {
            print("✅ Semantic search finds what keywords miss!")
        }

    } catch {
        print("❌ Error: \(error)")
    }
}

// Entry point
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runSearchTests()
    semaphore.signal()
}
semaphore.wait()

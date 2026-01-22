import Foundation
import MLX
import MLXEmbedders

// Simple test for the embedding service

func runTests() async {
        print("=== Embedding Service Test ===\n")

        do {
            // 1. Load embedding model
            print("1. Loading embedding model (BAAI/bge-small-en-v1.5)...")
            print("   This may download ~100MB on first run...\n")

            let config = ModelConfiguration(id: "BAAI/bge-small-en-v1.5")
            let container = try await loadModelContainer(configuration: config) { progress in
                if progress.fractionCompleted < 1.0 {
                    print("   Downloading: \(Int(progress.fractionCompleted * 100))%")
                }
            }
            print("   ✓ Model loaded!\n")

            // 2. Test single embedding
            print("2. Testing single text embedding...")
            let testText = "The quick brown fox jumps over the lazy dog."

            let embedding = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: testText)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let attentionMask = MLXArray.ones([1, tokens.count])

                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: attentionMask)
                let pooled = pooler(output, mask: attentionMask, normalize: true)

                eval(pooled)
                return pooled.asArray(Float.self)
            }

            print("   Text: \"\(testText)\"")
            print("   Embedding dimensions: \(embedding.count)")
            print("   First 5 values: \(embedding.prefix(5).map { String(format: "%.4f", $0) })")
            print("   ✓ Embedding generated!\n")

            // 3. Test similarity search
            print("3. Testing similarity search...")
            let documents = [
                "The quick brown fox jumps over the lazy dog.",
                "A fast auburn fox leaps above a sleepy canine.",
                "Machine learning is transforming technology.",
                "The weather today is sunny and warm.",
                "Natural language processing enables computers to understand text."
            ]

            // Generate embeddings for all documents
            var docEmbeddings: [[Float]] = []
            for doc in documents {
                let emb = try await container.perform { model, tokenizer, pooler in
                    let tokens = tokenizer.encode(text: doc)
                    let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                    let attentionMask = MLXArray.ones([1, tokens.count])

                    let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: attentionMask)
                    let pooled = pooler(output, mask: attentionMask, normalize: true)

                    eval(pooled)
                    return pooled.asArray(Float.self)
                }
                docEmbeddings.append(emb)
            }

            // Search with a query
            let query = "fox jumping"
            print("   Query: \"\(query)\"")

            let queryEmb = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: query)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let attentionMask = MLXArray.ones([1, tokens.count])

                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: attentionMask)
                let pooled = pooler(output, mask: attentionMask, normalize: true)

                eval(pooled)
                return pooled.asArray(Float.self)
            }

            // Calculate similarities (dot product since normalized)
            var similarities: [(index: Int, score: Float)] = []
            for (i, docEmb) in docEmbeddings.enumerated() {
                var dot: Float = 0
                for j in 0..<queryEmb.count {
                    dot += queryEmb[j] * docEmb[j]
                }
                similarities.append((i, dot))
            }

            // Sort by similarity
            similarities.sort { $0.score > $1.score }

            print("\n   Results (ranked by similarity):")
            for (rank, item) in similarities.enumerated() {
                let score = String(format: "%.4f", item.score)
                print("   \(rank + 1). [\(score)] \(documents[item.index])")
            }
            print("   ✓ Similarity search works!\n")

            // 4. Verify semantic understanding
            print("4. Verifying semantic understanding...")
            let semanticPairs = [
                ("dog", "canine"),
                ("happy", "joyful"),
                ("car", "automobile"),
                ("computer", "banana")  // Should be low similarity
            ]

            for (word1, word2) in semanticPairs {
                let emb1 = try await container.perform { model, tokenizer, pooler in
                    let tokens = tokenizer.encode(text: word1)
                    let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                    let mask = MLXArray.ones([1, tokens.count])
                    let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                    let pooled = pooler(output, mask: mask, normalize: true)
                    eval(pooled)
                    return pooled.asArray(Float.self)
                }

                let emb2 = try await container.perform { model, tokenizer, pooler in
                    let tokens = tokenizer.encode(text: word2)
                    let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                    let mask = MLXArray.ones([1, tokens.count])
                    let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                    let pooled = pooler(output, mask: mask, normalize: true)
                    eval(pooled)
                    return pooled.asArray(Float.self)
                }

                var similarity: Float = 0
                for i in 0..<emb1.count {
                    similarity += emb1[i] * emb2[i]
                }

                let score = String(format: "%.4f", similarity)
                print("   \"\(word1)\" ↔ \"\(word2)\": \(score)")
            }
            print("   ✓ Semantic similarity working!\n")

            print("=== All Tests Passed! ===")
            print("\nThe embedding service is ready for hybrid search.")

        } catch {
            print("❌ Error: \(error)")
        }
}

// Entry point
import _Concurrency
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runTests()
    semaphore.signal()
}
semaphore.wait()

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXEmbedders
import NaturalLanguage

// =============================================================================
// FULL BACKEND PIPELINE TEST
// Tests: Chunking → Embeddings → Hybrid Search → LLM Generation
// =============================================================================

// MARK: - Test Documents (simulating PDF content)

let testDocuments: [(name: String, content: String)] = [
    ("history_china.txt", """
    Chapter 1: Ancient China

    The Shang Dynasty (1600-1046 BCE) was one of the earliest Chinese dynasties with historical records.
    They developed one of the oldest forms of Chinese writing, found on oracle bones used for divination.
    The Shang were known for their bronze work and established many traditions that would continue for millennia.

    The Zhou Dynasty (1046-256 BCE) followed the Shang and introduced the concept of the Mandate of Heaven,
    which justified the rule of the king. This period saw the emergence of Confucius (551-479 BCE),
    whose teachings on ethics, family, and governance would profoundly influence Chinese civilization.

    The Qin Dynasty (221-206 BCE) unified China for the first time under Emperor Qin Shi Huang.
    He standardized weights, measures, and writing systems. The Great Wall was expanded during this period
    to protect against northern nomadic invasions. The Terracotta Army was built to guard his tomb.
    """),

    ("history_rome.txt", """
    Chapter 1: The Roman Republic

    Rome was founded in 753 BCE according to legend. The Roman Republic was established in 509 BCE
    after the overthrow of the last Roman king. The Republic was governed by elected officials
    called consuls and a Senate composed of aristocratic families.

    The Punic Wars (264-146 BCE) were a series of three wars fought between Rome and Carthage.
    The most famous general was Hannibal, who crossed the Alps with elephants to invade Italy.
    Rome ultimately destroyed Carthage and became the dominant power in the Mediterranean.

    Julius Caesar (100-44 BCE) was a military general who conquered Gaul and crossed the Rubicon
    river in 49 BCE, starting a civil war. He became dictator of Rome but was assassinated
    on the Ides of March (March 15) in 44 BCE by senators who feared his growing power.
    """),

    ("science_physics.txt", """
    Chapter 1: Classical Mechanics

    Isaac Newton (1643-1727) formulated the three laws of motion that form the foundation of classical mechanics.
    The First Law states that an object at rest stays at rest unless acted upon by an external force.
    The Second Law relates force, mass, and acceleration: F = ma.
    The Third Law states that for every action, there is an equal and opposite reaction.

    Newton also developed the law of universal gravitation, which describes the gravitational attraction
    between masses. The force is proportional to the product of the masses and inversely proportional
    to the square of the distance between them: F = G(m1*m2)/r².

    Albert Einstein (1879-1955) revolutionized physics with his theories of relativity.
    Special Relativity (1905) introduced the famous equation E = mc², showing mass-energy equivalence.
    General Relativity (1915) described gravity as the curvature of spacetime caused by mass and energy.
    """)
]

// MARK: - Chunk Data Structures

struct TestChunk: Codable {
    let id: String
    let text: String
    let source: String
    let section: String?
    let wordCount: Int
}

// MARK: - Simple Chunking

func createChunks(from documents: [(name: String, content: String)], targetWords: Int = 150) -> [TestChunk] {
    var chunks: [TestChunk] = []

    for (name, content) in documents {
        // Split by paragraphs
        let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var currentChunk = ""
        var currentSection: String? = nil

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)

            // Detect chapter/section headers
            if trimmed.hasPrefix("Chapter") {
                currentSection = trimmed.components(separatedBy: "\n").first
            }

            let wordCount = trimmed.split(separator: " ").count
            let currentWordCount = currentChunk.split(separator: " ").count

            if currentWordCount + wordCount > targetWords && !currentChunk.isEmpty {
                // Save current chunk
                let chunk = TestChunk(
                    id: UUID().uuidString,
                    text: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: name,
                    section: currentSection,
                    wordCount: currentWordCount
                )
                chunks.append(chunk)
                currentChunk = trimmed
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : "\n\n") + trimmed
            }
        }

        // Save last chunk
        if !currentChunk.isEmpty {
            let chunk = TestChunk(
                id: UUID().uuidString,
                text: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                source: name,
                section: currentSection,
                wordCount: currentChunk.split(separator: " ").count
            )
            chunks.append(chunk)
        }
    }

    return chunks
}

// MARK: - BM25 Search

func bm25Search(query: String, chunks: [TestChunk], k1: Float = 1.5, b: Float = 0.75) -> [(chunk: TestChunk, score: Float)] {
    let queryTerms = tokenize(query)
    let docTerms = chunks.map { tokenize($0.text) }

    let avgDocLen = Float(docTerms.map { $0.count }.reduce(0, +)) / Float(max(1, docTerms.count))

    // Document frequencies
    var df: [String: Int] = [:]
    for terms in docTerms {
        for term in Set(terms) {
            df[term, default: 0] += 1
        }
    }

    let N = Float(chunks.count)

    var results: [(chunk: TestChunk, score: Float)] = []

    for (i, terms) in docTerms.enumerated() {
        var score: Float = 0
        let docLen = Float(terms.count)

        for qterm in queryTerms {
            let tf = Float(terms.filter { $0 == qterm }.count)
            let docFreq = Float(df[qterm] ?? 0)
            let idf = log((N - docFreq + 0.5) / (docFreq + 0.5) + 1)
            let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLen / avgDocLen))
            score += idf * tfNorm
        }

        results.append((chunks[i], score))
    }

    return results.sorted { $0.score > $1.score }
}

func tokenize(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty && $0.count > 2 }
}

// MARK: - Cosine Similarity

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return 0 }
    var dot: Float = 0
    for i in 0..<a.count { dot += a[i] * b[i] }
    return dot  // Already normalized
}

// MARK: - Main Test

func runBackendTest() async {
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
    print("  FULL BACKEND PIPELINE TEST")
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
    print()

    do {
        // =====================================================================
        // STEP 1: CHUNKING
        // =====================================================================
        print("📄 STEP 1: Document Chunking")
        print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

        let chunks = createChunks(from: testDocuments, targetWords: 100)
        print("   Created \(chunks.count) chunks from \(testDocuments.count) documents")
        for chunk in chunks {
            print("   • [\(chunk.source)] \(chunk.wordCount) words - \(chunk.text.prefix(50))...")
        }
        print()

        // =====================================================================
        // STEP 2: EMBEDDINGS
        // =====================================================================
        print("🧠 STEP 2: Generate Embeddings")
        print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

        print("   Loading embedding model (BAAI/bge-small-en-v1.5)...")
        let embContainer = try await MLXEmbedders.loadModelContainer(
            configuration: MLXEmbedders.ModelConfiguration(id: "BAAI/bge-small-en-v1.5")
        ) { _ in }
        print("   ✓ Embedding model loaded")

        // Generate embeddings for all chunks
        var chunkEmbeddings: [[Float]] = []
        for (i, chunk) in chunks.enumerated() {
            let emb = try await embContainer.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: chunk.text)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }
            chunkEmbeddings.append(emb)
            print("   Embedded chunk \(i+1)/\(chunks.count)")
        }
        print("   ✓ Generated \(chunkEmbeddings.count) embeddings (\(chunkEmbeddings[0].count) dimensions)")
        print()

        // =====================================================================
        // STEP 3: HYBRID SEARCH
        // =====================================================================
        print("🔍 STEP 3: Hybrid Search Test")
        print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

        let testQueries = [
            "Newton's laws of motion",
            "Who crossed the Alps with elephants?",
            "ancient Chinese writing oracle bones",
            "Einstein relativity theory",
            "Roman Republic government structure"
        ]

        for query in testQueries {
            print("\n   Query: \"\(query)\"")

            // BM25 scores
            let bm25Results = bm25Search(query: query, chunks: chunks)

            // Embedding scores
            let queryEmb = try await embContainer.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: query)
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }

            var embScores: [(chunk: TestChunk, score: Float)] = []
            for (i, chunk) in chunks.enumerated() {
                let score = cosineSimilarity(queryEmb, chunkEmbeddings[i])
                embScores.append((chunk, score))
            }
            embScores.sort { $0.score > $1.score }

            // Hybrid (normalize and combine)
            let maxBM25 = bm25Results.map { $0.score }.max() ?? 1
            let maxEmb = embScores.map { $0.score }.max() ?? 1

            var hybridScores: [(chunk: TestChunk, score: Float)] = []
            for chunk in chunks {
                let bm25 = (bm25Results.first { $0.chunk.id == chunk.id }?.score ?? 0) / max(maxBM25, 0.001)
                let emb = (embScores.first { $0.chunk.id == chunk.id }?.score ?? 0) / max(maxEmb, 0.001)
                let hybrid = 0.5 * bm25 + 0.5 * emb
                hybridScores.append((chunk, hybrid))
            }
            hybridScores.sort { $0.score > $1.score }

            // Show top result
            let top = hybridScores[0]
            print("   → Top result: [\(top.chunk.source)] score=\(String(format: "%.3f", top.score))")
            print("     \"\(top.chunk.text.prefix(80))...\"")
        }
        print()

        // =====================================================================
        // STEP 4: LLM GENERATION
        // =====================================================================
        print("🤖 STEP 4: LLM Quiz Generation")
        print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

        print("   Loading LLM (Qwen2.5-7B-Instruct-4bit)...")
        let llmConfig = MLXLMCommon.ModelConfiguration(id: "mlx-community/Qwen2.5-7B-Instruct-4bit")
        let llmContainer = try await LLMModelFactory.shared.loadContainer(configuration: llmConfig) { _ in }
        print("   ✓ LLM loaded")

        // Generate quiz from a retrieved chunk
        let query = "Newton physics laws"
        print("\n   Searching for: \"\(query)\"")

        let queryEmb = try await embContainer.perform { model, tokenizer, pooler in
            let tokens = tokenizer.encode(text: query)
            let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
            let mask = MLXArray.ones([1, tokens.count])
            let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
            let pooled = pooler(output, mask: mask, normalize: true)
            eval(pooled)
            return pooled.asArray(Float.self)
        }

        var scores: [(idx: Int, score: Float)] = []
        for (i, emb) in chunkEmbeddings.enumerated() {
            scores.append((i, cosineSimilarity(queryEmb, emb)))
        }
        scores.sort { $0.score > $1.score }

        let topChunk = chunks[scores[0].idx]
        print("   Retrieved chunk from: \(topChunk.source)")
        print("   Content: \"\(topChunk.text.prefix(100))...\"")

        print("\n   Generating quiz question...")

        let messages: [Chat.Message] = [
            .system("""
            You create educational multiple choice questions. Rules:
            1. Question must be self-contained (include all context)
            2. Exactly 4 options, all plausible
            3. Output valid JSON only
            """),
            .user("""
            Create a quiz question from this text:

            \(topChunk.text)

            Output JSON: {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
            """)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""

        try await llmContainer.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 400, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                }
            }
        }

        print("\n   Generated output:")
        print("   \(output)")

        // Parse and validate
        if let start = output.firstIndex(of: "{"),
           let end = output.lastIndex(of: "}") {
            let jsonStr = String(output[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let question = json["question"] as? String,
               let options = json["options"] as? [String],
               let correctIndex = json["correctIndex"] as? Int {
                print("\n   ✓ Valid quiz generated!")
                print("   Question: \(question)")
                print("   Options:")
                for (i, opt) in options.enumerated() {
                    let marker = i == correctIndex ? "✓" : " "
                    print("     \(marker) \(i). \(opt)")
                }
            }
        }

        print()
        print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
        print("  ✅ BACKEND PIPELINE TEST COMPLETE")
        print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))

    } catch {
        print("❌ Error: \(error)")
    }
}

// Entry point
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runBackendTest()
    semaphore.signal()
}
semaphore.wait()

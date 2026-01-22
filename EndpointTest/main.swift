import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXEmbedders
import NaturalLanguage

// =============================================================================
// SERVICE ENDPOINT TESTS
// Tests all service APIs before UI testing
// =============================================================================

// MARK: - Test Configuration

let testProjectPath = FileManager.default.temporaryDirectory.appendingPathComponent("custos_test_\(UUID().uuidString)")

// MARK: - Test Data

let samplePDFContent = """
Chapter 1: Introduction to Machine Learning

Machine learning is a subset of artificial intelligence that enables systems to learn from data.
Unlike traditional programming where rules are explicitly coded, machine learning algorithms
identify patterns in data and make decisions with minimal human intervention.

There are three main types of machine learning:
1. Supervised Learning: The algorithm learns from labeled training data
2. Unsupervised Learning: The algorithm finds patterns in unlabeled data
3. Reinforcement Learning: The algorithm learns through trial and error

Deep learning is a subset of machine learning that uses neural networks with multiple layers.
These networks can learn hierarchical representations of data, making them powerful for
tasks like image recognition, natural language processing, and speech recognition.

Chapter 2: Neural Networks

A neural network consists of layers of interconnected nodes called neurons.
The input layer receives data, hidden layers process it, and the output layer produces results.
Each connection has a weight that is adjusted during training.

The backpropagation algorithm is used to train neural networks by calculating gradients
and updating weights to minimize the error between predicted and actual outputs.

Common activation functions include:
- ReLU (Rectified Linear Unit): f(x) = max(0, x)
- Sigmoid: f(x) = 1 / (1 + e^(-x))
- Tanh: f(x) = (e^x - e^(-x)) / (e^x + e^(-x))

Chapter 3: Applications

Machine learning has numerous real-world applications:
- Healthcare: Disease diagnosis, drug discovery, personalized treatment
- Finance: Fraud detection, algorithmic trading, credit scoring
- Transportation: Self-driving cars, route optimization, demand prediction
- Entertainment: Recommendation systems, content generation, game AI
"""

// MARK: - Result Tracking

struct TestResult {
    let name: String
    let passed: Bool
    let duration: TimeInterval
    let details: String
}

var testResults: [TestResult] = []

func recordTest(_ name: String, passed: Bool, duration: TimeInterval, details: String = "") {
    testResults.append(TestResult(name: name, passed: passed, duration: duration, details: details))
    let status = passed ? "✅" : "❌"
    let time = String(format: "%.2fs", duration)
    print("   \(status) \(name) (\(time))")
    if !details.isEmpty && !passed {
        print("      → \(details)")
    }
}

// MARK: - Setup

func setupTestProject() throws {
    // Create project directory structure
    try FileManager.default.createDirectory(at: testProjectPath, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testProjectPath.appendingPathComponent("documents"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testProjectPath.appendingPathComponent("data"), withIntermediateDirectories: true)

    // Create config file
    let config = """
    {
        "name": "Test Project",
        "model": "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "embedding_model": "BAAI/bge-small-en-v1.5"
    }
    """
    try config.write(to: testProjectPath.appendingPathComponent("librarian.json"), atomically: true, encoding: .utf8)

    // Create sample document
    try samplePDFContent.write(
        to: testProjectPath.appendingPathComponent("documents/ml_intro.txt"),
        atomically: true,
        encoding: .utf8
    )

    print("   Created test project at: \(testProjectPath.path)")
}

func cleanup() {
    try? FileManager.default.removeItem(at: testProjectPath)
}

// MARK: - Chunk Data Structures (matching app)

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
}

struct ChunkData: Codable {
    let id: String
    let text: String
    let source: String
    let title: String
    let author: String
    let index: Int
}

// MARK: - Simple Chunking Service (simulating DocumentProcessingService)

func processDocument(at path: URL, chunkSize: Int = 200) -> [SemanticChunk] {
    guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }

    var chunks: [SemanticChunk] = []
    let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    var currentText = ""
    var currentChapter: String? = nil
    var chunkIndex = 0

    for para in paragraphs {
        let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect chapter headers
        if trimmed.hasPrefix("Chapter") {
            currentChapter = trimmed.components(separatedBy: "\n").first
        }

        let wordCount = trimmed.split(separator: " ").count
        let currentWordCount = currentText.split(separator: " ").count

        if currentWordCount + wordCount > chunkSize && !currentText.isEmpty {
            let chunk = SemanticChunk(
                id: UUID().uuidString,
                text: currentText,
                source: path.lastPathComponent,
                page: nil,
                section: nil,
                chapter: currentChapter,
                startIndex: chunkIndex,
                endIndex: chunkIndex + currentText.count,
                sentenceCount: currentText.components(separatedBy: ".").count - 1,
                wordCount: currentWordCount,
                precedingContext: nil,
                followingContext: nil
            )
            chunks.append(chunk)
            currentText = trimmed
            chunkIndex += 1
        } else {
            currentText += (currentText.isEmpty ? "" : "\n\n") + trimmed
        }
    }

    // Last chunk
    if !currentText.isEmpty {
        let chunk = SemanticChunk(
            id: UUID().uuidString,
            text: currentText,
            source: path.lastPathComponent,
            page: nil,
            section: nil,
            chapter: currentChapter,
            startIndex: chunkIndex,
            endIndex: chunkIndex + currentText.count,
            sentenceCount: currentText.components(separatedBy: ".").count - 1,
            wordCount: currentText.split(separator: " ").count,
            precedingContext: nil,
            followingContext: nil
        )
        chunks.append(chunk)
    }

    return chunks
}

// MARK: - BM25 Search

func bm25Search(query: String, chunks: [SemanticChunk], topK: Int = 5) -> [(chunk: SemanticChunk, score: Float)] {
    let queryTerms = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
    let docTerms = chunks.map { $0.text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 } }

    let avgDocLen = Float(docTerms.map { $0.count }.reduce(0, +)) / Float(max(1, docTerms.count))
    let k1: Float = 1.5
    let b: Float = 0.75

    var df: [String: Int] = [:]
    for terms in docTerms {
        for term in Set(terms) {
            df[term, default: 0] += 1
        }
    }

    let N = Float(chunks.count)
    var results: [(chunk: SemanticChunk, score: Float)] = []

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

    return results.sorted { $0.score > $1.score }.prefix(topK).map { $0 }
}

// MARK: - Main Test Runner

func runEndpointTests() async {
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
    print("  SERVICE ENDPOINT TESTS")
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
    print()

    // Setup
    print("📁 Setting up test project...")
    do {
        try setupTestProject()
        print()
    } catch {
        print("   ❌ Setup failed: \(error)")
        return
    }

    var chunks: [SemanticChunk] = []
    var chunkEmbeddings: [[Float]] = []
    var embContainer: MLXEmbedders.ModelContainer?
    var llmContainer: MLXLMCommon.ModelContainer?

    // =========================================================================
    // TEST 1: Document Processing
    // =========================================================================
    print("📄 TEST 1: Document Processing Service")
    print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

    do {
        var start = Date()

        // Test 1.1: Process document
        let docPath = testProjectPath.appendingPathComponent("documents/ml_intro.txt")
        chunks = processDocument(at: docPath, chunkSize: 150)
        recordTest("Process document into chunks", passed: chunks.count > 0, duration: Date().timeIntervalSince(start),
                   details: "Created \(chunks.count) chunks")

        // Test 1.2: Chunk metadata
        start = Date()
        let hasChapters = chunks.contains { $0.chapter != nil }
        recordTest("Extract chapter metadata", passed: hasChapters, duration: Date().timeIntervalSince(start))

        // Test 1.3: Save chunks
        start = Date()
        let chunksPath = testProjectPath.appendingPathComponent("data/chunks_v2.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let chunksData = try encoder.encode(chunks)
        try chunksData.write(to: chunksPath)
        let savedExists = FileManager.default.fileExists(atPath: chunksPath.path)
        recordTest("Save chunks to JSON", passed: savedExists, duration: Date().timeIntervalSince(start))

        // Test 1.4: Load chunks
        start = Date()
        let loadedData = try Data(contentsOf: chunksPath)
        let loadedChunks = try JSONDecoder().decode([SemanticChunk].self, from: loadedData)
        recordTest("Load chunks from JSON", passed: loadedChunks.count == chunks.count, duration: Date().timeIntervalSince(start))

        print()
    } catch {
        recordTest("Document processing", passed: false, duration: 0, details: error.localizedDescription)
    }

    // =========================================================================
    // TEST 2: Embedding Service
    // =========================================================================
    print("🧠 TEST 2: Embedding Service")
    print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

    do {
        var start = Date()

        // Test 2.1: Load embedding model
        embContainer = try await MLXEmbedders.loadModelContainer(
            configuration: MLXEmbedders.ModelConfiguration(id: "BAAI/bge-small-en-v1.5")
        ) { _ in }
        recordTest("Load embedding model", passed: embContainer != nil, duration: Date().timeIntervalSince(start))

        // Test 2.2: Generate single embedding
        start = Date()
        var singleEmb: [Float] = []
        if let container = embContainer {
            singleEmb = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: "test query")
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }
        }
        recordTest("Generate single embedding", passed: singleEmb.count == 384, duration: Date().timeIntervalSince(start),
                   details: "Dimensions: \(singleEmb.count)")

        // Test 2.3: Batch embeddings
        start = Date()
        if let container = embContainer {
            for chunk in chunks {
                let emb = try await container.perform { model, tokenizer, pooler in
                    let tokens = tokenizer.encode(text: chunk.text)
                    let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                    let mask = MLXArray.ones([1, tokens.count])
                    let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                    let pooled = pooler(output, mask: mask, normalize: true)
                    eval(pooled)
                    return pooled.asArray(Float.self)
                }
                chunkEmbeddings.append(emb)
            }
        }
        recordTest("Generate batch embeddings", passed: chunkEmbeddings.count == chunks.count,
                   duration: Date().timeIntervalSince(start),
                   details: "\(chunkEmbeddings.count) embeddings")

        // Test 2.4: Save embeddings
        start = Date()
        struct SavedEmbeddings: Codable {
            let ids: [String]
            let texts: [String]
            let embeddings: [[Float]]
        }
        let saved = SavedEmbeddings(
            ids: chunks.map { $0.id },
            texts: chunks.map { $0.text },
            embeddings: chunkEmbeddings
        )
        let embPath = testProjectPath.appendingPathComponent("data/embeddings.json")
        try JSONEncoder().encode(saved).write(to: embPath)
        recordTest("Save embeddings to disk", passed: FileManager.default.fileExists(atPath: embPath.path),
                   duration: Date().timeIntervalSince(start))

        print()
    } catch {
        recordTest("Embedding service", passed: false, duration: 0, details: error.localizedDescription)
    }

    // =========================================================================
    // TEST 3: Search Service
    // =========================================================================
    print("🔍 TEST 3: Search Service")
    print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

    do {
        var start = Date()

        // Test 3.1: BM25 search
        let bm25Results = bm25Search(query: "neural network layers", chunks: chunks, topK: 3)
        recordTest("BM25 keyword search", passed: !bm25Results.isEmpty, duration: Date().timeIntervalSince(start),
                   details: "Top result: \(bm25Results.first?.chunk.chapter ?? "unknown")")

        // Test 3.2: Embedding search
        start = Date()
        var embResults: [(idx: Int, score: Float)] = []
        if let container = embContainer {
            let queryEmb = try await container.perform { model, tokenizer, pooler in
                let tokens = tokenizer.encode(text: "deep learning neural networks")
                let inputIds = MLXArray(tokens).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, tokens.count])
                let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let pooled = pooler(output, mask: mask, normalize: true)
                eval(pooled)
                return pooled.asArray(Float.self)
            }

            for (i, emb) in chunkEmbeddings.enumerated() {
                var dot: Float = 0
                for j in 0..<queryEmb.count { dot += queryEmb[j] * emb[j] }
                embResults.append((i, dot))
            }
            embResults.sort { $0.score > $1.score }
        }
        recordTest("Embedding similarity search", passed: !embResults.isEmpty, duration: Date().timeIntervalSince(start),
                   details: "Top score: \(String(format: "%.3f", embResults.first?.score ?? 0))")

        // Test 3.3: Hybrid search
        start = Date()
        let query = "machine learning types supervised"
        let bm25 = bm25Search(query: query, chunks: chunks, topK: chunks.count)

        var hybridScores: [(chunk: SemanticChunk, score: Float)] = []
        let maxBM25 = bm25.map { $0.score }.max() ?? 1
        let maxEmb = embResults.map { $0.score }.max() ?? 1

        for (i, chunk) in chunks.enumerated() {
            let bm25Score = (bm25.first { $0.chunk.id == chunk.id }?.score ?? 0) / max(maxBM25, 0.001)
            let embScore = (embResults.first { $0.idx == i }?.score ?? 0) / max(maxEmb, 0.001)
            let hybrid = 0.5 * bm25Score + 0.5 * embScore
            hybridScores.append((chunk, hybrid))
        }
        hybridScores.sort { $0.score > $1.score }

        recordTest("Hybrid search (BM25 + embeddings)", passed: !hybridScores.isEmpty,
                   duration: Date().timeIntervalSince(start),
                   details: "Top: \(hybridScores.first?.chunk.chapter ?? "?")")

        // Test 3.4: Query expansion
        start = Date()
        let synonyms = ["learning": ["training", "education"], "network": ["graph", "system"]]
        var expandedQuery = query
        for (word, syns) in synonyms {
            if query.lowercased().contains(word) {
                expandedQuery += " " + syns.joined(separator: " ")
            }
        }
        recordTest("Query expansion", passed: expandedQuery.count > query.count,
                   duration: Date().timeIntervalSince(start),
                   details: "Expanded: \(expandedQuery.prefix(50))...")

        print()
    } catch {
        recordTest("Search service", passed: false, duration: 0, details: error.localizedDescription)
    }

    // =========================================================================
    // TEST 4: LLM Generation Service
    // =========================================================================
    print("🤖 TEST 4: LLM Generation Service")
    print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

    do {
        var start = Date()

        // Test 4.1: Load LLM
        llmContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: MLXLMCommon.ModelConfiguration(id: "mlx-community/Qwen2.5-7B-Instruct-4bit")
        ) { _ in }
        recordTest("Load LLM model", passed: llmContainer != nil, duration: Date().timeIntervalSince(start))

        // Test 4.2: Simple generation
        start = Date()
        var simpleOutput = ""
        if let container = llmContainer {
            let messages: [Chat.Message] = [
                .system("You are helpful. Be very brief."),
                .user("What is 2+2? Answer with just the number.")
            ]
            let input = UserInput(chat: messages)

            try await container.perform { context in
                let prepared = try await context.processor.prepare(input: input)
                let params = GenerateParameters(maxTokens: 10, temperature: 0.1)
                for await item in try MLXLMCommon.generate(input: prepared, parameters: params, context: context) {
                    if case .chunk(let c) = item { simpleOutput += c }
                }
            }
        }
        recordTest("Simple generation", passed: simpleOutput.contains("4"),
                   duration: Date().timeIntervalSince(start),
                   details: "Output: \(simpleOutput.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Test 4.3: RAG generation
        start = Date()
        var ragOutput = ""
        let context = chunks.prefix(2).map { $0.text }.joined(separator: "\n\n")
        if let container = llmContainer {
            let messages: [Chat.Message] = [
                .system("Answer based on the context provided. Be concise."),
                .user("Context:\n\(context)\n\nQuestion: What are the three types of machine learning?")
            ]
            let input = UserInput(chat: messages)

            try await container.perform { ctx in
                let prepared = try await ctx.processor.prepare(input: input)
                let params = GenerateParameters(maxTokens: 100, temperature: 0.7)
                for await item in try MLXLMCommon.generate(input: prepared, parameters: params, context: ctx) {
                    if case .chunk(let c) = item { ragOutput += c }
                }
            }
        }
        let hasTypes = ragOutput.lowercased().contains("supervised") ||
                       ragOutput.lowercased().contains("unsupervised") ||
                       ragOutput.lowercased().contains("reinforcement")
        recordTest("RAG generation with context", passed: hasTypes,
                   duration: Date().timeIntervalSince(start),
                   details: "Found ML types in response")

        // Test 4.4: Quiz generation
        start = Date()
        var quizOutput = ""
        if let container = llmContainer {
            let chunkText = chunks.first?.text ?? ""
            let messages: [Chat.Message] = [
                .system("Create quiz questions. Output valid JSON only."),
                .user("""
                Create a multiple choice question from this text:

                \(chunkText.prefix(500))

                Output: {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
                """)
            ]
            let input = UserInput(chat: messages)

            try await container.perform { ctx in
                let prepared = try await ctx.processor.prepare(input: input)
                let params = GenerateParameters(maxTokens: 300, temperature: 0.7)
                for await item in try MLXLMCommon.generate(input: prepared, parameters: params, context: ctx) {
                    if case .chunk(let c) = item { quizOutput += c }
                }
            }
        }

        var validQuiz = false
        if let start = quizOutput.firstIndex(of: "{"),
           let end = quizOutput.lastIndex(of: "}") {
            let jsonStr = String(quizOutput[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["question"] != nil,
               (json["options"] as? [String])?.count == 4 {
                validQuiz = true
            }
        }
        recordTest("Quiz question generation", passed: validQuiz,
                   duration: Date().timeIntervalSince(start),
                   details: validQuiz ? "Valid JSON with 4 options" : "Invalid JSON output")

        // Test 4.5: Few-shot prompting
        start = Date()
        var fewShotOutput = ""
        if let container = llmContainer {
            let messages: [Chat.Message] = [
                .system("You create quiz questions following the examples."),
                .user("""
                Example 1:
                Text: "Python was created by Guido van Rossum in 1991."
                Question: {"question": "Who created Python?", "options": ["Guido van Rossum", "James Gosling", "Bjarne Stroustrup", "Dennis Ritchie"], "correctIndex": 0}

                Example 2:
                Text: "JavaScript was developed by Brendan Eich at Netscape in 1995."
                Question: {"question": "When was JavaScript developed?", "options": ["1995", "1991", "2000", "1989"], "correctIndex": 0}

                Now create a question:
                Text: "Machine learning is a subset of artificial intelligence."
                Question:
                """)
            ]
            let input = UserInput(chat: messages)

            try await container.perform { ctx in
                let prepared = try await ctx.processor.prepare(input: input)
                let params = GenerateParameters(maxTokens: 150, temperature: 0.7)
                for await item in try MLXLMCommon.generate(input: prepared, parameters: params, context: ctx) {
                    if case .chunk(let c) = item { fewShotOutput += c }
                }
            }
        }
        let followedFormat = fewShotOutput.contains("question") && fewShotOutput.contains("options")
        recordTest("Few-shot prompting", passed: followedFormat,
                   duration: Date().timeIntervalSince(start),
                   details: followedFormat ? "Followed example format" : "Did not follow format")

        print()
    } catch {
        recordTest("LLM generation", passed: false, duration: 0, details: error.localizedDescription)
    }

    // =========================================================================
    // TEST 5: Validation Service
    // =========================================================================
    print("✅ TEST 5: Validation Service")
    print("-".padding(toLength: 70, withPad: "-", startingAt: 0))

    do {
        var start = Date()

        // Test 5.1: JSON validation
        let validJSON = """
        {"question": "What is ML?", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "Test"}
        """
        let invalidJSON = """
        {"question": "Test", "options": ["A", "B"]}
        """

        func validateQuizJSON(_ json: String) -> (valid: Bool, reason: String) {
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (false, "Invalid JSON")
            }
            guard obj["question"] is String else { return (false, "Missing question") }
            guard let options = obj["options"] as? [String], options.count == 4 else { return (false, "Need 4 options") }
            guard obj["correctIndex"] is Int else { return (false, "Missing correctIndex") }
            return (true, "Valid")
        }

        let valid1 = validateQuizJSON(validJSON)
        let valid2 = validateQuizJSON(invalidJSON)
        recordTest("JSON structure validation", passed: valid1.valid && !valid2.valid,
                   duration: Date().timeIntervalSince(start))

        // Test 5.2: Self-containment check
        start = Date()
        func checkSelfContainment(_ question: String) -> (valid: Bool, issues: [String]) {
            var issues: [String] = []
            let vagueRefs = ["the author", "the text", "this passage", "the article", "according to"]
            for ref in vagueRefs {
                if question.lowercased().contains(ref) {
                    issues.append("Contains vague reference: '\(ref)'")
                }
            }
            let pronounStarts = ["he ", "she ", "it ", "they ", "this ", "that "]
            for p in pronounStarts {
                if question.lowercased().hasPrefix(p) {
                    issues.append("Starts with undefined pronoun")
                }
            }
            return (issues.isEmpty, issues)
        }

        let good = checkSelfContainment("What year did Newton publish Principia Mathematica?")
        let bad = checkSelfContainment("According to the text, what did he discover?")
        recordTest("Self-containment validation", passed: good.valid && !bad.valid,
                   duration: Date().timeIntervalSince(start))

        // Test 5.3: Option quality check
        start = Date()
        func checkOptionQuality(_ options: [String]) -> (valid: Bool, issues: [String]) {
            var issues: [String] = []
            if Set(options).count != options.count { issues.append("Duplicate options") }
            if options.contains(where: { $0.count < 2 }) { issues.append("Option too short") }
            let placeholders = ["option1", "option2", "...", "answer"]
            for opt in options {
                if placeholders.contains(where: { opt.lowercased().contains($0) }) {
                    issues.append("Contains placeholder")
                }
            }
            return (issues.isEmpty, issues)
        }

        let goodOpts = checkOptionQuality(["Paris", "London", "Berlin", "Madrid"])
        let badOpts = checkOptionQuality(["A", "A", "B", "..."])
        recordTest("Option quality validation", passed: goodOpts.valid && !badOpts.valid,
                   duration: Date().timeIntervalSince(start))

        print()
    } catch {
        recordTest("Validation service", passed: false, duration: 0, details: error.localizedDescription)
    }

    // =========================================================================
    // SUMMARY
    // =========================================================================
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
    print("  TEST SUMMARY")
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))

    let passed = testResults.filter { $0.passed }.count
    let total = testResults.count
    let percentage = Int(Float(passed) / Float(total) * 100)

    print()
    print("   Total:  \(total) tests")
    print("   Passed: \(passed) ✅")
    print("   Failed: \(total - passed) ❌")
    print("   Score:  \(percentage)%")
    print()

    if total - passed > 0 {
        print("   Failed tests:")
        for result in testResults.filter({ !$0.passed }) {
            print("   • \(result.name): \(result.details)")
        }
    }

    print()
    print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))

    // Cleanup
    cleanup()
}

// Entry point
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runEndpointTests()
    semaphore.signal()
}
semaphore.wait()

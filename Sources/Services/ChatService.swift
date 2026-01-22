import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Service for LLM chat and generation with RAG support
actor ChatService {
    private let projectPath: URL
    private var modelContainer: ModelContainer?
    private var modelConfig: ModelConfiguration?
    private var searchService: SearchService?
    private let rerankingService = RerankingService()

    init(projectPath: URL) {
        self.projectPath = projectPath
        self.searchService = SearchService(projectPath: projectPath)
    }

    // MARK: - RAG Generation

    /// Generate response with automatic retrieval (RAG)
    func generateWithRAG(query: String, topK: Int = 5, useMultiHop: Bool = false, onProgress: ((GenerationProgress) -> Void)? = nil) async throws -> String {
        let context: [String]

        if useMultiHop {
            // Multi-hop retrieval for complex questions
            context = try await multiHopRetrieval(query: query, maxHops: 2, topK: topK)
        } else {
            // Standard single-hop retrieval with reranking
            let searchResults = try await searchService?.search(query: query, topK: topK * 2) ?? []
            let reranked = await rerankingService.rerank(query: query, results: searchResults, topK: topK)
            context = reranked.map { formatResult($0) }
        }

        // Generate with context
        return try await generate(query: query, context: context, onProgress: onProgress)
    }

    // MARK: - Multi-Hop Retrieval

    /// Iteratively retrieves context for complex questions
    private func multiHopRetrieval(query: String, maxHops: Int, topK: Int) async throws -> [String] {
        var allContext: [String] = []
        var seenIds = Set<String>()

        // First hop: Use query expansion for better initial recall
        let queryVariants = QueryExpander.generateVariants(query: query)
        var currentQuery = query

        for hop in 0..<maxHops {
            // Use expanded query on first hop
            let searchQuery = hop == 0 ? QueryExpander.expand(query: currentQuery) : currentQuery

            // Retrieve for current query (fetch more candidates for reranking)
            let results = try await searchService?.search(query: searchQuery, topK: topK * 2) ?? []
            let reranked = await rerankingService.rerank(query: currentQuery, results: results, topK: topK)

            // Add new unique results
            for result in reranked {
                let id = "\(result.source):\(result.text.prefix(50))"
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    allContext.append(formatResult(result))
                }
            }

            // For subsequent hops, extract sub-questions from the context
            if hop < maxHops - 1 && !allContext.isEmpty {
                let subQuery = extractFollowUpQuery(originalQuery: query, context: allContext)
                if subQuery != currentQuery {
                    currentQuery = subQuery
                } else {
                    break // No new direction to explore
                }
            }
        }

        // If first hop didn't get enough results, try query variants
        if allContext.count < topK && queryVariants.count > 1 {
            for variant in queryVariants.dropFirst() {
                let results = try await searchService?.search(query: variant, topK: topK) ?? []
                for result in results {
                    let id = "\(result.source):\(result.text.prefix(50))"
                    if !seenIds.contains(id) {
                        seenIds.insert(id)
                        allContext.append(formatResult(result))
                    }
                    if allContext.count >= topK * 2 { break }
                }
                if allContext.count >= topK * 2 { break }
            }
        }

        return allContext
    }

    /// Extract follow-up query from context for multi-hop retrieval
    private func extractFollowUpQuery(originalQuery: String, context: [String]) -> String {
        // Simple heuristic: look for related terms or references in context
        // that might need additional context
        let combinedContext = context.joined(separator: " ")
        let words = combinedContext.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 4 }

        // Find frequent terms not in original query
        var termFreq: [String: Int] = [:]
        let queryWords = Set(originalQuery.lowercased().components(separatedBy: .whitespaces))
        for word in words {
            if !queryWords.contains(word) && !stopWords.contains(word) {
                termFreq[word, default: 0] += 1
            }
        }

        // Get top terms to expand query
        let topTerms = termFreq.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        if topTerms.isEmpty {
            return originalQuery
        }

        return originalQuery + " " + topTerms.joined(separator: " ")
    }

    // Common stop words to filter out
    private let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "have", "has",
        "been", "were", "was", "are", "will", "would", "could", "should",
        "their", "there", "they", "them", "these", "those", "which", "what",
        "when", "where", "about", "into", "over", "also", "more", "some",
        "such", "than", "then", "only", "other", "being", "made", "many"
    ]

    /// Format a search result with metadata for context
    private func formatResult(_ result: SearchResult) -> String {
        var ctx = result.text
        if let meta = result.metadata {
            if let chapter = meta.chapter { ctx = "[\(chapter)] " + ctx }
            if let section = meta.section { ctx = "[\(section)] " + ctx }
        }
        return ctx
    }

    /// Initialize search service (call after model is loaded)
    func initializeSearch(embeddingModelId: String = "mlx-community/bge-small-en-v1.5-4bit") async throws {
        try await searchService?.loadEmbeddingModel(modelId: embeddingModelId)
    }

    /// Build embedding index for chunks
    func buildSearchIndex(onProgress: ((String) -> Void)? = nil) async throws {
        try await searchService?.buildEmbeddingIndex(onProgress: onProgress)
    }

    /// Check if embeddings are available
    var hasEmbeddings: Bool {
        get async {
            await searchService?.hasEmbeddings ?? false
        }
    }

    func loadModel() async throws {
        let configPath = projectPath.appendingPathComponent("librarian.json")
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(AppProjectConfig.self, from: data)

        modelConfig = ModelConfiguration(id: config.model)
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfig!)
    }

    func generate(query: String, context: [String], onProgress: ((GenerationProgress) -> Void)? = nil) async throws -> String {
        guard let container = modelContainer else {
            throw ServiceError.modelNotLoaded
        }

        let contextText = context.isEmpty ? "" : """
        Use the following context to answer the question:

        \(context.joined(separator: "\n\n"))

        ---
        """

        let messages: [Chat.Message] = [
            .system("""
            You are a knowledgeable research assistant. Answer questions based on the provided context.
            If the context doesn't contain relevant information, say so and provide general knowledge.
            Be concise and accurate.
            """),
            .user(contextText + "\nQuestion: " + query)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""
        var tokenCount = 0
        let startTime = Date()

        // Report preparing stage
        onProgress?(GenerationProgress(tokensGenerated: 0, tokensPerSecond: 0, elapsedTime: 0, stage: .preparing))

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 512, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                switch item {
                case .chunk(let chunk):
                    output += chunk
                    tokenCount += 1
                    let elapsed = Date().timeIntervalSince(startTime)
                    let tokensPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                    onProgress?(GenerationProgress(
                        tokensGenerated: tokenCount,
                        tokensPerSecond: tokensPerSec,
                        elapsedTime: elapsed,
                        stage: .generating
                    ))
                case .info, .toolCall:
                    break
                }
            }
        }

        // Report finishing stage
        let elapsed = Date().timeIntervalSince(startTime)
        onProgress?(GenerationProgress(tokensGenerated: tokenCount, tokensPerSecond: Double(tokenCount) / elapsed, elapsedTime: elapsed, stage: .finishing))

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateFlashcards(count: Int) async throws -> [Flashcard] {
        guard let container = modelContainer else {
            throw ServiceError.modelNotLoaded
        }

        // Load chunks
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        guard FileManager.default.fileExists(atPath: chunksPath.path) else {
            return []
        }

        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        guard !chunks.isEmpty else { return [] }

        // Select random chunks
        let selectedChunks = chunks.shuffled().prefix(min(3, chunks.count))
        let chunkText = selectedChunks.map { $0.text }.joined(separator: "\n\n")

        let messages: [Chat.Message] = [
            .system("You are a helpful assistant that creates educational flashcards."),
            .user("""
            Create \(count) flashcards from this text. Each flashcard should have a question and answer.
            Output as JSON array: [{"question": "...", "answer": "..."}]

            Text:
            \(chunkText)
            """)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                }
            }
        }

        // Parse JSON
        guard let start = output.firstIndex(of: "["),
              let end = output.lastIndex(of: "]") else {
            return []
        }

        let jsonStr = String(output[start...end])
        guard let jsonData = jsonStr.data(using: .utf8) else { return [] }

        struct RawFlashcard: Codable {
            let question: String
            let answer: String
        }

        let raw = try JSONDecoder().decode([RawFlashcard].self, from: jsonData)
        return raw.map { Flashcard(question: $0.question, answer: $0.answer, source: selectedChunks.first?.source ?? "") }
    }

    func generateQuiz(count: Int, difficulty: QuizDifficulty, sources: [String]? = nil, onProgress: ((QuizGenerationProgress) -> Void)? = nil) async throws -> [QuizQuestion] {
        guard let container = modelContainer else {
            throw ServiceError.modelNotLoaded
        }

        // Load chunks
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        guard FileManager.default.fileExists(atPath: chunksPath.path) else {
            return []
        }

        let data = try Data(contentsOf: chunksPath)
        var chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        guard !chunks.isEmpty else { return [] }

        // Filter by sources if specified
        if let sources = sources, !sources.isEmpty {
            chunks = chunks.filter { sources.contains($0.source) }
        }

        guard !chunks.isEmpty else { return [] }

        // Generate one question per chunk for variety
        let selectedChunks = Array(chunks.shuffled().prefix(min(count, chunks.count)))
        var questions: [QuizQuestion] = []
        let totalQuestions = selectedChunks.count

        // Few-shot examples for each difficulty level
        let fewShotExamples = getFewShotExamples(difficulty: difficulty)

        // Difficulty-specific chain-of-thought guidance
        let chainOfThought = getChainOfThoughtPrompt(difficulty: difficulty)

        for (index, chunk) in selectedChunks.enumerated() {
            // Report progress
            onProgress?(QuizGenerationProgress(
                currentQuestion: index + 1,
                totalQuestions: totalQuestions,
                stage: .generating
            ))

            // Generate with validation and retry logic
            if let question = try await generateWithRetry(
                container: container,
                chunk: chunk,
                fewShotExamples: fewShotExamples,
                chainOfThought: chainOfThought,
                maxRetries: 2 // Try up to 2 times if validation fails
            ) {
                questions.append(question)
            }
        }

        // Report completion
        onProgress?(QuizGenerationProgress(
            currentQuestion: totalQuestions,
            totalQuestions: totalQuestions,
            stage: .complete
        ))

        return questions
    }

    // MARK: - Few-Shot Examples

    private func getFewShotExamples(difficulty: QuizDifficulty) -> String {
        switch difficulty {
        case .easy:
            return """
            Example 1:
            Text: "The Silk Road was an ancient network of trade routes connecting East and West, established during the Han Dynasty around 130 BCE."
            Question: {"question": "When was the Silk Road established?", "options": ["130 BCE", "500 CE", "1200 CE", "50 BCE"], "correctIndex": 0, "explanation": "The Silk Road was established during the Han Dynasty around 130 BCE."}

            Example 2:
            Text: "Marco Polo was a Venetian merchant who traveled to China in the 13th century and wrote about his experiences."
            Question: {"question": "What was Marco Polo's profession?", "options": ["Merchant", "Soldier", "Priest", "Scholar"], "correctIndex": 0, "explanation": "Marco Polo was a Venetian merchant who traveled to China."}
            """
        case .medium:
            return """
            Example 1:
            Text: "The Tang Dynasty is considered a golden age of Chinese civilization, known for its advances in art, poetry, and technology."
            Question: {"question": "Why is the Tang Dynasty considered a golden age of Chinese civilization?", "options": ["Advances in art, poetry, and technology", "Military conquests across Asia", "Establishment of paper currency", "Development of gunpowder weapons"], "correctIndex": 0, "explanation": "The Tang Dynasty is known for its advances in art, poetry, and technology."}

            Example 2:
            Text: "Confucianism emphasizes filial piety, respect for elders, and social harmony, which influenced Chinese governance for centuries."
            Question: {"question": "Which philosophical tradition emphasized filial piety and social harmony in Chinese governance?", "options": ["Confucianism", "Daoism", "Legalism", "Buddhism"], "correctIndex": 0, "explanation": "Confucianism emphasizes filial piety, respect for elders, and social harmony."}
            """
        case .hard:
            return """
            Example 1:
            Text: "The examination system in imperial China was both a tool for social mobility and a mechanism for reinforcing Confucian orthodoxy."
            Question: {"question": "How did the imperial examination system serve dual purposes in Chinese society?", "options": ["It enabled social mobility while reinforcing Confucian orthodoxy", "It trained soldiers while spreading Buddhism", "It promoted trade while limiting foreign influence", "It centralized power while encouraging regional autonomy"], "correctIndex": 0, "explanation": "The examination system allowed talented individuals to rise socially while ensuring Confucian values remained dominant."}

            Example 2:
            Text: "The One-Child Policy, implemented in 1979, aimed to curb population growth but led to demographic imbalances and aging population concerns."
            Question: {"question": "What unintended demographic consequences emerged from China's One-Child Policy implemented in 1979?", "options": ["Gender imbalance and aging population", "Rural depopulation and urbanization", "Ethnic minority decline and cultural loss", "Economic stagnation and unemployment"], "correctIndex": 0, "explanation": "The One-Child Policy led to demographic imbalances including gender imbalance and an aging population."}
            """
        }
    }

    // MARK: - Chain-of-Thought Prompting

    private func getChainOfThoughtPrompt(difficulty: QuizDifficulty) -> String {
        switch difficulty {
        case .easy:
            return """
            Think step by step:
            1. Identify the main FACT in the text (a date, name, place, or definition)
            2. Create a direct question asking about that fact
            3. The correct answer should be stated explicitly in the text
            4. Create 3 plausible but incorrect options of the SAME TYPE
            """
        case .medium:
            return """
            Think step by step:
            1. Identify the main CONCEPT or RELATIONSHIP in the text
            2. Create a question that tests understanding, not just recall
            3. The answer should require connecting ideas from the text
            4. Create 3 plausible alternatives that represent common misconceptions
            """
        case .hard:
            return """
            Think step by step:
            1. Identify the IMPLICATIONS or ANALYSIS possible from the text
            2. Create a question requiring synthesis or evaluation
            3. The answer should require inferring beyond what's explicitly stated
            4. Create 3 alternatives that are partially correct or represent sophisticated misunderstandings
            """
        }
    }

    // MARK: - Best-of-N Generation

    private func generateQuestionCandidates(
        container: ModelContainer,
        chunk: ChunkData,
        fewShotExamples: String,
        chainOfThought: String,
        numCandidates: Int
    ) async throws -> [QuizQuestion] {
        var candidates: [QuizQuestion] = []

        for _ in 0..<numCandidates {
            let messages: [Chat.Message] = [
                .system("""
                You create educational multiple choice questions. Follow these rules:
                1. SELF-CONTAINED: Include all context in the question itself
                2. SPECIFIC: Name all people, places, events explicitly
                3. CONSISTENT: Question type must match answer type
                4. FOUR OPTIONS: All options must be the same type

                \(fewShotExamples)
                """),
                .user("""
                \(chainOfThought)

                Now create a question from this text.

                Text from "\(chunk.source)":
                \(chunk.text.prefix(800))

                Output ONLY valid JSON:
                {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
                """)
            ]

            let userInput = UserInput(chat: messages)
            var output = ""

            try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let parameters = GenerateParameters(maxTokens: 512, temperature: 0.8)

                for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                    if case .chunk(let c) = item {
                        output += c
                    }
                }
            }

            // Parse the output
            if let question = parseQuizOutput(output: output, source: chunk.source) {
                candidates.append(question)
            }
        }

        return candidates
    }

    private func parseQuizOutput(output: String, source: String) -> QuizQuestion? {
        var cleanOutput = output
        if cleanOutput.contains("```") {
            cleanOutput = cleanOutput
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        // Try parsing as single object
        guard let start = cleanOutput.firstIndex(of: "{"),
              let end = cleanOutput.lastIndex(of: "}") else {
            return nil
        }

        let jsonStr = String(cleanOutput[start...end])
        guard let jsonData = jsonStr.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawQ.self, from: jsonData) else {
            return nil
        }

        // Validate
        let placeholders = ["option1", "option2", "option3", "option4", "...", "answer1", "answer2"]
        guard raw.options.count == 4,
              Set(raw.options).count == 4,
              !raw.options.contains(where: { placeholders.contains($0.lowercased()) }),
              raw.options.allSatisfy({ $0.count > 1 }) else {
            return nil
        }

        // Shuffle options
        var shuffledOptions = raw.options.enumerated().map { ($0.offset, $0.element) }
        shuffledOptions.shuffle()
        let newCorrectIndex = shuffledOptions.firstIndex { $0.0 == raw.correctIndex } ?? 0

        return QuizQuestion(
            question: raw.question,
            options: shuffledOptions.map { $0.1 },
            correctIndex: newCorrectIndex,
            source: source,
            explanation: raw.explanation ?? "The correct answer is based on the source material."
        )
    }

    // MARK: - Candidate Selection & Validation

    private func selectBestCandidate(candidates: [QuizQuestion], chunk: ChunkData) -> QuizQuestion? {
        guard !candidates.isEmpty else { return nil }

        // Filter candidates that pass validation
        let validCandidates = candidates.filter { validateQuestion($0).isValid }

        guard !validCandidates.isEmpty else {
            // If no candidates pass validation, return the original best with warnings
            return candidates.first
        }

        if validCandidates.count == 1 { return validCandidates[0] }

        // Score each valid candidate
        var scored = validCandidates.map { candidate -> (question: QuizQuestion, score: Float) in
            var score: Float = 0

            // 1. Question length (prefer medium length)
            let qLen = candidate.question.count
            if qLen >= 30 && qLen <= 150 {
                score += 2
            } else if qLen >= 20 && qLen <= 200 {
                score += 1
            }

            // 2. Self-containment score from validation
            let validation = validateQuestion(candidate)
            score += Float(validation.selfContainmentScore) * 2

            // 3. Option quality (all options should have similar length)
            let optLengths = candidate.options.map { $0.count }
            let avgLen = Float(optLengths.reduce(0, +)) / Float(optLengths.count)
            let variance = optLengths.map { pow(Float($0) - avgLen, 2) }.reduce(0, +) / Float(optLengths.count)
            if variance < 100 {
                score += 2
            } else if variance < 400 {
                score += 1
            }

            // 4. Explanation quality
            if candidate.explanation.count >= 20 {
                score += 1
            }

            // 5. Question contains specific terms from chunk
            let chunkWords = Set(chunk.text.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 5 })
            let questionWords = Set(candidate.question.lowercased().components(separatedBy: .whitespaces))
            let overlap = chunkWords.intersection(questionWords).count
            score += Float(min(overlap, 3))

            return (candidate, score)
        }

        scored.sort { $0.score > $1.score }
        return scored.first?.question
    }

    // MARK: - Question Validation

    struct ValidationResult {
        let isValid: Bool
        let selfContainmentScore: Int // 0-5
        let issues: [String]
    }

    private func validateQuestion(_ question: QuizQuestion) -> ValidationResult {
        var issues: [String] = []
        var selfContainmentScore = 5

        // 1. Structure checks
        if question.options.count != 4 {
            issues.append("Must have exactly 4 options")
        }

        if question.correctIndex < 0 || question.correctIndex >= question.options.count {
            issues.append("correctIndex out of bounds")
        }

        if Set(question.options).count != question.options.count {
            issues.append("Duplicate options detected")
        }

        if question.question.count < 15 {
            issues.append("Question too short")
        }

        // 2. Self-containment checks
        let vagueReferences = [
            "the author", "the writer", "this text", "the passage",
            "the article", "the document", "according to the text",
            "in the reading", "the above", "mentioned above"
        ]
        let questionLower = question.question.lowercased()
        for vague in vagueReferences {
            if questionLower.contains(vague) {
                issues.append("Contains vague reference: '\(vague)'")
                selfContainmentScore -= 1
            }
        }

        // 3. Check for undefined pronouns at start
        let pronounStarts = ["he ", "she ", "they ", "it ", "this ", "that ", "these ", "those "]
        for pronoun in pronounStarts {
            if questionLower.hasPrefix(pronoun) {
                issues.append("Starts with undefined pronoun")
                selfContainmentScore -= 2
                break
            }
        }

        // 4. Check for specific named entities (good sign)
        let hasCapitalizedWord = question.question.contains { $0.isUppercase }
        if !hasCapitalizedWord {
            selfContainmentScore -= 1
        }

        // 5. Option type consistency
        let optionTypes = question.options.map { classifyOptionType($0) }
        let uniqueTypes = Set(optionTypes)
        if uniqueTypes.count > 1 && !uniqueTypes.contains(.mixed) {
            issues.append("Options are not all the same type")
        }

        // 6. Check for placeholder text
        let placeholders = ["...", "[", "]", "option", "answer", "example"]
        for opt in question.options {
            for placeholder in placeholders {
                if opt.lowercased().contains(placeholder) {
                    issues.append("Option contains placeholder text")
                    break
                }
            }
        }

        selfContainmentScore = max(0, selfContainmentScore)
        let isValid = issues.filter { !$0.contains("vague") && !$0.contains("pronoun") }.isEmpty

        return ValidationResult(
            isValid: isValid,
            selfContainmentScore: selfContainmentScore,
            issues: issues
        )
    }

    private enum OptionType {
        case year
        case number
        case name
        case phrase
        case mixed
    }

    private func classifyOptionType(_ option: String) -> OptionType {
        let trimmed = option.trimmingCharacters(in: .whitespaces)

        // Check if it's a year (4 digits, optionally with BCE/CE/AD/BC)
        let yearPattern = #"^\d{4}\s*(BCE|CE|AD|BC)?$"#
        if trimmed.range(of: yearPattern, options: .regularExpression) != nil {
            return .year
        }

        // Check if it's a pure number
        if Int(trimmed) != nil || Double(trimmed) != nil {
            return .number
        }

        // Check if it's likely a name (starts with capital, 1-4 words)
        let words = trimmed.split(separator: " ")
        if words.count <= 4 && words.allSatisfy({ $0.first?.isUppercase == true }) {
            return .name
        }

        return .phrase
    }

    // MARK: - Training Data Export

    /// Generate and export validated questions as training data
    func exportQuestionsForTraining(
        count: Int,
        difficulty: QuizDifficulty,
        outputPath: URL,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> Int {
        onProgress?("Generating questions...")

        // Generate questions with validation
        let questions = try await generateQuiz(count: count, difficulty: difficulty, onProgress: nil)

        onProgress?("Generated \(questions.count) validated questions")

        // Load chunks for context
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        // Export to training format
        let generator = QuizTrainingDataGenerator(projectPath: projectPath)
        let exportedCount = try generator.exportTrainingData(
            questions: questions,
            chunks: chunks,
            outputPath: outputPath
        )

        onProgress?("Exported \(exportedCount) training examples")

        return exportedCount
    }

    /// Prepare training data by generating questions across all difficulties
    func prepareFullTrainingSet(
        questionsPerDifficulty: Int,
        outputDir: URL,
        onProgress: ((String) -> Void)? = nil
    ) async throws {
        let allPath = outputDir.appendingPathComponent("quiz_training_all.jsonl")
        let trainPath = outputDir.appendingPathComponent("quiz_training_train.jsonl")
        let validPath = outputDir.appendingPathComponent("quiz_training_valid.jsonl")

        var allQuestions: [QuizQuestion] = []

        // Generate questions for each difficulty
        for difficulty in QuizDifficulty.allCases {
            onProgress?("Generating \(difficulty.rawValue) questions...")
            let questions = try await generateQuiz(
                count: questionsPerDifficulty,
                difficulty: difficulty,
                onProgress: nil
            )
            allQuestions.append(contentsOf: questions)
            onProgress?("Generated \(questions.count) \(difficulty.rawValue) questions")
        }

        // Load chunks
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        // Export all questions
        let generator = QuizTrainingDataGenerator(projectPath: projectPath)
        let exportedCount = try generator.exportTrainingData(
            questions: allQuestions,
            chunks: chunks,
            outputPath: allPath
        )

        onProgress?("Exported \(exportedCount) total training examples")

        // Split into train/validation
        try generator.splitTrainingData(
            inputPath: allPath,
            trainPath: trainPath,
            validPath: validPath,
            validationRatio: 0.1
        )

        onProgress?("Split into train/validation sets")
        onProgress?("Training data ready at: \(outputDir.path)")
    }

    // MARK: - Retry Logic

    private func generateWithRetry(
        container: ModelContainer,
        chunk: ChunkData,
        fewShotExamples: String,
        chainOfThought: String,
        maxRetries: Int = 3
    ) async throws -> QuizQuestion? {
        for attempt in 0..<maxRetries {
            let candidates = try await generateQuestionCandidates(
                container: container,
                chunk: chunk,
                fewShotExamples: fewShotExamples,
                chainOfThought: chainOfThought,
                numCandidates: attempt == 0 ? 2 : 1 // More candidates on first try
            )

            // Check if any candidate passes validation
            for candidate in candidates {
                let validation = validateQuestion(candidate)
                if validation.isValid && validation.selfContainmentScore >= 3 {
                    return candidate
                }
            }

            // If we have candidates but none pass strict validation, use best one on last retry
            if attempt == maxRetries - 1 && !candidates.isEmpty {
                return selectBestCandidate(candidates: candidates, chunk: chunk)
            }
        }

        return nil
    }

    func getAvailableSources() throws -> [String] {
        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        guard FileManager.default.fileExists(atPath: chunksPath.path) else {
            return []
        }

        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        return Array(Set(chunks.map { $0.source })).sorted()
    }

    // MARK: - Open-Ended Questions

    func generateOpenEndedQuiz(count: Int, difficulty: QuizDifficulty, sources: [String]? = nil, onProgress: ((QuizGenerationProgress) -> Void)? = nil) async throws -> [OpenEndedQuestion] {
        guard let container = modelContainer else {
            throw ServiceError.modelNotLoaded
        }

        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        guard FileManager.default.fileExists(atPath: chunksPath.path) else {
            return []
        }

        let data = try Data(contentsOf: chunksPath)
        var chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        guard !chunks.isEmpty else { return [] }

        if let sources = sources, !sources.isEmpty {
            chunks = chunks.filter { sources.contains($0.source) }
        }

        guard !chunks.isEmpty else { return [] }

        let selectedChunks = Array(chunks.shuffled().prefix(min(count, chunks.count)))
        var questions: [OpenEndedQuestion] = []
        let totalQuestions = selectedChunks.count

        let difficultyPrompt: String
        switch difficulty {
        case .easy:
            difficultyPrompt = "Create an EASY question - ask about a basic fact or definition that can be answered in 1-2 sentences."
        case .medium:
            difficultyPrompt = "Create a MEDIUM question - ask about relationships between concepts or require explanation."
        case .hard:
            difficultyPrompt = "Create a HARD question - require analysis, comparison, or synthesis of multiple ideas."
        }

        for (index, chunk) in selectedChunks.enumerated() {
            // Report progress
            onProgress?(QuizGenerationProgress(
                currentQuestion: index + 1,
                totalQuestions: totalQuestions,
                stage: .generating
            ))

            let messages: [Chat.Message] = [
                .system("""
                You create open-ended study questions. Output valid JSON only.
                Questions must be SELF-CONTAINED - include all necessary context so someone who hasn't read the source can understand what's being asked.
                NEVER use vague references like "the author", "the organization", "the theory" - always name them specifically.
                """),
                .user("""
                \(difficultyPrompt)

                Create an open-ended question (not multiple choice) from this text.
                Include the ideal answer that a student should provide.

                CRITICAL: Questions must be specific and self-contained.
                - BAD: "What does the author argue about society?" (vague)
                - GOOD: "What does Wang Huning argue about American individualism in 'America Against America'?" (specific)

                Example:
                {"question": "Explain the significance of the Silk Road in facilitating cultural exchange between China and Rome.", "idealAnswer": "The Silk Road was a network of trade routes connecting East and West, facilitating exchange of goods, culture, and ideas for over 1,500 years.", "keyPoints": ["trade routes", "East-West connection", "cultural exchange"]}

                Text from "\(chunk.source)":
                \(chunk.text.prefix(800))

                JSON:
                """)
            ]

            let userInput = UserInput(chat: messages)
            var output = ""

            try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let parameters = GenerateParameters(maxTokens: 4096, temperature: 0.8)

                for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                    if case .chunk(let chunk) = item {
                        output += chunk
                    }
                }
            }

            // Parse JSON
            var cleanOutput = output
            if cleanOutput.contains("```") {
                cleanOutput = cleanOutput
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let start = cleanOutput.firstIndex(of: "{"),
               let end = cleanOutput.lastIndex(of: "}") {
                let jsonStr = String(cleanOutput[start...end])
                if let jsonData = jsonStr.data(using: .utf8) {
                    struct RawOE: Codable {
                        let question: String
                        let idealAnswer: String
                        let keyPoints: [String]?
                    }

                    if let raw = try? JSONDecoder().decode(RawOE.self, from: jsonData) {
                        questions.append(OpenEndedQuestion(
                            question: raw.question,
                            idealAnswer: raw.idealAnswer,
                            keyPoints: raw.keyPoints ?? [],
                            source: chunk.source,
                            context: String(chunk.text.prefix(500))
                        ))
                    }
                }
            }
        }

        // Report completion
        onProgress?(QuizGenerationProgress(
            currentQuestion: totalQuestions,
            totalQuestions: totalQuestions,
            stage: .complete
        ))

        return questions
    }

    func discussAnswer(question: OpenEndedQuestion, userAnswer: String, previousMessages: [DiscussionMessage]) async throws -> String {
        guard let container = modelContainer else {
            throw ServiceError.modelNotLoaded
        }

        var chatHistory: [Chat.Message] = [
            .system("""
            You are a thoughtful study partner engaging in Socratic dialogue. Your role is to:
            - Acknowledge what the student got right
            - Gently probe areas they might have missed or misunderstood
            - Ask follow-up questions to deepen understanding
            - Provide hints rather than direct answers when they're stuck
            - Be encouraging and conversational, not lecturing
            - Keep responses concise (2-3 paragraphs max)

            Context from their study material:
            \(question.context)

            The discussion topic: \(question.question)
            Key concepts to explore: \(question.keyPoints.joined(separator: ", "))
            """)
        ]

        // Add previous discussion messages
        for msg in previousMessages {
            if msg.isUser {
                chatHistory.append(.user(msg.content))
            } else {
                chatHistory.append(.assistant(msg.content))
            }
        }

        // Add current user message
        chatHistory.append(.user(userAnswer))

        let userInput = UserInput(chat: chatHistory)
        var output = ""

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChunkData: Codable {
    let id: String
    let text: String
    let source: String
    let title: String
    let author: String
    let index: Int
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
    let correctIndex: Int
    let source: String
    var explanation: String = ""
    var userAnswer: Int? = nil
}

struct OpenEndedQuestion: Identifiable {
    let id = UUID()
    let question: String
    let idealAnswer: String
    let keyPoints: [String]
    let source: String
    let context: String
    var discussion: [DiscussionMessage] = []
    var isComplete: Bool = false
}

struct DiscussionMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date = Date()
}

enum QuizDifficulty: String, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

enum QuizType: String, CaseIterable {
    case multipleChoice = "Multiple Choice"
    case openEnded = "Open Ended"
}

struct AppProjectConfig: Codable {
    let name: String
    let model: String
    let embeddingModel: String

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case embeddingModel = "embedding_model"
    }
}

struct QuizGenerationProgress {
    let currentQuestion: Int
    let totalQuestions: Int
    let stage: QuizGenerationStage

    enum QuizGenerationStage: String {
        case preparing = "Preparing..."
        case generating = "Generating"
        case complete = "Complete"
    }

    var displayText: String {
        switch stage {
        case .preparing:
            return stage.rawValue
        case .generating:
            return "Generating question \(currentQuestion) of \(totalQuestions)"
        case .complete:
            return "Complete!"
        }
    }

    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentQuestion) / Double(totalQuestions)
    }
}

enum ServiceError: Error {
    case modelNotLoaded
    case projectNotFound
}

// MARK: - Training Data Generation

/// Generates training data from validated quiz questions for fine-tuning
class QuizTrainingDataGenerator {
    private let projectPath: URL

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    /// Export validated questions as training data for fine-tuning
    func exportTrainingData(
        questions: [QuizQuestion],
        chunks: [ChunkData],
        outputPath: URL
    ) throws -> Int {
        var trainingLines: [String] = []

        for question in questions {
            // Find the corresponding chunk
            guard let chunk = chunks.first(where: { $0.source == question.source }) else {
                continue
            }

            // Create training example in conversation format
            let trainingExample = createTrainingExample(question: question, chunk: chunk)
            trainingLines.append(trainingExample)
        }

        // Write as JSONL
        let jsonlContent = trainingLines.joined(separator: "\n")
        try jsonlContent.write(to: outputPath, atomically: true, encoding: .utf8)

        return trainingLines.count
    }

    private func createTrainingExample(question: QuizQuestion, chunk: ChunkData) -> String {
        // Format as instruction-following conversation
        let systemPrompt = "You create educational multiple choice questions. Output valid JSON only."

        let userPrompt = """
        Create a multiple choice question from this text.

        Text from "\(chunk.source)":
        \(String(chunk.text.prefix(800)))

        Output JSON: {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
        """

        let assistantResponse = """
        {"question": "\(escapeJson(question.question))", "options": [\(question.options.map { "\"\(escapeJson($0))\"" }.joined(separator: ", "))], "correctIndex": \(question.correctIndex), "explanation": "\(escapeJson(question.explanation))"}
        """

        // Create the training text in chat format
        let trainingText = """
        <|system|>
        \(systemPrompt)<|end|>
        <|user|>
        \(userPrompt)<|end|>
        <|assistant|>
        \(assistantResponse)<|end|>
        """

        // Wrap in JSON for training
        let jsonLine = ["text": trainingText]
        if let jsonData = try? JSONEncoder().encode(jsonLine),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return ""
    }

    private func escapeJson(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Split data into train/validation sets
    func splitTrainingData(
        inputPath: URL,
        trainPath: URL,
        validPath: URL,
        validationRatio: Double = 0.1
    ) throws {
        let content = try String(contentsOf: inputPath, encoding: .utf8)
        var lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        lines.shuffle()

        let validCount = max(1, Int(Double(lines.count) * validationRatio))
        let validLines = Array(lines.prefix(validCount))
        let trainLines = Array(lines.dropFirst(validCount))

        try trainLines.joined(separator: "\n").write(to: trainPath, atomically: true, encoding: .utf8)
        try validLines.joined(separator: "\n").write(to: validPath, atomically: true, encoding: .utf8)
    }

    /// Load and validate existing training data
    func validateTrainingData(path: URL) throws -> (valid: Int, invalid: Int) {
        let content = try String(contentsOf: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var valid = 0
        var invalid = 0

        for line in lines {
            if let data = line.data(using: .utf8),
               let json = try? JSONDecoder().decode([String: String].self, from: data),
               let text = json["text"],
               text.contains("<|assistant|>") && text.contains("<|end|>") {
                valid += 1
            } else {
                invalid += 1
            }
        }

        return (valid, invalid)
    }
}

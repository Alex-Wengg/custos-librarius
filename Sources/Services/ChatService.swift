import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Service for LLM chat and generation
actor ChatService {
    private let projectPath: URL
    private var modelContainer: ModelContainer?
    private var modelConfig: ModelConfiguration?

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    func loadModel() async throws {
        let configPath = projectPath.appendingPathComponent("librarian.json")
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(AppProjectConfig.self, from: data)

        modelConfig = ModelConfiguration(id: config.model)
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfig!)
    }

    func generate(query: String, context: [String]) async throws -> String {
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

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 512, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                switch item {
                case .chunk(let chunk):
                    output += chunk
                case .info, .toolCall:
                    break
                }
            }
        }

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

    func generateQuiz(count: Int, difficulty: QuizDifficulty, sources: [String]? = nil) async throws -> [QuizQuestion] {
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
        let selectedChunks = chunks.shuffled().prefix(min(count, chunks.count))
        var questions: [QuizQuestion] = []

        let difficultyPrompt: String
        switch difficulty {
        case .easy:
            difficultyPrompt = "Create an EASY question - focus on basic facts, definitions, or simple recall. The question should be straightforward."
        case .medium:
            difficultyPrompt = "Create a MEDIUM difficulty question - require understanding of concepts or relationships between ideas."
        case .hard:
            difficultyPrompt = "Create a HARD question - require deep analysis, inference, or connecting multiple concepts. Make wrong answers very plausible."
        }

        for chunk in selectedChunks {
            let messages: [Chat.Message] = [
                .system("""
                You create educational multiple choice questions. You MUST:
                1. Write a clear question about the text
                2. Provide exactly 4 answer options with REAL content from the text
                3. NEVER use placeholder text like "option1" or "option2"
                4. Each option must be a real, specific answer
                """),
                .user("""
                \(difficultyPrompt)

                Create a multiple choice question from this text.

                RULES:
                - Write 4 SPECIFIC answers using facts from the text
                - DO NOT write "option1", "option2" - use REAL answers
                - correctIndex is which option (0-3) is correct
                - explanation must be 1-2 sentences MAX

                Example:
                {"question": "What year was the treaty signed?", "options": ["1842", "1856", "1901", "1923"], "correctIndex": 0, "explanation": "The treaty was signed in 1842."}

                Text from "\(chunk.source)":
                \(chunk.text.prefix(800))

                JSON:
                """)
            ]

            let userInput = UserInput(chat: messages)
            var output = ""

            try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let parameters = GenerateParameters(maxTokens: 4096, temperature: 0.9)

                for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                    if case .chunk(let chunk) = item {
                        output += chunk
                    }
                }
            }

            // Parse JSON from LLM output
            var cleanOutput = output
            if cleanOutput.contains("```") {
                cleanOutput = cleanOutput
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Parse JSON - handle both object {...} and array [{...}]
            struct RawQ: Codable {
                let question: String
                let options: [String]
                let correctIndex: Int
                let explanation: String?
            }

            var rawQuestions: [RawQ] = []

            // Try parsing as array first
            if let start = cleanOutput.firstIndex(of: "["),
               let end = cleanOutput.lastIndex(of: "]") {
                let jsonStr = String(cleanOutput[start...end])
                if let jsonData = jsonStr.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode([RawQ].self, from: jsonData) {
                    rawQuestions = parsed
                }
            }

            // Try parsing as single object
            if rawQuestions.isEmpty,
               let start = cleanOutput.firstIndex(of: "{"),
               let end = cleanOutput.lastIndex(of: "}") {
                let jsonStr = String(cleanOutput[start...end])
                if let jsonData = jsonStr.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(RawQ.self, from: jsonData) {
                    rawQuestions = [parsed]
                }
            }

            // Validate and add questions
            let placeholders = ["option1", "option2", "option3", "option4", "option 1", "option 2", "option 3", "option 4", "...", "answer1", "answer2"]

            for raw in rawQuestions {
                if raw.options.count == 4,
                   Set(raw.options).count == 4,
                   !raw.options.contains(where: { placeholders.contains($0.lowercased()) }),
                   raw.options.allSatisfy({ $0.count > 1 }) {
                    // Shuffle options and track new correct index
                    var shuffledOptions = raw.options.enumerated().map { ($0.offset, $0.element) }
                    shuffledOptions.shuffle()
                    let newCorrectIndex = shuffledOptions.firstIndex { $0.0 == raw.correctIndex } ?? 0

                    let explanation = raw.explanation ?? "The correct answer is based on the source material."

                    questions.append(QuizQuestion(
                        question: raw.question,
                        options: shuffledOptions.map { $0.1 },
                        correctIndex: newCorrectIndex,
                        source: chunk.source,
                        explanation: explanation
                    ))
                }
            }
        }

        return questions
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

    func generateOpenEndedQuiz(count: Int, difficulty: QuizDifficulty, sources: [String]? = nil) async throws -> [OpenEndedQuestion] {
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

        let selectedChunks = chunks.shuffled().prefix(min(count, chunks.count))
        var questions: [OpenEndedQuestion] = []

        let difficultyPrompt: String
        switch difficulty {
        case .easy:
            difficultyPrompt = "Create an EASY question - ask about a basic fact or definition that can be answered in 1-2 sentences."
        case .medium:
            difficultyPrompt = "Create a MEDIUM question - ask about relationships between concepts or require explanation."
        case .hard:
            difficultyPrompt = "Create a HARD question - require analysis, comparison, or synthesis of multiple ideas."
        }

        for chunk in selectedChunks {
            let messages: [Chat.Message] = [
                .system("You create open-ended study questions. Output valid JSON only."),
                .user("""
                \(difficultyPrompt)

                Create an open-ended question (not multiple choice) from this text.
                Include the ideal answer that a student should provide.

                Example:
                {"question": "Explain the significance of the Silk Road in ancient trade.", "idealAnswer": "The Silk Road was a network of trade routes connecting East and West, facilitating exchange of goods, culture, and ideas for over 1,500 years.", "keyPoints": ["trade routes", "East-West connection", "cultural exchange"]}

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

enum ServiceError: Error {
    case modelNotLoaded
    case projectNotFound
}

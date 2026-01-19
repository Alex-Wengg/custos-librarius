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
                .system("You create educational multiple choice questions with explanations. Always provide 4 UNIQUE and SPECIFIC answer options."),
                .user("""
                \(difficultyPrompt)

                IMPORTANT RULES:
                - All 4 options must be DIFFERENT and SPECIFIC to the content
                - Use actual names, numbers, concepts from the text
                - The wrong answers should be plausible but clearly incorrect
                - Include a brief explanation of why the correct answer is right

                Output ONLY this JSON (no other text):
                {"question": "...", "options": ["option1", "option2", "option3", "option4"], "correctIndex": 0, "explanation": "..."}

                Text from "\(chunk.source)":
                \(chunk.text.prefix(800))
                """)
            ]

            let userInput = UserInput(chat: messages)
            var output = ""

            try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let parameters = GenerateParameters(maxTokens: 600, temperature: 0.9)

                for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                    if case .chunk(let chunk) = item {
                        output += chunk
                    }
                }
            }

            // Parse JSON
            if let start = output.firstIndex(of: "{"),
               let end = output.lastIndex(of: "}") {
                let jsonStr = String(output[start...end])
                if let jsonData = jsonStr.data(using: .utf8) {
                    struct RawQ: Codable {
                        let question: String
                        let options: [String]
                        let correctIndex: Int
                        let explanation: String?
                    }

                    if let raw = try? JSONDecoder().decode(RawQ.self, from: jsonData),
                       raw.options.count == 4,
                       Set(raw.options).count == 4 {
                        // Shuffle options and track new correct index
                        var shuffledOptions = raw.options.enumerated().map { ($0.offset, $0.element) }
                        shuffledOptions.shuffle()
                        let newCorrectIndex = shuffledOptions.firstIndex { $0.0 == raw.correctIndex } ?? 0

                        questions.append(QuizQuestion(
                            question: raw.question,
                            options: shuffledOptions.map { $0.1 },
                            correctIndex: newCorrectIndex,
                            source: chunk.source,
                            explanation: raw.explanation ?? "The correct answer is based on the source material."
                        ))
                    }
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

enum QuizDifficulty: String, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
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

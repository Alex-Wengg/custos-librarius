import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Generates high-quality training data using LOCAL Qwen model
/// Formats output for Qwen LoRA fine-tuning
actor TrainingDataGenerator {
    private let projectPath: URL
    private var modelContainer: ModelContainer?

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    // MARK: - Model Loading

    /// Load the local LLM model for generation
    func loadModel() async throws {
        let configPath = projectPath.appendingPathComponent("librarian.json")
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(AppProjectConfig.self, from: data)

        let modelConfig = ModelConfiguration(id: config.model)
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfig)
    }

    /// Use an existing model container (to avoid loading twice)
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Main Generation Pipeline

    /// Generate training data from chunks using LOCAL Qwen model
    func generateTrainingData(
        chunks: [SemanticChunk],
        targetCount: Int = 250,
        difficulties: [QuizDifficulty] = [.easy, .medium, .hard],
        onProgress: ((TrainingDataProgress) -> Void)? = nil
    ) async throws -> TrainingDataResult {
        guard let container = modelContainer else {
            throw TrainingDataError.modelNotLoaded
        }

        var allExamples: [TrainingExample] = []
        var errors: [String] = []

        // Use ALL chunks, generate 1-2 examples per chunk
        let shuffledChunks = chunks.shuffled()
        let totalChunks = shuffledChunks.count

        onProgress?(TrainingDataProgress(
            completed: 0,
            total: totalChunks,
            currentStatus: "Starting generation with local model...",
            examplesGenerated: 0
        ))

        for (index, chunk) in shuffledChunks.enumerated() {
            // Randomly select difficulty for variety
            let difficulty = difficulties.randomElement() ?? .medium

            do {
                let examples = try await generateExamplesFromChunk(
                    container: container,
                    chunk: chunk,
                    difficulty: difficulty,
                    count: 1 // Generate 1 example per chunk to cover all chunks
                )
                allExamples.append(contentsOf: examples)

                onProgress?(TrainingDataProgress(
                    completed: index + 1,
                    total: totalChunks,
                    currentStatus: "Generated \(allExamples.count) examples from \(index + 1)/\(totalChunks) chunks",
                    examplesGenerated: allExamples.count
                ))
            } catch {
                errors.append("Chunk \(chunk.id): \(error.localizedDescription)")

                // Continue on error, don't fail entire batch
                onProgress?(TrainingDataProgress(
                    completed: index + 1,
                    total: totalChunks,
                    currentStatus: "Error on chunk \(index + 1), continuing...",
                    examplesGenerated: allExamples.count
                ))
            }
        }

        // Deduplicate
        let uniqueExamples = deduplicateExamples(allExamples)

        onProgress?(TrainingDataProgress(
            completed: totalChunks,
            total: totalChunks,
            currentStatus: "Complete! \(uniqueExamples.count) unique examples from \(totalChunks) chunks",
            examplesGenerated: uniqueExamples.count
        ))

        return TrainingDataResult(
            examples: uniqueExamples,
            totalGenerated: allExamples.count,
            duplicatesRemoved: allExamples.count - uniqueExamples.count,
            errors: errors
        )
    }

    // MARK: - Local Model Generation

    private func generateExamplesFromChunk(
        container: ModelContainer,
        chunk: SemanticChunk,
        difficulty: QuizDifficulty,
        count: Int
    ) async throws -> [TrainingExample] {
        var examples: [TrainingExample] = []

        for _ in 0..<count {
            let prompt = buildPrompt(chunk: chunk, difficulty: difficulty)

            let messages: [Chat.Message] = [
                .system("""
                You are an expert quiz creator. Create high-quality multiple choice questions following these STRICT rules:

                QUESTION RULES:
                1. SELF-CONTAINED: The question must make sense without seeing the source text
                2. SPECIFIC: Name all people, places, events, dates explicitly
                3. NO VAGUE REFERENCES: Never use "the author", "this text", "the passage"
                4. COMPLETE CONTEXT: Include all necessary background in the question

                ANSWER RULES:
                1. FOUR OPTIONS: Exactly 4 choices
                2. SAME TYPE: All options must be the same category (all dates, all names, all concepts)
                3. PLAUSIBLE: Wrong answers should be believable
                4. DISTINCT: Each option must be clearly different
                """),
                .user(prompt)
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
            if let example = parseResponse(response: output, chunk: chunk, difficulty: difficulty) {
                examples.append(example)
            }
        }

        return examples
    }

    private func buildPrompt(chunk: SemanticChunk, difficulty: QuizDifficulty) -> String {
        let difficultyGuide = switch difficulty {
        case .easy:
            "EASY: Test factual recall (dates, names, places, definitions). Direct questions with explicit answers."
        case .medium:
            "MEDIUM: Test understanding (why/how questions). Requires connecting ideas."
        case .hard:
            "HARD: Test analysis (implications, paradoxes, synthesis). Requires inference."
        }

        return """
        DIFFICULTY LEVEL: \(difficulty.rawValue)
        \(difficultyGuide)

        Create ONE multiple choice question from this text. The question must stand completely alone.

        Source: "\(chunk.source)"
        Text:
        \(chunk.text.prefix(800))

        Output ONLY valid JSON (no other text):
        {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
        """
    }

    private func parseResponse(response: String, chunk: SemanticChunk, difficulty: QuizDifficulty) -> TrainingExample? {
        // Clean response
        var cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanResponse.hasPrefix("```json") {
            cleanResponse = cleanResponse.replacingOccurrences(of: "```json", with: "")
        }
        if cleanResponse.contains("```") {
            cleanResponse = cleanResponse.replacingOccurrences(of: "```", with: "")
        }
        cleanResponse = cleanResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object
        guard let startIndex = cleanResponse.firstIndex(of: "{"),
              let endIndex = cleanResponse.lastIndex(of: "}") else {
            return nil
        }

        let jsonString = String(cleanResponse[startIndex...endIndex])

        struct RawQuestion: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawQuestion.self, from: jsonData) else {
            return nil
        }

        // Validate
        guard raw.options.count == 4,
              Set(raw.options).count == 4,
              raw.correctIndex >= 0 && raw.correctIndex < 4,
              raw.question.count > 20 else {
            return nil
        }

        return TrainingExample(
            question: raw.question,
            options: raw.options,
            correctIndex: raw.correctIndex,
            explanation: raw.explanation ?? "The correct answer is based on the source material.",
            difficulty: difficulty,
            sourceChunkId: chunk.id,
            sourceDocument: chunk.source
        )
    }

    // MARK: - Deduplication

    private func deduplicateExamples(_ examples: [TrainingExample]) -> [TrainingExample] {
        var seen = Set<String>()
        return examples.filter { example in
            // Normalize question for comparison
            let normalized = example.question.lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }

    // MARK: - Export to Training Format

    /// Export examples to Qwen chat template JSONL format
    func exportToJSONL(
        examples: [TrainingExample],
        trainRatio: Double = 0.8
    ) async throws -> (trainURL: URL, validURL: URL) {
        let shuffled = examples.shuffled()
        let splitIndex = Int(Double(shuffled.count) * trainRatio)
        let trainExamples = Array(shuffled.prefix(splitIndex))
        let validExamples = Array(shuffled.suffix(from: splitIndex))

        let dataDir = projectPath.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let trainURL = dataDir.appendingPathComponent("train.jsonl")
        let validURL = dataDir.appendingPathComponent("valid.jsonl")

        try exportExamplesToFile(trainExamples, url: trainURL)
        try exportExamplesToFile(validExamples, url: validURL)

        return (trainURL, validURL)
    }

    private func exportExamplesToFile(_ examples: [TrainingExample], url: URL) throws {
        var lines: [String] = []

        for example in examples {
            let formattedText = formatForQwen(example: example)
            let jsonLine = try JSONEncoder().encode(TrainingLine(text: formattedText))
            if let jsonString = String(data: jsonLine, encoding: .utf8) {
                lines.append(jsonString)
            }
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Format example in Qwen chat template
    private func formatForQwen(example: TrainingExample) -> String {
        let systemPrompt = """
        You are an expert quiz creator. Create high-quality multiple choice questions that are self-contained and specific.
        """

        let userPrompt = """
        Create a \(example.difficulty.rawValue.lowercased()) difficulty multiple choice question.
        The question should be self-contained and name all people, places, and events explicitly.
        Output only valid JSON.
        """

        let optionsJSON = example.options.map { "\"\($0)\"" }.joined(separator: ", ")
        let assistantResponse = """
        {"question": "\(escapeJSON(example.question))", "options": [\(optionsJSON)], "correctIndex": \(example.correctIndex), "explanation": "\(escapeJSON(example.explanation))"}
        """

        // Qwen chat template format
        return """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(userPrompt)<|im_end|>
        <|im_start|>assistant
        \(assistantResponse)<|im_end|>
        """
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - Load/Save Examples

    /// Save generated examples to disk for reuse
    func saveExamples(_ examples: [TrainingExample]) async throws {
        let dataDir = projectPath.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let url = dataDir.appendingPathComponent("training_examples.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(examples)
        try data.write(to: url)
    }

    /// Load previously generated examples
    func loadExamples() async throws -> [TrainingExample] {
        let url = projectPath.appendingPathComponent("data/training_examples.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TrainingExample].self, from: data)
    }
}

// MARK: - Data Types

struct TrainingExample: Codable, Identifiable {
    var id: String { "\(sourceChunkId)-\(question.prefix(20))" }

    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let difficulty: QuizDifficulty
    let sourceChunkId: String
    let sourceDocument: String
}

// TrainingLine is defined in TrainingService.swift

struct TrainingDataProgress {
    let completed: Int
    let total: Int
    let currentStatus: String
    let examplesGenerated: Int

    var percentComplete: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total) * 100
    }
}

struct TrainingDataResult {
    let examples: [TrainingExample]
    let totalGenerated: Int
    let duplicatesRemoved: Int
    let errors: [String]

    var successRate: Double {
        guard totalGenerated > 0 else { return 0 }
        return Double(examples.count) / Double(totalGenerated) * 100
    }
}

enum TrainingDataError: Error, LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case noChunksAvailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local model not loaded. Load the model first."
        case .invalidResponse:
            return "Invalid response from model"
        case .noChunksAvailable:
            return "No chunks available for training data generation"
        case .exportFailed:
            return "Failed to export training data"
        }
    }
}

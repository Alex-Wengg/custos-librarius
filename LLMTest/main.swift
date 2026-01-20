// Standalone LLM Test Runner
// Build and run: swift build --product LLMTest && .build/debug/LLMTest

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - Models (copied from main app for standalone build)

struct ChunkData: Codable {
    let id: String
    let text: String
    let source: String
    let title: String
    let author: String
    let index: Int
}

struct TestProjectConfig: Codable {
    let name: String
    let model: String
    let embeddingModel: String

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case embeddingModel = "embedding_model"
    }
}

enum QuizDifficulty: String, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

// MARK: - Test Chat Service

actor TestChatService {
    private let projectPath: URL
    private var modelContainer: ModelContainer?

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    func loadModel() async throws {
        let configPath = projectPath.appendingPathComponent("librarian.json")
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(TestProjectConfig.self, from: data)

        let modelConfig = ModelConfiguration(id: config.model)
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfig)
    }

    func generateQuiz(difficulty: QuizDifficulty) async throws -> (question: String, options: [String], correctIndex: Int, explanation: String)? {
        guard let container = modelContainer else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        guard let chunk = chunks.randomElement() else { return nil }

        let difficultyPrompt: String
        switch difficulty {
        case .easy:
            difficultyPrompt = "Create an EASY question - focus on basic facts, definitions, or simple recall."
        case .medium:
            difficultyPrompt = "Create a MEDIUM difficulty question - require understanding of concepts."
        case .hard:
            difficultyPrompt = "Create a HARD question - require deep analysis or connecting multiple concepts."
        }

        let messages: [Chat.Message] = [
            .system("""
            You create educational multiple choice questions. You MUST:
            1. Write a clear question about the text
            2. Provide exactly 4 answer options with REAL content
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
            let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.8)

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

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        if let start = cleanOutput.firstIndex(of: "{"),
           let end = cleanOutput.lastIndex(of: "}") {
            let jsonStr = String(cleanOutput[start...end])
            if let jsonData = jsonStr.data(using: .utf8),
               let raw = try? JSONDecoder().decode(RawQ.self, from: jsonData) {
                return (raw.question, raw.options, raw.correctIndex, raw.explanation ?? "")
            }
        }

        return nil
    }

    func generateOpenEnded() async throws -> (question: String, idealAnswer: String, keyPoints: [String])? {
        guard let container = modelContainer else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let chunksPath = projectPath.appendingPathComponent("data/chunks.json")
        let data = try Data(contentsOf: chunksPath)
        let chunks = try JSONDecoder().decode([ChunkData].self, from: data)

        guard let chunk = chunks.randomElement() else { return nil }

        let messages: [Chat.Message] = [
            .system("You create open-ended study questions. Output valid JSON only."),
            .user("""
            Create an open-ended question (not multiple choice) from this text.
            Include the ideal answer that a student should provide.

            Example:
            {"question": "Explain the significance of the Silk Road.", "idealAnswer": "The Silk Road was a network of trade routes...", "keyPoints": ["trade routes", "cultural exchange"]}

            Text from "\(chunk.source)":
            \(chunk.text.prefix(800))

            JSON:
            """)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.8)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                }
            }
        }

        var cleanOutput = output
        if cleanOutput.contains("```") {
            cleanOutput = cleanOutput
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct RawOE: Codable {
            let question: String
            let idealAnswer: String
            let keyPoints: [String]?
        }

        if let start = cleanOutput.firstIndex(of: "{"),
           let end = cleanOutput.lastIndex(of: "}") {
            let jsonStr = String(cleanOutput[start...end])
            if let jsonData = jsonStr.data(using: .utf8),
               let raw = try? JSONDecoder().decode(RawOE.self, from: jsonData) {
                return (raw.question, raw.idealAnswer, raw.keyPoints ?? [])
            }
        }

        return nil
    }

    func discuss(question: String, context: String, userAnswer: String) async throws -> String {
        guard let container = modelContainer else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let messages: [Chat.Message] = [
            .system("""
            You are a thoughtful study partner engaging in Socratic dialogue. Your role is to:
            - Acknowledge what the student got right
            - Gently probe areas they might have missed
            - Ask follow-up questions to deepen understanding
            - Be encouraging and conversational
            - Keep responses concise (2-3 paragraphs max)

            Context: \(context)
            Topic: \(question)
            """),
            .user(userAnswer)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 512, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Test Runner

@main
struct LLMTestRunner {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════╗")
        print("║              LLM Output Test Runner                        ║")
        print("╚════════════════════════════════════════════════════════════╝\n")

        // Setup test project
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("LLMTest-\(UUID().uuidString)")

        do {
            try setupTestProject(at: testDir)
            let service = TestChatService(projectPath: testDir)

            print("Loading model (this may take a moment)...")
            let loadStart = Date()
            try await service.loadModel()
            print("✅ Model loaded in \(String(format: "%.1f", Date().timeIntervalSince(loadStart)))s\n")

            var passed = 0
            var failed = 0

            // Test 1: Easy Quiz
            print("═══════════════════════════════════════════════════════════════")
            print("Test 1: Generate Easy Quiz Question")
            print("═══════════════════════════════════════════════════════════════")
            if let result = try await service.generateQuiz(difficulty: .easy) {
                let valid = validateQuiz(result)
                if valid.success {
                    passed += 1
                    print("✅ PASSED")
                } else {
                    failed += 1
                    print("❌ FAILED: \(valid.reason)")
                }
                print("   Q: \(result.question)")
                print("   Options: \(result.options.joined(separator: " | "))")
                print("   Answer: \(result.options[result.correctIndex])")
                print("   Explanation: \(result.explanation)")
            } else {
                failed += 1
                print("❌ FAILED: No question generated")
            }
            print()

            // Test 2: Medium Quiz
            print("═══════════════════════════════════════════════════════════════")
            print("Test 2: Generate Medium Quiz Question")
            print("═══════════════════════════════════════════════════════════════")
            if let result = try await service.generateQuiz(difficulty: .medium) {
                let valid = validateQuiz(result)
                if valid.success {
                    passed += 1
                    print("✅ PASSED")
                } else {
                    failed += 1
                    print("❌ FAILED: \(valid.reason)")
                }
                print("   Q: \(result.question)")
                print("   Options: \(result.options.joined(separator: " | "))")
            } else {
                failed += 1
                print("❌ FAILED: No question generated")
            }
            print()

            // Test 3: Hard Quiz
            print("═══════════════════════════════════════════════════════════════")
            print("Test 3: Generate Hard Quiz Question")
            print("═══════════════════════════════════════════════════════════════")
            if let result = try await service.generateQuiz(difficulty: .hard) {
                let valid = validateQuiz(result)
                if valid.success {
                    passed += 1
                    print("✅ PASSED")
                } else {
                    failed += 1
                    print("❌ FAILED: \(valid.reason)")
                }
                print("   Q: \(result.question)")
                print("   Options: \(result.options.joined(separator: " | "))")
            } else {
                failed += 1
                print("❌ FAILED: No question generated")
            }
            print()

            // Test 4: Open-Ended Question
            print("═══════════════════════════════════════════════════════════════")
            print("Test 4: Generate Open-Ended Question")
            print("═══════════════════════════════════════════════════════════════")
            if let result = try await service.generateOpenEnded() {
                let valid = validateOpenEnded(result)
                if valid.success {
                    passed += 1
                    print("✅ PASSED")
                } else {
                    failed += 1
                    print("❌ FAILED: \(valid.reason)")
                }
                print("   Q: \(result.question)")
                print("   Ideal: \(result.idealAnswer.prefix(150))...")
                print("   Key points: \(result.keyPoints.joined(separator: ", "))")
            } else {
                failed += 1
                print("❌ FAILED: No question generated")
            }
            print()

            // Test 5: Discussion
            print("═══════════════════════════════════════════════════════════════")
            print("Test 5: Socratic Discussion")
            print("═══════════════════════════════════════════════════════════════")
            let response = try await service.discuss(
                question: "What are the main types of machine learning?",
                context: "Machine learning has three main types: supervised, unsupervised, and reinforcement learning.",
                userAnswer: "I think there's supervised learning where you use labeled data to train."
            )
            if !response.isEmpty && response.count > 50 {
                passed += 1
                print("✅ PASSED")
                print("   User: I think there's supervised learning where you use labeled data to train.")
                print("   AI: \(response.prefix(300))...")
            } else {
                failed += 1
                print("❌ FAILED: Response too short or empty")
            }
            print()

            // Summary
            print("═══════════════════════════════════════════════════════════════")
            print("                        RESULTS                                ")
            print("═══════════════════════════════════════════════════════════════")
            print("✅ Passed: \(passed)")
            print("❌ Failed: \(failed)")
            print("═══════════════════════════════════════════════════════════════")

            if failed == 0 {
                print("\n🎉 All LLM output tests passed!")
            } else {
                print("\n⚠️  Some tests failed. Check the output above.")
            }

        } catch {
            print("❌ Error: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }

    static func setupTestProject(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let dataDir = path.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let chunks = [
            ChunkData(
                id: "1",
                text: """
                The Great Wall of China is one of the most famous structures in the world.
                Construction began in the 7th century BC and continued for many centuries.
                The wall stretches approximately 13,171 miles (21,196 kilometers) in total length.
                It was built primarily to protect against invasions from northern nomadic groups.
                The wall is made of stone, brick, tamped earth, and other materials.
                """,
                source: "History of China.pdf",
                title: "Great Wall",
                author: "Test",
                index: 0
            ),
            ChunkData(
                id: "2",
                text: """
                Machine learning is a subset of artificial intelligence that enables systems to
                learn and improve from experience without being explicitly programmed.
                The three main types are: supervised learning (uses labeled data),
                unsupervised learning (finds patterns in unlabeled data), and
                reinforcement learning (learns through environment interaction).
                """,
                source: "AI Introduction.pdf",
                title: "Machine Learning",
                author: "Test",
                index: 1
            ),
            ChunkData(
                id: "3",
                text: """
                Swift is a powerful programming language developed by Apple in 2014.
                It is designed to be safe, fast, and expressive. Swift eliminates
                entire classes of unsafe code through features like optionals and
                automatic memory management. It supports protocol-oriented programming.
                """,
                source: "Swift Guide.pdf",
                title: "Swift",
                author: "Test",
                index: 2
            )
        ]

        let chunksData = try JSONEncoder().encode(chunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        let config = """
        {
            "name": "TestProject",
            "model": "mlx-community/Qwen2.5-3B-Instruct-4bit",
            "embedding_model": "mlx-community/bge-small-en-v1.5-quantized-4bit"
        }
        """
        try config.write(to: path.appendingPathComponent("librarian.json"), atomically: true, encoding: .utf8)

        print("✅ Test project created at \(path.path)\n")
    }

    static func validateQuiz(_ result: (question: String, options: [String], correctIndex: Int, explanation: String)) -> (success: Bool, reason: String) {
        // Check question
        if result.question.isEmpty {
            return (false, "Question is empty")
        }

        // Check options count
        if result.options.count != 4 {
            return (false, "Expected 4 options, got \(result.options.count)")
        }

        // Check for placeholders
        let placeholders = ["option1", "option2", "option3", "option4", "option 1", "option 2", "option 3", "option 4", "..."]
        for option in result.options {
            if placeholders.contains(option.lowercased()) {
                return (false, "Placeholder option found: \(option)")
            }
            if option.count <= 1 {
                return (false, "Option too short: \(option)")
            }
        }

        // Check uniqueness
        if Set(result.options).count != 4 {
            return (false, "Duplicate options found")
        }

        // Check correct index
        if result.correctIndex < 0 || result.correctIndex >= 4 {
            return (false, "Invalid correct index: \(result.correctIndex)")
        }

        return (true, "")
    }

    static func validateOpenEnded(_ result: (question: String, idealAnswer: String, keyPoints: [String])) -> (success: Bool, reason: String) {
        if result.question.isEmpty {
            return (false, "Question is empty")
        }
        if result.idealAnswer.isEmpty {
            return (false, "Ideal answer is empty")
        }
        if result.idealAnswer.count < 20 {
            return (false, "Ideal answer too short")
        }
        return (true, "")
    }
}

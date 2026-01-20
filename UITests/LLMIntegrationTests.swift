import XCTest
@testable import CustosLibrarius

/// LLM Integration Tests - Run from Xcode with Cmd+U
/// These tests run inside the app process, giving them Metal/GPU access
final class LLMIntegrationTests: XCTestCase {

    var chatService: ChatService!
    var testProjectPath: URL!

    override func setUp() async throws {
        // Create test project with sample data
        testProjectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMTest-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: testProjectPath, withIntermediateDirectories: true)

        let dataDir = testProjectPath.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Create test chunks
        let chunks = [
            ChunkData(
                id: "1",
                text: """
                The Great Wall of China is one of the most famous structures in the world.
                Construction began in the 7th century BC and continued for centuries.
                The wall stretches approximately 13,171 miles (21,196 km) in total length.
                It was built to protect against invasions from northern nomadic groups.
                """,
                source: "History.pdf",
                title: "Great Wall",
                author: "Test",
                index: 0
            ),
            ChunkData(
                id: "2",
                text: """
                Machine learning is a subset of artificial intelligence that enables systems
                to learn from experience without being explicitly programmed.
                The three main types are: supervised learning, unsupervised learning,
                and reinforcement learning.
                """,
                source: "AI.pdf",
                title: "ML",
                author: "Test",
                index: 1
            ),
            ChunkData(
                id: "3",
                text: """
                Swift is a programming language developed by Apple in 2014.
                It is designed to be safe, fast, and expressive.
                Swift supports protocol-oriented programming and strong type inference.
                """,
                source: "Swift.pdf",
                title: "Swift",
                author: "Test",
                index: 2
            )
        ]

        let chunksData = try JSONEncoder().encode(chunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        // Create config - use smaller model for faster tests
        let config = """
        {
            "name": "TestProject",
            "model": "mlx-community/Qwen2.5-3B-Instruct-4bit",
            "embedding_model": "mlx-community/bge-small-en-v1.5-quantized-4bit"
        }
        """
        try config.write(to: testProjectPath.appendingPathComponent("librarian.json"), atomically: true, encoding: .utf8)

        // Initialize service
        chatService = ChatService(projectPath: testProjectPath)
        try await chatService.loadModel()
    }

    override func tearDown() async throws {
        if let path = testProjectPath {
            try? FileManager.default.removeItem(at: path)
        }
        chatService = nil
    }

    // MARK: - Quiz Generation Tests

    func testGenerateEasyQuiz() async throws {
        let questions = try await chatService.generateQuiz(count: 1, difficulty: .easy)

        XCTAssertFalse(questions.isEmpty, "Should generate at least one question")

        if let q = questions.first {
            validateQuizQuestion(q)
            print("Easy Q: \(q.question)")
            print("Options: \(q.options.joined(separator: " | "))")
        }
    }

    func testGenerateMediumQuiz() async throws {
        let questions = try await chatService.generateQuiz(count: 1, difficulty: .medium)

        XCTAssertFalse(questions.isEmpty, "Should generate at least one question")

        if let q = questions.first {
            validateQuizQuestion(q)
            print("Medium Q: \(q.question)")
        }
    }

    func testGenerateHardQuiz() async throws {
        let questions = try await chatService.generateQuiz(count: 1, difficulty: .hard)

        XCTAssertFalse(questions.isEmpty, "Should generate at least one question")

        if let q = questions.first {
            validateQuizQuestion(q)
            print("Hard Q: \(q.question)")
        }
    }

    // MARK: - Open-Ended Tests

    func testGenerateOpenEndedQuestion() async throws {
        let questions = try await chatService.generateOpenEndedQuiz(count: 1, difficulty: .medium)

        XCTAssertFalse(questions.isEmpty, "Should generate question")

        if let q = questions.first {
            XCTAssertFalse(q.question.isEmpty, "Question should not be empty")
            XCTAssertFalse(q.idealAnswer.isEmpty, "Ideal answer should not be empty")
            XCTAssertTrue(q.idealAnswer.count > 20, "Ideal answer should be substantive")

            print("Open Q: \(q.question)")
            print("Ideal: \(q.idealAnswer.prefix(150))...")
        }
    }

    // MARK: - Discussion Tests

    func testSocraticDiscussion() async throws {
        let question = OpenEndedQuestion(
            question: "What are the main types of machine learning?",
            idealAnswer: "Supervised, unsupervised, and reinforcement learning.",
            keyPoints: ["supervised", "unsupervised", "reinforcement"],
            source: "AI.pdf",
            context: "Machine learning has three main types."
        )

        let response = try await chatService.discussAnswer(
            question: question,
            userAnswer: "I think there's supervised learning where you use labeled data.",
            previousMessages: []
        )

        XCTAssertFalse(response.isEmpty, "Response should not be empty")
        XCTAssertTrue(response.count > 50, "Response should be substantive")

        print("User: I think there's supervised learning...")
        print("AI: \(response.prefix(200))...")
    }

    // MARK: - Helpers

    func validateQuizQuestion(_ q: QuizQuestion) {
        XCTAssertFalse(q.question.isEmpty, "Question should not be empty")
        XCTAssertEqual(q.options.count, 4, "Should have 4 options")
        XCTAssertTrue(q.correctIndex >= 0 && q.correctIndex < 4, "Valid correct index")
        XCTAssertEqual(Set(q.options).count, 4, "Options should be unique")

        // No placeholders
        let placeholders = ["option1", "option2", "option3", "option4"]
        for opt in q.options {
            XCTAssertFalse(placeholders.contains(opt.lowercased()), "No placeholder: \(opt)")
            XCTAssertTrue(opt.count > 1, "Option not empty: \(opt)")
        }
    }
}

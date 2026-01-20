import XCTest
@testable import CustosLibrarius

final class ModelTests: XCTestCase {

    // MARK: - ChunkData Tests

    func testChunkDataEncoding() throws {
        let chunk = ChunkData(
            id: "chunk_001",
            text: "This is test content",
            source: "document.pdf",
            title: "Test Document",
            author: "Test Author",
            index: 0
        )

        let encoded = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(ChunkData.self, from: encoded)

        XCTAssertEqual(decoded.id, "chunk_001")
        XCTAssertEqual(decoded.text, "This is test content")
        XCTAssertEqual(decoded.source, "document.pdf")
        XCTAssertEqual(decoded.title, "Test Document")
        XCTAssertEqual(decoded.author, "Test Author")
        XCTAssertEqual(decoded.index, 0)
    }

    func testChunkDataDecodingFromJSON() throws {
        let json = """
        {
            "id": "test_id",
            "text": "Sample text content",
            "source": "sample.txt",
            "title": "Sample",
            "author": "Author Name",
            "index": 5
        }
        """

        let data = json.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(ChunkData.self, from: data)

        XCTAssertEqual(chunk.id, "test_id")
        XCTAssertEqual(chunk.text, "Sample text content")
        XCTAssertEqual(chunk.index, 5)
    }

    // MARK: - QuizQuestion Tests

    func testQuizQuestionCreation() {
        let question = QuizQuestion(
            question: "What is 2 + 2?",
            options: ["3", "4", "5", "6"],
            correctIndex: 1,
            source: "math.txt",
            explanation: "Basic arithmetic"
        )

        XCTAssertEqual(question.question, "What is 2 + 2?")
        XCTAssertEqual(question.options.count, 4)
        XCTAssertEqual(question.correctIndex, 1)
        XCTAssertNil(question.userAnswer)
    }

    func testQuizQuestionUniqueID() {
        let q1 = QuizQuestion(question: "Q1", options: ["A", "B", "C", "D"], correctIndex: 0, source: "test")
        let q2 = QuizQuestion(question: "Q1", options: ["A", "B", "C", "D"], correctIndex: 0, source: "test")

        XCTAssertNotEqual(q1.id, q2.id, "Each question should have a unique ID")
    }

    // MARK: - OpenEndedQuestion Tests

    func testOpenEndedQuestionCreation() {
        let question = OpenEndedQuestion(
            question: "Explain the concept of recursion",
            idealAnswer: "Recursion is when a function calls itself to solve a problem",
            keyPoints: ["self-reference", "base case", "recursive case"],
            source: "programming.txt",
            context: "Chapter on algorithms"
        )

        XCTAssertEqual(question.question, "Explain the concept of recursion")
        XCTAssertEqual(question.keyPoints.count, 3)
        XCTAssertTrue(question.discussion.isEmpty)
        XCTAssertFalse(question.isComplete)
    }

    func testOpenEndedQuestionDiscussion() {
        var question = OpenEndedQuestion(
            question: "Test question",
            idealAnswer: "Test answer",
            keyPoints: ["point1"],
            source: "test.txt",
            context: "Test context"
        )

        let message1 = DiscussionMessage(content: "My answer", isUser: true)
        let message2 = DiscussionMessage(content: "Good start!", isUser: false)

        question.discussion.append(message1)
        question.discussion.append(message2)

        XCTAssertEqual(question.discussion.count, 2)
        XCTAssertTrue(question.discussion[0].isUser)
        XCTAssertFalse(question.discussion[1].isUser)
    }

    // MARK: - DiscussionMessage Tests

    func testDiscussionMessageCreation() {
        let message = DiscussionMessage(content: "Hello!", isUser: true)

        XCTAssertEqual(message.content, "Hello!")
        XCTAssertTrue(message.isUser)
        XCTAssertNotNil(message.timestamp)
    }

    func testDiscussionMessageUniqueID() {
        let m1 = DiscussionMessage(content: "Same content", isUser: true)
        let m2 = DiscussionMessage(content: "Same content", isUser: true)

        XCTAssertNotEqual(m1.id, m2.id)
    }

    // MARK: - QuizDifficulty Tests

    func testQuizDifficultyRawValues() {
        XCTAssertEqual(QuizDifficulty.easy.rawValue, "Easy")
        XCTAssertEqual(QuizDifficulty.medium.rawValue, "Medium")
        XCTAssertEqual(QuizDifficulty.hard.rawValue, "Hard")
    }

    func testQuizDifficultyAllCases() {
        XCTAssertEqual(QuizDifficulty.allCases.count, 3)
    }

    // MARK: - QuizType Tests

    func testQuizTypeRawValues() {
        XCTAssertEqual(QuizType.multipleChoice.rawValue, "Multiple Choice")
        XCTAssertEqual(QuizType.openEnded.rawValue, "Open Ended")
    }

    func testQuizTypeAllCases() {
        XCTAssertEqual(QuizType.allCases.count, 2)
    }

    // MARK: - AppProjectConfig Tests

    func testAppProjectConfigDecoding() throws {
        let json = """
        {
            "name": "My Project",
            "model": "mlx-community/Llama-3.2-1B-Instruct-4bit",
            "embedding_model": "mlx-community/bge-small-en-v1.5"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppProjectConfig.self, from: data)

        XCTAssertEqual(config.name, "My Project")
        XCTAssertEqual(config.model, "mlx-community/Llama-3.2-1B-Instruct-4bit")
        XCTAssertEqual(config.embeddingModel, "mlx-community/bge-small-en-v1.5")
    }

    func testAppProjectConfigEncoding() throws {
        let config = AppProjectConfig(
            name: "Test",
            model: "model-id",
            embeddingModel: "embedding-model-id"
        )

        let encoded = try JSONEncoder().encode(config)
        let json = String(data: encoded, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"name\":\"Test\""))
        XCTAssertTrue(json.contains("\"embedding_model\":\"embedding-model-id\""))
    }

    // MARK: - ServiceError Tests

    func testServiceErrorCases() {
        let error1: ServiceError = .modelNotLoaded
        let error2: ServiceError = .projectNotFound

        XCTAssertNotNil(error1)
        XCTAssertNotNil(error2)
    }

    // MARK: - SearchResult Tests

    func testSearchResultCreation() {
        let result = SearchResult(
            text: "Found content",
            source: "document.pdf",
            score: 0.85
        )

        XCTAssertEqual(result.text, "Found content")
        XCTAssertEqual(result.source, "document.pdf")
        XCTAssertEqual(result.score, 0.85, accuracy: 0.001)
    }
}

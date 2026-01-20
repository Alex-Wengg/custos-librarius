import XCTest
@testable import CustosLibrarius

final class JSONParsingTests: XCTestCase {

    // MARK: - Quiz JSON Parsing Tests

    func testParseQuizQuestionFromCleanJSON() throws {
        let json = """
        {"question": "What year was Swift released?", "options": ["2012", "2014", "2016", "2018"], "correctIndex": 1, "explanation": "Swift was released by Apple in 2014."}
        """

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        let data = json.data(using: .utf8)!
        let raw = try JSONDecoder().decode(RawQ.self, from: data)

        XCTAssertEqual(raw.question, "What year was Swift released?")
        XCTAssertEqual(raw.options.count, 4)
        XCTAssertEqual(raw.correctIndex, 1)
        XCTAssertEqual(raw.explanation, "Swift was released by Apple in 2014.")
    }

    func testParseQuizQuestionFromMarkdownFencedJSON() throws {
        let output = """
        Here is the question:
        ```json
        {"question": "What is 2+2?", "options": ["3", "4", "5", "6"], "correctIndex": 1, "explanation": "Basic math."}
        ```
        """

        // Strip markdown fences (same logic as ChatService)
        var cleanOutput = output
        if cleanOutput.contains("```") {
            cleanOutput = cleanOutput
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = cleanOutput.firstIndex(of: "{"),
              let end = cleanOutput.lastIndex(of: "}") else {
            XCTFail("Could not find JSON boundaries")
            return
        }

        let jsonStr = String(cleanOutput[start...end])
        let data = jsonStr.data(using: .utf8)!

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        let raw = try JSONDecoder().decode(RawQ.self, from: data)
        XCTAssertEqual(raw.question, "What is 2+2?")
        XCTAssertEqual(raw.options, ["3", "4", "5", "6"])
    }

    func testParseQuizQuestionArrayFromJSON() throws {
        let json = """
        [{"question": "Q1", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "E1"},
         {"question": "Q2", "options": ["W", "X", "Y", "Z"], "correctIndex": 2, "explanation": "E2"}]
        """

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        let data = json.data(using: .utf8)!
        let questions = try JSONDecoder().decode([RawQ].self, from: data)

        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].question, "Q1")
        XCTAssertEqual(questions[1].correctIndex, 2)
    }

    func testRejectPlaceholderOptions() {
        let placeholders = ["option1", "option2", "option3", "option4", "option 1", "option 2", "option 3", "option 4", "...", "answer1", "answer2"]

        let goodOptions = ["Paris", "London", "Berlin", "Rome"]
        let badOptions = ["option1", "option2", "option3", "option4"]

        // Good options should pass
        let goodValid = !goodOptions.contains(where: { placeholders.contains($0.lowercased()) })
        XCTAssertTrue(goodValid)

        // Bad options should fail
        let badValid = !badOptions.contains(where: { placeholders.contains($0.lowercased()) })
        XCTAssertFalse(badValid)
    }

    func testValidateUniqueOptions() {
        let uniqueOptions = ["A", "B", "C", "D"]
        let duplicateOptions = ["A", "B", "A", "D"]

        XCTAssertEqual(Set(uniqueOptions).count, 4)
        XCTAssertNotEqual(Set(duplicateOptions).count, 4)
    }

    func testValidateOptionLength() {
        let goodOptions = ["Yes", "No", "Maybe", "Unknown"]
        let badOptions = ["Y", "", "Maybe", "Unknown"]

        let goodValid = goodOptions.allSatisfy { $0.count > 1 }
        let badValid = badOptions.allSatisfy { $0.count > 1 }

        XCTAssertTrue(goodValid)
        XCTAssertFalse(badValid)
    }

    // MARK: - Open-Ended Question JSON Parsing Tests

    func testParseOpenEndedQuestionJSON() throws {
        let json = """
        {"question": "Explain recursion", "idealAnswer": "Recursion is when a function calls itself", "keyPoints": ["self-reference", "base case"]}
        """

        struct RawOE: Codable {
            let question: String
            let idealAnswer: String
            let keyPoints: [String]?
        }

        let data = json.data(using: .utf8)!
        let raw = try JSONDecoder().decode(RawOE.self, from: data)

        XCTAssertEqual(raw.question, "Explain recursion")
        XCTAssertEqual(raw.idealAnswer, "Recursion is when a function calls itself")
        XCTAssertEqual(raw.keyPoints?.count, 2)
    }

    func testParseOpenEndedQuestionWithoutKeyPoints() throws {
        let json = """
        {"question": "What is AI?", "idealAnswer": "Artificial intelligence is..."}
        """

        struct RawOE: Codable {
            let question: String
            let idealAnswer: String
            let keyPoints: [String]?
        }

        let data = json.data(using: .utf8)!
        let raw = try JSONDecoder().decode(RawOE.self, from: data)

        XCTAssertEqual(raw.question, "What is AI?")
        XCTAssertNil(raw.keyPoints)
    }

    // MARK: - Flashcard JSON Parsing Tests

    func testParseFlashcardJSON() throws {
        let json = """
        [{"question": "What is Swift?", "answer": "A programming language by Apple"}]
        """

        struct RawFlashcard: Codable {
            let question: String
            let answer: String
        }

        let data = json.data(using: .utf8)!
        let cards = try JSONDecoder().decode([RawFlashcard].self, from: data)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].question, "What is Swift?")
    }

    // MARK: - Edge Cases

    func testParseJSONWithExtraWhitespace() throws {
        let output = """


        ```json
        {
            "question": "Test?",
            "options": ["A", "B", "C", "D"],
            "correctIndex": 0,
            "explanation": "Test"
        }
        ```


        """

        var cleanOutput = output
        if cleanOutput.contains("```") {
            cleanOutput = cleanOutput
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = cleanOutput.firstIndex(of: "{"),
              let end = cleanOutput.lastIndex(of: "}") else {
            XCTFail("Could not find JSON boundaries")
            return
        }

        let jsonStr = String(cleanOutput[start...end])
        let data = jsonStr.data(using: .utf8)!

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let explanation: String?
        }

        let raw = try JSONDecoder().decode(RawQ.self, from: data)
        XCTAssertEqual(raw.question, "Test?")
    }

    func testParseJSONWithTrailingText() throws {
        let output = """
        {"question": "Q?", "options": ["A", "B", "C", "D"], "correctIndex": 0}
        This is some extra text after the JSON that should be ignored.
        """

        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}") else {
            XCTFail("Could not find JSON boundaries")
            return
        }

        let jsonStr = String(output[start...end])
        let data = jsonStr.data(using: .utf8)!

        struct RawQ: Codable {
            let question: String
            let options: [String]
            let correctIndex: Int
        }

        let raw = try JSONDecoder().decode(RawQ.self, from: data)
        XCTAssertEqual(raw.question, "Q?")
    }

    func testHandleMissingJSONBrackets() {
        let badOutput = "This output has no JSON at all"

        let hasObject = badOutput.firstIndex(of: "{") != nil
        let hasArray = badOutput.firstIndex(of: "[") != nil

        XCTAssertFalse(hasObject)
        XCTAssertFalse(hasArray)
    }
}

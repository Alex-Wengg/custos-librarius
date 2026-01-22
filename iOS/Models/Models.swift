import Foundation

// MARK: - Data Models

struct ChunkData: Codable, Identifiable {
    let id: String
    let text: String
    let source: String
    let title: String
    let author: String
    let index: Int
}

struct QuizQuestion: Codable, Identifiable {
    var id: String = UUID().uuidString
    let question: String
    let options: [String]
    let correctIndex: Int
    let source: String
    var explanation: String = ""
    var userAnswer: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, question, options, correctIndex, source, explanation
    }
}

enum QuizDifficulty: String, CaseIterable, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

struct QuizSet: Codable, Identifiable {
    let id: String
    let name: String
    let difficulty: QuizDifficulty
    let questions: [QuizQuestion]
    let createdAt: Date
}

struct Flashcard: Codable, Identifiable {
    var id: String = UUID().uuidString
    let question: String
    let answer: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, question, answer, source
    }
}

struct FlashcardSet: Codable, Identifiable {
    let id: String
    let name: String
    let cards: [Flashcard]
    let createdAt: Date
}

struct SearchResult: Identifiable {
    let id = UUID()
    let text: String
    let source: String
    let score: Float
}

struct StudyProgress: Codable {
    var quizzesTaken: Int = 0
    var totalScore: Int = 0
    var totalQuestions: Int = 0
    var flashcardsReviewed: Int = 0
    var lastStudied: Date?
}

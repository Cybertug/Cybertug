import Foundation

// Pure Swift data models. No HTML, JavaScript, WebView, or browser components.
struct LawQuestion: Codable, Identifiable, Hashable {
    let id: String
    let topic: String
    let source: String
    let question: String
    let options: [String]
    let correct: Int
    let explanation: String
}

struct ExamItem: Codable, Identifiable {
    let id: String
    let topic: String
    let source: String
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let isScored: Bool
    var selectedIndex: Int?
    var isFlagged: Bool
}

enum ExamStage: String, Codable {
    case tutorial
    case exam
    case review
    case results
}

enum ReviewFilter: String, Codable {
    case all
    case incomplete
    case flagged
}

struct ExamSnapshot: Codable {
    var stage: ExamStage = .tutorial
    var candidateName: String = ""
    var tutorialIndex: Int = 0
    var items: [ExamItem] = []
    var currentIndex: Int = 0
    var scratchPad: String = ""
    var endDate: Date?
    var didTimeExpire: Bool = false
    var reviewFilter: ReviewFilter = .all
    var showAllAnswers: Bool = false
}

struct ExamScore {
    let correct: Int
    let scored: Int
    let unscored: Int
    let passingThreshold: Int

    var passed: Bool { correct >= passingThreshold }
    var percentage: Int {
        guard scored > 0 else { return 0 }
        return Int((Double(correct) / Double(scored) * 100).rounded())
    }
}

enum ExamCreationError: Error, CustomStringConvertible {
    case insufficientQuestions(topic: String, requested: Int, available: Int)
    case insufficientPilots(requested: Int, available: Int)

    var description: String {
        switch self {
        case .insufficientQuestions(let topic, let requested, let available):
            return "Insufficient questions for \(topic): need \(requested), found \(available)."
        case .insufficientPilots(let requested, let available):
            return "Insufficient unscored questions: need \(requested), found \(available)."
        }
    }
}
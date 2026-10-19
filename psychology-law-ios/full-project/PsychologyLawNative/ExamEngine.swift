import Foundation

enum ExamEngine {
    // Same 40-question scored blueprint as the Psychology Law PC simulator.
    static let blueprint: [(topic: String, count: Int)] = [
        ("64B19", 12), ("490", 9), ("456", 8), ("394", 7),
        ("39", 2), ("90", 1), ("415", 1)
    ]
    static let questionCount = 45
    static let scoredCount = 40
    static let pilotCount = 5
    static let passingScore = 32
    static let examDurationSeconds = 60 * 60

    static func makeExam(from bank: [LawQuestion], excludingRecent recentIDs: Set<String> = []) throws -> [ExamItem] {
        var chosen: [LawQuestion] = []
        var used = Set<String>()
        for group in blueprint {
            let topicBank = bank.filter { $0.topic == group.topic }.shuffled()
            let prioritized = topicBank.filter { !recentIDs.contains($0.id) }
                + topicBank.filter { recentIDs.contains($0.id) }
            guard prioritized.count >= group.count else {
                throw ExamCreationError.insufficientQuestions(topic: group.topic,
                    requested: group.count, available: prioritized.count)
            }
            for q in prioritized.prefix(group.count) {
                chosen.append(q)
                used.insert(q.id)
            }
        }

        let remaining = bank.filter { !used.contains($0.id) }.shuffled()
        let prioritizedPilots = remaining.filter { !recentIDs.contains($0.id) }
            + remaining.filter { recentIDs.contains($0.id) }
        guard prioritizedPilots.count >= pilotCount else {
            throw ExamCreationError.insufficientPilots(requested: pilotCount, available: prioritizedPilots.count)
        }
        let flagged = chosen.map { (question: $0, scored: true) }
            + prioritizedPilots.prefix(pilotCount).map { (question: $0, scored: false) }
        return flagged.shuffled().map { pair in
            let q = pair.question
            let optionOrder = Array(q.options.indices).shuffled()
            return ExamItem(
                id: q.id, topic: q.topic, source: q.source, question: q.question,
                options: optionOrder.map { q.options[$0] },
                correctIndex: optionOrder.firstIndex(of: q.correct)!,
                explanation: q.explanation, isScored: pair.scored,
                selectedIndex: nil, isFlagged: false
            )
        }
    }

    /// Post-exam review follows the Pearson-style All / Incorrect / Flagged options.
    /// Only the 40 scored items are counted as incorrect for the score report;
    /// Review All includes every question, explicitly labelling the five pilots.
    static func reviewIndices(in items: [ExamItem], matching filter: ResultReviewFilter) -> [Int] {
        items.indices.filter { index in
            let item = items[index]
            switch filter {
            case .all:
                return true
            case .incorrect:
                return item.isScored && item.selectedIndex != item.correctIndex
            case .flagged:
                return item.isFlagged
            }
        }
    }

    static func score(_ items: [ExamItem]) -> ExamScore {
        let scoredItems = items.filter(\.isScored)
        let correct = scoredItems.filter { $0.selectedIndex == $0.correctIndex }.count
        return ExamScore(correct: correct, scored: scoredItems.count,
            unscored: items.count - scoredItems.count, passingThreshold: passingScore)
    }
}
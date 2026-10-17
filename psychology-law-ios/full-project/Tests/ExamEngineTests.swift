import Foundation

@main
struct ExamEngineTests {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let bank = try JSONDecoder().decode([LawQuestion].self, from: Data(contentsOf: url))
        precondition(bank.count == 325)
        // A closed/backgrounded app must return to an untouched new attempt.
        var abandoned = ExamSnapshot()
        abandoned.stage = .exam
        abandoned.candidateName = "Practice Candidate"
        abandoned.endDate = Date().addingTimeInterval(-300)
        abandoned.currentIndex = 5
        abandoned.tutorialIndex = 3
        abandoned.didTimeExpire = true
        abandoned.scratchPad = "old notes"
        let reopened = ExamSnapshot.freshAttempt(keepingCandidateName: abandoned.candidateName)
        precondition(reopened.stage == .tutorial)
        precondition(reopened.candidateName == "Practice Candidate")
        precondition(reopened.endDate == nil && reopened.items.isEmpty)
        precondition(reopened.currentIndex == 0 && reopened.tutorialIndex == 0)
        precondition(!reopened.didTimeExpire && reopened.scratchPad.isEmpty)
        precondition(ExamEngine.examDurationSeconds == 3600)
        precondition(Set(bank.map(\.id)).count == 325)
        precondition(bank.allSatisfy { $0.options.count == 4 && (0..<4).contains($0.correct) })
        precondition(bank.allSatisfy { !$0.explanation.isEmpty && !$0.source.isEmpty })
        let byID = Dictionary(uniqueKeysWithValues: bank.map { ($0.id, $0) })
        for repeatIndex in 0..<150 {
            let recentIDs = Set(repeatIndex % 2 == 0 ? Array(bank.prefix(45)).map(\.id) : [])
            var items = try ExamEngine.makeExam(from: bank, excludingRecent: recentIDs)
            precondition(items.count == 45)
            precondition(items.filter(\.isScored).count == 40)
            precondition(items.filter { !$0.isScored }.count == 5)
            precondition(Set(items.map(\.id)).count == items.count)
            precondition(items.allSatisfy { $0.selectedIndex == nil && !$0.isFlagged })
            for blueprint in ExamEngine.blueprint {
                precondition(items.filter { $0.isScored && $0.topic == blueprint.topic }.count == blueprint.count)
            }
            for item in items {
                let original = byID[item.id]!
                precondition(item.options[item.correctIndex] == original.options[original.correct],
                             "Answer key mismatch: \(item.id)")
            }
            let zero = ExamEngine.score(items)
            precondition(zero.correct == 0 && !zero.passed && zero.scored == 40 && zero.unscored == 5)
            var correctSoFar = 0
            for index in items.indices {
                if items[index].isScored && correctSoFar < 31 {
                    items[index].selectedIndex = items[index].correctIndex
                    correctSoFar += 1
                }
            }
            precondition(ExamEngine.score(items).correct == 31 && !ExamEngine.score(items).passed)
            let last = items.indices.first { items[$0].isScored && items[$0].selectedIndex == nil }!
            items[last].selectedIndex = items[last].correctIndex
            precondition(ExamEngine.score(items).correct == 32 && ExamEngine.score(items).passed)
        }
        print("PASS: 325 unique questions; 150 randomized exams; 45 questions, 40 scored, 5 pilots, exact topic quotas, option answer mappings, 31 fail / 32 pass.")
    }
}
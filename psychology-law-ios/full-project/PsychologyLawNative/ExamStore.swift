import Foundation
import Combine

/// Owns an entire attempt. Questions, answers, and clock state are saved on-device.
/// There are no browser dependencies, network requests, or WebViews.
@MainActor
final class ExamStore: ObservableObject {
    @Published private(set) var snapshot = ExamSnapshot()
    @Published private(set) var secondsRemaining = ExamEngine.examDurationSeconds
    @Published private(set) var errorText: String?

    private let bank: [LawQuestion]
    private var timer: Timer?
    private let snapshotKey = "psychologyLawNative.session.v1"
    private let recentIDsKey = "psychologyLawNative.lastIDs.v1"

    init() {
        if let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([LawQuestion].self, from: data) {
            bank = decoded
        } else {
            bank = []
        }
        if let data = UserDefaults.standard.data(forKey: snapshotKey),
           let saved = try? JSONDecoder().decode(ExamSnapshot.self, from: data) {
            snapshot = saved
        }
        refreshClock()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshClock() }
        }
    }

    deinit { timer?.invalidate() }

    var questionCount: Int { snapshot.items.count }
    var currentItem: ExamItem? {
        guard snapshot.items.indices.contains(snapshot.currentIndex) else { return nil }
        return snapshot.items[snapshot.currentIndex]
    }
    var score: ExamScore { ExamEngine.score(snapshot.items) }
    var answeredCount: Int { snapshot.items.filter { $0.selectedIndex != nil }.count }
    var incompleteCount: Int { questionCount - answeredCount }
    var flaggedCount: Int { snapshot.items.filter(\.isFlagged).count }
    var displayName: String {
        let trimmed = snapshot.candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Candidate Name" : trimmed
    }
    var clockText: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func commit(_ updated: ExamSnapshot) {
        snapshot = updated
        persist()
    }
    func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    func setCandidateName(_ newValue: String) {
        var next = snapshot
        next.candidateName = String(newValue.prefix(75))
        commit(next)
    }
    func nextTutorial() {
        if snapshot.tutorialIndex >= 3 { startExam(); return }
        var next = snapshot
        next.tutorialIndex += 1
        commit(next)
    }
    func previousTutorial() {
        var next = snapshot
        next.tutorialIndex = max(0, next.tutorialIndex - 1)
        commit(next)
    }
    func startExam() {
        let recent = Set(UserDefaults.standard.stringArray(forKey: recentIDsKey) ?? [])
        do {
            let newItems = try ExamEngine.makeExam(from: bank, excludingRecent: recent)
            var next = ExamSnapshot()
            next.candidateName = snapshot.candidateName
            next.stage = .exam
            next.items = newItems
            next.endDate = Date().addingTimeInterval(TimeInterval(ExamEngine.examDurationSeconds))
            secondsRemaining = ExamEngine.examDurationSeconds
            errorText = nil
            commit(next)
            UserDefaults.standard.set(newItems.map(\.id), forKey: recentIDsKey)
        } catch {
            errorText = "Unable to begin practice exam: \(error)"
        }
    }
    func dismissError() { errorText = nil }

    func chooseAnswer(_ option: Int) {
        guard snapshot.stage == .exam, let current = currentItem,
              current.options.indices.contains(option) else { return }
        var next = snapshot
        next.items[next.currentIndex].selectedIndex = option
        commit(next)
    }
    func toggleFlag() {
        guard snapshot.stage == .exam, currentItem != nil else { return }
        var next = snapshot
        next.items[next.currentIndex].isFlagged.toggle()
        commit(next)
    }
    func previousQuestion() {
        guard snapshot.stage == .exam else { return }
        var next = snapshot
        next.currentIndex = max(0, next.currentIndex - 1)
        commit(next)
    }
    func nextQuestion() {
        guard snapshot.stage == .exam else { return }
        var next = snapshot
        if next.currentIndex >= next.items.count - 1 {
            next.stage = .review
            next.reviewFilter = .all
        } else {
            next.currentIndex += 1
        }
        commit(next)
    }
    func goToQuestion(_ index: Int) {
        guard snapshot.items.indices.contains(index), snapshot.stage != .results else { return }
        var next = snapshot
        next.currentIndex = index
        next.stage = .exam
        commit(next)
    }
    func openReview(filter: ReviewFilter = .all) {
        guard snapshot.stage == .exam || snapshot.stage == .review else { return }
        var next = snapshot
        next.stage = .review
        next.reviewFilter = filter
        commit(next)
    }
    func selectReviewFilter(_ filter: ReviewFilter) {
        guard snapshot.stage == .review else { return }
        var next = snapshot
        next.reviewFilter = filter
        commit(next)
    }
    func returnToExam() {
        guard snapshot.stage == .review else { return }
        var next = snapshot
        next.stage = .exam
        commit(next)
    }
    func refreshClock() {
        guard snapshot.stage == .exam || snapshot.stage == .review,
              let endDate = snapshot.endDate else { return }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remaining != secondsRemaining { secondsRemaining = remaining }
        if remaining == 0 { finishExam(timedOut: true) }
    }
    func finishExam(timedOut: Bool = false) {
        guard snapshot.stage == .exam || snapshot.stage == .review else { return }
        var next = snapshot
        next.stage = .results
        next.didTimeExpire = timedOut
        next.showAllAnswers = false
        commit(next)
    }
    func toggleResultReview() {
        guard snapshot.stage == .results else { return }
        var next = snapshot
        next.showAllAnswers.toggle()
        commit(next)
    }
    func restart() {
        var next = ExamSnapshot()
        next.candidateName = snapshot.candidateName
        commit(next)
        secondsRemaining = ExamEngine.examDurationSeconds
    }
}
import SwiftUI
import Foundation
import Combine

private struct PMICPBank: Decodable {
    let total: Int
    let questions: [PMICPQuestion]
}

private struct PMICPQuestion: Decodable {
    let domain: String
    let task: Int
    let difficulty: String
    let stem: String
    let correct: String
    let distractors: [String]
    let rationale: String

    func examItem() -> PMICPItem {
        let choices = ([(correct, true)] + distractors.map { ($0, false) }).shuffled()
        return PMICPItem(id: UUID(), domain: domain, task: task, difficulty: difficulty,
                         stem: stem, rationale: rationale, options: choices.map { $0.0 },
                         correctIndex: choices.firstIndex { $0.1 }!)
    }
}

private struct PMICPItem: Codable, Identifiable {
    let id: UUID
    let domain: String
    let task: Int
    let difficulty: String
    let stem: String
    let rationale: String
    let options: [String]
    let correctIndex: Int

    var domainName: String {
        switch domain {
        case "C": return "Contracts Management"
        case "S": return "Stakeholder Engagement"
        case "T": return "Strategy & Scope Management"
        case "G": return "Project Governance"
        default: return domain
        }
    }
}

private struct PMICPAttempt: Codable {
    let candidate: String
    let items: [PMICPItem]
    var answers: [Int?]
    var flags: [Bool]
    var index: Int
    let deadline: Date
    var submitted: Bool
}

@MainActor
private final class PMICPStore: ObservableObject {
    @Published private(set) var attempt: PMICPAttempt?
    @Published private(set) var secondsLeft = 13_800
    @Published private(set) var loading = false
    @Published var error: String?

    private let key = "SimulaPro.PMICP.Attempt.v1"
    private let endpoint = URL(string: "https://pmi-cp-simulapro.pages.dev/api/questions")!

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(PMICPAttempt.self, from: data),
           saved.items.count == 120, saved.answers.count == 120,
           saved.flags.count == 120, (0..<120).contains(saved.index) {
            attempt = saved
            tick()
        }
    }

    var isFinished: Bool { attempt?.submitted == true || secondsLeft == 0 }
    var answered: Int { attempt?.answers.compactMap { $0 }.count ?? 0 }
    var flagged: Int { attempt?.flags.filter { $0 }.count ?? 0 }
    var correct: Int {
        guard let attempt else { return 0 }
        return attempt.items.indices.filter {
            attempt.answers[$0] == attempt.items[$0].correctIndex
        }.count
    }

    func load(candidate: String) async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw PMICPError.unavailable
            }
            let bank = try JSONDecoder().decode(PMICPBank.self, from: data)
            guard Self.valid(bank) else { throw PMICPError.invalidBank }
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            attempt = PMICPAttempt(candidate: name.isEmpty ? "Candidate" : name,
                                   items: bank.questions.shuffled().map { $0.examItem() },
                                   answers: Array(repeating: nil, count: 120),
                                   flags: Array(repeating: false, count: 120),
                                   index: 0, deadline: Date().addingTimeInterval(13_800),
                                   submitted: false)
            secondsLeft = 13_800
            save()
        } catch {
            self.error = "Could not load the 120-question exam. Check your connection and try again."
        }
    }

    func tick() {
        guard let attempt else { return }
        secondsLeft = max(0, Int(ceil(attempt.deadline.timeIntervalSinceNow)))
        if secondsLeft == 0 && !attempt.submitted { submit() }
    }

    func answer(_ option: Int) {
        guard var attempt, !isFinished, (0..<4).contains(option) else { return }
        attempt.answers[attempt.index] = option
        self.attempt = attempt
        save()
    }

    func toggleFlag() {
        guard var attempt, !isFinished else { return }
        attempt.flags[attempt.index].toggle()
        self.attempt = attempt
        save()
    }

    func go(_ index: Int) {
        guard var attempt, !isFinished, (0..<attempt.items.count).contains(index) else { return }
        attempt.index = index
        self.attempt = attempt
        save()
    }

    func submit() {
        guard var attempt else { return }
        attempt.submitted = true
        self.attempt = attempt
        save()
    }

    func restart() {
        UserDefaults.standard.removeObject(forKey: key)
        attempt = nil
        secondsLeft = 13_800
        error = nil
    }

    func domainScore(_ code: String) -> (Int, Int) {
        guard let attempt else { return (0, 0) }
        let indices = attempt.items.indices.filter { attempt.items[$0].domain == code }
        return (indices.filter {
            attempt.answers[$0] == attempt.items[$0].correctIndex
        }.count, indices.count)
    }

    private func save() {
        guard let attempt, let data = try? JSONEncoder().encode(attempt) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func valid(_ bank: PMICPBank) -> Bool {
        guard bank.total == 120, bank.questions.count == 120,
              Set(bank.questions.map { $0.stem }).count == 120 else { return false }
        let domains = ["C": 60, "S": 36, "T": 18, "G": 6]
        for (code, count) in domains {
            guard bank.questions.filter({ $0.domain == code }).count == count else { return false }
        }
        return bank.questions.allSatisfy { question in
            let choices = [question.correct] + question.distractors
            return choices.count == 4 && Set(choices).count == 4 &&
                !question.stem.isEmpty && !question.rationale.isEmpty &&
                choices.allSatisfy { !$0.isEmpty }
        }
    }

    private enum PMICPError: Error { case unavailable, invalidBank }
}

struct PMICPExamView: View {
    let onExit: () -> Void
    @StateObject private var store = PMICPStore()
    @State private var candidate = ""
    @State private var showingNavigator = false
    @State private var confirmSubmit = false
    @State private var confirmExit = false

    private let blue = Color(red: 0.075, green: 0.29, blue: 0.77)
    private let ink = Color(red: 0.075, green: 0.145, blue: 0.31)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let attempt = store.attempt {
                    if store.isFinished { results(attempt) }
                    else { exam(attempt) }
                } else {
                    welcome
                }
            }
            .navigationTitle("PMI-CP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if store.attempt != nil && !store.isFinished { confirmExit = true }
                        else { onExit() }
                    } label: {
                        Label("Simula Pro", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("pmiCPBackToCatalog")
                }
            }
        }
        .onReceive(timer) { _ in store.tick() }
        .sheet(isPresented: $showingNavigator) { navigator }
        .alert("Submit PMI-CP exam?", isPresented: $confirmSubmit) {
            Button("Keep Exam", role: .cancel) {}
            Button("Submit", role: .destructive) {
                showingNavigator = false
                store.submit()
            }
        } message: {
            Text("Your answers will be scored and the exam will end.")
        }
        .alert("Return to Simula Pro?", isPresented: $confirmExit) {
            Button("Keep Exam", role: .cancel) {}
            Button("Return") { onExit() }
        } message: {
            Text("Your PMI-CP progress and remaining time are saved. The timer continues while you are away.")
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 54))
                    .foregroundStyle(blue)
                Text("PMI Construction Professional (PMI-CP)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(ink)
                Text("A full-length practice exam with 120 original questions and a 230-minute timer.")
                    .font(.body)
                Label("120 questions, without repetition", systemImage: "checkmark.circle")
                Label("230 minutes", systemImage: "clock")
                Label("Answers, flags, and progress saved on this iPhone", systemImage: "square.and.arrow.down")
                TextField("Candidate name (optional)", text: $candidate)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await store.load(candidate: candidate) }
                } label: {
                    if store.loading { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Start PMI-CP Exam").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.loading)
                .accessibilityIdentifier("pmiCPStart")
                if let error = store.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("pmiCPError")
                }
                Text("Questions are downloaded when you start. An internet connection is required to begin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func exam(_ attempt: PMICPAttempt) -> some View {
        let item = attempt.items[attempt.index]
        return VStack(spacing: 0) {
            HStack {
                Text("Question \(attempt.index + 1) of 120").font(.headline)
                Spacer()
                Text(clockText).monospacedDigit().font(.headline)
                    .foregroundStyle(store.secondsLeft < 600 ? .red : blue)
            }
            .padding()
            .background(Color(red: 0.94, green: 0.97, blue: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.domainName).font(.subheadline).foregroundStyle(blue)
                    Text(item.stem).font(.title3.bold()).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(item.options.indices, id: \.self) { option in
                        Button { store.answer(option) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: attempt.answers[attempt.index] == option
                                      ? "largecircle.fill.circle" : "circle")
                                Text(item.options[option])
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(attempt.answers[attempt.index] == option
                                        ? blue.opacity(0.12) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pmiCPChoice-\(option)")
                    }
                }
                .padding(18)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            HStack {
                Button("Previous") { store.go(attempt.index - 1) }
                    .disabled(attempt.index == 0)
                Spacer()
                Button {
                    store.toggleFlag()
                } label: {
                    Image(systemName: attempt.flags[attempt.index] ? "flag.fill" : "flag")
                }
                .accessibilityLabel(attempt.flags[attempt.index] ? "Remove flag" : "Flag question")
                Spacer()
                Button("Review") { showingNavigator = true }
                Spacer()
                Button(attempt.index == 119 ? "Finish" : "Next") {
                    if attempt.index == 119 { showingNavigator = true }
                    else { store.go(attempt.index + 1) }
                }
            }
            .buttonStyle(.bordered)
            .padding()
            .background(.regularMaterial)
        }
        .accessibilityIdentifier("pmiCPExam")
    }

    private var navigator: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(store.answered) answered  •  \(store.flagged) flagged")
                }
                Section("Questions") {
                    if let attempt = store.attempt {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5),
                                  spacing: 10) {
                            ForEach(attempt.items.indices, id: \.self) { index in
                                Button {
                                    store.go(index)
                                    showingNavigator = false
                                } label: {
                                    Text("\(index + 1)")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(attempt.answers[index] != nil
                                                    ? blue.opacity(0.16) : Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .accessibilityLabel("Question \(index + 1)\(attempt.flags[index] ? ", flagged" : "")")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review & Navigate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { showingNavigator = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") { confirmSubmit = true }
                }
            }
        }
        .alert("Submit PMI-CP exam?", isPresented: $confirmSubmit) {
            Button("Keep Exam", role: .cancel) {}
            Button("Submit", role: .destructive) {
                showingNavigator = false
                store.submit()
            }
        } message: {
            Text("Your answers will be scored and the exam will end.")
        }
    }

    private func results(_ attempt: PMICPAttempt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Score Report").font(.largeTitle.bold()).foregroundStyle(ink)
                Text("\(store.correct) / 120 correct")
                    .font(.title.bold()).foregroundStyle(blue)
                Text("\(Int(Double(store.correct) / 120 * 100))%")
                    .font(.title2)
                Text("Domain breakdown").font(.title3.bold())
                ForEach(["C", "S", "T", "G"], id: \.self) { code in
                    let score = store.domainScore(code)
                    HStack {
                        Text(domainName(code))
                        Spacer()
                        Text("\(score.0)/\(score.1)").bold()
                    }
                }
                Divider()
                Text("Answer Review").font(.title3.bold())
                ForEach(attempt.items.indices, id: \.self) { index in
                    let item = attempt.items[index]
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(index + 1). \(item.stem)").font(.headline)
                        Text("Your answer: " + (attempt.answers[index].map {
                            item.options[$0]
                        } ?? "Not answered"))
                        Text("Correct: \(item.options[item.correctIndex])")
                            .foregroundStyle(.green)
                        Text(item.rationale).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button("Start a New PMI-CP Exam") { store.restart() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("pmiCPResults")
    }

    private var clockText: String {
        let hours = store.secondsLeft / 3600
        let minutes = (store.secondsLeft % 3600) / 60
        let seconds = store.secondsLeft % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func domainName(_ code: String) -> String {
        switch code {
        case "C": return "Contracts Management"
        case "S": return "Stakeholder Engagement"
        case "T": return "Strategy & Scope Management"
        case "G": return "Project Governance"
        default: return code
        }
    }
}


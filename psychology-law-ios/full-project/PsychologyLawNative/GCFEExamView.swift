import SwiftUI
import WebKit
import Combine

private struct PracticeQuestion: Codable, Identifiable {
    let id: String
    let topic: String
    let family: String
    let kind: String
    let question: String
    let options: [String]
    let explanation: String
    let reference: String
    let unit: String
    let diagramSVG: String
    let optionSVGs: [String]
    let tokens: [String]
    let slotLabels: [String]
    let blankLabels: [String]
    let tolerance: Double
    let radius: Double
    let answerIndex: Int
    let answerNumber: Double
    let answerIndices: [Int]
    let answerTexts: [String]
    let accepted: [[String]]
    let answerPoint: [Double]
}

private struct PracticeResponse: Codable {
    var indices: [Int] = []
    var texts: [String] = []
    var point: [Double] = []
    var numeric: String = ""
    var answered: Bool { indices.contains(where: { $0 >= 0 }) || !texts.allSatisfy(\.isEmpty) || point.count == 2 || !numeric.isEmpty }
}

private struct PracticeAttempt: Codable {
    let mode: String
    let ids: [String]
    var responses: [PracticeResponse]
    var flags: [Bool]
    var index: Int
    var deadline: Date
    var remainingAtBreak: Int?
    var breakUntil: Date?
    var sectionLocked: Bool
    var submitted: Bool
}

private enum NativePracticeBank {
    static let gcCategories = [
        "Establishing the Contracting Business",
        "Managing Administrative Duties",
        "Managing Trade Operations",
        "Conducting Accounting Functions",
        "Managing Human Resources",
        "Complying with Government Regulations"
    ]
    static let gcFull = [13, 31, 12, 38, 7, 19]
    static let gcQuick = [3, 8, 3, 10, 2, 4]
    static let feTargets: [(String, Int)] = [
        ("Mathematics", 7), ("Probability and Statistics", 4),
        ("Ethics and Professional Practice", 4), ("Engineering Economics", 4),
        ("Electricity and Magnetism", 6), ("Statics", 11),
        ("Dynamics, Kinematics, and Vibrations", 11), ("Mechanics of Materials", 10),
        ("Material Properties and Processing", 8), ("Fluid Mechanics", 11),
        ("Thermodynamics", 11), ("Heat Transfer", 8),
        ("Measurements, Instrumentation, and Controls", 5),
        ("Mechanical Design and Analysis", 10)
    ]
    static let fePriority: [(String, String)] = [
        ("Mathematics", "fill_blank"), ("Mathematics", "fill_blank"), ("Mathematics", "multi"),
        ("Probability and Statistics", "hotspot"), ("Probability and Statistics", "graphic_choice"),
        ("Ethics and Professional Practice", "multi"), ("Engineering Economics", "fill_blank"),
        ("Electricity and Magnetism", "multi"), ("Statics", "drag_drop"), ("Statics", "drag_drop"),
        ("Dynamics, Kinematics, and Vibrations", "graphic_choice"),
        ("Mechanics of Materials", "drag_drop"), ("Material Properties and Processing", "graphic_choice"),
        ("Fluid Mechanics", "drag_drop"), ("Fluid Mechanics", "drag_drop"), ("Fluid Mechanics", "hotspot"),
        ("Thermodynamics", "drag_drop"), ("Thermodynamics", "drag_drop"), ("Thermodynamics", "fill_blank"),
        ("Heat Transfer", "drag_drop"), ("Heat Transfer", "hotspot"),
        ("Measurements, Instrumentation, and Controls", "multi"),
        ("Measurements, Instrumentation, and Controls", "hotspot"),
        ("Measurements, Instrumentation, and Controls", "fill_blank"),
        ("Mechanical Design and Analysis", "multi"), ("Mechanical Design and Analysis", "drag_drop")
    ]

    static func load(_ fe: Bool) throws -> [PracticeQuestion] {
        guard let url = cacheURL(fe) else {
            throw NSError(domain: "SimulaPro", code: 1, userInfo: [NSLocalizedDescriptionKey: "Question bank unavailable"])
        }
        return try JSONDecoder().decode([PracticeQuestion].self, from: Data(contentsOf: url))
    }

    private static func cacheURL(_ fe: Bool) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fe ? "simulapro_fe_questions_v1.json" : "simulapro_gc_questions_v1.json")
    }

    private static func parseArray(_ source: String, marker: String) throws -> [[String: Any]] {
        guard let start = source.range(of: marker)?.upperBound,
              let open = source[start...].firstIndex(of: "[") else {
            throw NSError(domain: "SimulaPro", code: 3)
        }
        var depth = 0, quoted = false, escaped = false
        var close: String.Index?
        for i in source[open...].indices {
            let c = source[i]
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "[" { depth += 1 }
            else if c == "]" {
                depth -= 1
                if depth == 0 { close = i; break }
            }
        }
        guard let close, let json = String(source[open...close]).data(using: .utf8),
              let part = try JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
            throw NSError(domain: "SimulaPro", code: 4)
        }
        return part
    }

    static func downloadGC() async throws -> [PracticeQuestion] {
        var request = URLRequest(url: URL(string: "https://gc.simulapro.us/")!)
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let source = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SimulaPro", code: 8)
        }
        let records = try parseArray(source, marker: "let bank=")
        guard records.count == 242 else { throw NSError(domain: "SimulaPro", code: 9) }
        let normalized: [[String: Any]] = records.compactMap { q in
            guard let id = q["id"] as? String,
                  let topic = q["cat"] as? String,
                  let question = q["stem"] as? String else { return nil }
            return [
                "id": id, "topic": topic, "family": id, "kind": "single",
                "question": question, "options": q["options"] ?? [],
                "explanation": q["explanation"] ?? "", "reference": q["reference"] ?? "",
                "unit": "", "diagramSVG": "", "optionSVGs": [], "tokens": [],
                "slotLabels": [], "blankLabels": [], "tolerance": 0, "radius": 0.08,
                "answerIndex": q["answer"] ?? -1, "answerNumber": 0,
                "answerIndices": [], "answerTexts": [], "accepted": [], "answerPoint": []
            ]
        }
        guard normalized.count == 242 else { throw NSError(domain: "SimulaPro", code: 10) }
        let normalizedData = try JSONSerialization.data(withJSONObject: normalized)
        let bank = try JSONDecoder().decode([PracticeQuestion].self, from: normalizedData)
        guard Set(bank.map(\.id)).count == 242 else { throw NSError(domain: "SimulaPro", code: 11) }
        if let url = cacheURL(false) { try? normalizedData.write(to: url, options: .atomic) }
        return bank
    }

    static func downloadFE() async throws -> [PracticeQuestion] {
        let urls = [
            URL(string: "https://fe.simulapro.us/assets/bank.js")!,
            URL(string: "https://fe.simulapro.us/assets/advanced-bank.js?v=3")!
        ]
        var records: [[String: Any]] = []
        for (url, marker) in zip(urls, ["window.FE_BANK = ", "window.FE_BANK.push(..."]) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "SimulaPro", code: 3)
            }
            records += try parseArray(source, marker: marker)
        }
        guard records.count == 4073 else { throw NSError(domain: "SimulaPro", code: 5) }
        let normalized: [[String: Any]] = records.compactMap { q in
            guard let id = q["staticId"] as? String,
                  let topic = q["topic"] as? String,
                  let family = q["family"] as? Int,
                  let kind = q["kind"] as? String,
                  let question = q["question"] as? String,
                  let quality = q["quality"] as? [String: Any],
                  quality["status"] as? String == "auto_verified_practice" else { return nil }
            let answer = q["answer"]
            return [
                "id": id, "topic": topic, "family": String(family), "kind": kind,
                "question": question, "options": q["options"] ?? [],
                "explanation": q["explanation"] ?? "", "reference": "",
                "unit": q["unit"] ?? "", "diagramSVG": q["diagram_svg"] ?? "",
                "optionSVGs": q["option_svgs"] ?? [], "tokens": q["tokens"] ?? [],
                "slotLabels": ((q["slots"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String },
                "blankLabels": q["blank_labels"] ?? [],
                "tolerance": q["tolerance"] ?? 0, "radius": q["hotspot_radius"] ?? 0.08,
                "answerIndex": (kind == "single" || kind == "graphic_choice") ? (answer as? Int ?? -1) : -1,
                "answerNumber": kind == "numeric" ? (answer as? Double ?? 0) : 0,
                "answerIndices": (kind == "multi" || kind == "drag_drop") ? (answer as? [Int] ?? []) : [],
                "answerTexts": kind == "fill_blank" ? (answer as? [String] ?? []) : [],
                "accepted": q["accepted"] ?? [],
                "answerPoint": kind == "hotspot" ? (answer as? [Double] ?? []) : []
            ]
        }
        guard normalized.count == 4073 else { throw NSError(domain: "SimulaPro", code: 6) }
        let data = try JSONSerialization.data(withJSONObject: normalized)
        let bank = try JSONDecoder().decode([PracticeQuestion].self, from: data)
        guard Set(bank.map(\.id)).count == 4073 else { throw NSError(domain: "SimulaPro", code: 7) }
        if let url = cacheURL(true) {
            try? data.write(to: url, options: .atomic)
        }
        return bank
    }

    static func selectGC(_ bank: [PracticeQuestion], mode: String) -> [PracticeQuestion] {
        let quotas = mode == "quick" ? gcQuick : gcFull
        var result: [PracticeQuestion] = []
        for (category, count) in zip(gcCategories, quotas) {
            result += bank.filter { $0.topic == category }.shuffled().prefix(count)
        }
        return result.shuffled()
    }

    static func selectFE(_ bank: [PracticeQuestion]) -> [PracticeQuestion] {
        let history = Set((UserDefaults.standard.stringArray(forKey: "SimulaPro.FE.History") ?? []).suffix(650))
        var result: [PracticeQuestion] = []
        for (topic, target) in feTargets {
            let topicItems = bank.filter { $0.topic == topic }
            let byFamily = Dictionary(grouping: topicItems, by: \.family)
            var used = Set<String>()
            var part: [PracticeQuestion] = []
            func pick(_ kind: String) {
                guard part.count < target else { return }
                let families = byFamily.keys.filter {
                    !used.contains($0) && (byFamily[$0]?.contains { $0.kind == kind } == true)
                }.shuffled()
                guard let family = families.first else { return }
                let pool = (byFamily[family] ?? []).filter { $0.kind == kind }.shuffled()
                guard let item = pool.first(where: { !history.contains($0.id) }) ?? pool.first else { return }
                part.append(item)
                used.insert(family)
            }
            for (name, kind) in fePriority where name == topic { pick(kind) }
            pick("numeric")
            for family in byFamily.keys.shuffled() where part.count < target && !used.contains(family) {
                let pool = byFamily[family] ?? []
                let preferred = pool.contains(where: { $0.kind == "single" }) ? "single" : (pool.first?.kind ?? "")
                let eligible = pool.filter { $0.kind == preferred }.shuffled()
                if let item = eligible.first(where: { !history.contains($0.id) }) ?? eligible.first {
                    part.append(item)
                    used.insert(family)
                }
            }
            result += part
        }
        return result.shuffled()
    }
}

@MainActor
private final class NativePracticeStore: ObservableObject {
    let fe: Bool
    @Published var attempt: PracticeAttempt?
    @Published var error: String?
    @Published var secondsLeft = 0
    private(set) var questions: [PracticeQuestion] = []
    private var bank: [PracticeQuestion]
    @Published private(set) var loading = false
    private var key: String { fe ? "SimulaPro.FE.Attempt.v1" : "SimulaPro.GC.Attempt.v1" }

    init(fe: Bool) {
        self.fe = fe
        do {
            let loaded = try NativePracticeBank.load(fe)
            guard loaded.count == (fe ? 4073 : 242),
                  Set(loaded.map(\.id)).count == loaded.count else {
                throw NSError(domain: "SimulaPro", code: 2)
            }
            bank = loaded
            restore()
            tick()
        } catch {
            bank = []
        }
    }

    func prepare() async {
        guard bank.isEmpty, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if fe { bank = try await NativePracticeBank.downloadFE() }
            else { bank = try await NativePracticeBank.downloadGC() }
            restore()
            tick()
        } catch {
            self.error = "Questions are unavailable. Check your connection and try again."
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(PracticeAttempt.self, from: data) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: bank.map { ($0.id, $0) })
        let restored = saved.ids.compactMap { lookup[$0] }
        if restored.count == saved.ids.count && saved.responses.count == restored.count &&
            saved.flags.count == restored.count && restored.indices.contains(saved.index) {
            questions = restored
            attempt = saved
        }
    }

    var isFinished: Bool { attempt?.submitted == true || (attempt != nil && secondsLeft == 0 && attempt?.remainingAtBreak == nil) }
    var answered: Int { attempt?.responses.filter(\.answered).count ?? 0 }
    var flagged: Int { attempt?.flags.filter { $0 }.count ?? 0 }

    func start(mode: String) {
        guard !bank.isEmpty else { return }
        let selected = fe ? NativePracticeBank.selectFE(bank) : NativePracticeBank.selectGC(bank, mode: mode)
        let expected = fe ? 110 : mode == "quick" ? 30 : 120
        guard selected.count == expected && Set(selected.map(\.id)).count == expected,
              (!fe || Set(selected.map(\.family)).count == 110) else {
            error = "Could not assemble a complete, unique exam."
            return
        }
        questions = selected
        let duration = fe ? 19_200 : mode == "quick" ? 5_850 : 23_400
        attempt = PracticeAttempt(mode: mode, ids: selected.map(\.id),
                                  responses: Array(repeating: PracticeResponse(), count: expected),
                                  flags: Array(repeating: false, count: expected), index: 0,
                                  deadline: Date().addingTimeInterval(TimeInterval(duration)),
                                  remainingAtBreak: nil, breakUntil: nil,
                                  sectionLocked: false, submitted: false)
        if fe {
            var history = UserDefaults.standard.stringArray(forKey: "SimulaPro.FE.History") ?? []
            history += selected.map(\.id)
            UserDefaults.standard.set(Array(history.suffix(650)), forKey: "SimulaPro.FE.History")
        }
        secondsLeft = duration
        save()
    }

    func tick() {
        guard var attempt, !attempt.submitted else { return }
        if let breakUntil = attempt.breakUntil {
            if Date() >= breakUntil { resumeFromBreak() }
            return
        }
        secondsLeft = max(0, Int(ceil(attempt.deadline.timeIntervalSinceNow)))
        if secondsLeft == 0 {
            attempt.submitted = true
            self.attempt = attempt
            save()
        }
    }

    func update(_ response: PracticeResponse) {
        guard var attempt, !isFinished, attempt.breakUntil == nil else { return }
        attempt.responses[attempt.index] = response
        self.attempt = attempt
        save()
    }

    func toggleFlag() {
        guard var attempt, !isFinished, attempt.breakUntil == nil else { return }
        attempt.flags[attempt.index].toggle()
        self.attempt = attempt
        save()
    }

    func go(_ index: Int) {
        guard var attempt, !isFinished, attempt.breakUntil == nil,
              attempt.ids.indices.contains(index),
              !(fe && !attempt.sectionLocked && index >= 55),
              !(attempt.sectionLocked && index < 55) else { return }
        attempt.index = index
        self.attempt = attempt
        save()
    }

    func beginBreak() {
        guard fe, var attempt, attempt.index == 54, !attempt.sectionLocked, !isFinished else { return }
        attempt.remainingAtBreak = secondsLeft
        attempt.breakUntil = Date().addingTimeInterval(1_500)
        attempt.sectionLocked = true
        attempt.index = 55
        self.attempt = attempt
        save()
    }

    func resumeFromBreak() {
        guard var attempt, let remaining = attempt.remainingAtBreak else { return }
        attempt.deadline = Date().addingTimeInterval(TimeInterval(remaining))
        attempt.remainingAtBreak = nil
        attempt.breakUntil = nil
        secondsLeft = remaining
        self.attempt = attempt
        save()
    }

    func submit() {
        guard var attempt else { return }
        attempt.submitted = true
        attempt.breakUntil = nil
        attempt.remainingAtBreak = nil
        self.attempt = attempt
        save()
    }

    func restart() {
        UserDefaults.standard.removeObject(forKey: key)
        questions = []
        attempt = nil
        secondsLeft = 0
        error = nil
    }

    func correct(_ index: Int) -> Bool {
        guard let attempt, questions.indices.contains(index) else { return false }
        let q = questions[index], r = attempt.responses[index]
        switch q.kind {
        case "single", "graphic_choice": return r.indices.first == q.answerIndex
        case "multi": return Set(r.indices) == Set(q.answerIndices)
        case "drag_drop": return r.indices == q.answerIndices
        case "numeric":
            guard let n = Double(r.numeric.replacingOccurrences(of: ",", with: ".")) else { return false }
            return abs(n - q.answerNumber) <= q.tolerance
        case "fill_blank":
            return q.answerTexts.indices.allSatisfy { i in
                guard r.texts.indices.contains(i) else { return false }
                let value = r.texts[i].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let allowed = q.accepted.indices.contains(i) ? q.accepted[i] : [q.answerTexts[i]]
                return allowed.contains { $0.lowercased() == value }
            }
        case "hotspot":
            guard r.point.count == 2, q.answerPoint.count == 2 else { return false }
            return hypot(r.point[0] - q.answerPoint[0], r.point[1] - q.answerPoint[1]) <= q.radius
        default: return false
        }
    }

    private func save() {
        if let attempt, let data = try? JSONEncoder().encode(attempt) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct GCFEExamView: View {
    let fe: Bool
    let onExit: () -> Void
    @StateObject private var store: NativePracticeStore
    @State private var showingNavigator = false
    @State private var showingSubmit = false
    @State private var showingBreak = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let blue = Color(red: 0.07, green: 0.27, blue: 0.65)

    init(fe: Bool, onExit: @escaping () -> Void) {
        self.fe = fe
        self.onExit = onExit
        _store = StateObject(wrappedValue: NativePracticeStore(fe: fe))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let attempt = store.attempt {
                    if store.isFinished { results(attempt) }
                    else if attempt.breakUntil != nil { breakScreen(attempt) }
                    else { exam(attempt) }
                } else { welcome.task { await store.prepare() } }
            }
            .navigationTitle(fe ? "FE Mechanical" : "GC Business & Finance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onExit) { Label("Simula Pro", systemImage: "chevron.left") }
                }
            }
            .onReceive(timer) { _ in store.tick() }
            .sheet(isPresented: $showingNavigator) { navigator }
            .confirmationDialog("Submit this exam?", isPresented: $showingSubmit) {
                Button("Submit exam", role: .destructive) { store.submit() }
            } message: { Text("You can review answers and explanations after submitting.") }
            .confirmationDialog("Finish the first section and take the break?", isPresented: $showingBreak) {
                Button("Begin 25-minute break") { store.beginBreak() }
            } message: { Text("The first 55 FE questions will be locked. Your exam timer pauses during the break.") }
        }
        .tint(blue)
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(fe ? "FEMark" : "GCMark").resizable().scaledToFit()
                    .frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 18))
                Text(fe ? "FE Mechanical practice exam" : "GC Business & Finance practice exam")
                    .font(.title.bold())
                Text(fe ? "110 questions across 14 subjects · 5 hours 20 minutes of exam time · optional 25-minute break after question 55." :
                        "120 questions · 6 hours 30 minutes · six business and finance domains.")
                    .foregroundStyle(.secondary)
                Text(fe ? "Loads 4,073 practice questions from the existing FE simulator and caches them on this iPhone. Questions are auto-verified and have not been reviewed by an engineer." :
                        "Loads 242 practice questions from the existing GC simulator and caches them on this iPhone. This is independent exam preparation.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.loading { ProgressView("Loading questions…") }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button(fe ? "Start full FE exam" : "Start full GC exam") { store.start(mode: "full") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(store.loading || store.error != nil)
                if !fe {
                    Button("Start 30-question quick exam") { store.start(mode: "quick") }
                        .buttonStyle(.bordered).controlSize(.large)
                        .disabled(store.loading || store.error != nil)
                }
            }
            .padding(24).frame(maxWidth: 650, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func exam(_ attempt: PracticeAttempt) -> some View {
        let q = store.questions[attempt.index]
        let response = attempt.responses[attempt.index]
        return VStack(spacing: 0) {
            HStack {
                Text("Question \(attempt.index + 1) of \(attempt.ids.count)").font(.headline)
                Spacer()
                Text(clock(store.secondsLeft)).monospacedDigit().font(.headline)
                    .accessibilityIdentifier("examTimer")
            }.padding().background(Color(.secondarySystemBackground))
            ProgressView(value: Double(attempt.index + 1), total: Double(attempt.ids.count))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(q.topic.uppercased()).font(.caption.bold()).foregroundStyle(blue)
                    Text(q.question).font(.title3).textSelection(.enabled)
                    if !q.diagramSVG.isEmpty && q.kind != "hotspot" {
                        SVGPanel(svg: q.diagramSVG).frame(height: 245)
                    }
                    answerControls(q, response)
                    if !q.reference.isEmpty { Text("Reference: \(q.reference)").font(.caption).foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth: 730, alignment: .leading).frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                Button { showingNavigator = true } label: { Image(systemName: "square.grid.3x3") }
                    .accessibilityLabel("Question navigator")
                Button { store.toggleFlag() } label: {
                    Image(systemName: attempt.flags[attempt.index] ? "flag.fill" : "flag")
                }.accessibilityLabel("Flag question")
                Spacer()
                Button("Previous") { store.go(attempt.index - 1) }
                    .disabled(attempt.index == 0 || (fe && attempt.sectionLocked && attempt.index == 55))
                if fe && attempt.index == 54 && !attempt.sectionLocked {
                    Button("Section break") { showingBreak = true }.buttonStyle(.borderedProminent)
                } else if attempt.index + 1 < attempt.ids.count {
                    Button("Next") { store.go(attempt.index + 1) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Submit") { showingSubmit = true }.buttonStyle(.borderedProminent)
                }
            }.padding().background(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder private func answerControls(_ q: PracticeQuestion, _ response: PracticeResponse) -> some View {
        switch q.kind {
        case "single", "graphic_choice":
            ForEach(q.options.indices, id: \.self) { i in
                Button {
                    var r = response; r.indices = [i]; store.update(r)
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: response.indices.first == i ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(q.options[i]).frame(maxWidth: .infinity, alignment: .leading)
                            if q.optionSVGs.indices.contains(i) {
                                SVGPanel(svg: q.optionSVGs[i]).frame(height: 130)
                            }
                        }
                    }.padding(13).background(response.indices.first == i ? blue.opacity(0.1) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        case "multi":
            Text("Select all correct answers").font(.subheadline).foregroundStyle(.secondary)
            ForEach(q.options.indices, id: \.self) { i in
                Button {
                    var r = response
                    if r.indices.contains(i) { r.indices.removeAll { $0 == i } } else { r.indices.append(i) }
                    store.update(r)
                } label: {
                    HStack {
                        Image(systemName: response.indices.contains(i) ? "checkmark.square.fill" : "square")
                        Text(q.options[i]).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(13).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        case "numeric":
            TextField("Enter number \(q.unit)", text: Binding(
                get: { response.numeric },
                set: { var r = response; r.numeric = $0; store.update(r) }
            )).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            if !q.unit.isEmpty { Text("Unit: \(q.unit)").font(.caption).foregroundStyle(.secondary) }
        case "fill_blank":
            ForEach(q.blankLabels.indices, id: \.self) { i in
                TextField(q.blankLabels[i], text: Binding(
                    get: { response.texts.indices.contains(i) ? response.texts[i] : "" },
                    set: { value in
                        var r = response
                        while r.texts.count <= i { r.texts.append("") }
                        r.texts[i] = value
                        store.update(r)
                    }
                )).textFieldStyle(.roundedBorder)
            }
        case "drag_drop":
            Text("Choose a label for each diagram position.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(q.slotLabels.indices, id: \.self) { i in
                VStack(alignment: .leading) {
                    Text(q.slotLabels[i]).font(.headline)
                    Picker(q.slotLabels[i], selection: Binding(
                        get: { response.indices.indices.contains(i) ? response.indices[i] : -1 },
                        set: { value in
                            var r = response
                            while r.indices.count <= i { r.indices.append(-1) }
                            r.indices[i] = value
                            store.update(r)
                        }
                    )) {
                        Text("Select label").tag(-1)
                        ForEach(q.tokens.indices, id: \.self) { j in Text(q.tokens[j]).tag(j) }
                    }.pickerStyle(.menu)
                }.padding().background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case "hotspot":
            Text("Tap the correct point on the diagram.").font(.subheadline).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack {
                    SVGPanel(svg: q.diagramSVG)
                    if response.point.count == 2 {
                        Circle().stroke(.orange, lineWidth: 3).background(Circle().fill(.orange.opacity(0.25)))
                            .frame(width: 25, height: 25)
                            .position(x: response.point[0] * geometry.size.width,
                                      y: response.point[1] * geometry.size.height)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in
                    var r = response
                    r.point = [event.location.x / geometry.size.width, event.location.y / geometry.size.height]
                    store.update(r)
                })
            }.frame(height: 245)
        default:
            Text("Unsupported response format").foregroundStyle(.red)
        }
    }

    private var navigator: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(store.questions.indices, id: \.self) { i in
                        Button("\(i + 1)") { store.go(i); showingNavigator = false }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(store.attempt?.responses[i].answered == true ? blue.opacity(0.2) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .disabled(fe && ((store.attempt?.sectionLocked == true && i < 55) ||
                                              (store.attempt?.sectionLocked == false && i >= 55)))
                    }
                }.padding()
            }
            .navigationTitle("Questions · \(store.answered) answered")
            .toolbar { Button("Done") { showingNavigator = false } }
        }
    }

    private func breakScreen(_ attempt: PracticeAttempt) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 52)).foregroundStyle(blue)
            Text("Scheduled break").font(.title.bold())
            Text("Your exam timer is paused. Questions 1–55 are locked.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let until = attempt.breakUntil {
                Text("Break remaining: \(clock(max(0, Int(until.timeIntervalSinceNow))))")
                    .monospacedDigit().font(.headline)
            }
            Button("Resume section 2") { store.resumeFromBreak() }.buttonStyle(.borderedProminent)
        }.padding()
    }

    private func results(_ attempt: PracticeAttempt) -> some View {
        let score = store.questions.indices.filter { store.correct($0) }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Practice results").font(.largeTitle.bold())
                Text("\(score) / \(store.questions.count) correct")
                    .font(.title2.bold()).foregroundStyle(blue)
                Text("This practice score is not an official exam result.")
                    .foregroundStyle(.secondary)
                ForEach(store.questions.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(i + 1). \(store.questions[i].topic)")
                            .font(.headline)
                        Text(store.correct(i) ? "Correct" : "Incorrect")
                            .foregroundStyle(store.correct(i) ? .green : .red)
                        Text(store.questions[i].question)
                        Text(store.questions[i].explanation)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button("Start another exam") { store.restart() }
                    .buttonStyle(.borderedProminent)
            }.padding().frame(maxWidth: 730)
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

private struct SVGPanel: UIViewRepresentable {
    let svg: String
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{margin:0;display:flex;justify-content:center;align-items:center;height:100vh}svg{max-width:100%;max-height:100%;width:auto;height:auto}</style></head><body>\(svg)</body></html>"
        view.loadHTMLString(html, baseURL: nil)
    }
}

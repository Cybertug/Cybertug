import Foundation
import SwiftUI

private enum AccountPalette {
    static let navy = Color(red: 18 / 255, green: 48 / 255, blue: 95 / 255)
    static let green = Color(red: 31 / 255, green: 157 / 255, blue: 85 / 255)
    static let ink = Color(red: 28 / 255, green: 29 / 255, blue: 33 / 255)
    static let muted = Color(red: 107 / 255, green: 110 / 255, blue: 118 / 255)
    static let line = Color(red: 230 / 255, green: 230 / 255, blue: 234 / 255)
}

struct AccountExam: Identifiable {
    let id: String
    let name: String

    var nativeModule: SimulatorID? {
        switch id.lowercased() {
        case "psych", "fl-psych", "psychology-law": return .psychologyLaw
        case "pmi-cp", "pmicp": return .pmiCP
        case "gc", "gc-business-finance": return .gc
        case "fe", "fe-mechanical": return .fe
        default: return nil
        }
    }
}

fileprivate struct AccountAttempt: Identifiable {
    let id: UUID = UUID()
    let examID: String
    let examName: String
    let date: Double
    let questions: Int
    let score: Double
    let isFull: Bool
}

@MainActor
final class AccountDashboardStore: ObservableObject {
    @Published private(set) var exams: [AccountExam] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private var attempts: [AccountAttempt] = []
    @Published private var bankSizes: [String: Int] = [:]

    private let baseURL = URL(string: "https://simulapro.us")!

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            async let libraryData = fetch("/api/customer/dashboard", portalHeader: true)
            async let performanceData = fetch("/api/perf/summary")
            let (library, performance) = try await (libraryData, performanceData)
            let rows = library["library"] as? [[String: Any]] ?? []
            exams = rows.compactMap { row in
                guard let id = row["product_id"] as? String ?? row["id"] as? String else { return nil }
                return AccountExam(id: id, name: row["name"] as? String ?? id)
            }
            var results: [AccountAttempt] = []
            var sizes: [String: Int] = [:]
            for sim in performance["sims"] as? [[String: Any]] ?? [] {
                guard let id = sim["sim"] as? String else { continue }
                sizes[id] = Self.int(sim["bankN"])
                let name = sim["title"] as? String ?? id
                for attempt in sim["attempts"] as? [[String: Any]] ?? [] {
                    let count = Self.int(attempt["n"])
                    let correct = Self.int(attempt["right_n"])
                    var score = Self.double(attempt["pct"])
                    if score == 0 && count > 0 { score = Double(correct) * 100 / Double(count) }
                    if score <= 1 && correct > 0 && count > 0 { score *= 100 }
                    results.append(AccountAttempt(examID: id, examName: name,
                                                  date: Self.double(attempt["at"]),
                                                  questions: count, score: score,
                                                  isFull: attempt["full"] as? Bool ?? false))
                }
            }
            attempts = results.sorted { $0.date < $1.date }
            bankSizes = sizes
        } catch {
            self.error = "Your dashboard could not be loaded. Pull down to try again."
        }
    }

    private func fetch(_ path: String, portalHeader: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if portalHeader { request.setValue("portal", forHTTPHeaderField: "X-SimulaPro") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }

    private static func int(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    fileprivate static func canonical(_ id: String) -> String {
        switch id {
        case "gc": return "gc-business-finance"
        case "fl-psych": return "psych"
        default: return id
        }
    }

    fileprivate func attempts(for examID: String?) -> [AccountAttempt] {
        guard let examID else { return attempts }
        return attempts.filter { Self.canonical($0.examID) == Self.canonical(examID) }
    }

    fileprivate var practicedExams: [AccountExam] {
        let ids = Set(attempts.map { Self.canonical($0.examID) })
        return exams.filter { ids.contains(Self.canonical($0.id)) }
    }

    fileprivate func studyProgress(for examID: String) -> Double {
        let completed = attempts(for: examID).reduce(0) { $0 + $1.questions }
        guard completed > 0 else { return 0 }
        let bank = bankSizes[Self.canonical(examID)] ?? bankSizes[examID] ?? 0
        let target = bank > 0 ? Int(ceil(Double(bank) * log(1 / 0.3))) : 2400
        return min(1, Double(completed) / Double(max(1, target)))
    }
}

struct AccountDashboardView: View {
    let accountName: String
    let hasNativeAccess: (SimulatorID) -> Bool
    let onOpen: (SimulatorID) -> Void
    let onSignOut: () -> Void

    @StateObject private var store = AccountDashboardStore()
    @State private var selectedExam: String?
    @State private var search = ""

    private var recent: [AccountAttempt] { store.attempts(for: selectedExam) }
    private var firstName: String { accountName.split(separator: " ").first.map(String.init) ?? "there" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SimulaPro").font(.headline).foregroundColor(AccountPalette.navy)
                        Text("Hi, \(firstName)").font(.largeTitle.bold()).foregroundColor(AccountPalette.ink)
                    }
                    Spacer()
                    Button("Sign out", action: onSignOut).font(.footnote)
                }
                if store.isLoading && store.exams.isEmpty { ProgressView("Loading your dashboard…") }
                if let error = store.error { Text(error).foregroundColor(.red).font(.subheadline) }

                filterPicker
                metrics
                trend
                studyPlan
                continueStudying
                library
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.985, green: 0.985, blue: 0.99))
        .refreshable { await store.load() }
        .task { await store.load() }
        .accessibilityIdentifier("nativeOverview")
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("All exams", id: nil)
                ForEach(store.practicedExams) { exam in filterButton(exam.name, id: exam.id) }
            }
        }
    }

    private func filterButton(_ title: String, id: String?) -> some View {
        Button(title) { selectedExam = id }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(selectedExam == id ? AccountPalette.navy : .white)
            .foregroundColor(selectedExam == id ? .white : AccountPalette.navy)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metrics: some View {
        let total = recent.reduce(0) { $0 + $1.questions }
        let full = recent.filter(\.isFull).count
        let last = Array(recent.suffix(10))
        let average = last.isEmpty ? "–" : "\(Int((last.reduce(0) { $0 + $1.score } / Double(last.count)).rounded()))%"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric("Questions answered", "\(total)")
            metric("Practice sessions", "\(recent.count)")
            metric("Full exams taken", "\(full)")
            metric("Average score, last 10", average)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.title2.bold()).foregroundColor(AccountPalette.navy)
            Text(title).font(.caption).foregroundColor(AccountPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12).background(.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score trend").font(.headline).foregroundColor(AccountPalette.ink)
            if recent.isEmpty {
                Text("Your practice scores will appear here.").foregroundColor(AccountPalette.muted)
            } else {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(recent.suffix(10))) { attempt in
                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Text("\(Int(attempt.score.rounded()))%")
                                .font(.system(size: 9)).foregroundColor(AccountPalette.muted)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AccountPalette.green)
                                .frame(height: max(3, CGFloat(min(100, attempt.score)) * 1.1))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(attempt.examName), \(Int(attempt.score.rounded())) percent")
                    }
                }
                .frame(height: 135)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
    }

    private var studyPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Study plan").font(.headline).foregroundColor(AccountPalette.ink)
            ForEach(store.exams) { exam in
                let progress = store.studyProgress(for: exam.id)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(exam.name).font(.subheadline)
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.caption).foregroundColor(AccountPalette.muted)
                    }
                    ProgressView(value: progress).tint(AccountPalette.green)
                }
            }
            if store.exams.isEmpty && !store.isLoading {
                Text("Your simulators will appear here after you get access.")
                    .foregroundColor(AccountPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All your simulators").font(.headline).foregroundColor(AccountPalette.ink)
            TextField("Search exams", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("examSearch")
            ForEach(store.exams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { exam in
                HStack(spacing: 11) {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(AccountPalette.navy)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exam.name).font(.subheadline.weight(.semibold))
                        Text(exam.nativeModule.map { hasNativeAccess($0) ? "Ready on iPhone" : "iPhone version · Apple access required" } ?? "iPhone exam not yet available")
                            .font(.caption).foregroundColor(AccountPalette.muted)
                    }
                    Spacer(minLength: 0)
                    if let module = exam.nativeModule {
                        Button(hasNativeAccess(module) ? "Open" : "View plans") { onOpen(module) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 7)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
    }

    private var continueStudying: some View {
        let available = store.exams.filter { $0.nativeModule != nil && !store.attempts(for: $0.id).isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Continue studying").font(.headline).foregroundColor(AccountPalette.ink)
            if available.isEmpty {
                Text("Start a native practice exam to see it here.")
                    .foregroundColor(AccountPalette.muted)
            }
            ForEach(available) { exam in
                if let module = exam.nativeModule {
                    Button { onOpen(module) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exam.name).font(.subheadline.weight(.semibold))
                                Text("Open simulator · new session")
                                    .font(.caption).foregroundColor(AccountPalette.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(AccountPalette.navy)
                        .padding(12)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeStoreView: View {
    let offerings: [SimulatorOffering]
    let onChoose: (SimulatorID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Store").font(.largeTitle.bold()).foregroundColor(AccountPalette.ink)
                Text("Choose an iPhone simulator. Available plans and prices are supplied by Apple.")
                    .foregroundColor(AccountPalette.muted)
                ForEach(offerings) { offering in
                    HStack(spacing: 12) {
                        Image(offering.imageName).resizable().frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offering.title).font(.headline)
                            Text(offering.subtitle).font(.caption).foregroundColor(AccountPalette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccountPalette.line))
                    Button("View plans for \(offering.title)") { onChoose(offering.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(AccountPalette.navy)
                }
                Text("Other web simulator plans are not yet available as iPhone purchases.")
                    .font(.footnote).foregroundColor(AccountPalette.muted)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.985, green: 0.985, blue: 0.99))
        .accessibilityIdentifier("nativeStore")
    }
}

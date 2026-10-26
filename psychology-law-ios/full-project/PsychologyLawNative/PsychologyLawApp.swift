import SwiftUI

/// Only working native simulators belong in this catalog.
enum SimulatorID: String, Identifiable {
    case psychologyLaw, pmiCP, gc, fe
    var id: String { rawValue }
}

struct SimulatorOffering: Identifiable {
    let id: SimulatorID
    let title: String
    let subtitle: String
    let detail: String
    let imageName: String

    static let available: [SimulatorOffering] = [
        SimulatorOffering(id: .psychologyLaw,
                          title: "Psychology Law",
                          subtitle: "Florida Laws & Rules",
                          detail: "45 questions  ·  60 minutes",
                          imageName: "PsychologyLawMark"),
        SimulatorOffering(id: .pmiCP,
                          title: "PMI Construction Professional (PMI-CP)",
                          subtitle: "Construction practice exam",
                          detail: "120 questions  ·  230 minutes",
                          imageName: "PMICPMark"),
        SimulatorOffering(id: .gc,
                          title: "GC Business & Finance",
                          subtitle: "General Contractor practice exam",
                          detail: "120 questions  ·  390 minutes",
                          imageName: "GCMark"),
        SimulatorOffering(id: .fe,
                          title: "FE Mechanical",
                          subtitle: "Engineering practice exam",
                          detail: "110 questions  ·  320 minutes",
                          imageName: "FEMark")
    ]
}

@main
struct SimulaProApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-previewGC") {
                GCFEExamView(fe: false, onExit: {}).preferredColorScheme(.light)
            } else if ProcessInfo.processInfo.arguments.contains("-previewFE") {
                GCFEExamView(fe: true, onExit: {}).preferredColorScheme(.light)
            } else {
                SimulaProRootView().preferredColorScheme(.light)
            }
#else
            SimulaProRootView().preferredColorScheme(.light)
#endif
        }
    }
}

struct SimulaProRootView: View {
    @StateObject private var subscription = SubscriptionStore()
    @StateObject private var usage = UsageAccountStore()
    @State private var selectedModule: SimulatorID?
    @State private var paywallModule: SimulatorID = .psychologyLaw
    @State private var sessionNumber = 0
    @State private var showsSubscription = false
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    var body: some View {
        Group {
            if usage.isChecking {
                ProgressView("Checking your SimulaPro account…")
            } else if usage.user == nil {
                UsageSignInView(store: usage)
            } else if selectedModule == .psychologyLaw && subscription.hasAccess(to: "psychologyLaw") {
                ExamRootView(onExit: { selectedModule = nil }).id(sessionNumber)
            } else if selectedModule == .pmiCP && subscription.hasAccess(to: "pmiCP") {
                PMICPExamView(onExit: { selectedModule = nil }).id(sessionNumber)
            } else if selectedModule == .gc && subscription.hasAccess(to: "gc") {
                GCFEExamView(fe: false, onExit: { selectedModule = nil }).id(sessionNumber)
            } else if selectedModule == .fe && subscription.hasAccess(to: "fe") {
                GCFEExamView(fe: true, onExit: { selectedModule = nil }).id(sessionNumber)
            } else {
                SimulaProCatalogView(offerings: SimulatorOffering.available,
                                     subscription: subscription,
                                     accountName: usage.user?.name ?? "",
                                     onSignOut: { selectedModule = nil; Task { await usage.signOut() } },
                                     onSubscription: { showsSubscription = true }) { module in
                    if subscription.hasAccess(to: module.rawValue) {
                        sessionNumber += 1
                        selectedModule = module
                    } else {
                        paywallModule = module
                        showsSubscription = true
                    }
                }
            }
        }
        .task {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-reviewSubscription"),
               arguments.count > index + 1,
               let module = SimulatorID(rawValue: arguments[index + 1]) {
                paywallModule = module
                showsSubscription = true
            }
#endif
            await subscription.start()
            await usage.restore()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await subscription.refreshEntitlements() } }
            usage.setForeground(phase == .active, module: selectedModule?.rawValue ?? "catalog")
        }
        .onChange(of: selectedModule?.rawValue) { module in
            usage.setForeground(scenePhase == .active, module: module ?? "catalog")
        }
        .onChange(of: usage.user?.id) { _ in
            usage.setForeground(scenePhase == .active, module: selectedModule?.rawValue ?? "catalog")
        }
        .onChange(of: subscription.activeProductIDs) { _ in
            if let module = selectedModule, !subscription.hasAccess(to: module.rawValue) {
                selectedModule = nil
            }
        }
        .sheet(isPresented: $showsSubscription) {
            SubscriptionView(store: subscription, module: paywallModule.rawValue)
        }
    }
}

struct SimulaProCatalogView: View {
    let offerings: [SimulatorOffering]
    @ObservedObject var subscription: SubscriptionStore
    let accountName: String
    let onSignOut: () -> Void
    let onSubscription: () -> Void
    let onOpen: (SimulatorID) -> Void

    private let ink = Color(red: 0.075, green: 0.145, blue: 0.31)
    private let blue = Color(red: 0.075, green: 0.29, blue: 0.77)

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.967, blue: 0.988).ignoresSafeArea()
            VStack(spacing: 0) {
                brandHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your simulators")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(ink)
                            Text("Select a practice exam to get started.")
                                .font(.system(size: 16))
                                .foregroundColor(ink.opacity(0.73))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text("Signed in: " + accountName).font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Button("Sign out", action: onSignOut).font(.footnote)
                        }
                        Button(action: onSubscription) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Your subscriptions").font(.headline)
                                    Text(subscription.isLoading ? "Checking subscriptions…" :
                                         subscription.hasAccess ? "Manage access by simulator" :
                                         "Separate monthly and yearly plans for each simulator")
                                        .font(.subheadline)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(ink)
                            .padding(17)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .accessibilityIdentifier("subscriptionStatus")

                        HStack {
                            Text("AVAILABLE SIMULATORS")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(ink.opacity(0.68))
                            Spacer()
                            Text("\(offerings.count) AVAILABLE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(blue)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(blue.opacity(0.09)).clipShape(Capsule())
                        }

                        ForEach(offerings) { offering in
                            Button { onOpen(offering.id) } label: { simulatorCard(offering) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("openModule-\(offering.id.rawValue)")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 18)).foregroundColor(blue).frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("One app. Your simulators.")
                                    .font(.system(size: 15, weight: .bold)).foregroundColor(ink)
                                Text("Choose the simulators you need. Each has its own subscription and access.")
                                    .font(.system(size: 13)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text("SIMULA PRO  ·  EXAM PREPARATION")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.1).foregroundColor(ink.opacity(0.42))
                            .frame(maxWidth: .infinity).padding(.top, 13)
                    }
                    .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 36)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("simulaProHome")
    }

    private var brandHeader: some View {
        HStack(spacing: 13) {
            Image("SimulaProMark")
                .resizable().scaledToFill().frame(width: 49, height: 49)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Simula Pro")
                    .font(.system(size: 23, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text("Your exam simulator platform")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.81))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Color(red: 0.045, green: 0.16, blue: 0.44),
                     Color(red: 0.11, green: 0.25, blue: 0.77),
                     Color(red: 0.27, green: 0.14, blue: 0.68)],
            startPoint: .leading, endPoint: .trailing))
    }

    private func simulatorCard(_ offering: SimulatorOffering) -> some View {
        let unlocked = subscription.hasAccess(to: offering.id.rawValue)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 15) {
                Image(offering.imageName)
                    .resizable().scaledToFill().frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(offering.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(ink)
                    Text(offering.subtitle)
                        .font(.system(size: 15, weight: .medium)).foregroundColor(ink.opacity(0.70))
                    Text(offering.detail)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(blue)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            Rectangle().fill(Color(red: 0.88, green: 0.91, blue: 0.95)).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: unlocked ? "checkmark.circle.fill" : "lock.fill")
                    .foregroundColor(unlocked ? Color(red: 0.10, green: 0.55, blue: 0.41) : .secondary)
                Text(subscription.isLoading ? "Checking access" : unlocked ? "Ready to practice" : "Subscription required")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(ink.opacity(0.70))
                Spacer(minLength: 0)
                Text(unlocked ? "OPEN SIMULATOR" : "VIEW PLANS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.45).foregroundColor(blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(blue)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.85, green: 0.90, blue: 0.96), lineWidth: 1))
        .shadow(color: ink.opacity(0.07), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offering.title), \(offering.subtitle), \(unlocked ? "open simulator" : "view subscription")")
    }
}

private struct UsageIdentity: Codable {
    let id: String
    let name: String
    let email: String
}

private struct UsageEvent: Codable {
    let id: String
    let userID: String
    let module: String
    let seconds: Int
    let endedAt: String
}

@MainActor
private final class UsageAccountStore: ObservableObject {
    @Published private(set) var user: UsageIdentity?
    @Published private(set) var isChecking = true
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private let baseURL = URL(string: "https://simulapro.us")!
    private let savedUserKey = "simulapro.mobileUser.v1"
    private let savedEventsKey = "simulapro.mobileUsageEvents.v1"
    private let savedCSRFKey = "simulapro.mobileCSRF.v1"
    private var csrf = ""
    private var events: [UsageEvent] = []
    private var lastTick: TimeInterval?
    private var module = "catalog"
    private var foreground = false
    private var ticksSinceUpload = 0
    private var uploading = false
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: savedUserKey) {
            user = try? JSONDecoder().decode(UsageIdentity.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: savedEventsKey) {
            events = (try? JSONDecoder().decode([UsageEvent].self, from: data)) ?? []
        }
        csrf = UserDefaults.standard.string(forKey: savedCSRFKey) ?? ""
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func restore() async {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/customer/me"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { isChecking = false; return }
            if response.statusCode == 200,
               let result = try? JSONDecoder().decode(AccountResponse.self, from: data) {
                user = result.user
                csrf = result.csrf ?? ""
                saveAccount()
                if user != nil { Task { await flush() } }
            } else if response.statusCode == 401 || response.statusCode == 200 {
                user = nil
                csrf = ""
                saveAccount()
            }
        } catch {
            // Keep a previously signed-in user's local access and queue usage offline.
        }
        isChecking = false
    }

    func login(email: String, password: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/customer/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("portal", forHTTPHeaderField: "X-SimulaPro")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let result = try? JSONDecoder().decode(AccountResponse.self, from: data),
                  let identity = result.user, let token = result.csrf else {
                errorMessage = "Could not sign in. Check your email and password."
                return
            }
            user = identity
            csrf = token
            saveAccount()
            setForeground(true, module: module)
            Task { await flush() }
        } catch {
            errorMessage = "Could not connect to SimulaPro. Check your connection."
        }
    }

    func signOut() async {
        settle()
        foreground = false
        lastTick = nil
        await flush()
        let token = csrf
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/customer/logout"))
        request.httpMethod = "POST"
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("portal", forHTTPHeaderField: "X-SimulaPro")
        request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        _ = try? await URLSession.shared.data(for: request)
        for cookie in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] {
            if cookie.name == "__Host-sp_session" { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
        user = nil
        csrf = ""
        saveAccount()
    }

    func setForeground(_ active: Bool, module nextModule: String) {
        settle()
        module = nextModule
        foreground = active && user != nil
        lastTick = foreground ? ProcessInfo.processInfo.systemUptime : nil
        if !foreground { Task { await flush() } }
    }

    private func tick() {
        settle()
        ticksSinceUpload += 1
        if ticksSinceUpload >= 4 {
            ticksSinceUpload = 0
            Task { await flush() }
        }
    }

    private func settle() {
        guard foreground, let identity = user, let start = lastTick else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        lastTick = uptime
        let seconds = min(60, Int((uptime - start).rounded(.down)))
        guard seconds > 0 else { return }
        events.append(UsageEvent(id: UUID().uuidString, userID: identity.id,
                                 module: module, seconds: seconds,
                                 endedAt: ISO8601DateFormatter().string(from: Date())))
        if events.count > 3000 { events.removeFirst(events.count - 3000) }
        saveEvents()
    }

    private func flush() async {
        guard !uploading, let identity = user, !csrf.isEmpty else { return }
        let oldest = Date().addingTimeInterval(-89 * 86400)
        events.removeAll { (ISO8601DateFormatter().date(from: $0.endedAt) ?? .distantPast) < oldest }
        saveEvents()
        let pending = Array(events.filter { $0.userID == identity.id }.prefix(60))
        guard !pending.isEmpty else { return }
        uploading = true
        defer { uploading = false }
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/usage"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("portal", forHTTPHeaderField: "X-SimulaPro")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        request.httpBody = try? JSONEncoder().encode(["events": pending])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                let ids = Set(pending.map(\.id))
                events.removeAll { ids.contains($0.id) }
                saveEvents()
            } else if (response as? HTTPURLResponse)?.statusCode == 401 {
                await restore()
            }
        } catch {
            // Keep the queue until the next foreground period or connection.
        }
    }

    private func saveAccount() {
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: savedUserKey)
        UserDefaults.standard.set(csrf, forKey: savedCSRFKey)
    }
    private func saveEvents() {
        UserDefaults.standard.set(try? JSONEncoder().encode(events), forKey: savedEventsKey)
    }
    private struct AccountResponse: Decodable {
        let user: UsageIdentity?
        let csrf: String?
    }
}

private struct UsageSignInView: View {
    @ObservedObject var store: UsageAccountStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sign in to SimulaPro").font(.largeTitle.bold())
                    Text("Use your SimulaPro account to connect your app activity to your profile. Your Apple subscription still controls access to each simulator.")
                        .foregroundColor(.secondary)
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        Task { await store.login(email: email, password: password) }
                    } label: {
                        Text(store.isBusy ? "Signing in…" : "Sign in")
                            .frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy || email.isEmpty || password.isEmpty)
                    if let message = store.errorMessage {
                        Text(message).foregroundColor(.red).accessibilityIdentifier("signInError")
                    }
                    Link("Create an account or reset your password", destination: URL(string: "https://simulapro.us/account")!)
                    Text("The app sends active use time to SimulaPro for the administrator's usage report. Exam answers are not sent.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .padding(24)
            }
            .background(Color(red: 0.95, green: 0.967, blue: 0.988))
            .navigationTitle("SimulaPro")
        }
    }
}


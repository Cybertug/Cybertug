import SwiftUI

/// Modules shown here have a working, locally installed simulator.
/// Add future simulators to this registry when their native modules are ready.
enum SimulatorID: String, Identifiable {
    case psychologyLaw
    case pmiCP
    case gc
    case fe
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
                          detail: "45 questions  •  60 minutes",
                          imageName: "PsychologyLawMark"),
        SimulatorOffering(id: .pmiCP,
                          title: "PMI Construction Professional (PMI-CP)",
                          subtitle: "Construction practice exam",
                          detail: "120 questions  •  230 minutes",
                          imageName: "PMICPMark"),
        SimulatorOffering(id: .gc,
                          title: "GC Business & Finance",
                          subtitle: "General Contractor practice exam",
                          detail: "120 questions  •  390 minutes",
                          imageName: "GCMark"),
        SimulatorOffering(id: .fe,
                          title: "FE Mechanical",
                          subtitle: "Engineering practice exam",
                          detail: "110 questions  •  320 minutes",
                          imageName: "FEMark")
    ]
}

@main
struct SimulaProApp: App {
    var body: some Scene {
        WindowGroup {
            SimulaProRootView().preferredColorScheme(.light)
        }
    }
}

struct SimulaProRootView: View {
    @StateObject private var subscription = SubscriptionStore()
    @State private var selectedModule: SimulatorID?
    @State private var sessionNumber = 0
    @State private var showsSubscription = false
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    var body: some View {
        Group {
            if selectedModule == .psychologyLaw && subscription.hasAccess {
                ExamRootView(onExit: { selectedModule = nil })
                    .id(sessionNumber)
            } else if selectedModule == .pmiCP && subscription.hasAccess {
                PMICPExamView(onExit: { selectedModule = nil })
                    .id(sessionNumber)
            } else if selectedModule == .gc && subscription.hasAccess {
                GCFEExamView(fe: false, onExit: { selectedModule = nil })
                    .id(sessionNumber)
            } else if selectedModule == .fe && subscription.hasAccess {
                GCFEExamView(fe: true, onExit: { selectedModule = nil })
                    .id(sessionNumber)
            } else {
                SimulaProCatalogView(offerings: SimulatorOffering.available,
                                     subscription: subscription,
                                     onSubscription: { showsSubscription = true }) { module in
                    if subscription.hasAccess {
                        sessionNumber += 1
                        selectedModule = module
                    } else {
                        showsSubscription = true
                    }
                }
            }
        }
        .task { await subscription.start() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await subscription.refreshEntitlements() } }
        }
        .onChange(of: subscription.hasAccess) { hasAccess in
            if !hasAccess { selectedModule = nil }
        }
        .sheet(isPresented: $showsSubscription) {
            SubscriptionView(store: subscription)
        }
    }
}

struct SimulaProCatalogView: View {
    let offerings: [SimulatorOffering]
    @ObservedObject var subscription: SubscriptionStore
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
                        Button(action: onSubscription) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Simula Pro Access").font(.headline)
                                    Text(subscription.isLoading ? "Checking subscription…" :
                                         subscription.hasAccess ? "Active subscription · All available simulators" :
                                         "Subscription required · View monthly and yearly plans")
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(blue.opacity(0.09))
                                .clipShape(Capsule())
                        }

                        ForEach(offerings) { offering in
                            Button {
                                onOpen(offering.id)
                            } label: {
                                simulatorCard(offering)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("openModule-\(offering.id.rawValue)")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 18))
                                .foregroundColor(blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("One app. Your simulators.")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(ink)
                                Text("Additional exam simulators will appear here as new modules become available.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text("SIMULA PRO  •  EXAM PREPARATION")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundColor(ink.opacity(0.42))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 13)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("simulaProHome")
    }

    private var brandHeader: some View {
        HStack(spacing: 13) {
            Image("SimulaProMark")
                .resizable()
                .scaledToFill()
                .frame(width: 49, height: 49)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Simula Pro")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Your exam simulator platform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.81))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Color(red: 0.045, green: 0.16, blue: 0.44),
                     Color(red: 0.11, green: 0.25, blue: 0.77),
                     Color(red: 0.27, green: 0.14, blue: 0.68)],
            startPoint: .leading, endPoint: .trailing))
    }

    private func simulatorCard(_ offering: SimulatorOffering) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 15) {
                Image(offering.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(offering.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(ink)
                    Text(offering.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ink.opacity(0.70))
                    Text(offering.detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(blue)
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            Rectangle()
                .fill(Color(red: 0.88, green: 0.91, blue: 0.95))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.10, green: 0.55, blue: 0.41))
                Text(subscription.isLoading ? "Checking access" : subscription.hasAccess ? "Ready to practice" : "Subscription required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ink.opacity(0.70))
                Spacer(minLength: 0)
                Text(subscription.hasAccess ? "OPEN SIMULATOR" : "VIEW ACCESS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.45)
                    .foregroundColor(blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(blue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.85, green: 0.90, blue: 0.96), lineWidth: 1))
        .shadow(color: ink.opacity(0.07), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offering.title), \(offering.subtitle), \(subscription.hasAccess ? "open simulator" : "view subscription")")
    }
}



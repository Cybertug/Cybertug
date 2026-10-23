import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var store: SubscriptionStore
    @State private var selectedModule: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(store: SubscriptionStore, module: String = "psychologyLaw") {
        self.store = store
        _selectedModule = State(initialValue: SimulaProSubscription.modules.contains(module) ? module : "psychologyLaw")
    }

    private var moduleName: String { SimulaProSubscription.names[selectedModule] ?? "Simulator" }
    private var moduleProducts: [Product] { store.products(for: selectedModule) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("SimulaProMark")
                        .resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Choose your simulator")
                        .font(.largeTitle.bold())
                    Text("Each simulator has its own monthly and yearly plans. A subscription unlocks only the selected simulator.")
                    Picker("Simulator", selection: $selectedModule) {
                        ForEach(SimulaProSubscription.modules, id: \.self) { module in
                            Text(SimulaProSubscription.names[module] ?? module).tag(module)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("subscriptionModulePicker")
                    Text(moduleName).font(.title2.bold())
                    Text(statusText).foregroundColor(.secondary)

                    if store.hasAccess(to: selectedModule) {
                        Label("This simulator is unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Use Manage Subscriptions below to change or cancel this plan.")
                            .font(.subheadline).foregroundColor(.secondary)
                    } else {
                        Text("Choose a plan").font(.headline)
                        if store.isLoadingProducts {
                            ProgressView("Loading plans from Apple…")
                        }
                        ForEach(moduleProducts, id: \.id) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.id.hasSuffix(".monthly") ? "Monthly" : "Yearly")
                                            .font(.headline)
                                        Text("Auto-renewable · Cancel anytime")
                                            .font(.caption)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(product.displayPrice).font(.headline)
                                        Text(product.id.hasSuffix(".monthly") ? "per month" : "per year")
                                            .font(.caption)
                                    }
                                }
                                .padding()
                                .background(Color.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(store.isBusy || store.isLoading)
                            .accessibilityIdentifier("buy-\(product.id)")
                        }
                        if !store.isLoadingProducts && moduleProducts.isEmpty {
                            Text(store.productLoadError ?? "Apple has not returned available plans for this simulator in your App Store region. No purchase or charge has been made.")
                                .foregroundColor(.secondary)
                                .accessibilityIdentifier("subscriptionPlansUnavailable")
                        }
                        if moduleProducts.count < 2 && !store.isLoadingProducts {
                            Button("Retry loading plans") { Task { await store.loadProducts() } }
                                .accessibilityIdentifier("retrySubscriptionPlans")
                        }
                    }
                    if let errorMessage = store.errorMessage {
                        Text(errorMessage).foregroundColor(.red)
                    }
                    if store.isBusy { ProgressView() }
                    Divider()
                    Button("Restore Purchases") { Task { await store.restore() } }
                        .disabled(store.isBusy)
                        .accessibilityIdentifier("restorePurchases")
                    Button("Manage Subscriptions") {
                        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    .accessibilityIdentifier("manageSubscription")
                    Text("Payment and renewal are handled by Apple. Each purchased simulator subscription is billed separately and renews automatically until canceled in your Apple Account.")
                        .font(.footnote).foregroundColor(.secondary)
                    DisclosureGroup("Plan availability details") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("App Store region: \(store.storefrontCountry ?? "Not available")")
                            ForEach(SimulaProSubscription.productIDs(for: selectedModule).sorted(), id: \.self) { id in
                                Text("\(id): \(store.products.contains(where: { $0.id == id }) ? "Available" : "Not returned by Apple")")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Subscriptions")
            .toolbar { Button("Done") { dismiss() } }
        }
        .task { await store.loadProducts() }
        .onChange(of: selectedModule) { _ in store.errorMessage = nil }
    }

    private var statusText: String {
        if store.isLoading { return "Checking your purchases with Apple…" }
        guard store.hasAccess(to: selectedModule) else { return "No active subscription for this simulator" }
        if let date = store.expirationDate(for: selectedModule) {
            if date <= Date() { return "Active during Apple's billing grace period" }
            return "Active · Current period ends \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Active"
    }
}

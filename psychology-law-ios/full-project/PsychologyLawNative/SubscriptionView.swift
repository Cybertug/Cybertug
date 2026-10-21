import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("SimulaProMark")
                        .resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Simula Pro Access")
                        .font(.largeTitle.bold())
                    Text("One subscription gives you access to every simulator available in the catalog, starting with Psychology Law.")
                    Text("Subscription status")
                        .font(.headline)
                    Text(statusText)
                        .foregroundColor(.secondary)

                    if store.isLoading {
                        ProgressView("Checking your subscription…")
                    } else if !store.hasAccess {
                        Text("Choose a plan")
                            .font(.headline)
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.id == SimulaProSubscription.monthly ? "Monthly" : "Yearly")
                                            .font(.headline)
                                        Text("Auto-renewable · Cancel anytime")
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(store.isBusy)
                            .accessibilityIdentifier("buy-\(product.id)")
                        }
                        if store.products.isEmpty {
                            Button("Retry loading plans") { Task { await store.loadProducts() } }
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
                    Button("Manage Subscription") {
                        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    .accessibilityIdentifier("manageSubscription")
                    Text("Payment and renewal are handled by Apple. Your plan renews automatically until you cancel it in your Apple Account.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Access")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var statusText: String {
        if store.isLoading { return "Checking with Apple…" }
        guard store.hasAccess else { return "No active subscription" }
        if store.isInGracePeriod { return "Active during Apple's billing grace period" }
        if let date = store.expirationDate {
            return "Active · Current period ends \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Active"
    }
}


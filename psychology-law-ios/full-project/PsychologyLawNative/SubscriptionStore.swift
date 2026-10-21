import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isBusy = false
    @Published private(set) var hasAccess = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isInGracePeriod = false
    @Published var errorMessage: String?

    private var updateTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        // Start listening before the first entitlement read to avoid missing a renewal.
        updateTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.refreshEntitlements()
                    await transaction.finish()
                } else {
                    self.errorMessage = "Apple could not verify a transaction. Please try Restore Purchases."
                }
            }
        }
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Array(SimulaProSubscription.productIDs))
            products = fetched.filter { $0.type == .autoRenewable && SimulaProSubscription.productIDs.contains($0.id) }
                .sorted { order($0.id) < order($1.id) }
            if products.count != SimulaProSubscription.productIDs.count {
                errorMessage = "Subscription plans are not available from the App Store yet. Please try again later."
            } else {
                errorMessage = nil
            }
        } catch {
            products = []
            errorMessage = "Could not load subscription plans. Check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        var newest: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SimulaProSubscription.grantsAccess(productID: transaction.productID,
                                                     revokedAt: transaction.revocationDate) else { continue }
            if newest == nil || transaction.purchaseDate > newest!.purchaseDate {
                newest = transaction
            }
        }
        // currentEntitlements also includes subscriptions in Apple's billing grace period.
        hasAccess = newest != nil
        activeProductID = newest?.productID
        expirationDate = newest?.expirationDate
        isInGracePeriod = newest?.expirationDate.map { $0 <= Date() } ?? false
        isLoading = false
        scheduleExpiryCheck()
    }

    func purchase(_ product: Product) async {
        guard !isBusy, SimulaProSubscription.productIDs.contains(product.id),
              product.type == .autoRenewable else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refreshEntitlements()
                await transaction.finish()
            case .success(.unverified):
                errorMessage = "Apple could not verify this purchase. Access was not unlocked."
            case .pending:
                errorMessage = "Purchase pending approval. Access will unlock after Apple confirms it."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed. Please try again."
            }
        } catch {
            errorMessage = "The purchase could not be completed. Please try again."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasAccess { errorMessage = "No active Simula Pro Access subscription was found for this Apple Account." }
        } catch {
            errorMessage = "Purchases could not be restored. Check your connection and try again."
        }
    }

    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        guard let expirationDate, expirationDate > Date() else { return }
        let delay = max(1, expirationDate.timeIntervalSinceNow + 1)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshEntitlements()
        }
    }

    private func order(_ id: String) -> Int { id == SimulaProSubscription.monthly ? 0 : 1 }
}


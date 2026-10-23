import Combine
import Foundation
import OSLog
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasAccess = false
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var activeProductID: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isInGracePeriod = false
    @Published private(set) var storefrontCountry: String?
    @Published private(set) var missingProductIDs: Set<String> = []
    @Published private(set) var productLoadError: String?
    @Published var errorMessage: String?

    private var expirationDates: [String: Date] = [:]
    private var updateTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var started = false
    private let logger = Logger(subsystem: "com.simulapro.psychologylaw", category: "Subscriptions")

    deinit {
        updateTask?.cancel()
        storefrontTask?.cancel()
        expiryTask?.cancel()
    }

    func start() async {
        guard !started else { return }
        started = true
        updateTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result,
                   SimulaProSubscription.productIDs.contains(transaction.productID) {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
        storefrontTask = Task { [weak self] in
            for await _ in Storefront.updates {
                guard let self else { return }
                await self.loadProducts()
            }
        }
        // A slow entitlement refresh must not prevent the catalog request from starting.
        async let entitlements: Void = refreshEntitlements()
        async let catalog: Void = loadProducts()
        _ = await (entitlements, catalog)
    }

    func products(for module: String) -> [Product] {
        let ids = SimulaProSubscription.productIDs(for: module)
        return products.filter { ids.contains($0.id) }
            .sorted { SimulaProSubscription.order($0.id) < SimulaProSubscription.order($1.id) }
    }

    func hasAccess(to module: String) -> Bool {
        SimulaProSubscription.canAccess(module: module, activeProductIDs: activeProductIDs)
    }

    func expirationDate(for module: String) -> Date? {
        let ids = SimulaProSubscription.productIDs(for: module).union(SimulaProSubscription.legacyProductIDs)
        return expirationDates.filter { ids.contains($0.key) }.map(\.value).max()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        productLoadError = nil
        defer { isLoadingProducts = false }
        storefrontCountry = await Storefront.current?.countryCode
        let requested = SimulaProSubscription.purchaseProductIDs
        do {
            let fetched = try await Self.fetchProducts(Array(requested))
            products = fetched.filter { $0.type == .autoRenewable && requested.contains($0.id) }
            missingProductIDs = requested.subtracting(Set(products.map(\.id)))
            if !missingProductIDs.isEmpty {
                logger.warning("StoreKit did not return product IDs: \(self.missingProductIDs.sorted().joined(separator: ","), privacy: .public)")
            }
        } catch is CancellationError {
            return
        } catch {
            // Keep any products already fetched; a temporary network failure must not hide them.
            missingProductIDs = requested.subtracting(Set(products.map(\.id)))
            let code = (error as NSError).code
            logger.error("StoreKit product request failed: code \(code, privacy: .public)")
            productLoadError = "Apple could not load the plans. Check your connection, then tap Retry."
        }
    }

    private static func fetchProducts(_ ids: [String]) async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask { try await Product.products(for: ids) }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }

    func refreshEntitlements() async {
        var transactions: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  !transaction.isUpgraded,
                  SimulaProSubscription.grantsAccess(productID: transaction.productID,
                                                     revokedAt: transaction.revocationDate) else { continue }
            transactions.append(transaction)
        }
        // StoreKit includes eligible billing-grace-period subscriptions in currentEntitlements.
        activeProductIDs = Set(transactions.map(\.productID))
        expirationDates = [:]
        for transaction in transactions {
            if let date = transaction.expirationDate {
                expirationDates[transaction.productID] = max(expirationDates[transaction.productID] ?? .distantPast, date)
            }
        }
        let newest = transactions.max { $0.purchaseDate < $1.purchaseDate }
        hasAccess = !activeProductIDs.isEmpty
        activeProductID = newest?.productID
        expirationDate = newest?.expirationDate
        isInGracePeriod = newest?.expirationDate.map { $0 <= Date() } ?? false
        isLoading = false
        scheduleExpiryCheck()
    }

    func purchase(_ product: Product) async {
        guard !isBusy, SimulaProSubscription.purchaseProductIDs.contains(product.id),
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
            if !hasAccess { errorMessage = "No active Simula Pro subscription was found for this Apple Account." }
        } catch {
            errorMessage = "Purchases could not be restored. Check your connection and try again."
        }
    }

    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        guard let nextExpiry = expirationDates.values.filter({ $0 > Date() }).min() else { return }
        let delay = max(1, nextExpiry.timeIntervalSinceNow + 1)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshEntitlements()
        }
    }
}

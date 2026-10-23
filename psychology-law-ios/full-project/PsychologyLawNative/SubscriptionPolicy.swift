import Foundation

/// Product identifiers are shared with the App Store Connect setup script.
/// Prices always come from StoreKit; no recurring prices are invented in the app.
enum SimulaProSubscription {
    // Preserve access already purchased under the original all-access products.
    // These legacy products are not offered for new purchases in the paywall.
    static let monthly = "com.simulapro.access.monthly"
    static let yearly = "com.simulapro.access.yearly"
    static let legacyProductIDs: Set<String> = [monthly, yearly]

    static let modules = ["psychologyLaw", "pmiCP", "gc", "fe"]
    static let names: [String: String] = [
        "psychologyLaw": "Psychology Law",
        "pmiCP": "PMI-CP",
        "gc": "GC Business & Finance",
        "fe": "FE Mechanical"
    ]
    static let prefixes: [String: String] = [
        "psychologyLaw": "com.simulapro.psychologylaw",
        "pmiCP": "com.simulapro.pmicp",
        "gc": "com.simulapro.gc",
        "fe": "com.simulapro.fe"
    ]

    static func productIDs(for module: String) -> Set<String> {
        guard let prefix = prefixes[module] else { return [] }
        return [prefix + ".monthly", prefix + ".yearly"]
    }

    static let purchaseProductIDs: Set<String> = Set(modules.flatMap { productIDs(for: $0) })
    static let productIDs: Set<String> = purchaseProductIDs.union(legacyProductIDs)

    /// Call only for a transaction verified by StoreKit's currentEntitlements.
    static func grantsAccess(productID: String, revokedAt: Date?) -> Bool {
        productIDs.contains(productID) && revokedAt == nil
    }

    static func canAccess(module: String, activeProductIDs: Set<String>) -> Bool {
        guard prefixes[module] != nil else { return false }
        return !activeProductIDs.isDisjoint(with: legacyProductIDs)
            || !activeProductIDs.isDisjoint(with: productIDs(for: module))
    }

    static func order(_ productID: String) -> Int {
        productID.hasSuffix(".monthly") ? 0 : 1
    }
}

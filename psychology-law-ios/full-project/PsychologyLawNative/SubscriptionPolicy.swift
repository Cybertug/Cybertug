import Foundation

enum SimulaProSubscription {
    static let monthly = "com.simulapro.access.monthly"
    static let yearly = "com.simulapro.access.yearly"
    static let productIDs: Set<String> = [monthly, yearly]

    static func grantsAccess(productID: String, revokedAt: Date?) -> Bool {
        productIDs.contains(productID) && revokedAt == nil
    }
}


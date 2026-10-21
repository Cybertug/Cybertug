import Foundation

@main
struct SubscriptionPolicyTests {
    static func main() {
        precondition(SimulaProSubscription.productIDs.count == 2)
        precondition(SimulaProSubscription.grantsAccess(productID: SimulaProSubscription.monthly, revokedAt: nil))
        precondition(SimulaProSubscription.grantsAccess(productID: SimulaProSubscription.yearly, revokedAt: nil))
        precondition(!SimulaProSubscription.grantsAccess(productID: "unknown", revokedAt: nil))
        precondition(!SimulaProSubscription.grantsAccess(productID: SimulaProSubscription.monthly, revokedAt: Date()))
        print("PASS: only verified subscription product IDs without revocation may grant access.")
    }
}


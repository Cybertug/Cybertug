import Foundation

@main
struct SubscriptionPolicyTests {
    static func main() {
        let policy = SimulaProSubscription.self
        precondition(policy.purchaseProductIDs.count == 8)
        precondition(policy.productIDs.count == 10)
        precondition(policy.purchaseProductIDs.isDisjoint(with: policy.legacyProductIDs))
        for module in policy.modules {
            precondition(policy.productIDs(for: module).count == 2)
            precondition(!policy.canAccess(module: module, activeProductIDs: []))
            for product in policy.productIDs(for: module) {
                precondition(policy.grantsAccess(productID: product, revokedAt: nil))
                precondition(!policy.grantsAccess(productID: product, revokedAt: Date()))
                for target in policy.modules {
                    precondition(policy.canAccess(module: target, activeProductIDs: [product]) == (target == module),
                                 "A subscription must not unlock another simulator")
                }
            }
            for legacy in policy.legacyProductIDs {
                precondition(policy.grantsAccess(productID: legacy, revokedAt: nil))
                precondition(policy.canAccess(module: module, activeProductIDs: [legacy]))
                precondition(!policy.grantsAccess(productID: legacy, revokedAt: Date()))
            }
        }
        let independent: Set<String> = ["com.simulapro.pmicp.monthly", "com.simulapro.fe.yearly"]
        precondition(policy.canAccess(module: "pmiCP", activeProductIDs: independent))
        precondition(policy.canAccess(module: "fe", activeProductIDs: independent))
        precondition(!policy.canAccess(module: "gc", activeProductIDs: independent))
        precondition(!policy.canAccess(module: "psychologyLaw", activeProductIDs: independent))
        precondition(!policy.canAccess(module: "unknown", activeProductIDs: policy.productIDs))
        precondition(policy.productIDs(for: "unknown").isEmpty)
        precondition(!policy.grantsAccess(productID: "unknown", revokedAt: nil))
        precondition(!policy.canAccess(module: "gc", activeProductIDs: ["unknown"]))
        print("PASS: eight per-simulator plans; isolated access; concurrent subscriptions; revocations; legacy purchases preserved.")
    }
}

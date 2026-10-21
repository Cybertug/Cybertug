# Simula Pro Access setup

The iOS app uses StoreKit 2 and the existing bundle ID `com.simulapro.psychologylaw`.
Create **one auto-renewable subscription group** named `Simula Pro Access` in this app's
App Store Connect record. Add these two subscriptions to that same group:

| Plan | Product ID | Duration |
| --- | --- | --- |
| Monthly | `com.simulapro.access.monthly` | 1 month |
| Yearly | `com.simulapro.access.yearly` | 1 year |

The product IDs must match exactly. The owner must choose prices and storefront
availability in App Store Connect and complete any required Paid Apps Agreement,
tax, and banking steps. Add localized subscription names, descriptions, and review
information as required by Apple. No price is hard-coded in the app: the paywall
only displays Apple's `Product.displayPrice`. If the products are absent, purchases
remain unavailable and the app shows a retry/error state.

The first subscription submission may need to accompany an app version. Do not
submit the subscriptions or distribute the paywall build until the owner confirms
the commercial prices and agreements.

## TestFlight verification

This source change alone does not replace any installed TestFlight build.
After the products are configured and the owner approves the commercial setup,
upload a new build number and verify Apple processing and group assignment.
Existing internal testers can remain in their group; they do not need a new tester entry.

TestFlight purchases run in Apple's sandbox and do not charge real money.
On a device, verify a fresh tester sees the paywall, monthly and yearly localized
prices, purchase and unlock, relaunch and restore, renewal, expiration, refund or
revocation, offline launch, and Manage Subscription. Test pending purchases with
a Sandbox Apple Account. The simulator build in GitHub Actions verifies
compilation; a live StoreKit purchase still requires Apple products and a device.


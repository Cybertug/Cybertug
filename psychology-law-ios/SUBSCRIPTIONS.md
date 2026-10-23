# Simula Pro subscriptions

App Store Connect app: `6823960478`  
Existing iOS bundle: `com.simulapro.psychologylaw`

## Commercial model

Each simulator has an independent auto-renewable subscription group. Monthly and
yearly products are alternative durations within the same group. A customer may
subscribe to more than one simulator, with each billed separately.

| Simulator | Group ID | Monthly product | Yearly product |
| --- | --- | --- | --- |
| Psychology Law | 22507638 | `com.simulapro.psychologylaw.monthly` | `com.simulapro.psychologylaw.yearly` |
| PMI-CP | 22507941 | `com.simulapro.pmicp.monthly` | `com.simulapro.pmicp.yearly` |
| GC Business & Finance | 22507913 | `com.simulapro.gc.monthly` | `com.simulapro.gc.yearly` |
| FE Mechanical | 22507888 | `com.simulapro.fe.monthly` | `com.simulapro.fe.yearly` |

The eight products, en-US localizations and USA up-front billing availability were
verified through Apple's API on October 23, 2026. Existing products were reused;
the missing FE Mechanical yearly product was created. No existing prices,
agreements, tax details or banking details were changed, and nothing was submitted
for App Store review.

**Recurring prices have not been approved or configured for these eight plans.**
Do not infer them from former website one-time purchase prices or the previous
all-access subscription. The owner must define a monthly and yearly price for each
simulator. The app always displays StoreKit's localized `Product.displayPrice`;
it never fabricates a price when Apple does not return a product.

## Entitlements and compatibility

`SubscriptionPolicy.swift` is the shared product-ID registry and access policy.
Only verified, non-revoked, non-upgraded StoreKit current entitlements unlock
content. A module-specific product unlocks only its own simulator. Multiple
simulator subscriptions can coexist.

The previous `com.simulapro.access.monthly` and `com.simulapro.access.yearly`
products remain recognized for existing purchasers. They are not offered for new
purchases in the revised paywall. Do not delete or silently cancel these products
or remove previously purchased access.

`SubscriptionStore.swift` loads products independently of entitlement refresh,
tracks missing products and storefront changes, and allows retrying failed loads.
`SubscriptionView.swift` shows a simulator-specific plan selector, the billing
interval, restore/manage actions, and product availability diagnostics.

## Setup and verification workflows

- `simulapro-module-subscriptions.yml` runs
  `ci/configure_module_subscriptions.rb`. It is idempotent, verifies the target
  app/bundle, fills missing metadata/USA availability, and writes
  `artifacts/module-subscriptions-report.json`. It deliberately does not set prices.
- `simulapro-subscription-audit.yml` is a read-only Apple audit.
- `psychology-law-ios.yml` validates the exam banks/navigation, tests the scoped
  access policy, builds the native app, and runs simulator smoke tests. This is not
  an Apple purchase test and does not upload a new TestFlight build.
- `simulapro-subscription-review-capture.yml` captures actual simulator content for
  App Review. Its additional content-preview routes exist only in a temporary
  debug build; production subscription gates remain unchanged.
- `ci/upload_subscription_review_screenshots.rb` uploads visually verified review
  screenshots to the existing products and checks Apple's asset-processing state.
  It does not submit products for review or change prices.

The older `ci/configure_subscriptions.rb` only describes the legacy all-access
products. It is not the setup entrypoint for the current per-simulator model.

## Remaining launch gates

1. Obtain the owner's exact recurring prices and configure them in Apple. Re-read
   the effective USA price points and dates to verify each amount and interval.
2. Verify review screenshots have been uploaded and processed for every plan.
   Consult the latest read-back report rather than assuming a successful script
   means all launch requirements are complete.
3. Confirm the Paid Apps Agreement is Active and that any required tax/banking
   information is complete. A successful API metadata write alone is not proof of
   active agreements. The Account Holder must personally accept any new terms.
4. After the commercial setup is approved, upload a new uniquely numbered signed
   TestFlight build and verify Apple processing and assignment to the existing
   internal tester group. Source changes do not update the installed iPhone app.
5. On a real test device, check localized monthly/yearly prices for all simulators,
   a verified purchase, correct per-module unlock, no cross-module unlock, restore,
   relaunch, concurrent subscriptions, renewal, expiration, refunds/revocations,
   offline launch, and Manage Subscriptions. Sandbox/TestFlight purchases are not
   evidence of a completed production payment.

Apple approval is not required merely to test a configured purchase in Sandbox,
but active agreements and valid product configuration are required. The first
subscription review may need to accompany an app-version submission. Do not submit
or distribute a paywall release while commercial prices and agreements remain
unconfirmed.

## Official Apple references

- https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox
- https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase

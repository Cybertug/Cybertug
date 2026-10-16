# Psychology Law Simulator — Apple TestFlight setup

## Current status
- Simulator build succeeded in prior GitHub Action.
- SwiftUI branch: psychology-law-ios-native. Current app contains only seven pilot questions.
- Manual distribution workflow: .github/workflows/psychology-law-testflight.yml on main.
- Release gate blocks the unfinished seven-question pilot.
- No Apple signing key or secrets have been configured yet; no Apple upload has occurred.

## One-time Apple authorization (keep credentials private)
1. Open https://appstoreconnect.apple.com/ and confirm Apple Developer Program is active.
2. Go to Users and Access > Integrations > App Store Connect API > Team Keys.
3. Generate a Team API key with appropriate permissions, and download the AuthKey .p8 file once.
4. Add four GitHub Actions repository variables at https://github.com/Cybertug/Cybertug/settings/variables/actions :
   APPSTORE_API_KEY_ID (key ID), APPSTORE_ISSUER_ID (issuer ID), APPSTORE_TEAM_ID (10-character developer team), APPSTORE_BUNDLE_ID (registered bundle ID).
5. Add one GitHub Actions repository secret at https://github.com/Cybertug/Cybertug/settings/secrets/actions :
   APPSTORE_API_PRIVATE_KEY = the complete text of the .p8 private key, including BEGIN and END PRIVATE KEY lines.
6. Make sure the final App Store Connect app record, registered bundle ID, app icon, and agreements exist.
DO NOT share the .p8 file or its text in chat, GitHub issues, commits, or public files.

## Upload
After replacing the seven-question pilot with the fully reviewed 325-question app and AppIcon:
https://github.com/Cybertug/Cybertug/actions/workflows/psychology-law-testflight.yml
Click Run workflow on main, provide version e.g. 1.0.0, and type FULL_BUILD_APPROVED.
The workflow tries cloud-managed automatic signing with the Team API key. Certain Apple accounts may additionally require a reusable Apple Distribution signing certificate and provisioning profile; if so, the job will report this.
Uploads to TestFlight require a successful Apple processing stage after the file transfer.

## Current blockers
- Only seven pilot questions in the GitHub app; the original full bank still needs integration and review.
- Native AppIcon asset catalog is not yet present.
- Apple account authorization, bundle ID, signing privileges, and App Store Connect app record are not yet confirmed.
- The GitHub connector cannot create repository secrets/variables; an account administrator must use GitHub Settings to enter them.

Independent practice simulator, not affiliated with Pearson VUE or the Florida Board of Psychology.

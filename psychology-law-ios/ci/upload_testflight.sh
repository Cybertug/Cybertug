#!/usr/bin/env bash
# Distribute native SwiftUI app after separate release validation.
set -euo pipefail
umask 077
: "${APPSTORE_API_KEY_ID:?missing API key ID}"
: "${APPSTORE_ISSUER_ID:?missing issuer ID}"
: "${APPSTORE_TEAM_ID:?missing Apple team ID}"
: "${APPSTORE_BUNDLE_ID:?missing app bundle ID}"
: "${APPSTORE_API_PRIVATE_KEY:?missing API private key}"
: "${RELEASE_VERSION:?missing release version}"

# Apple's October 2026 App Store upload requirement is iOS 26 SDK or newer.
# macos-15 GitHub runners still default to Xcode 16.4 even though Xcode 26 is installed.
for xc in /Applications/Xcode_26.3.app /Applications/Xcode_26.2.app /Applications/Xcode_26.1.1.app /Applications/Xcode_26.0.1.app; do
  if [[ -d "$xc/Contents/Developer" ]]; then
    export DEVELOPER_DIR="$xc/Contents/Developer"
    break
  fi
done
echo "Selected Xcode: $(xcodebuild -version | head -1)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
  echo "::error::iOS 26+ SDK required for App Store Connect, found $SDK_VERSION"
  exit 1
fi
echo "iOS SDK: $SDK_VERSION"

WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/psychologylaw-apple.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
P8="$WORK/AuthKey_$APPSTORE_API_KEY_ID.p8"
KEY_JSON="$WORK/key.json"
printf '%s\n' "$APPSTORE_API_PRIVATE_KEY" > "$P8"
chmod 600 "$P8"
python3 - "$P8" "$KEY_JSON" <<'PY'
import json, os, pathlib, sys
pem = pathlib.Path(sys.argv[1]).read_text()
if "BEGIN PRIVATE KEY" not in pem:
    raise SystemExit("Invalid APPSTORE_API_PRIVATE_KEY secret")
with open(sys.argv[2],"w") as f:
    json.dump({"key_id":os.environ["APPSTORE_API_KEY_ID"],
               "issuer_id":os.environ["APPSTORE_ISSUER_ID"],
               "key":pem,"in_house":False},f)
PY
cd psychology-law-ios/full-project
test -s PsychologyLawNative.xcodeproj/project.pbxproj
ARCHIVE="$WORK/PsychologyLawNative.xcarchive"
EXPORT="$WORK/export"
mkdir -p "$EXPORT"

echo "Archiving native app; exporting with distribution signing next..."
xcodebuild -project PsychologyLawNative.xcodeproj \
 -scheme PsychologyLawNative -configuration Release \
 -sdk iphoneos -destination 'generic/platform=iOS' \
 -archivePath "$ARCHIVE" \
 -allowProvisioningUpdates \
 -authenticationKeyPath "$P8" \
 -authenticationKeyID "$APPSTORE_API_KEY_ID" \
 -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
 CODE_SIGNING_ALLOWED=NO \
 DEVELOPMENT_TEAM="$APPSTORE_TEAM_ID" \
 PRODUCT_BUNDLE_IDENTIFIER="$APPSTORE_BUNDLE_ID" \
 MARKETING_VERSION="$RELEASE_VERSION" \
 CURRENT_PROJECT_VERSION="$(( ${GITHUB_RUN_NUMBER:-1} + 1 ))" \
 archive > "$WORK/archive.log" 2>&1 || {
    tail -n 80 "$WORK/archive.log"
    exit 1
 }
python3 - "$WORK/ExportOptions.plist" <<'PY'
import os, plistlib, sys
with open(sys.argv[1],"wb") as f:
    plistlib.dump({"method":"app-store-connect",
                   "destination":"export",
                   "signingStyle":"automatic",
                   "signingCertificate":"Apple Distribution",
                   "teamID":os.environ["APPSTORE_TEAM_ID"],
                   "manageAppVersionAndBuildNumber":False},f)
PY

echo "Exporting signed IPA..."
xcodebuild -exportArchive \
 -archivePath "$ARCHIVE" \
 -exportPath "$EXPORT" \
 -exportOptionsPlist "$WORK/ExportOptions.plist" \
 -allowProvisioningUpdates \
 -authenticationKeyPath "$P8" \
 -authenticationKeyID "$APPSTORE_API_KEY_ID" \
 -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
 > "$WORK/export.log" 2>&1 || {
   tail -n 80 "$WORK/export.log"
   echo "::error::If cloud signing is unavailable, a distribution certificate and provisioning profile must be configured."
   exit 1
 }
IPA="$(find "$EXPORT" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
if [[ -z "$IPA" ]]; then echo "::error::Signed IPA not found"; exit 1; fi

echo "Uploading IPA to App Store Connect TestFlight..."
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 \
 fastlane pilot upload --ipa "$IPA" --api_key_path "$KEY_JSON" --skip_waiting_for_build_processing
echo "Upload complete; Apple must process the build before it appears in TestFlight."

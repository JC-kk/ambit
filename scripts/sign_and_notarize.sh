#!/bin/bash
# Signs and notarizes an .app for distribution.
#
# Skipped entirely when MACOS_CERTIFICATE is unset, so the build still produces a working ad-hoc
# signed bundle for anyone without an Apple Developer account.
set -euo pipefail

APP="${1:?usage: sign_and_notarize.sh <path to .app>}"

if [ -z "${MACOS_CERTIFICATE:-}" ]; then
  echo "No signing certificate configured; leaving the ad-hoc signature in place."
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 900 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

echo "$MACOS_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychain -d user -s "$KEYCHAIN" login.keychain-db
rm -f "$RUNNER_TEMP/cert.p12"

xattr -cr "$APP" || true
codesign --force --deep --options runtime --timestamp \
  --sign "$MACOS_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$RUNNER_TEMP/notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$NOTARY_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait
xcrun stapler staple "$APP"
echo "Signed, notarized and stapled $APP"

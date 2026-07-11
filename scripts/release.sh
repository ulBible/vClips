#!/usr/bin/env bash
set -euo pipefail

# Builds, Developer ID-signs, notarizes, staples, and packages vClips for
# public distribution (GitHub Releases). Local dev builds are covered by
# scripts/bundle.sh with a self-signed identity; this script re-signs its
# output for Gatekeeper.
#
# One-time setup (needs an approved Apple Developer Program membership):
#   1. Certificate — Xcode → Settings… → Accounts → your Apple ID →
#      Manage Certificates… → "+" → "Developer ID Application".
#   2. Notary credentials — create an app-specific password at
#      https://account.apple.com, then store it once:
#        xcrun notarytool store-credentials vclips-notary \
#          --apple-id <your-apple-id> --team-id <YOURTEAMID>
#
# Usage:
#   ./scripts/release.sh <version>          e.g. ./scripts/release.sh 1.0.0
#
# Environment overrides:
#   VCLIPS_DEV_ID          full signing identity string; auto-detected when
#                          exactly one "Developer ID Application" cert exists
#   VCLIPS_NOTARY_PROFILE  notarytool keychain profile (default: vclips-notary)

VERSION="${1:?usage: release.sh <version> (e.g. 1.0.0)}"
APP_NAME="vClips"
APP_BUNDLE="build/${APP_NAME}.app"
NOTARY_PROFILE="${VCLIPS_NOTARY_PROFILE:-vclips-notary}"
DIST_DIR="dist"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

cd "$(dirname "$0")/.."

# Resolve the Developer ID identity up front so we fail before the (slow)
# build when signing can't succeed anyway.
DEV_ID="${VCLIPS_DEV_ID:-}"
if [[ -z "${DEV_ID}" ]]; then
  matches=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" || true)
  count=$(grep -c . <<<"${matches}" || true)
  if [[ -z "${matches}" ]]; then
    echo "error: no 'Developer ID Application' certificate in the keychain." >&2
    echo "Create one via Xcode → Settings… → Accounts → Manage Certificates… (see header)." >&2
    exit 1
  elif [[ "${count}" -gt 1 ]]; then
    echo "error: multiple Developer ID certificates found — pick one via VCLIPS_DEV_ID:" >&2
    echo "${matches}" >&2
    exit 1
  fi
  DEV_ID=$(sed -E 's/.*"(.+)"$/\1/' <<<"${matches}")
fi

echo "==> Building ${APP_BUNDLE} (via bundle.sh)"
./scripts/bundle.sh release

echo "==> Stamping version ${VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
  "${APP_BUNDLE}/Contents/Info.plist"
# Monotonic build number so macOS never considers a newer build "older".
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" \
  "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Signing with: ${DEV_ID}"
# Hardened runtime + secure timestamp are notarization requirements.
codesign --force --options runtime --timestamp \
  --sign "${DEV_ID}" "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Notarizing (profile: ${NOTARY_PROFILE}) — takes a few minutes"
mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" --wait

echo "==> Stapling ticket"
xcrun stapler staple "${APP_BUNDLE}"

# Re-zip: stapling modified the .app, and the uploaded archive lacks the ticket.
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Gatekeeper check"
spctl --assess --type exec --verbose=2 "${APP_BUNDLE}"

echo "==> Done: ${ZIP_PATH}"
echo "Upload it to GitHub Releases: gh release create v${VERSION} ${ZIP_PATH}"

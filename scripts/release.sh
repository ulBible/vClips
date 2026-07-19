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
# Sparkle's nested executables must each carry a hardened-runtime signature
# or notarization rejects the bundle. Inside-out order, per Sparkle's docs.
SPARKLE_B="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in \
  "${SPARKLE_B}/XPCServices/Installer.xpc" \
  "${SPARKLE_B}/XPCServices/Downloader.xpc" \
  "${SPARKLE_B}/Autoupdate" \
  "${SPARKLE_B}/Updater.app" \
  "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"; do
  [[ -e "${nested}" ]] || continue
  codesign --force --options runtime --timestamp \
    --preserve-metadata=entitlements --sign "${DEV_ID}" "${nested}"
done
# Hardened runtime + secure timestamp are notarization requirements.
codesign --force --options runtime --timestamp \
  --sign "${DEV_ID}" "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Notarizing (profile: ${NOTARY_PROFILE}) — takes a few minutes"
mkdir -p "${DIST_DIR}"
# Old zips would end up in the appcast (and get re-signed) — keep dist/ to
# exactly this release.
rm -f "${DIST_DIR}"/*.zip "${DIST_DIR}"/*.dmg "${DIST_DIR}"/appcast.xml
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

echo "==> Generating Sparkle appcast"
# The Sparkle SPM artifact ships the CLI tools; the EdDSA private key lives in
# the login keychain (created once via generate_keys).
APPCAST_TOOL=""
for candidate in \
  ".xcbuild/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"; do
  [[ -x "${candidate}" ]] && APPCAST_TOOL="${candidate}" && break
done
if [[ -z "${APPCAST_TOOL}" ]]; then
  echo "error: generate_appcast not found — build once so SwiftPM fetches the Sparkle artifact." >&2
  exit 1
fi
"${APPCAST_TOOL}" "${DIST_DIR}" \
  --download-url-prefix "https://github.com/ulBible/vClips/releases/download/v${VERSION}/" \
  --link "https://github.com/ulBible/vClips"

# Human downloads ship as a DMG: no unzip step, so third-party archive tools
# can't strip the signature metadata (seen in the wild with the 1.2.3 zip —
# Gatekeeper then hard-blocks with no "Open" button). Sparkle keeps using the
# zip, which is why the DMG is built AFTER generate_appcast has scanned dist/.
echo "==> Building DMG (drag-to-Applications)"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_ROOT="${DIST_DIR}/dmg-root"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"
ditto "${APP_BUNDLE}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO -quiet "${DMG_PATH}"
rm -rf "${DMG_ROOT}"
codesign --force --timestamp --sign "${DEV_ID}" "${DMG_PATH}"

echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"

echo "==> Done: ${ZIP_PATH} + ${DMG_PATH} + ${DIST_DIR}/appcast.xml"
echo "Publish all three (Sparkle reads appcast.xml + zip; humans download the DMG):"
echo "  gh release create v${VERSION} ${ZIP_PATH} ${DMG_PATH} ${DIST_DIR}/appcast.xml"

#!/usr/bin/env bash
set -euo pipefail

# Builds and packages the Mac App Store variant (vClipsAppStore target:
# sandboxed, no Sparkle, no donation link) into an uploadable .pkg.
#
# One-time setup (needs the Apple Developer account):
#   1. Certificates (Xcode → Settings… → Accounts → Manage Certificates… → +):
#      "Apple Distribution" AND "Mac Installer Distribution".
#   2. Provisioning profile: developer.apple.com → Profiles → new "Mac App
#      Store Connect" distribution profile for com.vclips.app; download and
#      save as Resources/vClipsAppStore.provisionprofile (gitignored).
#   3. App Store Connect: create the app record for com.vclips.app.
#
# Usage:
#   ./scripts/appstore.sh <version>                  # distribution .pkg
#   ./scripts/appstore.sh <version> --sandbox-smoke  # local self-signed build
#                                                    # for testing the sandbox
#
# Upload the resulting dist/vClips-AppStore-<version>.pkg with the
# Transporter app (Mac App Store) and submit for review in App Store Connect.

VERSION="${1:?usage: appstore.sh <version> [--sandbox-smoke]}"
MODE="${2:-dist}"
APP_NAME="vClips"
TARGET="vClipsAppStore"
BUNDLE_ID="com.vclips.app"
APP_BUNDLE="build/${APP_NAME}-AppStore.app"
DERIVED_DATA=".xcbuild"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
DIST_DIR="dist"
PROFILE="Resources/vClipsAppStore.provisionprofile"

cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: xcodebuild requires full Xcode (active developer dir: $(xcode-select -p))." >&2
  exit 1
fi

echo "==> Building (Release via xcodebuild, scheme ${TARGET})"
xcodebuild -quiet \
  -scheme "${TARGET}" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${TARGET}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

copied_bundles=0
for resource_bundle in "${BUILD_DIR}"/*.bundle; do
  [[ -e "${resource_bundle}" ]] || continue
  cp -R "${resource_bundle}" "${APP_BUNDLE}/Contents/Resources/"
  copied_bundles=$((copied_bundles + 1))
done
if [[ "${copied_bundles}" -eq 0 ]]; then
  echo "error: no package resource bundles found in ${BUILD_DIR}." >&2
  exit 1
fi

# Store builds must not advertise a Sparkle feed (and there is no Sparkle in
# this binary); updates are the store's job.
PLIST="${APP_BUNDLE}/Contents/Info.plist"
for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
  /usr/libexec/PlistBuddy -c "Delete :${key}" "${PLIST}" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "${PLIST}"
# App Store binaries with no encryption beyond HTTPS: skip the export
# compliance questionnaire on every upload.
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "${PLIST}" 2>/dev/null || true

if [[ "${MODE}" == "--sandbox-smoke" ]]; then
  echo "==> Sandbox smoke signing (self-signed; NOT uploadable)"
  ENT="$(mktemp -t vclips-smoke).entitlements"
  cat > "${ENT}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
EOF
  codesign --force --deep --sign "vClips Self Signed" --entitlements "${ENT}" "${APP_BUNDLE}"
  echo "==> Done (smoke): ${APP_BUNDLE} — launch it to test sandboxed behavior"
  exit 0
fi

# --- Distribution signing ---
DIST_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 "Apple Distribution" | sed -E 's/.*"(.+)"$/\1/' || true)
if [[ -z "${DIST_ID}" ]]; then
  echo "error: no 'Apple Distribution' certificate — create it in Xcode (see header)." >&2
  exit 1
fi
# Installer identity lives in the keychain but not under codesigning policy.
INSTALLER_ID=$(security find-identity -v 2>/dev/null \
  | grep -m1 -E "(3rd Party Mac Developer Installer|Mac Installer Distribution)" \
  | sed -E 's/.*"(.+)"$/\1/' || true)
if [[ -z "${INSTALLER_ID}" ]]; then
  echo "error: no installer certificate ('Mac Installer Distribution') — create it in Xcode (see header)." >&2
  exit 1
fi
TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"${DIST_ID}")

if [[ ! -f "${PROFILE}" ]]; then
  echo "error: provisioning profile missing at ${PROFILE} (see header, step 2)." >&2
  exit 1
fi
cp "${PROFILE}" "${APP_BUNDLE}/Contents/embedded.provisionprofile"

ENT="$(mktemp -t vclips-mas).entitlements"
sed -e "s/TEAM_ID/${TEAM_ID}/g" -e "s/BUNDLE_ID/${BUNDLE_ID}/g" \
  Resources/vClips-AppStore.entitlements > "${ENT}"

echo "==> Signing with: ${DIST_ID} (team ${TEAM_ID})"
codesign --force --timestamp --sign "${DIST_ID}" --entitlements "${ENT}" "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Building installer package"
mkdir -p "${DIST_DIR}"
PKG="${DIST_DIR}/${APP_NAME}-AppStore-${VERSION}.pkg"
rm -f "${PKG}"
productbuild --component "${APP_BUNDLE}" /Applications \
  --sign "${INSTALLER_ID}" "${PKG}"

echo "==> Done: ${PKG}"
echo "Upload with the Transporter app, then submit for review in App Store Connect."

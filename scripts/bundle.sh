#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="vClips"
APP_BUNDLE="build/${APP_NAME}.app"
DERIVED_DATA=".xcbuild"

# Build with xcodebuild, not `swift build`. The two build systems generate
# different Bundle.module accessors for package resources (KeyboardShortcuts
# localizations): SwiftPM's variant only searches the app-bundle ROOT — where
# codesign forbids extra files ("unsealed contents present in the bundle
# root") — plus this machine's absolute build path, so an app assembled from
# a `swift build` binary fatal-errors on any other Mac the moment a package
# resource loads (e.g. opening Settings). Xcode's variant searches
# Contents/Resources, which is both signable and portable.
case "${CONFIG}" in
  release) XCODE_CONFIG="Release" ;;
  debug) XCODE_CONFIG="Debug" ;;
  *) echo "Unknown config '${CONFIG}' (expected release or debug)"; exit 1 ;;
esac
BUILD_DIR="${DERIVED_DATA}/Build/Products/${XCODE_CONFIG}"

# Code-signing identity.
# A stable identity (e.g. a self-signed "vClips Self Signed" cert) keeps the
# app's Designated Requirement constant across rebuilds, so the macOS
# Accessibility (auto-paste) permission persists instead of resetting every
# build the way ad-hoc signing does. Falls back to ad-hoc ("-") if no stable
# identity is available. Override with VCLIPS_SIGN_IDENTITY.
SIGN_IDENTITY="${VCLIPS_SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "vClips Self Signed"; then
    SIGN_IDENTITY="vClips Self Signed"
  else
    SIGN_IDENTITY="-"
  fi
fi

echo "==> Building (${XCODE_CONFIG} via xcodebuild)"
xcodebuild -quiet \
  -scheme "${APP_NAME}" \
  -configuration "${XCODE_CONFIG}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Package resource bundles, found via Bundle.main.resourceURL at runtime.
for resource_bundle in "${BUILD_DIR}"/*.bundle; do
  [[ -e "${resource_bundle}" ]] || continue
  cp -R "${resource_bundle}" "${APP_BUNDLE}/Contents/Resources/"
done

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  echo "==> Ad-hoc code signing (no stable identity found — Accessibility grant will reset each build)"
else
  echo "==> Code signing with identity: ${SIGN_IDENTITY}"
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"

if [[ "${2:-}" == "install" ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
  echo "==> Installed: /Applications/${APP_NAME}.app"
fi

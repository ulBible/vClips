#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="vClips"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="build/${APP_NAME}.app"

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

echo "==> Building (${CONFIG})"
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

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

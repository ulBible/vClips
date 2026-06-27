#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="vClips"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="build/${APP_NAME}.app"

echo "==> Building (${CONFIG})"
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"

if [[ "${2:-}" == "install" ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
  echo "==> Installed: /Applications/${APP_NAME}.app"
fi

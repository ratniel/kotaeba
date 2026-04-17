#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/KotaebaApp/KotaebaApp.xcodeproj"
SCHEME="KotaebaApp"
CONFIGURATION="Release"
DESTINATION="platform=macOS"
DERIVED_DATA_PATH="${REPO_ROOT}/.derivedData/KotaebaAppInstall"
APP_NAME="KotaebaApp"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.ratniel.KotaebaApp"
RESET_ACCESSIBILITY=0
BUILD_ONLY=0

usage() {
  cat <<'EOF'
Usage: scripts/install_local_app.sh [options]

Builds a signed local macOS app, installs it into /Applications, and launches it.

Options:
  --reset-accessibility   Reset Accessibility permission for com.ratniel.KotaebaApp before launch
  --build-only            Build the app but do not install or launch it
  --clean                 Remove the derived data folder before building
  --help                  Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset-accessibility)
      RESET_ACCESSIBILITY=1
      shift
      ;;
    --build-only)
      BUILD_ONLY=1
      shift
      ;;
    --clean)
      rm -rf "${DERIVED_DATA_PATH}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Xcode project not found at ${PROJECT_PATH}" >&2
  exit 1
fi

mkdir -p "${DERIVED_DATA_PATH}"

echo "Building ${SCHEME} (${CONFIGURATION}) with Xcode signing..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build finished but app bundle was not found at ${APP_PATH}" >&2
  exit 1
fi

echo "Built app: ${APP_PATH}"

if [[ "${BUILD_ONLY}" -eq 1 ]]; then
  exit 0
fi

if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  echo "Quitting running ${APP_NAME}..."
  pkill -x "${APP_NAME}" || true
  sleep 1
fi

echo "Installing app to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
ditto "${APP_PATH}" "${INSTALL_PATH}"

if [[ "${RESET_ACCESSIBILITY}" -eq 1 ]]; then
  echo "Resetting Accessibility permission for ${BUNDLE_ID}..."
  tccutil reset Accessibility "${BUNDLE_ID}" || true
fi

echo "Installed app signature:"
codesign -dv --verbose=4 "${INSTALL_PATH}" 2>&1 | sed -n '1,12p'

echo "Launching app..."
open "${INSTALL_PATH}"

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/KotaebaApp/KotaebaApp.xcodeproj"
SCHEME="KotaebaApp"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
DERIVED_DATA_PATH="${REPO_ROOT}/.derivedData/KotaebaApp"
OPEN_APP=1

usage() {
  cat <<'EOF'
Usage: scripts/run_app.sh [options]

Builds the macOS app into a stable repo-local DerivedData folder and launches it.

Options:
  --release                 Build Release instead of Debug
  --build-only              Build the app but do not launch it
  --derived-data-path PATH  Override the DerivedData output folder
  --clean                   Remove the DerivedData folder before building
  --help                    Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      CONFIGURATION="Release"
      shift
      ;;
    --build-only)
      OPEN_APP=0
      shift
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="${2:?missing path for --derived-data-path}"
      shift 2
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

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/KotaebaApp.app"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build finished but app bundle was not found at ${APP_PATH}" >&2
  exit 1
fi

echo "App bundle: ${APP_PATH}"

if [[ "${OPEN_APP}" -eq 1 ]]; then
  echo "Launching app..."
  open "${APP_PATH}"
else
  echo "Build-only mode: app was not launched."
fi

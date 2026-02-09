#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-KotaebaApp}"
PROJECT_PATH="${PROJECT_PATH:-KotaebaApp/KotaebaApp.xcodeproj}"
SCHEME="${SCHEME:-KotaebaApp}"
CONFIGURATION="${CONFIGURATION:-Release}"
OUT_DIR="${OUT_DIR:-dist}"

usage() {
  cat <<'EOF'
Usage:
  scripts/release/build_dmg.sh <version> [--out-dir <dir>]

Examples:
  scripts/release/build_dmg.sh 0.9
  scripts/release/build_dmg.sh 0.9 --out-dir release-artifacts

Environment:
  APP_NAME                       Default: KotaebaApp
  PROJECT_PATH                   Default: KotaebaApp/KotaebaApp.xcodeproj
  SCHEME                         Default: KotaebaApp
  CONFIGURATION                  Default: Release
  DEVELOPER_ID_APPLICATION       Optional. Enables app/DMG signing.
  APPLE_ID                       Optional. With team/password, enables notarization.
  APPLE_TEAM_ID                  Optional. With apple-id/password, enables notarization.
  APPLE_APP_SPECIFIC_PASSWORD    Optional. With apple-id/team, enables notarization.
EOF
}

VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${VERSION}" ]]; then
        VERSION="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "Missing required <version> argument." >&2
  usage
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required but not found." >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

NOTARIZE_VAR_COUNT=0
[[ -n "${APPLE_ID:-}" ]] && ((NOTARIZE_VAR_COUNT+=1))
[[ -n "${APPLE_TEAM_ID:-}" ]] && ((NOTARIZE_VAR_COUNT+=1))
[[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] && ((NOTARIZE_VAR_COUNT+=1))

if [[ "${NOTARIZE_VAR_COUNT}" -gt 0 && "${NOTARIZE_VAR_COUNT}" -lt 3 ]]; then
  echo "For notarization, set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
  exit 1
fi

if [[ "${NOTARIZE_VAR_COUNT}" -eq 3 && -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Notarization requires DEVELOPER_ID_APPLICATION for signing." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kotaeba-release.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

DERIVED_DATA="${WORK_DIR}/DerivedData"
STAGE_DIR="${WORK_DIR}/stage"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

mkdir -p "${STAGE_DIR}" "${OUT_DIR}"

echo "Building ${APP_NAME}.app (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build succeeded but app bundle not found: ${APP_PATH}" >&2
  exit 1
fi

cp -R "${APP_PATH}" "${STAGE_DIR}/"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Code-signing app bundle..."
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${STAGE_DIR}/${APP_NAME}.app"
fi

DMG_PATH="${OUT_DIR}/Kotaeba-${VERSION}.dmg"
echo "Creating DMG at ${DMG_PATH}..."
rm -f "${DMG_PATH}"
create-dmg \
  --volname "Kotaeba Installer" \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 220 190 \
  --app-drop-link 580 190 \
  "${DMG_PATH}" \
  "${STAGE_DIR}"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Code-signing DMG..."
  codesign --force --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${DMG_PATH}"
fi

if [[ "${NOTARIZE_VAR_COUNT}" -eq 3 ]]; then
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "${DMG_PATH}"
fi

SHA256_PATH="${OUT_DIR}/Kotaeba-${VERSION}.sha256.txt"
SHA256_VALUE="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
echo "${SHA256_VALUE}  $(basename "${DMG_PATH}")" > "${SHA256_PATH}"

echo
echo "Release artifacts ready:"
echo "- ${DMG_PATH}"
echo "- ${SHA256_PATH}"

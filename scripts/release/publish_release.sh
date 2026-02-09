#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-dist}"
REPO=""
NOTES_FILE=""
DRAFT=0

usage() {
  cat <<'EOF'
Usage:
  scripts/release/publish_release.sh <version> [--out-dir <dir>] [--repo <owner/repo>] [--notes-file <path>] [--draft]

Examples:
  scripts/release/publish_release.sh 0.9
  scripts/release/publish_release.sh 0.9 --repo ratniel/kotaeba --draft
EOF
}

VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    -r|--repo)
      REPO="$2"
      shift 2
      ;;
    -n|--notes-file)
      NOTES_FILE="$2"
      shift 2
      ;;
    --draft)
      DRAFT=1
      shift
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

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required but not found." >&2
  exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "gh is not authenticated. Run: gh auth login -h github.com" >&2
  exit 1
fi

if [[ -n "${NOTES_FILE}" && ! -f "${NOTES_FILE}" ]]; then
  echo "Release notes file not found: ${NOTES_FILE}" >&2
  exit 1
fi

DMG_PATH="${OUT_DIR}/Kotaeba-${VERSION}.dmg"
SHA256_PATH="${OUT_DIR}/Kotaeba-${VERSION}.sha256.txt"
TAG="v${VERSION}"
TITLE="Kotaeba ${VERSION}"

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "DMG not found: ${DMG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${SHA256_PATH}" ]]; then
  echo "SHA256 file not found: ${SHA256_PATH}" >&2
  exit 1
fi

REPO_FLAGS=()
if [[ -n "${REPO}" ]]; then
  REPO_FLAGS=(--repo "${REPO}")
fi

if gh release view "${TAG}" "${REPO_FLAGS[@]}" >/dev/null 2>&1; then
  echo "Release ${TAG} already exists. Uploading assets with --clobber..."
  gh release upload "${TAG}" "${DMG_PATH}" "${SHA256_PATH}" --clobber "${REPO_FLAGS[@]}"
  echo "Updated release assets for ${TAG}."
  exit 0
fi

CREATE_ARGS=(
  release create "${TAG}" "${DMG_PATH}" "${SHA256_PATH}"
  --title "${TITLE}"
)

if [[ -n "${NOTES_FILE}" ]]; then
  CREATE_ARGS+=(--notes-file "${NOTES_FILE}")
else
  CREATE_ARGS+=(--generate-notes)
fi

if [[ "${DRAFT}" -eq 1 ]]; then
  CREATE_ARGS+=(--draft)
fi

if [[ -n "${REPO}" ]]; then
  CREATE_ARGS+=(--repo "${REPO}")
fi

gh "${CREATE_ARGS[@]}"
echo "Created release ${TAG} with DMG assets."

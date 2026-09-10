#!/bin/bash
# Build a Release copy of CineSched and refresh /Applications with it — no version
# bump, no tag, no push. For picking up day-to-day changes on this Mac; use
# scripts/release.sh to cut a real version.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="LSVR CineSched"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT
xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" build | tail -2
APP="$DD/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

rm -rf "/Applications/$APP_NAME.app"
ditto "$APP" "/Applications/$APP_NAME.app"

INSTALLED="$(defaults read "/Applications/$APP_NAME.app/Contents/Info" CFBundleShortVersionString)"
echo "Installed CineSched ${INSTALLED} ($(git rev-parse --short HEAD)) to /Applications."

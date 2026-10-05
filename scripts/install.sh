#!/bin/bash
# Build a Release copy of Mainsheet and refresh /Applications with it — no version
# bump, no tag, no push. For picking up day-to-day changes on this Mac; use
# scripts/release.sh to cut a real version.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# The scheme keeps the CineSched code name; the product is Mainsheet (ADR 0008).
SCHEME="LSVR CineSched"
APP_NAME="Mainsheet"
# xcode-select on the dev machine points at the Command Line Tools; never touch it.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT
xcodebuild -scheme "$SCHEME" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" build | tail -2
APP="$DD/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

rm -rf "/Applications/$APP_NAME.app"
# The app was "LSVR CineSched.app" until 4.10; one copy in /Applications, not two.
rm -rf "/Applications/$SCHEME.app"
ditto "$APP" "/Applications/$APP_NAME.app"

INSTALLED="$(defaults read "/Applications/$APP_NAME.app/Contents/Info" CFBundleShortVersionString)"
echo "Installed Mainsheet ${INSTALLED} ($(git rev-parse --short HEAD)) to /Applications."

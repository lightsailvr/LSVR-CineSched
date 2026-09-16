#!/bin/bash
# Cut a CineSched release in one shot:
#   scripts/release.sh 4.6.0
# Bumps MARKETING_VERSION to the given version and CURRENT_PROJECT_VERSION by one
# (versions live in build settings — GENERATE_INFOPLIST_FILE=YES, the hand-written
# Info.plist is unused), rolls the changelog's [Unreleased] into a dated section,
# builds Release, installs to /Applications, commits, tags vX.Y.Z, pushes, and
# publishes a GitHub Release with the zipped app and the changelog as notes.
#
# For an untagged dev refresh of /Applications, use scripts/install.sh instead.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 4.6.0>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="LSVR CineSched"
PBXPROJ="$APP_NAME.xcodeproj/project.pbxproj"
CHANGELOG="$APP_NAME/CHANGELOG.md"
# xcode-select on the dev machine points at the Command Line Tools; never touch it.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean — commit or stash first" >&2; exit 1; }
git rev-parse "v${VERSION}" >/dev/null 2>&1 && { echo "error: tag v${VERSION} already exists" >&2; exit 1; }

# Release notes = everything under [Unreleased]; refuse to release nothing.
NOTES="$(awk '/^## \[Unreleased\]/{flag=1; next} /^## \[/{flag=0} flag' "$CHANGELOG")"
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "error: [Unreleased] section of the changelog is empty" >&2; exit 1; }

# --- Version bump ---
BUILD_NUM="$(sed -nE 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$PBXPROJ" | head -1)"
NEW_BUILD=$((BUILD_NUM + 1))
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# --- Roll the changelog ---
TODAY="$(date +%Y-%m-%d)"
perl -0pi -e "s/## \[Unreleased\]\n/## [Unreleased]\n\n## [${VERSION}] - ${TODAY}\n/" "$CHANGELOG"

# --- Build Release into a fresh DerivedData (the shared one can hit App Management
# denials when overwriting previously signed bundles) ---
DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT
xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" build | tail -2
APP="$DD/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

# --- Install to /Applications (remove first: ditto merges into existing bundles) ---
rm -rf "/Applications/$APP_NAME.app"
ditto "$APP" "/Applications/$APP_NAME.app"

# --- Commit, tag, push ---
MSG="Release ${VERSION} (build ${NEW_BUILD})"
[[ -n "${RELEASE_COMMIT_TRAILER:-}" ]] && MSG="${MSG}

${RELEASE_COMMIT_TRAILER}"
git add "$PBXPROJ" "$CHANGELOG"
git commit -m "$MSG"
git tag -a "v${VERSION}" -m "CineSched ${VERSION}"
git push origin HEAD "v${VERSION}"

# --- GitHub Release (zip stays in the temp dir: .app.zip never enters the source tree) ---
ZIP="$DD/LSVR-CineSched-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
gh release create "v${VERSION}" "$ZIP" --title "CineSched ${VERSION}" --notes "$NOTES"

echo "Released ${VERSION} (build ${NEW_BUILD}): installed to /Applications, tagged v${VERSION}, GitHub Release published."

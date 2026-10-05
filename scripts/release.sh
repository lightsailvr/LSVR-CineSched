#!/bin/bash
# Cut a Mainsheet release in one shot:
#   scripts/release.sh 4.6.0
#   scripts/release.sh 4.10.0 --testflight   # and upload every platform to TestFlight
# Bumps MARKETING_VERSION to the given version and CURRENT_PROJECT_VERSION by one
# (versions live in build settings — GENERATE_INFOPLIST_FILE=YES, the hand-written
# Info.plist is unused), rolls the changelog's [Unreleased] into a dated section,
# builds Release, installs to /Applications, commits, tags vX.Y.Z, pushes, and
# publishes a GitHub Release with the zipped app and the changelog as notes. With
# --testflight it then runs scripts/testflight.sh on the tagged commit (iOS, visionOS and
# macOS archives uploaded to App Store Connect; see that script for the API key).
#
# For an untagged dev refresh of /Applications, use scripts/install.sh instead.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 4.6.0> [--testflight]}"
TESTFLIGHT=0
case "${2:-}" in
    "")           ;;
    --testflight) TESTFLIGHT=1 ;;
    *) echo "error: unknown option '$2' (--testflight)" >&2; exit 1 ;;
esac
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# The Xcode project, scheme and source folder keep the CineSched code name; the product
# (the .app, the menu bar, the release) is Mainsheet since 4.10 (ADR 0008).
SCHEME="LSVR CineSched"
APP_NAME="Mainsheet"
PBXPROJ="$SCHEME.xcodeproj/project.pbxproj"
CHANGELOG="$SCHEME/CHANGELOG.md"
# xcode-select on the dev machine points at the Command Line Tools; never touch it.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean — commit or stash first" >&2; exit 1; }
git rev-parse "v${VERSION}" >/dev/null 2>&1 && { echo "error: tag v${VERSION} already exists" >&2; exit 1; }
# Fail before anything is bumped or pushed if the upload could not run.
if [[ $TESTFLIGHT == 1 ]]; then
    ASC_ENV="${HOME}/.config/cinesched/asc.env"
    # shellcheck disable=SC1090
    [[ -f "$ASC_ENV" ]] && source "$ASC_ENV"
    [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "${ASC_KEY_PATH:-/nonexistent}" ]] \
        || { echo "error: --testflight needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see scripts/testflight.sh)" >&2; exit 1; }
fi

# Release notes = everything under [Unreleased]; refuse to release nothing.
NOTES="$(awk '/^## \[Unreleased\]/{flag=1; next} /^## \[/{flag=0} flag' "$CHANGELOG")"
# (grep, not ${NOTES//[[:space:]]/}: bash 3.2's pattern substitution is pathologically
# slow on large strings and hung on 4.7.0's 47 KB of notes.)
grep -q '[^[:space:]]' <<<"$NOTES" || { echo "error: [Unreleased] section of the changelog is empty" >&2; exit 1; }

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
xcodebuild -scheme "$SCHEME" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" build | tail -2
APP="$DD/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

# --- Install to /Applications (remove first: ditto merges into existing bundles) ---
rm -rf "/Applications/$APP_NAME.app"
# The app was "LSVR CineSched.app" until 4.10; one copy in /Applications, not two.
rm -rf "/Applications/$SCHEME.app"
ditto "$APP" "/Applications/$APP_NAME.app"

# --- Commit, tag, push ---
MSG="Release ${VERSION} (build ${NEW_BUILD})"
[[ -n "${RELEASE_COMMIT_TRAILER:-}" ]] && MSG="${MSG}

${RELEASE_COMMIT_TRAILER}"
git add "$PBXPROJ" "$CHANGELOG"
git commit -m "$MSG"
git tag -a "v${VERSION}" -m "Mainsheet ${VERSION}"
git push origin HEAD "v${VERSION}"

# --- GitHub Release (zip stays in the temp dir: .app.zip never enters the source tree) ---
ZIP="$DD/Mainsheet-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
gh release create "v${VERSION}" "$ZIP" --title "Mainsheet ${VERSION}" --notes "$NOTES"

echo "Released ${VERSION} (build ${NEW_BUILD}): installed to /Applications, tagged v${VERSION}, GitHub Release published."

if [[ $TESTFLIGHT == 1 ]]; then
    # The release is already tagged and pushed; a failed upload is retried alone with
    # scripts/testflight.sh (or a subset: scripts/testflight.sh visionos).
    "$REPO_ROOT/scripts/testflight.sh" || { echo "error: TestFlight upload failed; ${VERSION} is released — rerun scripts/testflight.sh" >&2; exit 1; }
fi

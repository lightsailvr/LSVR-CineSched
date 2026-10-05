#!/bin/bash
# Archive CineSched and upload it to App Store Connect for TestFlight, one build per
# platform from the same commit, so every device runs the same version:
#   scripts/testflight.sh                  # iOS (iPhone and iPad), visionOS and macOS
#   scripts/testflight.sh ios macos        # a subset
# `scripts/release.sh <version> --testflight` runs this after tagging, which is the usual
# way in: each upload needs a build number App Store Connect has not seen for that
# version, and release.sh is what bumps it. Run alone, it uploads the build settings'
# current version and build, so it fails at the upload if they were already sent.
#
# Credentials: an App Store Connect API key with the App Manager role (Users and Access ▸
# Integrations), never in the repo. Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the
# .p8) in the environment or in ~/.config/cinesched/asc.env. With the key, xcodebuild
# signs for distribution itself (-allowProvisioningUpdates: cloud-managed certificates,
# App Store profiles), so no Xcode account login or local distribution certificate is
# needed. Internal testers see a build once App Store Connect finishes processing it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="LSVR CineSched"
TEAM_ID="647FZYVR5Q"
# xcode-select on the dev machine points at the Command Line Tools; never touch it.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ASC_ENV="${HOME}/.config/cinesched/asc.env"
# shellcheck disable=SC1090
[[ -f "$ASC_ENV" ]] && source "$ASC_ENV"
: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id), here or in $ASC_ENV}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (the issuer id of the key), here or in $ASC_ENV}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to the AuthKey_….p8), here or in $ASC_ENV}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "error: no API key at $ASC_KEY_PATH" >&2; exit 1; }

PLATFORMS=("$@")
[[ ${#PLATFORMS[@]} -gt 0 ]] || PLATFORMS=(ios visionos macos)

[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean — upload only what is committed" >&2; exit 1; }

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT

# Versions are ours (release.sh); App Store Connect must not renumber the build.
cat > "$DD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>                         <string>app-store-connect</string>
	<key>destination</key>                    <string>upload</string>
	<key>teamID</key>                         <string>${TEAM_ID}</string>
	<key>signingStyle</key>                   <string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key> <false/>
	<key>uploadSymbols</key>                  <true/>
</dict>
</plist>
PLIST

VERSION="$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);.*/\1/p' "$APP_NAME.xcodeproj/project.pbxproj" | head -1)"
BUILD="$(sed -nE 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$APP_NAME.xcodeproj/project.pbxproj" | head -1)"
echo "Uploading CineSched ${VERSION} (build ${BUILD}) for: ${PLATFORMS[*]}"

for PLATFORM in "${PLATFORMS[@]}"; do
    case "$PLATFORM" in
        ios)      DESTINATION="generic/platform=iOS" ;;
        visionos) DESTINATION="generic/platform=visionOS" ;;
        macos)    DESTINATION="generic/platform=macOS" ;;
        *) echo "error: unknown platform '$PLATFORM' (ios, visionos, macos)" >&2; exit 1 ;;
    esac
    ARCHIVE="$DD/$PLATFORM.xcarchive"

    echo "== $PLATFORM: archive"
    xcodebuild archive -scheme "$APP_NAME" -configuration Release -destination "$DESTINATION" \
        -archivePath "$ARCHIVE" -derivedDataPath "$DD/dd-$PLATFORM" "${AUTH[@]}" | tail -2

    # ADR 0006: the Mac never carries the iCloud entitlement; the other platforms must.
    APP_PATH="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
    ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null || true)"
    if [[ "$PLATFORM" == macos ]]; then
        grep -q "ubiquity" <<<"$ENTITLEMENTS" && { echo "error: the Mac archive carries an iCloud entitlement (ADR 0006)" >&2; exit 1; }
    else
        grep -q "iCloud.com.lsvr.LSVR-CineSched" <<<"$ENTITLEMENTS" || { echo "error: the $PLATFORM archive lacks the iCloud container entitlement (ADR 0006)" >&2; exit 1; }
    fi

    echo "== $PLATFORM: upload"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$DD/ExportOptions.plist" \
        -exportPath "$DD/export-$PLATFORM" "${AUTH[@]}" | tail -3
done

echo "Uploaded CineSched ${VERSION} (build ${BUILD}) for ${PLATFORMS[*]}. It reaches TestFlight's internal testers once App Store Connect finishes processing (usually 5–30 minutes)."

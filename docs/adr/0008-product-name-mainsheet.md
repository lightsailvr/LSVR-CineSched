# 0008 — The product is Mainsheet; CineSched stays the code name

Status: Accepted (2026-10-05, 4.10).

## Context

The app goes to TestFlight for internal testing (iOS, iPadOS, visionOS and macOS from one
App Store Connect record), which needs an App Store name unique across the store. Neither
"CineSched" nor the first choices (First Mate, Sail Plan) were free. The bundle identifier
`com.lsvr.LSVR-CineSched` is already registered with its iCloud container
`iCloud.com.lsvr.LSVR-CineSched` (ADR 0006), and every installed copy keeps its preferences
under it.

## Decision

The product is **Mainsheet**: the line that trims a mainsail, and a "sheet" like a call
sheet, in keeping with Light Sail VR. Everything a person reads says Mainsheet: the app's
name on every platform (`PRODUCT_NAME`, so the Mac's `Mainsheet.app` and its menu bar, and
`CFBundleDisplayName`), the launch screen, alert titles, the camera prompt, the PDFs'
fallback title, the document kind ("Mainsheet Project"), the iCloud Drive folder
(`NSUbiquitousContainerName`) and the scripts' releases.

Everything that identifies the app or its data keeps CineSched, because changing it would
strand data: the bundle identifier and the iCloud container (the files and preferences live
under them), the `.cinesched` extension and `com.lsvr.cinesched.*` types (ADR 0005: every
existing file and drag), the `CineSched…` preference keys, the Swift module
(`PRODUCT_MODULE_NAME = LSVR_CineSched`, so `@testable import` is unchanged), and the Xcode
project, scheme, target, source folders, type and file names.

## Consequences

- Code, issues and docs may keep saying CineSched for the codebase; a user-facing string
  says Mainsheet (through `L(...)` as always).
- The iCloud Drive folder is relabelled, not moved: the container is the same, so no file
  moves. iCloud rereads `NSUbiquitousContainers` only on a new bundle version, which every
  release bumps.
- The Mac's app is `Mainsheet.app`; `release.sh` and `install.sh` remove the old
  `LSVR CineSched.app` from /Applications so there is one copy. Preferences carry over (same
  bundle identifier). The test host is `Mainsheet.app/.../Mainsheet`.

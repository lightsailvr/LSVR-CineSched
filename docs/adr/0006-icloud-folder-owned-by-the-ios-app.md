# 0006 — The CineSched iCloud folder is owned by the iOS app; the Mac stays entitlement-free

Status: Accepted (2026-09-18, #12, part of #1)

## Context

Milestone 2 of #1 has iPad, iPhone and Vision Pro create, open and autosave projects in
one "CineSched" folder in iCloud Drive that every device, the Mac included, sees. iCloud
Documents needs an entitlement naming a container, an App ID with the iCloud capability,
and signing against that App ID. The Mac app is the shipping product, is built from source
by people without team membership (`CODE_SIGNING_ALLOWED=NO` builds), and already has the
files it needs through the sandbox's user-selected read/write: its Open and Save panels
can reach any folder, iCloud Drive included, without an entitlement.

One target builds all four platforms (ADR 0003), so "iOS gets iCloud, the Mac does not"
has to be expressed per SDK inside that target. The same goes for the iOS-only
`Info.plist` keys (document browser, open-in-place, the display name "CineSched").

## Decision

- **The container is the iOS, iPadOS and visionOS builds' alone.** They sign with
  `Config/CineSched-iOS.entitlements`: `com.apple.developer.icloud-services` =
  `CloudDocuments`, `com.apple.developer.icloud-container-identifiers` and
  `com.apple.developer.ubiquity-container-identifiers` = `iCloud.com.lsvr.LSVR-CineSched`
  (the bundle identifier under `iCloud.`). Wired with
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`, `[sdk=iphonesimulator*]`, `[sdk=xros*]` and
  `[sdk=xrsimulator*]`.
- **The Mac keeps sandbox plus user-selected files and nothing else.** The unconditional
  `CODE_SIGN_ENTITLEMENTS` is `LSVR CineSched/CineSched.entitlements` (unchanged), so a
  Mac build signs with Apple Development and no provisioning profile, as before. The Mac
  build's signed entitlements are checked to contain no `icloud` or `ubiquity` key.
- **`NSUbiquitousContainers` lives in the shared partial plist** (`Config/Info.plist`):
  the container, `NSUbiquitousContainerIsDocumentScopePublic` true (the folder shows in
  iCloud Drive), `NSUbiquitousContainerName` "CineSched", folder levels `Any`. A
  dictionary cannot be an `INFOPLIST_KEY_` setting, and a second, per-SDK partial plist
  would duplicate the type declarations of ADR 0005, so the Mac's plist carries the key
  too. It grants nothing: without the entitlement the Mac cannot open the container, and
  iCloud only reads these keys from an app that can. The keys are read when the bundle
  version changes; any edit to them needs a `CURRENT_PROJECT_VERSION` bump.
- **The iOS-only plist keys are per-SDK build settings**:
  `INFOPLIST_KEY_UISupportsDocumentBrowser[sdk=…]` = YES and
  `INFOPLIST_KEY_CFBundleDisplayName[sdk=…]` = CineSched for the four non-Mac SDKs.
  Xcode emits a per-SDK boolean as `false` and a per-SDK string as empty on the SDKs it
  is not set for, so the Mac's plist carries `UISupportsDocumentBrowser = false` (inert
  on macOS, and true to the Mac, which has no document browser) and the unconditional
  display name is the Mac's existing "LSVR CineSched".
  `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace` is YES unconditionally: the build
  system refuses `NO` on macOS, and a document-based Mac app does open in place.
- **The document scenes.** The same `DocumentGroup(editor:makeDocument:)` over
  `ProjectDocument` (ADR 0004) runs on every platform, from CineSchedApp's one seam:
  the Mac with `ContentView` and the menus, the others with `MinimalProjectEditor` (title
  field, shoot days with scene counts, every write through `perform`) and the system's
  `DocumentGroupLaunchScene` (title, New Project, recents, the document browser, which
  starts in the CineSched folder). The launch screen's Import buttons are #13's.
- **Legacy `.json` is not a document type off the Mac.** `ProjectDocument`'s readable
  types come from the `PlatformDocumentTypes` seam: `[.cineschedProject, .json]` on the
  Mac (the viewer role, ADR 0005), `[.cineschedProject]` on iOS and visionOS, whose
  browser and launch screen offer exactly the readable types and whose editor has no
  `LegacyProjectHandoff`. A legacy file is imported into a new project there (#13).
- **How the Mac finds the folder.** With no entitlement,
  `FileManager.url(forUbiquityContainerIdentifier:)` is unavailable, and the system's
  panels belong to `DocumentGroup` (`NSSavePanel.directoryURL` is out of reach). What
  works, and is verified under the sandbox: the folder's on-disk path is a function of the
  real home directory (`CineSchedFolder.macDocumentsURL(home:)`:
  `~/Library/Mobile Documents/iCloud~com~lsvr~LSVR-CineSched/Documents`, from `getpwuid`
  because `NSHomeDirectory()` is the container in a sandboxed app); the sandbox lets the
  app `stat` that folder though not read it; the panels start in their own remembered
  directory, `NSNavLastRootDirectory` in the app's defaults, which honours an absolute
  path outside the sandbox because the panel runs out of process. So `MacAppDelegate`
  seeds that key with the folder's path, once (its own flag), the first launch on which
  the folder exists, before AppKit's launch-time Open panel. It is a nudge, not a pin:
  from then on the panels remember wherever the user last saved, as in every Mac app,
  and the folder exists only once a device has saved a project in it and iCloud Drive has
  synced it down.

## Consequences

- A source build of the Mac app needs no team membership and no App ID change; a device
  build of the iOS app needs the App ID `com.lsvr.LSVR-CineSched` to have the iCloud
  capability with this container (Xcode's automatic signing adds it once, from a
  logged-in account, or the developer portal does).
- The simulators run the iOS and visionOS builds unsigned (`CODE_SIGNING_ALLOWED=NO`);
  there the launch screen, the editor, open-in-place and autosave work against local
  documents and the container is unavailable. Signing in to iCloud in a simulator is a
  human step.
- The Mac build's Info.plist mentions the container it cannot use; documented in the
  plist's own comment. Nothing else on the Mac changes.
- Renaming the container, the folder or the bundle identifier means: the entitlements
  file, `NSUbiquitousContainers`, `CineSchedFolder.containerIdentifier` (a test pins it)
  and a build-number bump.
- `PlatformDocumentTypes` is a new seam (ADR 0003's table grows a row); `ProjectDocument`
  itself stays free of `#if os`, and `PlatformPlaceholderView` is gone.

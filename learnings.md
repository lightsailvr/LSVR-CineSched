# Learnings

A running log of non-obvious things learned while building CineSched. Add an entry whenever
something cost real time, surprised you, or would surprise the next person. Newest first.

Format: date, one-line title, then what happened / why / what to do instead. Keep entries short.
If a learning becomes a rule for the whole codebase, promote it into `CLAUDE.md` or an ADR in
`docs/adr/` and leave a pointer here.

---

## 2026-09-18 — The CineSched iCloud folder: per-SDK entitlements, a merged plist that will not take NO, the panels' remembered directory, and a simulator that autosaves a minute later (#12)

Giving iOS and visionOS the document lifecycle with iCloud Documents while the Mac stays
entitlement-free:

- **The Mac had no `CODE_SIGN_ENTITLEMENTS` at all.** `LSVR CineSched/CineSched.entitlements`
  sat in the synchronized folder unreferenced (Xcode does not bundle `.entitlements` as a
  resource, so it did no harm); the Mac's sandbox entitlements came from `ENABLE_APP_SANDBOX`
  and `ENABLE_USER_SELECTED_FILES`. Wiring the file unconditionally and the iOS one per SDK
  (`"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]"`, `iphonesimulator`, `xros`, `xrsimulator`)
  gives the Mac exactly what it had (`app-sandbox`, `files.user-selected.read-write`,
  `get-task-allow` in Debug), checked with `codesign -d --entitlements - --xml`.
- **A per-SDK boolean `INFOPLIST_KEY_` lands in the other SDKs' plists as `false`, and a
  per-SDK string as `""`**, not as an absent key: the Mac's plist got
  `UISupportsDocumentBrowser = false` (harmless) and `CFBundleDisplayName = ""` (not
  harmless; Finder would show an empty name), so the unconditional display name is set to
  the Mac's existing "LSVR CineSched". And `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace`
  set per SDK fails the *Mac* build ("'LSSupportsOpeningDocumentsInPlace = NO' is not
  supported on macOS"); it is unconditional YES. The three keys are typed in
  `CoreBuildSystem.xcspec` (grep the spec under `SharedFrameworks/SwiftBuild.framework`
  before inventing an `INFOPLIST_KEY_`); an unknown key would be emitted as a string.
- **`NSUbiquitousContainers` in the shared partial plist reaches the Mac's plist too.** It
  grants nothing without the entitlement, and a per-SDK `INFOPLIST_FILE` would mean two
  copies of the type declarations, so it stays shared and the Mac carries an inert key.
- **A simulator build with signing on embeds the iCloud entitlements as a `__TEXT,
  __entitlements` section (`…-Simulated.xcent`), and `codesign -d --entitlements` shows
  `{}`.** Read the `.xcent` in `Intermediates.noindex/…/LSVR CineSched.build/` to check
  them. The device build (`generic/platform=iOS`, no `-allowProvisioningUpdates`) fails
  with "Provisioning profile … doesn't include the iCloud capability" and "doesn't support
  the iCloud.com.lsvr.LSVR-CineSched iCloud Identifier": the App ID needs the capability
  from a logged-in Xcode or the portal; nothing in the repo can do that.
- **The 27 SDK spellings** (from `SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`;
  there is no `arm64-apple-ios` file, and the XROS one matches):
  `DocumentGroupLaunchScene(_ title: LocalizedStringKey, _ actions:, background:)` (plus
  `backgroundAccessoryView:` / `overlayAccessoryView:` taking a `DocumentLaunchGeometryProxy`),
  `NewDocumentButton(_ title:, contentType: UTType? = nil)` and, for #13,
  `NewDocumentButton(_:contentType:source: DocumentCreationSource(id:))`, which arrives in
  `DocumentGroup(editor:makeDocument:)`'s second parameter as `context.creationSource` (also
  on `configuration.creationSource`). `makeDocument` is `@MainActor async throws`. The
  environment's `newDocument(_:)` for a `ReadableDocument` is **macOS-only**; on iOS a
  creation source is the way to hand a `ProjectData` to a new document.
- **The system's Open/Save panels start in `NSNavLastRootDirectory`** (a plain path string
  in the app's defaults), and honour it only when the process has a bundle identifier (a
  bare `swiftc` binary always got `~/Documents`). Verified with a sandboxed throwaway
  bundle: an existing folder under `~/Library/Mobile Documents` outside the container is
  honoured (the panel runs out of process), a nonexistent one falls back to `~/Documents`,
  `~`-relative forms are not expanded, and each confirmed panel rewrites the key. The app
  may `stat` that folder from inside the sandbox (`fileExists` true, `access(R_OK)` false).
  `NSHomeDirectory()` in a sandboxed app is the container; `getpwuid` gives the real home.
  The panel's own `directoryURL` on the app side never reflects what the remote panel
  shows, and `NSSavePanel.ok(nil)` is "not implemented" for the remote panel, so read the
  panel service's log (`Open Sync Started` / `OpenSync: Begin` lines from
  `com.apple.appkit.xpc.openAndSavePanelService`) or `panel.urls` after `cancel`.
- **`getpwuid` in the simulator is the host's password database**, so a test on it is a
  test of the Mac; `realHomeDirectoryIsAnAbsoluteDirectory` is `#if os(macOS)`.
- **The iOS document infrastructure autosaves about a minute after the edit** (the Mac
  writes within seconds): the file's mtime moved 65 s after the typed title, with the app
  in the foreground. Kill the app before that and the edit is gone; the human check for
  "survives killing and relaunching" has to wait it out or background the app first.
- **Checking the iOS document lifecycle without tapping**: `simctl openurl <device>
  file://<the app's data container>/Documents/X.cinesched` opens the document in the app
  on a cold launch (a warm `openurl` on the launch screen did nothing), and a throwaway
  XCUITest that calls `XCUIApplication().activate()` (not `launch()`, which would relaunch
  to the launch screen) can then type into the title field and read it back. A tap on the
  launch screen's New Project from XCUITest registered but opened nothing, twice; the
  document browser runs in a remote view service (`DocumentManagerUICore.Service`) that
  the automation touch reaches but the creation never follows. `app.buttons["New Project"]`
  also matches the button *and* its label (use `.matching(identifier:).firstMatch`), and
  `-parallel-testing-enabled NO` keeps the test on the real device, whose log survives.
- **Nothing in the app's data container is `.cinesched` before the first save**, and with
  no iCloud account in the simulator the launch screen's Browse shows "On My iPhone"; the
  CineSched folder itself needs a signed-in simulator or a device.

---

## 2026-09-18 — Sync state and conflict policy as pure values: `nonisolated Codable, Equatable` leaves `Equatable` on the main actor, and the warning it causes has no file (#14, #15)

Building `SyncState.derive` and `ConflictPolicy.decide` as `nonisolated` pure-core types:

- **`struct ProjectData: nonisolated Codable, Equatable` makes only `Codable` nonisolated.**
  The modifier applies to the one conformance it precedes; `Equatable` stays inferred
  `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A `nonisolated struct`
  holding a `ProjectData?` and synthesizing its own `Equatable` then warns "main
  actor-isolated conformance of 'ProjectData' to 'Equatable' cannot be used in nonisolated
  context", and the warning is reported at `<unknown>:0:` (synthesized code), so a grep
  by file name misses it; grep the whole log for `warning:` and count. Making the model's
  `Equatable` nonisolated would cascade through every type it contains (`ShootDay`,
  `Scene`'s `Hashable`, `CallSheetData`, `ProductionInfo`, …); `ConflictVersion` instead
  hand-writes `==` over its identity (id, date, device) and treats the snapshot as payload,
  which is the comparison the decision wants anyway. Worth doing the cascade once a second
  nonisolated type needs to compare projects.
- **The resource values carry no "waiting" state.** `URLResourceValues` says uploading,
  uploaded, downloading and a downloading status; whether the item is *waiting* is the
  network's, so the mapping takes reachability as its own input and puts it above every
  transfer flag (a stale `isUploading` offline is not to be believed). The acceptance test
  for airplane mode expects "waiting" with nothing pending, which settles the precedence.
- **`URLUbiquitousItemDownloadingStatus` is a struct of static constants, not an enum**;
  a `switch` over `.current` / `.downloaded` / `.notDownloaded` needs a `default`. The
  snapshot's own `DownloadingStatus` enum exists so tests and the mapping never touch it.

---

## 2026-09-18 — Call sheet pagination: a closure that captures the outer `y` is stale on both sides, and Quartz stamps every PDF with a fresh date and ID (#32)

Fixing the call sheet's blank continuation pages (`ensureRoom` reset an outer `y` that each
section shadowed with its own `var y = y`):

- **The stale capture broke the check as well as the reset.** `ensureRoom` compared the
  *outer* `y`, frozen at the section's starting position, against the bottom margin, so the
  scenes table never broke at all: all 27 rows of the long fixture went onto page 1, the last
  eleven below the margin and off the media box, and the three extra pages were opened only
  because the following sections were handed a negative `y`. The issue's first suggestion —
  return the current `y` from the closure — would have fixed the reset and left the check
  stale. The section's running `y` has to reach the closure, hence `inout`
  (`ensureRoom(rowH, &y)`, the closure typed `(CGFloat, inout CGFloat) -> Void`; the shooting
  schedule already passes `yPosition: inout`). With the check honest the fixture is 3 pages,
  not 4, and page 1 ends at scene 311, not 313.
- **"Byte-for-byte" needs a mask.** Two exports of the same call sheet seconds apart differ in
  74 bytes: the `CreationDate` / `ModDate` digits in the Info dictionary and the 32-byte
  trailer `/ID`, which Quartz derives from the time. Every object and the xref table were
  identical (same size, same `startxref`), so `cmp -l` plus a look at the offsets settles it;
  the pixel diff (#4–#6's scratch tool, rebuilt in a few dozen lines on PDFKit + CoreGraphics)
  is the cleaner statement and is what the report should quote.
- **The general-call banner overdraws itself when both a quote and a schedule line are set**:
  the 26pt call time sits on the italic "Schedule:" line (see the long fixture's page 1, and
  `CallSheet.pdf`). Pre-existing, pixel-identical before and after; not #32's.

---

## 2026-09-18 — Checking whether a PDF label fits is a five-line CoreText script, and a taller label box is not a fix (#33)

The breakdown sheet's "BREAKDOWN SHEET #" wrapped because 9pt bold SF measures 104.4pt
against the cell's 103pt label area; 8.5pt is 99.1pt. `CTLineGetTypographicBounds` on a
`CTLineCreateWithAttributedString` of `CTFontCreateUIFontForLanguage(.emphasizedSystem, …)`
gives the width `PDFCanvas` will lay out (tracking included), so a `swift` script answers
"does this label fit?" without dumping and rasterizing a PDF. Of the three fixes the issue
offered, the label box cannot simply grow: `drawCell` takes the value's height from what
the label leaves, so a two-line label in the 44pt top row leaves the 13pt sheet number
11pt and the auto-scaling loop shrinks it to the 7pt floor. A smaller size changes
`labelHeight` (`labelSize + 5`) and moves the value half a point; the shorter "SHEET #"
keeps every metric in the cell where it was, and the masthead already carries the full
name. The scene number now follows `ShootingSchedulePDFExporter`'s order (`sceneNumber`,
then the title's prefix); `Scene.extractedSceneNumber` was not used because its "1"
fallback would number every banner and event.

---

## 2026-09-18 — The palette in the file: adoption cannot mark the document edited, `JSONEncoder` orders keys its own way, and an environment value is the cheap way to reach every strip (#11)

Moving the strip colors from per-device `UserDefaults` keys into `ProjectData.palette`:

- **A document cannot mark itself edited.** The 27 `Document` protocol has `apply(snapshot:)`
  and `snapshot(contentType:)` and nothing else; the infrastructure autosaves only from undo
  actions registered with the window's `UndoManager`, which only `ContentView` has. So the
  adoption of a device's overrides into a paletteless project (story 19 of #1) happens in the
  document's constructors and `apply`, in memory, and reaches the file with the project's
  next `perform`. The alternative, an `edit` from the view on load, would put "Undo Adopt
  Scene Colors" in the Edit menu the moment a file opens, and could not run in the document
  tests. Until that next edit, reopening on the same device adopts the same colors again;
  on another device the file still has no palette. Recorded in the CHANGELOG.
- **The device overrides are injected, not read, by `ProjectDocument`.** Its default is
  `nil` (no device overrides); only the app's two constructors (`makeDocument` in
  CineSchedApp and `LegacyProjectHandoff`) pass `SceneColorSettings.deviceOverrides()`. A
  default that read `UserDefaults.standard` would have made `applyReplacesTheWholeSnapshot`
  fail on any Mac whose colors were customized, since the test host is the app.
- **`JSONEncoder` without `.sortedKeys` writes a keyed container's keys in hash order, not
  encoding order**, and `ProjectCodec` sets no `sortedKeys` (the whole file has always been
  ordered that way: `productionInfo` comes first). A test that pinned `"palette" : {
  "intDay" …, "extDay" …` in slot order failed; pin key presence, not order.
- **`nonisolated struct` / `nonisolated enum` work for a pure-core type** under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (the reader and writer already used it). A
  member that touches a main-actor API (`Color(hex:)` in ThemeManager.swift) is then a
  warning ("call to main actor-isolated initializer in a synchronous nonisolated context");
  mark that one member `@MainActor` rather than the whole type. The reverse trap: a plain
  `enum` of static functions is main-actor by default, and calling one from the system's
  off-main-actor document factory (`LegacyProjectHandoff`'s `init(untitled:)` path) is
  the same warning; `SceneColorSettings` is `nonisolated` for that reason. Grep the
  whole build log for `warning:` before claiming the count, not just the files touched.
- **A strip's color can be read back from a PDF without PDFKit's help**: rasterize the
  page into a `CGBitmapContext` (sRGB, 1 pt per pixel, antialiasing off) with
  `drawPDFPage` and scan for the exact RGB triple; a flat rectangle fill lands exact
  pixels on every platform. `pdfPage(_:_:containsColorHex:)` in PDFTestSupport is the
  helper, and the exporter tests use a magenta no standard slot has so the check cannot
  pass by accident.
- **Threading a per-document value to every strip is one `.environment` at the editor's
  root** (`@Entry var scenePalette`), read with `@Environment` in the four views that call
  `stripColor(in:)`; the explicit alternative was a new `let` through `CompactMonthCalendarView
  → DayCellView → SceneCardView` and `StripboardView → SceneStripRow`, plus every preview
  and sheet. Sheets inherit the presenting view's environment, so the Day Detail sheet gets
  it for free. Exporters are pure functions and take `palette:` explicitly.
- **The color editor coalesces per slot**: a `ColorPicker` writes its binding on every
  movement of the color wheel, so `ContentView` keeps one `EditGesture` per slot being
  edited (`paletteGesture`), new token when the slot changes, cleared when the sheet closes.
  One token for the whole sheet session would have made "change two colors, undo" revert
  both. Reset is untokened, its own step.

---

## 2026-09-17 — Recovering the UserDefaults working copy: no view exists at launch, `makeDocument` runs after `openUntitledDocumentAndDisplay` returns, and a foreign security-scoped bookmark is "not in the correct format" (#10)

Recovering the pre-document builds' `SavedProject` blob and `CineSchedCurrentFileBookmark`
on the first launch of the document model:

- **There is no SwiftUI view to run a launch-time recovery from.** With iCloud Drive on the
  app shows the Open panel at launch (no window, no `DocumentGroup` editor), and the
  `openDocument` / `newDocument` environment actions need a view. So it is an
  `@NSApplicationDelegateAdaptor` (`MacAppDelegate`, a seam) driving `NSDocumentController`,
  which is what those actions use anyway, from `applicationDidFinishLaunching`. That runs
  before AppKit's "open untitled" step, and a document open (or opening) by then suppresses
  the Open panel and the blank window; no second window appeared in any case tried.
- **SwiftUI's own app delegate does not forward `applicationShouldOpenUntitledFile`** to the
  adaptor's delegate (never called across six launches, including one where the Open panel
  did appear). Do not make a launch decision depend on it.
- **`NSDocumentController.openUntitledDocumentAndDisplay(true)` returns before
  `DocumentGroup`'s `makeDocument` closure runs**; the infrastructure builds the SwiftUI
  document lazily. A "set the seed, open, clear the seed" sequence hands `makeDocument` nil.
  The seed (`MacAppDelegate.pendingUntitledProject`) therefore stays set until
  `makeDocument` takes it, which is the next document made; on the first launch nothing
  else is making one. Taking the seed is also what removes the legacy keys, so "after a
  successful open" means after the project is in a document, not after the
  `NSDocumentController` call returned.
- **`updateChangeCount(.changeDone)` on the returned `NSDocument` is enough for "edited"**:
  closing raised the Save sheet (Delete / Cancel / Save, the autosave-in-place form) and the
  document reported `isDocumentEdited`. The window's own edited flag reads false within a
  second, the same as after any real edit (the draft autosaves at once and the title's
  "Edited" clears; 2026-09-16 #8). A seeded project registers no undo action, so without
  this call the recovered window would close silently.
- **A security-scoped bookmark resolves only in the app that made it.** One made by a
  helper tool, or to a file since deleted, fails with `NSCocoaErrorDomain 259` ("isn't in
  the correct format"), not "no such file". Seed a test bookmark from inside the app under
  test (a temporary env-gated branch that calls `bookmarkData(options: .withSecurityScope)`
  and writes the key), never from a script.
- **The oldest lineage's file shape can never compare equal to anything**: `ProjectCodec`
  gives it `createdDate = Date()` on every decode. Only matters for a fixture; a real
  working copy is the current shape.
- **An undecodable blob is left in place, not deleted.** The spec removes the keys "after a
  successful open", and nothing opened; the check on every later launch is one defaults
  read and a failed decode. With no blob at all, the bookmark key alone is removed.
- **Checking launch behaviour without touching the real container**: the shell cannot read
  `~/Library/Containers/com.lsvr.LSVR-CineSched` (TCC), so build with
  `PRODUCT_BUNDLE_IDENTIFIER=com.lsvr.CineSched-recoverytest ENABLE_APP_SANDBOX=NO
  CODE_SIGNING_ALLOWED=NO`, seed with `defaults write <id> SavedProject -data <hex>`, launch
  with `open -n … --args -ApplePersistenceIgnoreState YES`, and read the outcome from a
  temporary `os.Logger` trace (`/usr/bin/log show --predicate 'subsystem == "<id>"'`; the
  delegate's subsystem is the bundle identifier) that lists
  `NSDocumentController.shared.documents` (`isDocumentEdited`, `fileURL`) and `NSApp.windows`
  (`attachedSheet`) and calls `performClose(nil)` on the first window. `NSApp.terminate` is
  blocked by the Save sheet; end the trace with `exit(0)`. Every row was run this way,
  plus a launch with the keys already gone (the second launch: the Open panel, nothing
  touched). What this does not cover: the sandboxed container's prefs and a panel-made
  bookmark under the real bundle identifier, which need the human's Mac.
- **Closing the untitled document a legacy `.json` hands off to is silent** (pre-existing,
  #8): it is not marked edited, so the window closes without a Save prompt and the copy is
  gone (the `.json` on disk is untouched). The "equal" recovery row goes through that path.

---

## 2026-09-17 — Undo coverage on the document model: the funnel was already complete, the gaps were editors writing a field at a time (#9)

Auditing every edit path for #9 after #8 and #34:

- **Every write already reached `perform`**; nothing bypassed it and the manual snapshot
  stack was gone. What #8 left was two editors writing their value back one property at a
  time through their binding: `CallSheetEditor.saveToDay` made 19 binding writes and
  `ProductionSetupSheet`'s Save 11, i.e. 19 and 11 `perform`s (each a whole-project
  compare and an undo registration). In the app they still undid as one step only because
  the window's `UndoManager` groups by run-loop event; with `groupsByEvent` off (the tests)
  they were 19 and 11 steps. Build the whole value locally and assign it once. Any new
  editor should write its value back as **one assignment** to its binding.
- **A pure `ProjectData` mutation that lives as a `private func` on a SwiftUI view is
  untestable through the funnel.** The range regeneration was one; it moved to
  `ProjectData.updateProductionRange` (ProductionRange.swift) unchanged apart from the
  Boneyard return order, which used to come from iterating a `[UUID: Scene]`, i.e.
  arbitrary. Iterating the days instead is deterministic and lets a test pin it.
- **The regeneration appends a day's calendar events after its script scenes** (it buckets
  the two separately), so a day that held an event before its last strip comes back with
  the event last. Long-standing; the Stripboard and calendar draw events in their own row
  anyway, so nothing visible changes. A test comparing whole scene arrays across a
  regeneration must compare script scenes and events separately.
- **The Stripboard had no `onBeforeSceneChange` at all**, so its drops (`shootDays` then
  `allScenes`), its quick-time sheet (scene then lunch time) and its call sheet Save
  (the day, then the auto-meal sync) were one undo step only by run-loop grouping. It now
  takes the same closure as the calendar and opens the gesture in `editSchedule`, the
  quick-time save and a wrapping binding for the call sheet editor (the editor writes
  before `onSave` runs, so the binding's setter is the place to open it). Likewise a
  Production Setup save that renames characters: `renameCastCharacter` opens the gesture
  (once) so the roster write that follows folds in. Any new child-view action that writes
  a binding more than once must call `onBeforeSceneChange()` first.
- **Child-view edits (calendar and Stripboard bindings) carry no action name**, so a drag
  or a call sheet Save shows as plain "Undo" in the Edit menu, while `ContentView`'s own
  edits are labelled. Naming them means `onBeforeSceneChange` carrying a name through ~18
  call sites; not done in #9.

## 2026-09-16 — Measuring the document model's lag: the funnel was innocent, `L()` built its 250-entry table per call, and every drop drew the calendar twice (#34)

Every hypothesis in #34 pointed at `perform`, the whole-project `!=` compare and the binding
writes. Measured (a 300-scene, 200-day project, main-thread CPU per operation, Debug), the
funnel was 2–10 ms of a 125 ms drop. What the profile actually showed, in order:

- **`L(_:lang:)` built a `[String: [AppLanguage: String]]` literal of ~250 entries on every
  call**, and a calendar redraw calls it from every day cell's context menu, tooltip and
  "Day N" badge, and from every Boneyard row's context menu: 20–30 ms of every drop, in
  Release too (allocation, not code, dominates). It is a lookup in a global `let` now.
- **SwiftUI evaluates `.contextMenu { … }` builders eagerly** on every body pass of the
  view they hang off, not when the menu opens. `View.contextMenu<A>(menuItems:)` was 429 ms
  of a 1.5 s profile. Anything inside one is body cost.
- **A drop cost two full body passes**: the edit invalidated `ContentView`, then
  `onChange(of: document.project)` (a whole-project compare per pass) wrote five `@State`
  values, one a tuple array that is never `Equatable`, so the calendar and Boneyard drew
  again. Undo the same. `DerivedScheduleState` + a cache keyed on `ProjectDocument.changeCount`
  makes the derivation part of the one pass, and the compare is gone. `pruneSelection` only
  writes the selection when it actually shrinks (SwiftUI does compare `Equatable` state on
  write — the pre-#8 profile showed `ShootDay ==` under `ContentView.shootDays.setter`).
- Not on the profile at all: the fresh `ProjectCommands` published per body pass (one
  `FocusedValues` assign sample in a 1.5 s trace, no `Commands` or `NSMenu` frames), the
  `perform` compare, and the `@Observable` granularity of `document.project`. Left alone.
- Smaller: three `DateFormatter()`s per day cell (35 ms/run; now `formattedDate(_:pattern:)`
  caches them), `productionDayNumbers` and a `firstIndex(where: isDate(inSameDayAs:))` per
  cell, `ConflictScanner.scan` trimming and comparing every roster name for every character
  of every scene (a normalized dictionary now), and the calendar's cross-day move writing
  the `shootDays` binding once per day in the range (a local copy, written once).

Numbers (main-thread CPU per operation, 300 scenes / 200 days, Release; Debug in brackets):
pre-#8 `2f48f5c` drop 106 [123], move 84 [101], undo 68 [74], redo 71 [70]; `document-model`
tip `20d06d2` drop 108 [129], move 104 [125], undo 107 [123], redo 103 [136]; after this
change drop 73 [72], move 72 [80], undo 60–70 [76], redo 65 [66]. What is left is SwiftUI's
own update of ~4–6k attributes per redraw (every `DayCellView` and `SceneCardView` takes
closures, so none is skipped); the next step, if ever needed, is Equatable cells.

How it was measured, since none of it needs a screen (the harness lived in a temporary
`PerfFixture.swift` + an env-gated `.task` in `applyLifecycle`, removed before commit):

- **Drive the editor from inside**: a `.task` gated on `CINESCHED_PERF` that loads a
  generated project through `edit`, then replays the calendar's exact binding-write
  sequences (`allScenesBinding.wrappedValue.removeAll…`, `shootDaysBinding.wrappedValue[i]
  .scenes.insert…` under `beginEditGesture`/`endEditGesture`) and `undoManager?.undo()`.
  The pre-#8 worktree got the same script against its `@State` and `performUndo()`.
- **"Lag" = main-thread time until the run loop sleeps**: a `CFRunLoopObserver` on
  `beforeWaiting` with order `CFIndex.max` (after Core Animation's commit) records the first
  and last wake within 400 ms of the edit; `thread_info(THREAD_BASIC_INFO)` on the main
  thread gives its CPU over the same span. Both agreed to the millisecond, so the lag is CPU.
- **`xctrace record --launch` runs the copy LaunchServices knows**, i.e. the human's
  DerivedData build, not the scratch one (the trace's `<process path>` tells). Launch the
  scratch binary yourself (`open -n --env K=V app --args …`, or the executable directly with
  the env in the shell) and `--attach <pid>`; an unsigned scratch build attaches fine.
  `xctrace export --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'`
  gives XML with `ref`-deduplicated frames (resolve `id`/`ref` yourself); frames carry
  `<source line=…>`, which is how `L()` at `contextMenu` call sites was pinned. The Time
  Profiler template only records signposts in the `PointsOfInterest` category, so window
  each operation with `OSSignposter(subsystem:category: .pointsOfInterest)`. The `SwiftUI`
  template's `swiftui-updates` table gives per-view update counts and durations.
- **Harness pitfalls**: state restoration reopened the previous run's window, so the `.task`
  ran in two documents (`-ApplePersistenceIgnoreState YES` as a launch argument); the
  window's `NSUndoManager` does not close its per-event group between Swift-concurrency
  continuations, so every scripted edit folded into one undo step until the script posted an
  `.applicationDefined` `NSEvent` between operations; `open` with `--args <file>` silently did
  nothing for the pre-#8 (non-document) app, whose binary had to be run directly; and the
  pre-#8 build must run under its own `PRODUCT_BUNDLE_IDENTIFIER`, or its two-second
  autosave overwrites the human's UserDefaults working copy.

## 2026-09-16 — The Mac as a document app: `makeDocument` gets no URL, the Open panel follows `readableContentTypes`, LaunchServices ignores apps in /tmp, and how to check any of it without a screen (#8)

Wiring `DocumentGroup(editor:makeDocument:)` around `ProjectDocument` and moving every
mutation in `ContentView` onto `perform`:

- **`makeDocument`'s `configuration.fileURL` is nil even when a file is being opened**
  (observed for File ▸ Open, LaunchServices and state restoration alike; it was set for one
  `open file.cinesched` and nil for the others). The URL is settable on the configuration and
  arrives by the time `apply(snapshot:previous:)` runs, so the document keeps the
  configuration and reads `fileURL` live rather than copying it at construction. Do not
  branch on the URL in `makeDocument`; give every document the blank template and let
  `apply` replace it.
- **The system Open panel offers exactly `readableContentTypes`** (`com.lsvr.cinesched.project`
  and `public.json`, read straight off `NSOpenPanel`'s log line) with no `CFBundleDocumentTypes`
  entry for JSON. So the viewer role for a legacy `.json` needs nothing in the plist, which is
  what keeps iOS from claiming every JSON later. The plist declares only the native type, as
  Editor with `LSHandlerRank` Owner, which is what Finder's kind string ("CineSched Project")
  and double-click come from.
- **With iCloud Drive on, a document app launched with nothing to open shows the Open panel,
  not an untitled window** (the `NSShowAppCentricOpenPanelInsteadOfUntitledFile` behaviour
  TextEdit has). ⌘N still makes the untitled window; the AC's "New Project opens an untitled
  window" is about that, not launch.
- **LaunchServices will not make an app under `/private/tmp` (so a scratch `-derivedDataPath`)
  the handler for anything**: `lsregister -dump` shows the claim, `NSWorkspace
  .urlsForApplications(toOpen:)` leaves the app out, and `open file.cinesched` goes to
  TextEdit. Copy the build to `~/Applications` (then remove it and `lsregister -u`) to test
  the association.
- **Checking the lifecycle from an agent shell that has no screen-recording or automation
  permission** (screenshots come back black, `osascript` to System Events hangs on the consent
  prompt): temporary `os.Logger(subsystem: "cinesched.trace", …).notice("… \(x, privacy:
  .public)")` lines in `makeDocument`, `apply` and `snapshot`, launch with `open -n`, drive it
  with `open -a App file` / `open file`, and read `/usr/bin/log show --info --predicate
  'subsystem == "cinesched.trace"'`. `print` is block-buffered off a tty and `NSLog` payloads
  show as `<private>`; and `log` is a zsh builtin, so spell out `/usr/bin/log`. What this
  cannot check is Save/autosave/undo through the menus; that stays a human step.
- **The infrastructure autosaves an opened file within seconds of the first edit and does
  not honour the readable/writable split as a viewer role.** A `.json` opened through
  `readableContentTypes` was rewritten in place by the writer (checksum changed, no panel)
  after one scripted edit, and File ▸ Save did the same; `configuration.fileURL = nil` from
  `apply` changed nothing. NSDocument's "Save As for an unwritable type" does not exist
  here. The fix is the spec's own design: `LegacyProjectHandoff` hands the contents to
  `newDocument(ProjectDocument(untitled:))` and `dismiss()`es the `.json` window; the Save
  panel then opens with `currentContentType: com.lsvr.cinesched.project`, and the writer
  throws on any `.json` destination as a backstop. `newDocument`'s factory closure is
  `@Sendable`, hence the `nonisolated init(untitled:)` that writes the Observation backing
  store (`_project`) directly. Also: the "Edited" title state clears as soon as autosave
  has written, which is Lion-style behaviour, not a missing dirty flag.
- **What a headless harness could and could not reproduce from the human test.** With a
  temporary env-gated script in `onAppear` (edit through `edit`, `undoManager.undo()`, then
  `menu.delegate?.menuNeedsUpdate?(menu)` + `performActionForItem(at:)` on the real Edit ▸
  Undo and Production ▸ Production Setup… items): undo and redo revert through the window's
  undo manager whether the first responder is the window or a SwiftUI field editor; the
  focused scene value reaches the `Commands` body once the window is key and routes to
  whichever of two windows is key. Reading `NSMenuItem.isEnabled` / `action` without
  `menuNeedsUpdate` shows stale (disabled, nil) items — SwiftUI refreshes them when the menu
  opens — so do not judge command enablement from a raw item snapshot. Launching with a file
  path as argv in the sandboxed build makes the file unwritable ("You don't own the file…
  Duplicate?"); use `ENABLE_APP_SANDBOX=NO` for the harness build. And `pkill -f "LSVR
  CineSched"` also hits a copy the human is running from Xcode; kill by PID.
- **An `@AppStorage` view toggle is an app preference, and the moment there are two windows
  it flips both.** Human testing caught Calendar/Stripboard, cast row, times-vs-pages and
  all-days switching every open project. `@WindowPreference` (a `DynamicProperty` around
  `@State`, seeded from the defaults key once per window and written back on change) keeps
  the last-used behaviour with per-window state, and the View menu binds to the key window's
  values through `ProjectCommands` (`commands?.x ?? .constant(…)`, disabled when nil).
  Appearance (Dark Mode, Theme) is deliberately still app-wide.
- **`onBeforeSceneChange` cannot be a strict undo bracket.** Several calendar paths call it and
  then finish through `assign`/`removeScene` without `onSceneChanged`, so an `EditGesture`
  opened there is also closed at the end of the run-loop turn (`DispatchQueue.main.async`);
  otherwise the next unrelated edit would fold into the drag's undo step. The window's
  `UndoManager` groups by event anyway, so the token only matters for gestures that span
  turns.
- **A no-op `perform` must not register**: the editors write their whole value back on Save,
  and with bindings now funnelling into `perform` that would dirty the document (and add a
  blank undo step) every time a sheet is dismissed with Save. `perform` compares before and
  after and returns early.

## 2026-09-16 — The project document: `nonisolated Codable` is a two-word fix, UndoManager needs a run loop or a group, a partial Info.plist merges (#7)

Building `ProjectDocument` on the 27 `Document` protocol and extracting `ProjectCodec`:

- **The 27 document protocols are `Document = ReadableDocument & WritableDocument`, with
  `DocumentReader` / `DocumentWriter` as separate `@concurrent` types** whose `read` /
  `write` take a `consuming Subprogress` (the new `ProgressManager` API: `progress.start(
  totalCount:)` gives the manager to `complete(count:)` on). `DocumentReadConfiguration`
  and `DocumentWriteConfiguration` have no public initializer, so a test cannot call
  `document.reader(configuration:)`; it constructs `ProjectDocumentReader()` directly.
  `DocumentGroup(editor:makeDocument:)` hands the document a `URLDocumentConfiguration`
  (file URL, modification date, file coordinator) — for the next ticket.
- **A main-actor-isolated `Codable` conformance is a one-line change to make nonisolated:**
  `struct Scene: Identifiable, nonisolated Codable, Hashable`, plus `nonisolated` on any
  hand-written `init(from:)` / `encode(to:)` and on anything they touch (`ShootDay.
  isBlackout`, `ProjectData.init`). Synthesized witnesses follow the conformance. Under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` every conformance is inferred `@MainActor`,
  which is why the baseline had 4 "isolated conformance cannot be used in nonisolated
  context" warnings at the old `ProjectFile` call sites; the codec would have carried them
  over. Scratch-checking the syntax with `swiftc -typecheck -Xfrontend -default-isolation
  -Xfrontend MainActor -enable-upcoming-feature InferIsolatedConformances` took a minute
  and saved a build cycle.
- **`UndoManager.registerUndo` with `groupsByEvent` on and no run loop folds every
  registration into one step**, so a test that performs two edits and undoes gets both back.
  With `groupsByEvent = false` and no open group it throws (`must begin a group before
  registering undo`). `perform` therefore opens and closes an explicit group around each
  registration — invisible in the app, where it nests inside the event group — and the tests
  turn `groupsByEvent` off. Re-registering inside the undo handler (the redo) needs no
  group of its own: `undo()` opens one.
- **`GENERATE_INFOPLIST_FILE = YES` plus `INFOPLIST_FILE = Config/Info.plist` merges**: the
  built `Info.plist` carries the generated keys (bundle id, version, the iOS scene manifest)
  and the file's `UTExportedTypeDeclarations`. Keep the file outside the synchronized
  folder. The exported type resolves at runtime in the test host on the Mac and on both
  simulators (`UTType("com.lsvr.cinesched.project")` is non-nil, `preferredFilenameExtension`
  is `cinesched`), so the plist really is registered when the host launches.
- **The date formatter writes the machine's zone and locale.** `yyyy-MM-dd'T'HH:mm:ssZ` on
  a default `DateFormatter` produces `-0700` here and `+0000` on a UTC machine, and a
  non-Gregorian device calendar would write a different year. Left as is for byte-for-byte
  compatibility (ADR 0005), the test pins the shape only; worth fixing to `en_US_POSIX` +
  UTC before two devices with different locales share a file (M2 sync).
- **The fixtures mint fresh UUIDs on every access.** `PDFFixture.days` is a computed
  property, so a test comparing "the project" against itself must store the fixture once
  (`let project = ProjectCodecTests.project`), or two reads never compare equal.
- `-only-testing:"LSVR CineSchedTests/ProjectDocumentTests"` works at suite level without
  parentheses; the #5 note about needing them applies to individual test functions.

---

## 2026-09-16 — Breakdown and DOOD off AppKit: `boundingRect` is a point short of `draw(in:)`, TextKit drops lines by their top edge, `calibratedWhite` is a different gray, system colors follow the theme (#6)

The last two exporters, same method as #4 and #5 (dump every fixture PDF before and after,
rasterize, pixel-diff). Every fixture — the two migrated and the four already on the helper —
came out identical at 288 dpi. The measuring was done up front with scratch AppKit scripts
(`NSAttributedString` into a `CGContext` PDF, then reading the `Tm` operators back out of the
inflated content stream), which is much faster than fixing pixel diffs one at a time:

- **`NSAttributedString.boundingRect(with:options:)` measures a line as `round(ascent) +
  round(descent)` but `draw(in:)` advances `round(ascent) + ceil(descent)`.** They only agree
  where SF's descent rounds up; at 7, 9.5, 10, 11, 11.5 and 15pt the measurement is one
  point per line short of what is drawn (11pt: 13 vs 14; three 9.5pt lines with 1.71pt
  spacing measure 36.42 but occupy 39.42). `boundingRect` equals
  `NSLayoutManager.defaultLineHeight`; `size().height` equals the drawn height. The #4 note
  that `boundingRect` "reports the same whole numbers" was only true at the sizes it checked.
  The breakdown sheet's auto-scaling loop compares `boundingRect` against its cell, so
  `PDFFont.boundingLineHeight` / `PDFCanvas.boundingHeight(of:)` carry the smaller number for
  that comparison and `height(of:)` keeps the drawn one. `PDFCanvasTests` pins both tables.
- **TextKit lays out a line only if its top edge is above the rect's bottom, and clips only
  when the text overran.** Line *i* (0-based) is drawn iff `rect.height > i × (lineHeight +
  lineSpacing)`, whole and unclipped-at-the-line; if the text as a whole is taller than the
  rect a `re W n` clip to the rect is emitted (so the "#" of the breakdown sheet's
  "BREAKDOWN SHEET #" label, which wraps, shows as a sliver, #33). `draw(_:in:)` now does
  exactly this; it made no difference to the four earlier exporters' fixtures, which never
  overflow, and is what a wrapped name in a one-line DOOD cell needs.
- **`NSColor(calibratedWhite:alpha:)` is the legacy generic gray (gamma 1.8), not the
  gamma-2.2 gray that `NSColor(white:alpha:)`, `.gray`, `.lightGray` and `.darkGray` are.**
  The PDF carries a separate ICC profile for it and 0.35 renders 19/255 lighter than
  `gray(0.35)`. `CGColor.calibratedGray` keeps the space; `kCGColorSpaceGenericGray` is
  `nonswift` in the API notes, so it is looked up by name.
- **`NSColor.systemBlue` / `.systemYellow` / `.systemRed` resolve against the current
  appearance even when drawing into a PDF context**, so the DOOD's status cells came out a
  shade lighter when the app (or, in tests, the machine) was in dark mode. Pinned to the
  light values (sRGB 0/136/255, 255/204/0, 255/56/60); noted in the changelog. The baseline
  for the pixel diff was dumped with the old code wrapped in
  `NSAppearance(named: .aqua).performAsCurrentDrawingAppearance`.
- **`NSAttributedString.size().height` matches `PDFFont.lineHeight` at 7, 8 and 9pt** (9,
  10, 11), which is all the DOOD centres with; the ≥ 26pt mismatch from #5 still stands.
- **iOS's narrower SF fits "BREAKDOWN SHEET #" on one line**, so the wrap is pinned only
  under `PDFFixture.hasMacSystemFace` (moved to `PDFTestSupport` for every suite to use).
- **`Scene.scriptOrderKey` ties for unnumbered scenes** (events, banners, the untitled
  company-move line), and `sort` is not stable, so a test must not assume which of them
  comes last.
- **Test-target warnings from `#expect((x ?? "").contains(…))`**: the macro's rewrite
  complains about the `??`. Hoist the string into a `let` first.
- The scratch tools (a PDF→bitmap pixel differ on PDFKit + CoreGraphics, a PDF→PNG
  rasterizer, a text dumper) are a few dozen lines each; `learnings.md` #4 and #5 describe
  the same ones. There is still no ImageMagick on the machine.

## 2026-09-16 — Month calendar and call sheet off AppKit: named fonts get a synthetic gap, `draw(at:)` is a line box, emoji change nothing (#5)

Same method as #4 (dump the fixture PDFs before and after, rasterize, pixel-diff — the
tools were a scratch Swift CLI on PDFKit + CoreGraphics, no ImageMagick on the machine).
Everything came out identical except the known ellipsis lines, but a few things had to be
measured first, all with a scratch AppKit script driving `NSLayoutManager` and reading the
`Tm` operators back out of the PDF stream:

- **Non-system faces get a synthetic leading in TextKit.** SF follows the #4 rule
  (baseline `round(ascent)`, line `+ ceil(descent)`), but Helvetica, Times and Courier, which
  report zero leading, are laid out with `round(0.2 × size)` added *above* the ascent and
  `round(descent)` below: Helvetica-Oblique 8.5pt is an 11pt line with the baseline 9pt
  down, where the SF rule would say 9 and 7. It fits every size 6–30 for those three faces;
  faces that carry their own leading (Arial, Helvetica Neue) follow yet another rule that is
  not modelled because nothing uses them. `PDFFont.named` encodes the gap; `PDFCanvasTests`
  pins the numbers. The one Helvetica line in the app (the call sheet quote) sits exactly
  where it did. (#5 asked for "font descriptor traits" in place of the `NSFontManager`
  lookups; that is what the schedule line gets, but the quote was never the system italic,
  so it keeps its Helvetica by name — traits would have changed its face.)
- **`NSAttributedString.draw(at:)` is `draw(in:)` with a one-line-tall rect.** The point is
  the bottom-left of the line box, so the baseline lands `lineHeight - baselineOffset`
  (the rounded descent) above it — not at the point. `PDFCanvas.draw(_:lineOrigin:…)`.
- **Emoji do not make a TextKit line taller.** `size().height` for "📍 HOLLYWOOD" equals
  the plain line's at every size tried (the fallback face is used for the glyph, not for the
  line metrics), so the old `PDFExporter` comment that pills had to measure their own line
  height "because emoji sit taller" was wrong; `PDFFont.lineHeight` is the height.
- **`NSParagraphStyle.lineSpacing` goes between lines only**, never after the last (two
  8.5pt lines with 3pt spacing measure 23, not 26), and `.usesFontLeading` changes nothing
  for SF (leading 0). `draw(in:lineSpacing:)` / `height(of:lineSpacing:)`.
- **`NSFont.systemFont(ofSize:weight: .semibold)` is the system face with CoreText's
  weight trait 0.3** (`.SFNS-Semibold`); `CTFontCreateCopyWithAttributes` on the UI font keeps
  its tracking, and the pixel diff on the breakdown headings is clean.
- **`NSColor(red:green:blue:alpha:)` is sRGB; `NSColor.gray` / `.lightGray` / `.darkGray`
  are calibrated whites 1/2, 2/3, 1/3.** `CGColor.srgb` and the `pdf*Gray` statics.
- **`PDFExporter.generatePDF` (File ▸ Export Schedule PDF) rides along** in the same file
  and was diffed too: identical except its truncated titles and a 1/255 shade on the grid
  lines (one path stroked once vs. one stroke per line).
- **`NSAttributedString.size()` disagrees with `NSLayoutManager.defaultLineHeight(for:)` for
  SF** at several sizes (11pt: 14 vs 13; 26pt: 30 vs 30 but the #4 rule says 31). The
  exporters only ever place a single 26pt line by its baseline, so the mismatch at ≥ 26pt is
  harmless today, but `height(of:)` at those sizes is not verified against TextKit.
- **The call sheet already loses everything after its first page break** (#32): each
  section keeps a local `var y` that `ensureRoom`'s page reset never reaches. Reproduced
  faithfully here (the page count is pinned by a test); fix it separately.
- **`-only-testing:` with a Swift Testing function needs the parentheses**
  (`Suite/test()`); without them nothing runs and xcodebuild still reports success.

## 2026-09-16 — Moving two exporters off AppKit: TextKit's layout is reproducible, its truncation is not (#4)

`PDFCanvas` replaces `NSAttributedString.draw(in:)` with CoreText. What it took to keep the
strip schedule pixel-identical, measured by dumping the fixture PDFs before and after
(`SchedulePDFExporterTests` + `TEST_RUNNER_CINESCHED_PDF_DUMP_DIR`, decompressing the content
streams and rasterizing both for a pixel diff):

- **TextKit rounds line metrics; CoreText does not.** `draw(in:)` puts the first baseline
  `round(ascent)` below the top of the rect and advances `round(ascent) + ceil(descent) +
  ceil(leading)` per line (SF 18pt: 17 + 4 = 21, not 21.2; 11pt: 11 + 3 = 14, not 12.95;
  SF's leading is 0). `boundingRect` reports
  the same whole numbers. `PDFFont.baselineOffset` / `lineHeight` encode that rule and
  `PDFCanvasTests` pins the measured table, so nothing moved by a fraction of a point.
- **The system font is the same font.** `CTFontCreateUIFontForLanguage(.system / .emphasizedSystem)`
  is exactly `NSFont.systemFont` / `boldSystemFont`: same glyphs, same metrics, and CoreText
  applies SF's optical tracking (the `Tc` operator in the PDF) on its own, so plain lines came
  out byte-for-byte equal.
- **Colors convert exactly.** `Color.resolve(in: EnvironmentValues()).cgColor` gives the same
  extended-sRGB components as `NSColor(Color)`, and `CGColor(genericGrayGamma2_2Gray:)` is the
  space `NSColor(white:alpha:)` used.
- **TextKit draws truncated lines tighter than everything else.** A line it cut with "…" was
  tracked about 13/1000 em tighter than the untruncated line above it (the PDF shows `Tc 0.0013`
  where its neighbours have `0.0152`), and the ellipsis was appended un-kerned. Nothing in
  CoreText reproduces that (`kCTTrackingAttributeName: 0` and `kCTKernAttributeName: 0` both
  give the normal width), and it looks like a quirk rather than a design, so `PDFCanvas` does
  not try: truncated lines keep their neighbours' tracking, which means a strip-schedule title
  may now end one character before the ellipsis where it used to squeeze one more in.
  Deliberate; noted in the changelog. `CTLineCreateTruncatedLine` (what the shooting schedule
  used directly) was also rejected because it measures the prefix and the token separately and
  so gives up a character early; the helper binary-searches the longest prefix whose width
  *with* the ellipsis fits, so on the shooting schedule the change runs the other way — a
  truncated title now keeps one more character when it fits, and the ellipsis is kerned to it.
- **iOS has a different SF.** The same point sizes give different ascents and widths on the
  simulator (18pt line height 22, not 21; the wrap fixture takes two lines, not three), so the
  Mac-measured tables in `PDFCanvasTests` are `.enabled(if:)` the Mac face is present, and
  everything else asserts the rule, not the numbers. iOS output is therefore not pixel-equal
  to the Mac's, which no ticket asked for.
- **Dumping files from tests on the Mac needs `ENABLE_APP_SANDBOX=NO`**, and the env var must
  be a real environment variable (`TEST_RUNNER_X=… xcodebuild …`), not a build-setting
  argument after `xcodebuild`. The test host is the sandboxed app, which cannot write outside
  its container, and the terminal cannot read inside it (TCC), so the two never meet otherwise.

## 2026-09-16 — Getting the target to build for iOS was mostly a plist collision and AppKit hunting (#3)

Three things that surprised, in the order they bit:

- **A stray `Info.plist` in the synchronized folder breaks the iOS build, not the Mac one.**
  `ProcessInfoPlistFile … Multiple commands produce …/LSVR CineSched.app/Info.plist`. The
  hand-written plist was documented as unused, but a synchronized folder copies it into the
  bundle as a resource; on the Mac that lands in `Contents/Resources/` and nobody notices,
  in a flat iOS bundle it is the same path as the generated plist. Deleted it; do not add one.
- **`URL.BookmarkCreationOptions.withSecurityScope` is macOS-only.** iOS bookmarks are
  implicitly security-scoped, so the option simply does not exist there. `FilePanels` owns
  the options now; grep for `withSecurityScope` should only hit that file.
- **The compiler stops at the first missing module, one file at a time.** `import AppKit`
  in one file hides every other error in the build, so "fix, rebuild, repeat" is slow.
  `grep -ln "^import AppKit"` plus a grep for `NSEvent|NSColor|NSSavePanel|NSOpenPanel|
  \.checkbox|\.radioGroup|borderlessButton|withSecurityScope` up front found everything
  the compiler later would have, in one pass. After that the whole UI compiled unchanged on
  iOS and visionOS: `.help`, `.onHover`, `.keyboardShortcut`, `.commands`, `NSItemProvider`
  and `DropDelegate` are all cross-platform.
- **Simulator names drift from the spec.** #3 asked for "iPhone 17 Pro" and "iPad Pro
  13-inch (M4)"; the installed 27.0 runtime has iPhone 17 and iPad Pro 13-inch (M5).
  Check `xcrun simctl list devices available` before copying a destination string. Also,
  `xcodebuild test` on a simulator runs in a *clone* and reboots the original device, so a
  `simctl launch` right after a test run can hit a device that is still booting (black
  screen with an Apple logo in the screenshot); `simctl bootstatus <device> -b` first.

## 2026-09-16 — Moving to the release Xcode 27 SDK at a 27.0 floor was a one-warning affair (#2)

The spec for the 27 baseline (#2) expected source fixes for "the state property wrapper
became a macro; the view builders were unified". Neither surfaced: the whole app compiles
unchanged against the 27.0 SDKs (Xcode 27.0, 27A266a). The *only* thing the raised floor
exposed was `NSItemProvider.loadItem(forTypeIdentifier:options:completionHandler:)`, deprecated
in macOS 27.0, at the two `DropDelegate.performDrop` sites in `CalendarView.swift`. Fixed by
loading with `loadObject(ofClass: NSString.self)`, which `ContentView`'s Boneyard drop already
used; every drag payload in the app is built with `NSItemProvider(object: … as NSString)`, so
the string round-trips the same way. Warning count: the release Xcode 27 gives 11 app-target
warnings at the old 26.5 floor (the "~20" `CLAUDE.md` used to record was the beta compiler's
count), and still 11 at 27.0 once those two drop sites were fixed.
Rule of thumb: when raising the deployment floor, diff the sorted `: warning:` lines of a clean
build before and after — deprecations gated on the *new* floor are the only class of warning a
floor bump can add, and they hide inside an otherwise green build.

## 2026-09-16 — The 27 beta is gone; build with the release `/Applications/Xcode.app`

Supersedes the 2026-09-02 entry below. `/Applications/Xcode-beta.app` no longer exists on the
dev machine; the shipped Xcode 27.0 lives at `/Applications/Xcode.app`. `xcode-select -p` now
points at `/Library/Developer/CommandLineTools`, so a bare `xcodebuild` errors with
"requires Xcode, but active developer directory … is a command line tools instance". Keep
passing `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command (the scripts in
`scripts/` default to it). Do not change `xcode-select`.

## 2026-09-09 — `xcodebuild test` fails with ld EPERM in the default DerivedData; use a fresh `-derivedDataPath`

Running the test suite from an agent shell died linking `LSVR CineSchedUITests-Runner.app`:
`ld: open() failed, errno=1 (Operation not permitted)` writing into the existing runner
bundle under `~/Library/Developer/Xcode/DerivedData`. Even `touch` inside that .app fails
for the owner — macOS App Management (TCC) protects signed app bundles from processes
without that permission, and disabling the shell sandbox doesn't help. Workaround: pass
`-derivedDataPath <scratch dir>` so everything builds fresh in an unprotected location.
Also: `-only-testing:"LSVR CineSchedTests"` still *builds* the UITests target, so the
workaround is needed regardless of test selection. Plain `build` is unaffected.

## 2026-09-09 — Spanish strings leak into English PDFs; exporters are full of legacy `isSpanish` ternaries

The month breakdown page printed "Esc 36:" and "págs" in an English export: two strings in
`PDFExporter.drawMonthBreakdownPage` were hardcoded Spanish with no `isSpanish` guard, left over
from when the app was developed Spanish-first. The exporters still mostly localize via inline
`isSpanish ? … : …` ternaries rather than `L()`. When touching exporter text, check the string is
actually guarded (grep for `Esc`, `págs`, `DÍA`, etc.), and per CLAUDE.md fix it with `L("…")`
(adding a table entry in `Localization.swift`), not another ternary.

## 2026-09-02 — `updateShootDays` rebuilds every `ShootDay`; anything per-day must be carried across explicitly

Changing the production range regenerates the whole `shootDays` list in
`ContentView.updateShootDays`. Until day types landed it built each day as
`ShootDay(date:scenes:)`, which silently threw away every call sheet and every blackout flag
on any start/end date change. Scenes and calendar events were the only things it preserved
because they were the only things anyone had noticed going missing. Rule: when adding a field
to `ShootDay`, decide whether it follows the shoot (shift mode slides it; call sheet, day type,
day note) or the date (anchored; calendar events only), add it to the bookkeeping in that
function, and add it to both `handleDayRearrange` swaps (calendar and Stripboard).
`DayTypeTests` covers the model; the regeneration itself is untested because it lives on
`ContentView` state.

## 2026-09-02 — A `Picker` inside a context menu is the cheapest "radio submenu"

SwiftUI renders a `Picker` placed directly in `.contextMenu { }` as a titled submenu with a
checkmark on the selected tag, so a "Set Day Type ▸" menu needs no manual checkmark
bookkeeping. It logs a warning when the selection matches no tag, so the variant that acts on
a whole weekday (where days may disagree) is a plain `Menu` of `Button`s instead. See
`dayTypePicker(_:current:onSelect:)` in `CalendarView.swift`.

## 2026-09-02 — `@ViewBuilder` bodies reject local `var` mutation

Building up a `[String]` with `var details = []; if … { details.append(…) }` inside a
`@ViewBuilder` function fails with the unhelpful "type '()' cannot conform to 'View'" on the
`append` lines: statements inside a result builder must produce views. Move the mutation into
a plain helper (`gapDetails(_:)` in `StripboardView.swift`) and bind the result with `let`.

## 2026-09-02 — Stripboard folds empty days into gap rows; the row list is a pure function

`stripboardRows(for:showAllDays:expandedDayIDs:)` in `StripboardRows.swift` decides what the
board draws. A day is "empty" (and folds into a gap) only when it has no scenes, no calendar
events, a plain shoot day type, and no note; see `stripboardDayIsEmpty`. Event-only and typed
days used to be hidden or folded, which made a travel day impossible to see or drag on the
board. Calendar events are drawn as a chip row above the strips and are deliberately kept out
of `computeDayTimeline`: an event's `customStartTime` ("10:00 AM") would otherwise reset the
call-time cascade for every strip after it. Expansion is tracked per day id, not per gap, so a
gap that splits keeps both halves open. `scrollToDate` into a collapsed gap opens it and
scrolls on the next run loop turn, because the target row doesn't exist until the state
change renders.

---

## 2026-09-02 — View preferences live in `defaults` under `com.lsvr.LSVR-CineSched`

The app's bundle ID is `com.lsvr.LSVR-CineSched` (not anything with "lightsailvr"). App-wide
view settings such as `CineSchedViewMode`, `CineSchedShowCastRow`, the scene color overrides,
and the Stripboard field selection (`CineSchedStripboardFields`, a comma-joined list of
`StripboardField` raw values) are plain `@AppStorage`/`UserDefaults` keys there, so you can
seed a state for manual testing with `defaults write com.lsvr.LSVR-CineSched <key> <value>`
before launching. They are deliberately not in the project file. Also: a copy of the app
launched from Xcode (`-NSDocumentRevisionsDebugMode YES` in its argv) keeps running when you
`open` the DerivedData build, so check `pgrep -fl "LSVR CineSched"` before assuming a fresh
launch picked up your changes.

## 2026-09-02 — Build with the Xcode beta, not the release Xcode *(superseded 2026-09-16)*

Historical: until Xcode 27 shipped, `xcode-select -p` pointed at the release Xcode (26.5) and
this project had to be built with `/Applications/Xcode-beta.app` (27.0 beta) via
`DEVELOPER_DIR`. The beta is gone; see the 2026-09-16 entry above for the current command.
The durable part still holds: never change the system-wide `xcode-select`, pass
`DEVELOPER_DIR` per invocation.

## 2026-09-02 — The Xcode target is a synchronized folder, so *everything* in `LSVR CineSched/` is in the target

The project uses `PBXFileSystemSynchronizedRootGroup`: there is no per-file membership list in
`project.pbxproj`. Any file dropped into `LSVR CineSched/` is automatically compiled (if `.swift`)
or copied into the app bundle as a resource (anything else). Two consequences:

- New Swift files need no project-file edits. Just create them in the folder.
- Non-source files in that folder (README, CHANGELOG, `1024.png`, the old `*.app.zip` bundles)
  get copied into the built `.app`. Keep large or unrelated files out of that folder.

## 2026-09-02 — `Info.plist` in the source folder is not the one the target uses *(superseded 2026-09-16)*

Historical: the target has `GENERATE_INFOPLIST_FILE = YES` and no `INFOPLIST_FILE` setting, so
Xcode synthesizes its own Info.plist and the hand-written `LSVR CineSched/Info.plist` was a plain
resource, not merged. That file is gone (see the 2026-09-16 entry on #3: it collided with the
generated plist in the flat iOS bundle). If document types need to take effect, use
`INFOPLIST_KEY_*` build settings; do not reintroduce a plist in the source folder.

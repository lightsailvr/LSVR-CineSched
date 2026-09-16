# Learnings

A running log of non-obvious things learned while building CineSched. Add an entry whenever
something cost real time, surprised you, or would surprise the next person. Newest first.

Format: date, one-line title, then what happened / why / what to do instead. Keep entries short.
If a learning becomes a rule for the whole codebase, promote it into `CLAUDE.md` or an ADR in
`docs/adr/` and leave a pointer here.

---

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

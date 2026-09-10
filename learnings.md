# Learnings

A running log of non-obvious things learned while building CineSched. Add an entry whenever
something cost real time, surprised you, or would surprise the next person. Newest first.

Format: date, one-line title, then what happened / why / what to do instead. Keep entries short.
If a learning becomes a rule for the whole codebase, promote it into `CLAUDE.md` or an ADR in
`docs/adr/` and leave a pointer here.

---

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

## 2026-09-02 — Build with the Xcode beta, not the release Xcode

`xcode-select -p` on the dev machine points at the release Xcode (26.5), but this project must be
built with `/Applications/Xcode-beta.app` (27.0 beta). From the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=macOS' build
```

Don't change the system-wide `xcode-select` setting; use `DEVELOPER_DIR` per invocation.

## 2026-09-02 — The Xcode target is a synchronized folder, so *everything* in `LSVR CineSched/` is in the target

The project uses `PBXFileSystemSynchronizedRootGroup`: there is no per-file membership list in
`project.pbxproj`. Any file dropped into `LSVR CineSched/` is automatically compiled (if `.swift`)
or copied into the app bundle as a resource (anything else). Two consequences:

- New Swift files need no project-file edits. Just create them in the folder.
- Non-source files in that folder (README, CHANGELOG, `1024.png`, the old `*.app.zip` bundles)
  get copied into the built `.app`. Keep large or unrelated files out of that folder.

## 2026-09-02 — `Info.plist` in the source folder is not the one the target uses

The target has `GENERATE_INFOPLIST_FILE = YES` and no `INFOPLIST_FILE` setting, so Xcode
synthesizes its own Info.plist. The hand-written `LSVR CineSched/Info.plist` (which declares the
`.json` document type and version 4.5.1) is treated as a plain resource, not merged. If document
types or the version string need to take effect, either set `INFOPLIST_FILE` to point at it or
move the keys into `INFOPLIST_KEY_*` build settings.

# Learnings

A running log of non-obvious things learned while building CineSched. Add an entry whenever
something cost real time, surprised you, or would surprise the next person. Newest first.

Format: date, one-line title, then what happened / why / what to do instead. Keep entries short.
If a learning becomes a rule for the whole codebase, promote it into `CLAUDE.md` or an ADR in
`docs/adr/` and leave a pointer here.

---

## 2026-09-02 — `@ViewBuilder` bodies reject local `var` mutation

Building up a `[String]` with `var details = []; if … { details.append(…) }` inside a
`@ViewBuilder` function fails with the unhelpful "type '()' cannot conform to 'View'" on the
`append` lines: statements inside a result builder must produce views. Move the mutation into
a plain helper (`gapDetails(_:)` in `StripboardView.swift`) and bind the result with `let`.

## 2026-09-02 — Stripboard folds empty days into gap rows; the row list is a pure function

`stripboardRows(for:showAllDays:expandedDayIDs:)` in `StripboardRows.swift` decides what the
board draws. A day is "empty" when it has no non-calendar-event scenes, so calendar-only days
(which the old board hid entirely) now count toward a gap and appear as empty sections when the
gap is opened or "All days" is on. Expansion is tracked per day id, not per gap, so a gap that
splits keeps both halves open. `scrollToDate` into a collapsed gap opens it and scrolls on the
next run loop turn, because the target row doesn't exist until the state change renders.

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

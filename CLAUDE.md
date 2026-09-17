# CLAUDE.md

CineSched: a SwiftUI app for film production scheduling. The Mac app is the shipping product;
iOS, iPadOS and visionOS build from the same target and currently launch to a placeholder (#1).
Read `CONTEXT.md` for the glossary and system map before touching the code, and `learnings.md`
for things that have already cost time.

## Build and run

Build with the release **Xcode 27** (`/Applications/Xcode.app`, 27.0 build 27A266a); the 27 beta
is no longer installed or needed. `xcode-select` on this machine points at the Command Line
Tools, so a bare `xcodebuild` fails. Never change the system-wide `xcode-select`; set
`DEVELOPER_DIR` per command.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=macOS' build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=macOS' -derivedDataPath "$(mktemp -d)" test
```

(`test` needs the fresh `-derivedDataPath`; see `learnings.md` for the App Management EPERM it
avoids.)

Add `CODE_SIGNING_ALLOWED=NO` for a headless build that should not touch signing.

**iOS and visionOS** build and test against the simulators (the installed 27.0 runtimes have
iPhone 17, iPad Pro 13-inch (M5) and Apple Vision Pro; `xcrun simctl list devices available`
for the current names). Everything, including every PDF exporter and its tests
(`PDFCanvasTests`, `SchedulePDFExporterTests`, `MonthPDFExporterTests`,
`CallSheetPDFExporterTests`, `BreakdownPDFExporterTests`, `DaysOutOfDaysPDFExporterTests`),
must pass there.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=visionOS Simulator,name=Apple Vision Pro' CODE_SIGNING_ALLOWED=NO build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$(mktemp -d)" -only-testing:"LSVR CineSchedTests" CODE_SIGNING_ALLOWED=NO test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -derivedDataPath "$(mktemp -d)" -only-testing:"LSVR CineSchedTests" CODE_SIGNING_ALLOWED=NO test
```

To see it run: `xcrun simctl install <device> <DerivedData>/Build/Products/Debug-iphonesimulator/LSVR\ CineSched.app`,
then `xcrun simctl launch <device> com.lsvr.LSVR-CineSched` (`Debug-xrsimulator` for Vision Pro).

**Releases**: `scripts/release.sh <version>` cuts a release — bumps the versions in build
settings, rolls the changelog's `[Unreleased]` into a dated section, builds Release, installs
to `/Applications`, commits, tags `v<version>`, pushes, and publishes a GitHub Release with
the zipped app. `scripts/install.sh` just builds and refreshes `/Applications` (no version,
no tag). Version and build number live only in build settings; keep the changelog's newest
section in sync with `MARKETING_VERSION`. A clean build
on 2026-09-16 with Xcode 27.0 (27A266a) at the 27.0 floor succeeds with exactly 7 warnings in the
app target (all deprecated one-argument `onChange`); do not add new ones. (The 4 main-actor-isolated
`Codable` warnings went with #7: the model's `Codable` conformances are `nonisolated`.) The test
targets add 5 more of the same kinds.

Project facts: single scheme `LSVR CineSched`; Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency on; deployment target
27.0 on macOS, iOS and visionOS (one target builds all three; only the Mac ships today);
sandboxed with user-selected file read/write; no SPM packages or other dependencies.

The Xcode target is a **synchronized folder group**. Any file placed in `LSVR CineSched/` is
automatically compiled (`.swift`) or bundled as a resource (everything else). No pbxproj edits are
needed to add a source file, and non-source files should not be put in that folder.

## Where things are

All Swift sources are flat in `LSVR CineSched/`, one responsibility per file (the partial
`Config/Info.plist` is the one build input outside it, see Working agreements):

- `CineSchedApp.swift`: `@main`; on the Mac a `DocumentGroup` (one window per `ProjectDocument`)
  and the menus, which act on the key window through `@FocusedValue(\.projectCommands)`.
- `ProjectCommands.swift`: the closure slots (and View-menu bindings) a `ContentView` publishes
  for those menus. `WindowPreference.swift`: `@WindowPreference`, per-window view state (Calendar
  vs Stripboard, cast row, times vs pages, all days, grid vs list) seeded from and written back to
  the last-used value; app-wide preferences (Dark Mode, Theme, Stripboard fields) stay `@AppStorage`.
- `ContentView.swift`: the Mac editor for one document (`ContentView(document:)`). It reads
  `document.project` and writes only through `edit(_:_:)` or the bindings built on it. There is
  no view model; UI-only state (range-picker dates, selection, sheets) stays `@State`.
- `ContentView+ScriptImport.swift`: File ▸ Import Script… into the Boneyard.
  `ContentView+PDFExports.swift`: every PDF export call site and its save panel.
- `ProjectCodec.swift`: the one encoder/decoder for project files (pretty JSON, ISO dates, legacy
  shapes). Every save and load path uses it; nothing else constructs a `JSONEncoder` for a project.
- `ProjectDocument.swift`: the project document (ADR 0004) on the 27 `Document` protocol, its URL
  reader/writer, the `perform` undo funnel, `ProjectData.newProject` (the File ▸ New template) and
  `UTType.cineschedProject` (ADR 0005). Project open, save, autosave, Open Recent, Duplicate,
  Rename, Move To and Revert To are the document infrastructure's; nothing in the app implements
  them. A legacy `.json` is never edited in place: `LegacyProjectHandoff` (a Mac seam) moves its
  contents to an untitled document and the writer refuses `.json` destinations, because the
  infrastructure autosaves an opened file within seconds and ignores the readable/writable split.
- `Models.swift`: all value types. `Scene` doubles as banner, auto-meal, and calendar event via flags.
- `DerivedScheduleState.swift`: everything `ContentView` shows that is computed from the whole
  project (sorted Boneyard, conflict sets, duplicate numbers, lock drift), the `BoneyardSort`
  enum, and the cache that computes it once per `ProjectDocument.changeCount`. Add new
  whole-project derivations here, not as `@State` recomputed in an `onChange`.
- `ProductionRange.swift`: `ProjectData.updateProductionRange`, the range regeneration (merge or
  shift) that Update Calendar applies as one edit; pure, tested in `ProductionRangeTests`.
- `CalendarView.swift`, `StripboardView.swift`: the two schedule views.
- `*Sheet.swift`: modal editors. `*Exporter.swift`: PDF generators; every call site is in
  `ContentView+PDFExports.swift`. `PDFCanvas.swift` is the shared drawing helper (CoreGraphics +
  CoreText, no AppKit); all six exporters (`StripboardPDFExporter`, `ShootingSchedulePDFExporter`,
  `PDFExporter` (the month calendar), `CallSheetExporter`, `BreakdownExporter`,
  `DaysOutOfDaysExporter`) draw on it and build everywhere (its header comment is the recipe
  for writing one). `Fountain*`, `FinalDraftParser`, `HighlandArchiveReader`: importers.
- Platform seams (ADR 0003): `FilePanels`, `SelectAllTextField`, `WindowAccessor`, `ModifierKeys`,
  `PlatformControlStyles`, `PlatformColors`, `PlatformPlaceholderView`, `LegacyProjectHandoff`,
  plus the root/tabbing choice in `CineSchedApp`. These are the only files allowed to contain
  `#if os(...)`.

## Conventions

- **Adding a menu command touches three places**: a closure slot in `ProjectCommands`, the `Button`
  in `CineSchedApp.swift` (calling `commands?.slot()` and `.disabled(commands == nil)`), and the
  slot's assignment in `ContentView.projectCommands`. Do not add `Notification.Name`s for menus:
  a notification reaches every open window. A View-menu toggle for window state is a `Binding`
  slot bound to a `@WindowPreference`, not an `@AppStorage`, or it flips every open project.
- **Adding a sheet**: add a case to `ContentView.ActiveSheet` and to the `switch` in `applySheets`.
  Sheets take `@Binding var isPresented` and an `onSave` closure; editors copy the model into local
  `@State` on appear and write back in an explicit save function.
- **Mutating schedule state from a child view**: call `onBeforeSceneChange()` first (opens the edit
  gesture), mutate through the binding, then `onSceneChanged()` (closes it). The binding's setter is
  what runs `perform`; the gesture only decides that several writes are one undo step. Inside
  `ContentView` itself, mutate with `edit("Action Name") { data in … }`, never by assigning to
  `document.project` (it is read-only from outside the document anyway).
- **Model changes**: every new `Codable` field gets a `CodingKeys` entry and a
  `decodeIfPresent(...) ?? default` line in the hand-written `init(from:)`. Old project files must
  still open. There is no schema version. Model `Codable` conformances are `nonisolated` (and so
  are their hand-written `init(from:)` / `encode(to:)`) because `ProjectCodec` runs off the main
  actor; a new model type follows suit, and a decoder must not touch main-actor state.
- **Mutating the project document**: only through `ProjectDocument.perform`, which registers the
  undo action the document infrastructure autosaves from. Pass one `EditGesture` token for every
  edit of a drag or typing burst so it undoes as one step. A `perform` whose edit changes nothing
  registers nothing, so an editor's Save may write its whole value back unconditionally.
- **Platform ownership of the document**: `DocumentGroup` is macOS-only for now (CineSchedApp is a
  seam file); the other platforms get their own document scenes in #12. `ContentView` compiles on
  every platform and must stay free of `#if os`.
- **Colors**: resolve scene colors only via `Scene.stripColor`. Exporters must not hardcode strip colors.
- **PDF drawing**: new or migrated exporters draw through `PDFCanvas` (`PDFFont`, `CGColor`
  helpers, `draw(_:in:)` / `draw(_:at:)`), never through `NSFont` / `NSColor` /
  `NSAttributedString.draw`. Do not add `#if os` to an exporter; migrate it instead.
- **Platform APIs**: no `#if os(...)` outside the seam files listed above, and no `AppKit`/`UIKit`
  import in the pure core (models, parsers, importers, scanners, formatting, row logic, palette
  settings) or the views. Need `NSEvent`, a panel, a Mac-only control style, a system color? Add
  to the matching seam and call it from the view. Color arithmetic uses `Color.Resolved`.
- **`ContentView.body`** is a chain of `applyX(_:)` helper functions to keep the type-checker fast.
  Add new modifiers inside one of those helpers, not inline.
- Use the two-argument `onChange(of:) { old, new in }` form. The one-argument form is deprecated.
- **View-body costs** (#34): a calendar or Stripboard redraw evaluates every day cell, every
  strip, every Boneyard row and every `.contextMenu` builder (SwiftUI evaluates those eagerly,
  not when the menu opens), so nothing drawn per day or per strip may build a table or a
  `DateFormatter`. `L()` is a lookup in a table built once; date strings go through
  `formattedDate(_:pattern:)`, which caches its formatters; whole-project derivations go in
  `DerivedScheduleState`. Anything a cell needs from the whole `shootDays` array (day numbers,
  a date index) is computed once per redraw, not per cell.
- Match the existing style: `// MARK: -` sections, vertically aligned assignment blocks, header
  comments that explain *why*. Many inline comments document past bugs; read them before simplifying.
- Localization is intentionally disabled (`LocalizationManager.setLanguage` is a no-op). Wrap new
  user-facing strings in `L("...")` anyway so re-enabling stays a one-line change; do not add
  Spanish ternaries.
- Zero dependencies is deliberate. Zip reading and PDF drawing are hand-rolled on system frameworks.

## Testing

The test targets are Xcode template stubs. `LSVR CineSchedTests` uses Swift Testing (`@Test`,
`#expect`). Pure, testable units: `FountainParser`, `FountainPaginator`, `FractionParser`,
`TimeParser`, `Formatting.swift` free functions, `ConflictScanner` (`ConflictScannerTests`),
`ScheduleLockScanner`, `ProjectData.updateProductionRange` (`ProductionRangeTests`),
`DerivedScheduleState` and its cache (`DerivedScheduleStateTests`),
`L(_:)` (`LocalizationTests`),
`DaysOutOfDaysExporter.buildRows`, `PDFCanvas`, `ProjectCodec` (`ProjectCodecTests`),
`ProjectDocument` with its reader, writer, type and undo funnel (`ProjectDocumentTests`, against a
real `UndoManager` with `groupsByEvent` off), and all six exporters (rendered from the shared
fixture in `PDFTestSupport.swift` and read back through PDFKit in `SchedulePDFExporterTests`,
`MonthPDFExporterTests`, `CallSheetPDFExporterTests`, `BreakdownPDFExporterTests` and
`DaysOutOfDaysPDFExporterTests`; set `CINESCHED_PDF_DUMP_DIR` to keep the PDFs for a visual
diff, see `PDFTestSupport`'s header). Prefer adding tests there over UI tests. The document
lifecycle itself (Open panel types, Finder association, autosave, the viewer role of `.json`)
has no unit seam; check it by running the app (learnings.md, 2026-09-16 #8 has a recipe that
works without screen access). Any change to
`PDFCanvas` gets the pixel comparison: dump every fixture before and after, rasterize and
diff (learnings.md, 2026-09-16 #6 has the recipe); expectations that depend on the Mac's SF
metrics or wrapping are guarded by `PDFFixture.hasMacSystemFace`.

## Working agreements

- Log anything non-obvious you learn in `learnings.md` (newest first). Promote durable rules here or to an ADR.
- Update `LSVR CineSched/CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- Keep the `.app.zip` bundles, `1024.png`, and other non-source files out of `LSVR CineSched/`; they get copied into the app.
- The `Info.plist` is generated from build settings (`GENERATE_INFOPLIST_FILE = YES`) and merged with the partial
  `Config/Info.plist`, which holds only keys that cannot be `INFOPLIST_KEY_` settings (today the exported
  `.cinesched` type, ADR 0005). Never put a plist in the source folder: it would be bundled as a resource and
  collide with the generated plist in the flat iOS bundle. Version and bundle identifier live in build settings.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `lightsailvr/LSVR-CineSched`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the root plus ADRs in `docs/adr/`. See `docs/agents/domain.md`.

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
on 2026-09-16 with Xcode 27.0 (27A266a) at the 27.0 floor succeeds with exactly 11 warnings in the
app target (7 deprecated one-argument `onChange`, 4 main-actor-isolated `Codable` conformances in
`ProjectStore.swift`); do not add new ones. The test targets add 5 more of the same kinds.

Project facts: single scheme `LSVR CineSched`; Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency on; deployment target
27.0 on macOS, iOS and visionOS (one target builds all three; only the Mac ships today);
sandboxed with user-selected file read/write; no SPM packages or other dependencies.

The Xcode target is a **synchronized folder group**. Any file placed in `LSVR CineSched/` is
automatically compiled (`.swift`) or bundled as a resource (everything else). No pbxproj edits are
needed to add a source file, and non-source files should not be put in that folder.

## Where things are

All sources are flat in `LSVR CineSched/`, one responsibility per file:

- `CineSchedApp.swift`: `@main`, menus. Menu items post `Notification.Name`s.
- `ContentView.swift`: root view that also owns all project state as `@State`. There is no view model.
- `ProjectStore.swift`: an `extension ContentView` with load/save/autosave/import and the PDF save panels.
- `RecentFilesStore.swift`: recent-file bookmarks and every `Notification.Name` used by menus.
- `Models.swift`: all value types. `Scene` doubles as banner, auto-meal, and calendar event via flags.
- `CalendarView.swift`, `StripboardView.swift`: the two schedule views.
- `*Sheet.swift`: modal editors. `*Exporter.swift`: PDF generators; every call site is in
  `ProjectStore+PDFExports.swift`. `PDFCanvas.swift` is the shared drawing helper (CoreGraphics +
  CoreText, no AppKit); all six exporters (`StripboardPDFExporter`, `ShootingSchedulePDFExporter`,
  `PDFExporter` (the month calendar), `CallSheetExporter`, `BreakdownExporter`,
  `DaysOutOfDaysExporter`) draw on it and build everywhere (its header comment is the recipe
  for writing one). `Fountain*`, `FinalDraftParser`, `HighlandArchiveReader`: importers.
- Platform seams (ADR 0003): `FilePanels`, `SelectAllTextField`, `WindowAccessor`, `ModifierKeys`,
  `PlatformControlStyles`, `PlatformColors`, `PlatformPlaceholderView`, plus the root/tabbing
  choice in `CineSchedApp`. These are the only files allowed to contain `#if os(...)`.

## Conventions

- **Adding a menu command touches three files**: the `Notification.Name` in `RecentFilesStore.swift`,
  the `Button` in `CineSchedApp.swift`, and an `.onReceive` in one of the `applyNotificationHandlers*`
  functions in `ContentView.swift`.
- **Adding a sheet**: add a case to `ContentView.ActiveSheet` and to the `switch` in `applySheets`.
  Sheets take `@Binding var isPresented` and an `onSave` closure; editors copy the model into local
  `@State` on appear and write back in an explicit save function.
- **Mutating schedule state from a child view**: call `onBeforeSceneChange()` first (undo snapshot),
  mutate through the binding, then `onSceneChanged()` (dirty flag + recompute). Skipping the first
  makes the edit non-undoable.
- **Model changes**: every new `Codable` field gets a `CodingKeys` entry and a
  `decodeIfPresent(...) ?? default` line in the hand-written `init(from:)`. Old project files must
  still open. There is no schema version.
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
- Match the existing style: `// MARK: -` sections, vertically aligned assignment blocks, header
  comments that explain *why*. Many inline comments document past bugs; read them before simplifying.
- Localization is intentionally disabled (`LocalizationManager.setLanguage` is a no-op). Wrap new
  user-facing strings in `L("...")` anyway so re-enabling stays a one-line change; do not add
  Spanish ternaries.
- Zero dependencies is deliberate. Zip reading and PDF drawing are hand-rolled on system frameworks.

## Testing

The test targets are Xcode template stubs. `LSVR CineSchedTests` uses Swift Testing (`@Test`,
`#expect`). Pure, testable units: `FountainParser`, `FountainPaginator`, `FractionParser`,
`TimeParser`, `Formatting.swift` free functions, `ConflictScanner`, `ScheduleLockScanner`,
`DaysOutOfDaysExporter.buildRows`, `PDFCanvas`, and all six exporters (rendered from the shared
fixture in `PDFTestSupport.swift` and read back through PDFKit in `SchedulePDFExporterTests`,
`MonthPDFExporterTests`, `CallSheetPDFExporterTests`, `BreakdownPDFExporterTests` and
`DaysOutOfDaysPDFExporterTests`; set `CINESCHED_PDF_DUMP_DIR` to keep the PDFs for a visual
diff, see `PDFTestSupport`'s header). Prefer adding tests there over UI tests. Any change to
`PDFCanvas` gets the pixel comparison: dump every fixture before and after, rasterize and
diff (learnings.md, 2026-09-16 #6 has the recipe); expectations that depend on the Mac's SF
metrics or wrapping are guarded by `PDFFixture.hasMacSystemFace`.

## Working agreements

- Log anything non-obvious you learn in `learnings.md` (newest first). Promote durable rules here or to an ADR.
- Update `LSVR CineSched/CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- Keep the `.app.zip` bundles, `1024.png`, and other non-source files out of `LSVR CineSched/`; they get copied into the app.
- There is no hand-written `Info.plist` (`GENERATE_INFOPLIST_FILE = YES`); do not add one to the source folder, it would be
  bundled as a resource and collide with the generated plist in the flat iOS bundle. Version and document-type settings live in build settings.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `lightsailvr/LSVR-CineSched`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the root plus ADRs in `docs/adr/`. See `docs/agents/domain.md`.

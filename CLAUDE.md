# CLAUDE.md

CineSched: a macOS SwiftUI app for film production scheduling. Read `CONTEXT.md` for the glossary
and system map before touching the code, and `learnings.md` for things that have already cost time.

## Build and run

Use the **Xcode beta** on this machine (`/Applications/Xcode-beta.app`); `xcode-select` points at
the release Xcode and that is not what this project is developed against. Never change the
system-wide `xcode-select`; set `DEVELOPER_DIR` per command.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=macOS' build
```

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme "LSVR CineSched" -destination 'platform=macOS' test
```

Add `CODE_SIGNING_ALLOWED=NO` for a headless build that should not touch signing. A clean build
on 2026-09-02 succeeds with ~20 warnings (deprecated one-argument `onChange`, and main-actor-isolated
`Codable` conformances in `ProjectStore.swift`); do not add new ones.

Project facts: single scheme `LSVR CineSched`; Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency on; deployment target
macOS 26.5; sandboxed with user-selected file read/write; no SPM packages or other dependencies.

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
- `*Sheet.swift`: modal editors. `*Exporter.swift`: PDF generators. `Fountain*`, `FinalDraftParser`, `HighlandArchiveReader`: importers.

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
`TimeParser`, `Formatting.swift` free functions, `ConflictScanner`, `ScheduleLockScanner`, and
`DaysOutOfDaysExporter.buildRows`. Prefer adding tests there over UI tests.

## Working agreements

- Log anything non-obvious you learn in `learnings.md` (newest first). Promote durable rules here or to an ADR.
- Update `LSVR CineSched/CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- Keep the `.app.zip` bundles, `1024.png`, and other non-source files out of `LSVR CineSched/`; they get copied into the app.
- The hand-written `LSVR CineSched/Info.plist` is not used by the target (`GENERATE_INFOPLIST_FILE = YES`). Version and document-type settings live in build settings.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `lightsailvr/LSVR-CineSched`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the root plus ADRs in `docs/adr/`. See `docs/agents/domain.md`.

# CineSched — Domain Context

CineSched is a SwiftUI app for scheduling film shoots: import a screenplay, break it into
scenes, drag scenes onto shoot days, track cast availability, and export industry-standard PDFs
(shooting schedule, stripboard, call sheets, breakdown sheets, Days Out of Days). The Mac app is
the product today; one target also builds iOS, iPadOS and visionOS, which open, create and
autosave projects from the CineSched folder in iCloud Drive through a minimal editor (#12)
while the port (#1) is in progress.

This file is the glossary and system map. Use these terms exactly in issues, code, and tests.
Architecture decisions live in `docs/adr/`. Hard-won surprises live in `learnings.md`.

## Lineage

Three layers, in order: Chris Tempel's original calendar scheduler; alucardGonza's fork (Stripboard,
month calendar, bilingual EN/ES, time cascade, vector PDFs, banners, calendar events); and this LSVR
version (Sunday-first weeks, custom scene colors, English-only, FDX dual-dialogue fix, drag/drop
fixes). Project files are compatible across all three for shared fields. See `LSVR CineSched/README.md`.

## Glossary

Film-production terms first, then app-specific ones.

| Term | Meaning in CineSched |
|---|---|
| **Scene** | One unit of the screenplay to be shot. Modelled by `Scene` in `Models.swift`. Has a scene number, slugline-style title (`INT. KITCHEN - NIGHT`), page length in **eighths**, estimated shoot time in minutes, cast (character names), a summary, and breakdown tags. |
| **Eighths** | Script length is measured in eighths of a page (industry standard). `Scene.duration` is an `Int` count of eighths, so `12` means 1 4/8 pages. `FractionParser` converts to and from strings like `1 7/8`. |
| **Slugline / scene heading** | The `INT./EXT. LOCATION - TIME` line that opens a scene. CineSched stores it as `Scene.title` and derives INT/EXT and time-of-day from it by regex. |
| **INT / EXT** | Interior or exterior. Derived from the title prefix; anything not starting with `EXT` is treated as interior. |
| **Time of day** | `DayNightType`: day, night, dawn, dusk, afternoon, or custom. Combined with INT/EXT it selects the strip color. |
| **Strip** | The colored horizontal bar representing one scene (or banner) on the calendar and the stripboard. Named after the paper strips on a physical production board. |
| **Strip color** | The industry color code (e.g. white = INT day, yellow = EXT day, blue = INT night, green = EXT night). Customizable per project through the **palette**; `Scene.stripColor(in:)` is the single resolver for every view and exporter. |
| **Palette** | The production's strip colors, `ScenePalette`: a hex per **color slot** (the ten INT/EXT × time-of-day cells plus Custom, `SceneColorSlot`), an optional field of the project file (`ProjectData.palette`, #11). Views read it from the `scenePalette` environment set at the editor's root; exporters take it with the project. Nil in every file from before #11, which resolves to the standard code (`ProjectData.resolvedPalette`) until the project adopts or edits one. |
| **Palette adoption** | A project without a palette takes the device's legacy color overrides (the pre-#11 `UserDefaults` keys, `SceneColorSettings.deviceOverrides`) as its own the moment it enters a `ProjectDocument`, new or from disk; a project with a palette ignores them, so it happens once. The adoption is not an undo step, so it reaches the file with the project's next edit. |
| **Stripboard** | The vertical strip-schedule view (`StripboardView`), the digital equivalent of a production board. Shows a time cascade per day. |
| **Boneyard** | The sidebar list of **unscheduled** scenes. Backed by `ProjectData.allScenes`. A scene is either in the Boneyard or on exactly one shoot day, never both. |
| **Shoot day** | One calendar date in the production, modelled by `ShootDay`: a date, an ordered list of scenes, an optional call sheet, a day type, and a day note. Every date in the production range has a `ShootDay`, even if empty. |
| **Production range** | The start and end dates of the shoot. Changing it regenerates the `ShootDay` list (`ProjectData.updateProductionRange`, a pure edit in `ProductionRange.swift`); scenes on removed days are returned to the Boneyard, everything else on them is kept on its date. |
| **Production day number** | "Day 1, Day 2, …" counting only days that have real scenes and are not blackouts. Computed by `productionDayNumbers(for:)` in `Formatting.swift`. |
| **Day type** | What a date is for: shoot (default), travel, scout, prep, rehearsal, weather hold, holiday, day off, or unavailable (`DayType`, stored in `ShootDay.dayType`). Only shoot days earn a production day number. Non-shoot days are tinted and labelled on the calendar, kept as full badged day rows on the Stripboard (never folded into a gap), and shaded in the DOOD. Scenes may still be placed on them but are flagged. Set or cleared from the day's right-click menu or the Day Detail sheet. Belongs to the shoot, not the date: it slides with the scenes in shift mode. Dragging the type band moves only the type and note; dragging the day handle swaps the whole day. |
| **Day note** | Free text on a `ShootDay` (`dayNote`), e.g. travel details or a hold reason. Shown under the day-type band in the calendar cell, in the Stripboard day header, and in the month PDF. |
| **Blackout day** | Legacy name for the `unavailable` day type. `ShootDay.isBlackout` is now a read-only alias, still written to project files so older builds keep seeing unavailable days. |
| **Shift mode** | When the start date moves, shift everything on the schedule by the same offset instead of leaving it on absolute dates: scenes, calendar events, call sheets, day types, and day notes. |
| **Banner** | A non-scene strip on a day: company move, meal break, or free-text notice. Still a `Scene` value with `isBanner == true` and a `BannerType`. |
| **Auto-meal** | A banner inserted automatically from call-sheet times (lunch, snack, wrap, etc.). `Scene.isAutoMeal` + `MealKind`. Synced by the stripboard. |
| **Calendar event** | A dated non-production item (travel day, rehearsal, scout). A `Scene` with `isCalendarEvent == true`. Never in the Boneyard, never counted as a scene, never in the time cascade. Slides with the shoot in shift mode and swaps with a day drag. Shown as chips on the calendar cell and above the strips on the Stripboard. |
| **Notice strip** | Umbrella term for banners, auto-meals, and calendar events. |
| **Time cascade** | On the stripboard, start and end times computed for each strip from the day's general call time and each strip's estimated duration. See `computeDayTimeline` in `StripboardView.swift`. |
| **Call sheet** | The per-day document telling cast and crew when and where to be. Modelled by `CallSheetData` on each `ShootDay`; edited in `CallSheetEditor`, exported by `CallSheetExporter`. |
| **General call** | The day's main call time on the call sheet. Drives the time cascade and the auto-meal strips. |
| **Cast member** | An actor and the character they play (`CastMember` in `ProductionInfo.castList`), plus unavailable date ranges. |
| **Character name join** | Scenes store cast as raw character-name strings. Every feature that needs the actor (call sheets, conflicts, DOOD, schedule lock) joins on a case-insensitive, trimmed name match against `castList`. Renaming a character must fan out everywhere. |
| **Crew member** | A role and name in the crew roster. `isDailyDefault` crew are pre-checked on every call sheet. |
| **Location roster** | Reusable real-world locations (`Location`) used for autocomplete on scenes and call sheets. Distinct from the slugline location inside the scene title. |
| **Production Setup** | The project-wide sheet for company, director, producer, 1st AD, cast roster, crew roster, and location roster (`ProductionInfo`). |
| **Conflict** | A scheduled scene whose cast includes a character whose actor is unavailable that date. Found by `ConflictScanner`; shown red on the calendar and in the Conflict Report. |
| **Schedule lock** | A snapshot of each character's working days (`ScheduleLock`). Later edits are not blocked; they are reported as drift by `ScheduleLockScanner` and a badge. |
| **Breakdown** | Per-scene tagging of extras, props, set dressing, wardrobe, makeup/hair, vehicles, special equipment, stunts, SFX, VFX, and notes. The Breakdown Browser steps through scenes in script order; `BreakdownExporter` prints one sheet per scene. |
| **Script order** | Scenes sorted by scene number with letter suffixes (12, 12A, 12B, 13). `Scene.scriptOrderKey`. |
| **DOOD (Days Out of Days)** | Industry grid of which cast members work which days, using codes SW (start work), W (work), WF (work finish), SWF (start-work-finish), H (hold), X (unavailable). `DaysOutOfDaysExporter`. |
| **Hold day** | A DOOD day where the production shoots but this actor does not. Optionally excluded via the "Include Hold" toggle. |
| **One-line schedule / shooting schedule** | The portrait PDF listing every day's strips with times and page counts. `ShootingSchedulePDFExporter`. Called "Plan de Rodaje" in the fork's Spanish-era code. |
| **Project file** | A `.cinesched` document (or a legacy `.json`) holding `ProjectData`: all scenes, shoot days, call sheets, production info, and schedule lock. Human-readable JSON, portable across lineages. |
| **Autosave** | The document infrastructure's autosave in place: an edit registered with the window's `UndoManager` is written to the project file by the system without a Save. (Formerly a `UserDefaults` blob written two seconds after the last change; gone since #8. The first launch of a document-model build recovers that blob once, `LegacyWorkingCopyRecovery` deciding whether it is already in the bookmarked file or needs an untitled window, #10.) |
| **Fountain / FDX / Highland** | Supported screenplay import formats: plain-text Fountain, Final Draft XML, and Highland's zipped TextBundle. |
| **Project document** | `ProjectDocument`: the one observable document every platform reads, writes and edits (ADR 0004). Its snapshot is `ProjectData`; its reader and writer go through `ProjectCodec`; every edit goes through `perform`, which registers the undo action. On the Mac, `DocumentGroup` makes one per window and `ContentView` edits it. |
| **Edit gesture** | An `EditGesture` token passed to every `perform` of one user gesture (a drag, a typing burst) so the gesture undoes as one step. |
| **Sync state** | What the indicator beside the project title says about this copy of an iCloud Drive project (#14): up to date, uploading, downloading, waiting for network, or conflict resolved (`SyncState`). Derived by `SyncState.derive` from the document URL's ubiquitous resource values (`UbiquitousResourceSnapshot`), the network and the conflict policy's flag; a file outside iCloud has none, and the indicator draws nothing. Conflict resolved is shown until the next edit. |
| **Conflict notice** | What the user sees after iCloud reported the same project edited on two devices (#15): the newest version was kept, and the notice names the device and time of the one that lost, with a **Restore other version** action. The decision is `ConflictPolicy.decide` over `ConflictVersion` values: newest wins (the current one on a tie), the rest are resolved, the loser is retained for the session; a single version yields no notice. Restore applies the retained snapshot through `perform`, so it is undoable. Lives in the sync indicator area; dismisses when acted on or after the next edit. |
| **Native file type** | `com.lsvr.cinesched.project`, extension `.cinesched`, conforming to JSON (ADR 0005). Same bytes as the `.json` the app has always written; declared in `Config/Info.plist` as the exported type and the only document type. |
| **Viewer role** | How a legacy `.json` opens on the Mac: it is a readable type there (`PlatformDocumentTypes`), so File ▸ Open lists it, but the document infrastructure would autosave it in place, so `LegacyProjectHandoff` moves its contents into an untitled document and closes the `.json` window. The first Save asks for a `.cinesched` destination; the `.json` is never modified (the writer refuses it). iOS and visionOS have no viewer role: `.json` is not readable there, the browser shows only `.cinesched`, and a legacy file is imported into a new project instead (#13). |
| **CineSched folder** | The iCloud Documents container `iCloud.com.lsvr.LSVR-CineSched`, public and named "CineSched", so iCloud Drive shows it as a folder on every device of the account (ADR 0006). Owned by the iOS, iPadOS and visionOS builds through their entitlement (`Config/CineSched-iOS.entitlements`); their launch screen and document browser start in it. The Mac has no iCloud entitlement, so it reaches the folder like any other (user-selected files); `CineSchedFolder` derives its on-disk path (`~/Library/Mobile Documents/iCloud~com~lsvr~LSVR-CineSched/Documents`) and `MacAppDelegate` points the Open and Save panels there once, the first launch on which it exists. It exists only after a device has saved a project in it. |
| **Launch screen** | The system's `DocumentGroupLaunchScene` on iOS and visionOS: the title, New Project (and, from #13, the import actions), the recents grid and the document browser. The Mac has no equivalent; it opens windows and, with iCloud Drive on, the Open panel. |
| **Minimal editor** | `MinimalProjectEditor`, what a project document shows on iOS, iPadOS and visionOS until milestones 3 and 4: the title as a field and the shoot days with their scene counts. Every write goes through `perform`; it exists to prove create, autosave, reopen and sync there. |
| **Project commands** | `ProjectCommands`: the closure slots (and View-menu bindings) a `ContentView` publishes as a focused scene value so the app-wide menus act on the frontmost window. |
| **Window preference** | `@WindowPreference`: view state that belongs to one window (Calendar vs Stripboard, cast row, times vs pages, all days, grid vs list), seeded from the last-used value and written back for the next window. Distinct from an app preference (Dark Mode, Theme, Stripboard fields), which applies everywhere at once. |
| **Pure core** | The platform-free part of the code: models, parsers and importers, scanners, formatting, row logic, palette settings. Compiles on every platform with no `#if os`. |
| **Platform seam** | A file that exists to hold a platform difference (`FilePanels`, `ModifierKeys`, `PlatformControlStyles`, …). The only places `#if os(...)` may appear; each starts with a comment saying why. See ADR 0003. |

## System shape

Everything lives flat in `LSVR CineSched/`. One responsibility per file; no third-party dependencies.

```
CineSchedApp.swift        @main; a DocumentGroup over ProjectDocument on every platform. On the Mac one window per
                          document plus the menus, which reach the key window through @FocusedValue(\.projectCommands);
                          on iOS and visionOS MinimalProjectEditor and the system's launch screen (#12).
MinimalProjectEditor.swift  The iOS/visionOS editor until M3/M4 (title field, shoot days with scene counts) and the
                          launch screen's background. Platform-free.
CineSchedFolder.swift     The iCloud container identifier, folder name and the Mac's derivation of its on-disk path (pure).
ProjectCommands.swift     The closure slots a ContentView publishes for those menus (focused scene value).
ContentView.swift         The Mac editor for one document: sidebar, toolbar, calendar and stripboard. Reads
                          `document.project`, writes only through `edit` / bindings built on `perform`.
  ContentView+ScriptImport.swift   File ▸ Import Script… (Final Draft, Fountain, Highland) into the Boneyard.
  ContentView+PDFExports.swift     every "generate then save" PDF action; the panel comes from FilePanels.
Models.swift              All value types (Scene, ShootDay, ProjectData, CallSheetData, ...). Hand-written Codable.
ProjectCodec.swift        The one project encoder/decoder (pretty JSON, ISO dates, legacy shapes).
ProjectDocument.swift     The project document (27 Document protocol), URL reader/writer, perform undo funnel,
                          UTType.cineschedProject, ProjectData.newProject (the File ▸ New template).
CalendarView.swift        Month grid / full-schedule scroll, drag & drop, day cells.
StripboardView.swift      Strip schedule with time cascade and auto-meal sync.
*Sheet.swift              Modal editors (Scene, CallSheet, ProductionSetup, Banner, CalendarEvent, SendToDay, ...).
PDFCanvas.swift           Shared PDF drawing helper: pages, rects, lines, TextKit-compatible text on CoreGraphics + CoreText.
*Exporter.swift           PDF generation, one file per document type (Stripboard, ShootingSchedule, the month
                          calendar (PDFExporter), CallSheet, Breakdown, DaysOutOfDays). All draw on PDFCanvas
                          and build everywhere.
Fountain*.swift, FinalDraftParser.swift, HighlandArchiveReader.swift   Script importers (pure Swift).
Parsers.swift, Formatting.swift                                        Eighths/time parsing, date/number formatting.
ConflictScanner.swift, ScheduleLockScanner.swift                       Pure analysis over shoot days.
ProductionRange.swift                                                  Regenerating the shoot days for a new range (merge or shift), as one edit.
DerivedScheduleState.swift                                             What the editor derives from the whole project (sorted Boneyard,
                                                                       conflict sets, lock drift) and the per-window cache that memoizes it.
Localization.swift, ThemeManager.swift                                Cross-cutting settings.
SceneColorSettings.swift                                              The color slots, the project palette, the legacy device-overrides reader and the palette environment key.
HoverTooltip.swift, LocationAutocompleteField.swift                            UI utilities.
FilePanels, SelectAllTextField, WindowAccessor, ModifierKeys, PlatformControlStyles,
PlatformColors, PlatformDocumentTypes, LegacyProjectHandoff, MacAppDelegate  Platform seams (ADR 0003).
LegacyWorkingCopyRecovery.swift                                       The first-launch decision over the pre-document builds' UserDefaults
                                                                       working copy and file bookmark (#10); MacAppDelegate acts on it.
SyncState.swift                                                       The sync state beside the title (#14): the five states and the pure
                                                                       mapping from a URL's ubiquitous resource values, the network and
                                                                       the conflict flag; nil outside iCloud. The platform scenes wire it.
ConflictPolicy.swift                                                  The conflict decision (#15): newest version wins, the rest resolved,
                                                                       the loser retained for the notice and Restore other version.
```

### Data flow

1. `DocumentGroup` (CineSchedApp) makes a `ProjectDocument` per window and reads the file into it
   through `ProjectDocumentReader`; `ContentView(document:)` is the window's content on the Mac,
   `MinimalProjectEditor(document:)` on iOS and visionOS, where the file lives in the CineSched
   folder (or wherever the document browser opened it in place) and the launch screen is the
   system's.
2. `ContentView` reads `document.project` and hands the calendar and Stripboard `Binding`s whose
   setters call `edit`, i.e. `document.perform(…, undoManager: environment's)`. The child views'
   callbacks are `onBeforeSceneChange` (open an `EditGesture` so the action's several binding
   writes are one undo step) and `onSceneChanged` (close it); the window's `UndoManager` also groups
   by run-loop event, so a single-event action undoes as one step either way.
3. `perform` registers the undo action with the window's `UndoManager`; that is what marks the
   document edited and what the system autosaves from (on iOS about a minute after the edit, on
   the Mac within seconds). A mutation that bypasses `perform` never saves and cannot be undone.
   Save, Save As (for a viewer-role `.json`), Duplicate, Rename, Move To, Revert To and Open
   Recent are the system's.
4. Derived state (the sorted Boneyard, conflict sets, duplicate scene numbers, schedule-lock
   drift) is `DerivedScheduleState`, a pure function of the project that `ContentView` reads
   through a cache keyed on `document.changeCount` and the Boneyard sort, so it is computed at
   most once per change and never stored as view state (#34). `changeCount` moves on every
   change to the project (edit, undo, redo, reload); the selection is pruned in
   `onChange(of: document.changeCount)`. `document.restoreCount` tells views with drag state
   that the model was replaced under them (undo, redo, reload only).
5. Menu commands reach the key window through `ProjectCommands`: `ContentView` publishes its
   closures with `.focusedSceneValue`, `CineSchedApp` reads `@FocusedValue` and disables the item
   when no project window is key.
6. Exporters are pure functions from model values to `Data` (PDF). The save-panel actions around them
   live in `ContentView+PDFExports.swift`; the panels themselves come from `FilePanels`.

### Invariants to preserve

- A scene ID appears in exactly one of `allScenes` or some `shootDays[i].scenes`. Nothing enforces
  this; `ProjectData.updateProductionRange` has an explicit safety net that returns orphans to
  the Boneyard.
- Every write to the project goes through `ProjectDocument.perform` (in `ContentView`, through
  `edit` or a binding built on it). Nothing writes `document.project` directly.
- Project files must stay backward compatible. Every new `Codable` field is optional in the decoder
  with a default (`decodeIfPresent ?? default`). There is no schema version number.
- `Scene.stripColor(in:)` is the only place strip colors are resolved, and the palette it is handed comes from the project (never from the device).
- Nothing is anchored to a date: scenes, calendar events, call sheets, day types, and day notes all slide together in shift mode, and a day drag swaps all of them between two dates. Script scenes that fall outside a new range go to the Boneyard; everything else is kept on its (shifted) date.
- `BannerType`'s decoder maps legacy Spanish raw values; keep it.

## Terms we avoid

- "Shot" for a scene; "block" for a strip; "task" or "event" for a scene. Use **scene** and **strip**.
- "Unscheduled list" or "backlog": use **Boneyard**.
- "Pages" as a float: durations are **eighths**.
- "Actor name" when you mean the character: scenes reference **characters**; the cast roster maps characters to actors.

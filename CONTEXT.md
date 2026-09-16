# CineSched — Domain Context

CineSched is a SwiftUI app for scheduling film shoots: import a screenplay, break it into
scenes, drag scenes onto shoot days, track cast availability, and export industry-standard PDFs
(shooting schedule, stripboard, call sheets, breakdown sheets, Days Out of Days). The Mac app is
the product today; one target also builds iOS, iPadOS and visionOS, which currently launch to a
placeholder while the port (#1) is in progress.

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
| **Strip color** | The industry color code (e.g. white = INT day, yellow = EXT day, blue = INT night, green = EXT night). User-overridable via `SceneColorSettings`; `Scene.stripColor` is the single source of truth for every view and exporter. |
| **Stripboard** | The vertical strip-schedule view (`StripboardView`), the digital equivalent of a production board. Shows a time cascade per day. |
| **Boneyard** | The sidebar list of **unscheduled** scenes. Backed by `ContentView.allScenes`. A scene is either in the Boneyard or on exactly one shoot day, never both. |
| **Shoot day** | One calendar date in the production, modelled by `ShootDay`: a date, an ordered list of scenes, an optional call sheet, a day type, and a day note. Every date in the production range has a `ShootDay`, even if empty. |
| **Production range** | The start and end dates of the shoot. Changing it regenerates the `ShootDay` list; scenes on removed days are returned to the Boneyard. |
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
| **Project file** | A `.json` document holding `ProjectData`: all scenes, shoot days, call sheets, production info, and schedule lock. Human-readable and portable. |
| **Autosave** | The whole project blob written to `UserDefaults` two seconds after the last change. Distinct from the manual Save to a `.json` file. |
| **Fountain / FDX / Highland** | Supported screenplay import formats: plain-text Fountain, Final Draft XML, and Highland's zipped TextBundle. |
| **Pure core** | The platform-free part of the code: models, parsers and importers, scanners, formatting, row logic, palette settings. Compiles on every platform with no `#if os`. |
| **Platform seam** | A file that exists to hold a platform difference (`FilePanels`, `ModifierKeys`, `PlatformControlStyles`, …). The only places `#if os(...)` may appear; each starts with a comment saying why. See ADR 0003. |

## System shape

Everything lives flat in `LSVR CineSched/`. One responsibility per file; no third-party dependencies.

```
CineSchedApp.swift        @main, WindowGroup, all menus. Menu items post NotificationCenter names.
ContentView.swift         Root view AND the owner of all project state (@State). No view model.
  ProjectStore.swift      extension ContentView: load/save/autosave/import/export panels.
  RecentFilesStore.swift  Recent-file bookmarks + every Notification.Name the menus use.
Models.swift              All value types (Scene, ShootDay, ProjectData, CallSheetData, ...). Hand-written Codable.
CalendarView.swift        Month grid / full-schedule scroll, drag & drop, day cells.
StripboardView.swift      Strip schedule with time cascade and auto-meal sync.
*Sheet.swift              Modal editors (Scene, CallSheet, ProductionSetup, Banner, CalendarEvent, SendToDay, ...).
*Exporter.swift           PDF generation via CoreGraphics + AppKit text. One file per document type. Mac-only for now;
  ProjectStore+PDFExports.swift   every "generate then save" action, gated with the exporters.
Fountain*.swift, FinalDraftParser.swift, HighlandArchiveReader.swift   Script importers (pure Swift).
Parsers.swift, Formatting.swift                                        Eighths/time parsing, date/number formatting.
ConflictScanner.swift, ScheduleLockScanner.swift                       Pure analysis over shoot days.
Localization.swift, ThemeManager.swift, SceneColorSettings.swift       Cross-cutting settings.
HoverTooltip.swift, LocationAutocompleteField.swift                            UI utilities.
FilePanels, SelectAllTextField, WindowAccessor, ModifierKeys, PlatformControlStyles,
PlatformColors, PlatformPlaceholderView                                        Platform seams (ADR 0003).
```

### Data flow

1. `ContentView` holds `allScenes` (Boneyard) and `shootDays` as `@State`, and hands them to child
   views as `@Binding` plus two callbacks: `onBeforeSceneChange` (capture an undo snapshot) and
   `onSceneChanged` (mark dirty, recompute conflicts and caches).
2. Menu commands cannot reach window state, so `CineSchedApp` posts a `Notification.Name` and
   `ContentView` observes it in one of three `applyNotificationHandlers*` functions.
3. Every mutation calls `markDirty()`; a debounced task autosaves to `UserDefaults` two seconds later.
   Manual Save writes the same JSON to the current file URL via a security-scoped bookmark.
4. Undo is a manual 30-deep snapshot stack of `(allScenes, shootDays)` in `ContentView`, not `UndoManager`.
   It does not cover call sheets, production info, or the title.
5. Exporters are pure functions from model values to `Data` (PDF). The save-panel actions around them
   live in `ProjectStore+PDFExports.swift`; the panels themselves come from `FilePanels`.

### Invariants to preserve

- A scene ID appears in exactly one of `allScenes` or some `shootDays[i].scenes`. Nothing enforces
  this; `updateShootDays` has an explicit safety net that returns orphans to the Boneyard.
- Project files must stay backward compatible. Every new `Codable` field is optional in the decoder
  with a default (`decodeIfPresent ?? default`). There is no schema version number.
- `Scene.stripColor` is the only place strip colors are resolved.
- Nothing is anchored to a date: scenes, calendar events, call sheets, day types, and day notes all slide together in shift mode, and a day drag swaps all of them between two dates. Script scenes that fall outside a new range go to the Boneyard; everything else is kept on its (shifted) date.
- `BannerType`'s decoder maps legacy Spanish raw values; keep it.

## Terms we avoid

- "Shot" for a scene; "block" for a strip; "task" or "event" for a scene. Use **scene** and **strip**.
- "Unscheduled list" or "backlog": use **Boneyard**.
- "Pages" as a float: durations are **eighths**.
- "Actor name" when you mean the character: scenes reference **characters**; the cast roster maps characters to actors.

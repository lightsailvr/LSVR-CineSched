# CineSched — Domain Context

CineSched is a SwiftUI app for scheduling film shoots: import a screenplay, break it into
scenes, drag scenes onto shoot days, track cast availability, and export industry-standard PDFs
(shooting schedule, stripboard, call sheets, breakdown sheets, Days Out of Days). The Mac app is
the product today; one target also builds iOS, iPadOS and visionOS, which open, create and
autosave projects from the CineSched folder in iCloud Drive (#12) into the three-column
editor with an inspector in regular width (#17) and a minimal editor in compact width
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
| **Drag payload** | `ScheduleDragPayload` (`ScheduleDrag.swift`, #18): the one `Transferable` value every drag on the schedule carries, on its own in-app type (`UTType.cineschedDragPayload`, conforming to `public.data`, declared in `Config/Info.plist`). Its kind is scenes (many, with the day they left or nil for the Boneyard), a whole day, a day-type band, or a calendar event. A drop switches on the kind; the pure moves it drives (`ScheduleMoves.moveScenes` to a `SceneDropDestination` — a day and `.before(sceneID)` or `.end` — and `.returnToBoneyard`) are what `ScheduleDragTests` pins. Replaced the pre-#18 three text encodings and two `DropDelegate`s. Strips, the day handle, the band and event chips are `.draggable(payload)` and the cells and day sections are `.dropDestination`, not the 27 reorder/drag containers (which crash together, see `learnings.md` 2026-09-20). |
| **Sync state** | What the indicator beside the project title says about this copy of an iCloud Drive project (#14): up to date, uploading, downloading, waiting for network, or conflict resolved (`SyncState`). Derived by `SyncState.derive` from the document URL's ubiquitous resource values (`UbiquitousResourceSnapshot`), the network and the conflict notice's presence; a file outside iCloud has none, and the indicator draws nothing. `SyncMonitor` (one per editor) reads the values on every change, restore, activation and a short poll, with an `NSMetadataQuery` on the entitled platforms and an `NWPathMonitor` everywhere; `SyncStateIndicator` draws it. Conflict resolved is shown until the next edit. |
| **Conflict notice** | What the user sees after iCloud reported the same project edited on two devices (#15): the newest version was kept, and the notice names the device and time of the one that lost, with a **Restore other version** action. The decision is `ConflictPolicy.decide` over `ConflictVersion` values: newest wins (the current one on a tie), the rest are resolved, the loser is retained for the session; a single version yields no notice. `SyncMonitor` runs it on iOS and visionOS over `NSFileVersion`'s unresolved conflict versions (read and removed under the document's coordinator); on the Mac the system's own conflict sheet resolves them (`PlatformConflictResolution`). Either way, a snapshot from disk that replaces unsaved local edits raises the same notice from the document's record of those edits (the **fallback**, `ConflictNotice.Origin.replacedUnsavedEdits`). Restore applies the retained snapshot through `perform`, so it is undoable. Lives in the sync indicator area (`ConflictNoticeState` is the lifecycle); dismisses when acted on or after the next edit. |
| **Native file type** | `com.lsvr.cinesched.project`, extension `.cinesched`, conforming to JSON (ADR 0005). Same bytes as the `.json` the app has always written; declared in `Config/Info.plist` as the exported type and the only document type. |
| **Viewer role** | How a legacy `.json` opens on the Mac: it is a readable type there (`PlatformDocumentTypes`), so File ▸ Open lists it, but the document infrastructure would autosave it in place, so `LegacyProjectHandoff` moves its contents into an untitled document and closes the `.json` window. The first Save asks for a `.cinesched` destination; the `.json` is never modified (the writer refuses it). iOS and visionOS have no viewer role: `.json` is not readable there, the browser shows only `.cinesched`, and a legacy file is imported into a new project from the launch screen instead (**launch import**, #13). |
| **CineSched folder** | The iCloud Documents container `iCloud.com.lsvr.LSVR-CineSched`, public and named "CineSched", so iCloud Drive shows it as a folder on every device of the account (ADR 0006). Owned by the iOS, iPadOS and visionOS builds through their entitlement (`Config/CineSched-iOS.entitlements`); their launch screen and document browser start in it. The Mac has no iCloud entitlement, so it reaches the folder like any other (user-selected files); `CineSchedFolder` derives its on-disk path (`~/Library/Mobile Documents/iCloud~com~lsvr~LSVR-CineSched/Documents`) and `MacAppDelegate` points the Open and Save panels there once, the first launch on which it exists. It exists only after a device has saved a project in it. |
| **Launch screen** | The system's `DocumentGroupLaunchScene` on iOS and visionOS: the title, New Project, Import Script…, Import Project… (the screen shows two actions and folds the rest into a More… menu), the recents grid and the document browser. The Mac has no equivalent; it opens windows and, with iCloud Drive on, the Open panel. |
| **Launch import** | Import Script… and Import Project… on the launch screen (#13): a new project made from a screenplay (its scenes in the Boneyard, its title page's title as the name) or from a legacy `.json` (its contents exactly, older shapes included), created in the CineSched folder like New Project. Each is a `NewDocumentButton` with a **creation source** (`DocumentCreationSource`, `.importScript` / `.importProject`); `makeDocument` sees it in its context and awaits `LaunchImportFlow`, which presents the file picker (and, for a script, the import summary with Create Project), then hands back the `ProjectData`. Cancelling anywhere throws, and the launch screen creates nothing. The original file is never written. Pure steps: `LaunchImport`; shared with the Mac's menu: `ScriptImport`. |
| **Minimal editor** | `MinimalProjectEditor`, what a project document shows in a compact-width window on iOS, iPadOS and visionOS (an iPhone, a narrow iPad pane) until milestone 4: the title as a field and the shoot days with their scene counts. Every write goes through `perform`; it was written (#12) to prove create, autosave, reopen and sync there. |
| **Editor layout** | Which window `ContentView` draws for (`EditorLayout`, #17): **two-column**, the Mac window (sidebar and detail, the toolbar row, the menus), or **three-column**, the iPad and Vision Pro window in regular width (the same sidebar, the schedule under a system toolbar, the **inspector**). `ProjectEditor` picks three-column or the minimal editor by the window's horizontal size class. One `ContentView`, one set of state and sheets, two bodies. |
| **Inspector** | The three-column layout's trailing column (340 pt): the selected scene's **adaptive editor** (the same form the sheets show; Save applies as one undo step and keeps the selection, Cancel and Delete clear it) or the selected day's detail (the same form as the Day Detail sheet: statistics, day type and note, its actions, call sheet milestones, events, scenes), or the project's statistics when nothing is selected. Bound to the **editor selection**; opened and closed from the toolbar, per window. |
| **Editor selection** | `EditorSelection`: the one scene (`.scene(id:)`) or day (`.day(id:)`) the inspector shows, addressed by id so it follows a scene a drag moves and prunes itself (`pruned(in:)`) when the target leaves the project. Written by every single tap on a strip (the schedule views' `lastSelectedSceneID` write, the Boneyard's select) or on a day (`onSelectDay`). Distinct from the multi-selection (`selectedSceneIDs`) that says which strips drag and act together. On the Mac it is set and never shown. |
| **Touch affordances** | How the Mac's pointer gestures map on iPad and Vision Pro (#17): a single tap selects into the inspector, a double tap opens the full editor sheet, a long press opens the context menu (SwiftUI's `.contextMenu` is the Mac's right-click and the touch long-press alike), a pointer or trackpad hover shows the strip tooltip. The schedule views take them as optional parameters (`onSelectDay`, `selectedDayID`) the Mac leaves nil; `ModifierKeys` reports none on touch, so a tap is a plain single select. |
| **Adaptive editor** | One of the five editors rebuilt as a form for every container (#19): the scene editor (`SceneEditSheet`), the day detail (`DayDetailSheet`), the banner input, the calendar event input and Send to Day. Each is `EditorChrome` (a header, a grouped `Form`, a footer button row, the same in every container) around a **draft** (`SceneDraft`, `BannerDraft`, `CalendarEventDraft` in `EditorDrafts.swift`: the fields as plain values, read from the model, validated, written back as one assignment, so Save is one `perform` and one undo step) with `editorContainer` at its root. The shared settings and reports (#21) take the same shape without a draft, being live or read-only: the Stripboard fields picker (writes the app preference as each switch flips), Customize Scene Colors (each pick through `perform` into the project's palette), the color legend (swatches from the `scenePalette` environment), the conflict report, the schedule lock report, the import summary (both modes) and the month PDF options. |
| **Editor container** | Where an adaptive editor is presented and how the sheet is sized, the `PlatformEditorContainer` seam over `EditorSheetSize` (the editor's platform-free numbers): the Mac's fixed-frame sheet at the size the old sheet had, a sheet with detents on the iPhone, a form-sized sheet on iPad and Vision Pro (at the editor's own height for a short one), and nothing in the inspector, where the form fills the column. |
| **Project commands** | `ProjectCommands`: the closure slots (and View-menu bindings) a `ContentView` publishes as a focused scene value so the app-wide menus act on the frontmost window. |
| **Window preference** | `@WindowPreference`: view state that belongs to one window (Calendar vs Stripboard, cast row, times vs pages, all days, grid vs list), seeded from the last-used value and written back for the next window. Distinct from an app preference (Dark Mode, Theme, Stripboard fields), which applies everywhere at once. |
| **Export request** | `PDFExportRequest` (#23): what one PDF export produces before the platform decides where it goes: the document's kind, the file name the user sees (`.pdf` included, the Mac's save panel's name) and the exporter's bytes. Built by `PDFExport`, one function per document from the project and the export's parameters, the only place the exporters are called with the project's values, so a request is the same bytes on every platform. Delivered to the **export presentation**. |
| **Export presentation** | Where an export request goes: the Mac's save panel (`FilePanels`, unchanged), or on iPad, iPhone and Vision Pro the **preview sheet** (`PDFExportPreviewSheet`: the PDF through PDFKit, Done, Share), whose share sheet offers AirDrop, Messages, Mail, Print, Save to Files and the rest for the file under its export name. `PlatformExportPresentation` (a seam) decides; the iPad reaches it from the toolbar's Export menu, the calendar's Export Month button, the Stripboard day header, the day inspector and the call sheet editor. |
| **Pure core** | The platform-free part of the code: models, parsers and importers, scanners, formatting, row logic, palette settings. Compiles on every platform with no `#if os`. |
| **Platform seam** | A file that exists to hold a platform difference (`FilePanels`, `ModifierKeys`, `PlatformControlStyles`, …). The only places `#if os(...)` may appear; each starts with a comment saying why. See ADR 0003. |

## System shape

Everything lives flat in `LSVR CineSched/`. One responsibility per file; no third-party dependencies.

```
CineSchedApp.swift        @main; a DocumentGroup over ProjectDocument on every platform. On the Mac one window per
                          document plus the menus, which reach the key window through @FocusedValue(\.projectCommands);
                          on iOS and visionOS ProjectEditor and the system's launch screen (#12, #17).
ProjectEditor.swift       The non-Mac editor by size class (#17): ContentView's three-column layout in regular width,
                          MinimalProjectEditor in compact width. Platform-free.
MinimalProjectEditor.swift  The compact-width editor until M4 (title field, shoot days with scene counts) and the
                          launch screen's background. Platform-free.
CineSchedFolder.swift     The iCloud container identifier, folder name and the Mac's derivation of its on-disk path (pure).
ProjectCommands.swift     The closure slots a ContentView publishes for those menus (focused scene value).
ContentView.swift         The editor for one document: sidebar, toolbar, calendar and stripboard, in the Mac's
                          two-column layout or the iPad's three-column layout with the inspector (#17). Reads
                          `document.project`, writes only through `edit` / bindings built on `perform`.
  ContentView+Inspector.swift      the three-column layout's trailing column: the selected scene's editor, the selected
                                   day's detail and its edits, the project statistics when nothing is selected.
  ContentView+ScriptImport.swift   File ▸ Import Script… (Final Draft, Fountain, Highland) into the Boneyard.
  ContentView+PDFExports.swift     every PDF export action: build the PDFExportRequest, deliver it to the save panel
                                   (Mac, FilePanels) or the preview sheet (iOS, visionOS).
PDFExportRequest.swift    The export request and PDFExport, one pure function per document from the project to a
                          request or a PDFExportError (#23).
PDFExportPresentation.swift  The preview sheet with Done and Share, the request as a Transferable file, the modifier
                          ContentView hangs off its root. Platform-free.
BoneyardListView.swift    The Boneyard list both layouts draw (strip rows, drag out, drop back, tooltip, menu).
EditorSelection.swift     The inspector's selection (a scene or a day by id), locating it in the project, pruning (pure).
EditorPresentation.swift  The environment value telling an editor it is in the inspector rather than a sheet, and
                          EditorSheetSize, what an editor asks of its sheet (#19).
PlatformEditorContainer.swift  Seam: the editorContainer modifier sizing an adaptive editor's sheet per platform.
EditorChrome.swift        The adaptive editors' shared chrome (header, grouped form, footer buttons), the color
                          swatch row and the prompted text editor.
EditorDrafts.swift        The editors' drafts (SceneDraft, BannerDraft, CalendarEventDraft), pure.
ScriptImport.swift        What both script imports share: the screenplay types, the dispatch by extension to the
                          Fountain or Final Draft importer, the Final Draft scene mapping, one parse for any format.
LaunchImportFlow.swift    The launch screen's Import Script… / Import Project… (#13): the pure steps (LaunchImport),
                          the coordinator makeDocument awaits (LaunchImportFlow) and the picker/summary presentation.
ImportSummaryView.swift   The import summary sheet (adaptive, #21): Done after the Mac's import, Cancel / Create
                          Project before the launch screen's.
Models.swift              All value types (Scene, ShootDay, ProjectData, CallSheetData, ...). Hand-written Codable.
ProjectCodec.swift        The one project encoder/decoder (pretty JSON, ISO dates, legacy shapes).
ProjectDocument.swift     The project document (27 Document protocol), URL reader/writer, perform undo funnel,
                          UTType.cineschedProject, ProjectData.newProject (the File ▸ New template).
CalendarView.swift        Month grid / full-schedule scroll, drag & drop, day cells. Holds the shared drop plumbing.
StripboardView.swift      Strip schedule with time cascade and auto-meal sync.
ScheduleDrag.swift        The one typed drag payload every schedule drag carries and the pure moves a drop makes (#18).
*Sheet.swift              Modal editors (Scene, CallSheet, ProductionSetup, Banner, CalendarEvent, SendToDay, ...);
                          the scene, day detail, banner, calendar event and Send to Day ones are adaptive (#19), as
                          are the Stripboard fields picker, scene colors, the conflict and schedule lock reports and
                          the month PDF options (#21; ColorLegendView.swift and ImportSummaryView.swift likewise).
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
PlatformColors, PlatformDocumentTypes, PlatformInspector, PlatformExportPresentation,
LegacyProjectHandoff, MacAppDelegate                                  Platform seams (ADR 0003).
LegacyWorkingCopyRecovery.swift                                       The first-launch decision over the pre-document builds' UserDefaults
                                                                       working copy and file bookmark (#10); MacAppDelegate acts on it.
SyncState.swift                                                       The sync state beside the title (#14): the five states and the pure
                                                                       mapping from a URL's ubiquitous resource values, the network and
                                                                       the conflict flag; nil outside iCloud.
ConflictPolicy.swift                                                  The conflict decision (#15): newest version wins, the rest resolved,
                                                                       the loser retained for the notice and Restore other version.
ConflictNotice.swift                                                  The notice and its lifecycle (raised at a change count, retired by the
                                                                       next), and how the document's own version is dated. Pure.
SyncMonitor.swift                                                     The wiring, one per editor: resource values, metadata query, path
                                                                       monitor, the NSFileVersion pipeline through the coordinator, the
                                                                       fallback from the document's replaced-edits record.
SyncStateIndicator.swift                                              The indicator beside the title and the notice popover. Platform-free.
PlatformConflictResolution.swift                                      Seam: whether the system presents its own conflict UI (the Mac).
```

### Data flow

1. `DocumentGroup` (CineSchedApp) makes a `ProjectDocument` per window and reads the file into it
   through `ProjectDocumentReader`; `ContentView(document:)` is the window's content on the Mac,
   `ProjectEditor(document:)` on iOS and visionOS (`ContentView` in its three-column layout in
   regular width, `MinimalProjectEditor` in compact), where the file lives in the CineSched
   folder (or wherever the document browser opened it in place) and the launch screen is the
   system's. A launch import (#13) is the same `makeDocument`, which sees the button's creation
   source and starts the document from what `LaunchImportFlow` returns instead of the template.
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
6. Exporters are pure functions from model values to `Data` (PDF). `PDFExport` calls them with the
   project's values and wraps the result in a `PDFExportRequest` (kind, file name, bytes); the
   actions in `ContentView+PDFExports.swift` deliver a request to the Mac's save panel
   (`FilePanels`) or, on iOS and visionOS, to the preview sheet with Share
   (`PDFExportPresentation`, the choice in `PlatformExportPresentation`, #23).
7. The sync state and the conflict notice (#14, #15) come from a `SyncMonitor` each editor
   owns through the `syncMonitored(_:document:)` modifier, which starts it with the document
   and hands it every `changeCount`, `restoreCount` and `writtenChangeCount` change, the scene
   phase and the undo manager; the monitor reads `document.fileURL`'s ubiquitous resource
   values (on those triggers, on a poll, and when its metadata query or path monitor
   reports), runs `SyncState.derive`, and `SyncStateIndicator` beside the title reads
   `monitor.state`. A restore is where a conflict shows: on iOS and visionOS the monitor
   reads `NSFileVersion`'s unresolved conflict versions under the document's coordinator, runs
   `ConflictPolicy.decide` and acts on `ConflictResolutionPlan`: applies a winning other
   version through `perform` ("Undo Resolve Conflict"), marks and removes the losing conflict
   versions at once, keeps the winner's own version unresolved until the document reports
   the write that carries its contents (`writtenChangeCount`, then resolved and removed),
   and raises the notice with the loser retained; with no undo manager attached nothing is
   applied or resolved until one is. On the Mac NSDocument's own conflict sheet does the
   choosing, and the notice comes only from the fallback, the edits `ProjectDocument.apply`
   found unsaved and recorded. Restore other version is a `perform` of the retained snapshot
   ("Undo Restore Other Version"); the next `changeCount` that is not the resolution's own
   retires the notice.

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

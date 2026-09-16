# Changelog

All notable changes to CineSched are documented here.

## [Unreleased]
### Changed
- **Requires macOS 27.** The deployment floor moves from 26.5 to 27.0 (on every platform in the project) as the baseline for the upcoming iPad, iPhone and Vision Pro work. Nothing about the Mac app's behavior changes.

## [4.6.0] - 2026-09-09
### Added
- **Day types** — any calendar date can now be marked as a Travel Day, Scout Day, Prep Day, Rehearsal Day, Weather Hold, Holiday, Day Off, or Unavailable, from the day's right-click menu ("Set Day Type", plus "Set Every Saturday…" to apply one to a whole weekday) or from a new Day Type card at the top of the Day Detail sheet. The cell is tinted and carries a labelled band in the type's color; the Day Detail header, the Stripboard day header, and the month PDF show the same label, and the Days Out of Days shades those columns. Only shoot days earn a production day number, and a scene dropped on a non-shoot day is flagged red the way scenes on unavailable days always were. Right-clicking a date outside the production range offers the same menu and creates the day. "Clear Day Type" (in the same menu, and a Clear button on the card) turns the day back into a plain shoot day and drops its note; a date outside the production range that held nothing else disappears back into an empty tile. Day types move with the shoot: shift mode slides them along with the scenes and call sheets, and dragging the type band itself (the "TRAVEL DAY" label in the cell) onto another date moves just the type and note there, while dragging the day's three-line handle swaps the whole day (scenes, call sheet, type, note). Both work onto a date outside the range that has no day yet. The old "Mark as Unavailable" toggles are folded into this menu as the Unavailable type; existing projects open with their unavailable days intact, and files saved by this build still open in older builds.
- **Calendar events and typed days on the Stripboard** — the Stripboard no longer hides calendar events or folds event-only, typed, or noted days into gap rows. Such days are full day rows with their type badge, so a travel day can be seen and dragged while the schedule is built; events appear as a row of colored chips under the day header (right-click to edit or delete, drag to another day), kept out of the time cascade so an event time never shifts the call-time math. The Stripboard PDF prints them as slim tinted lines above the strips.
- **Calendar events slide with the shoot** — in shift mode calendar events now move by the same offset as everything else instead of staying pinned to their dates, and a day drag swaps them along with the scenes.
- **Day notes** — a free-text note per date ("Fly LAX → ABQ, crew van 6 AM"), edited in the Day Detail sheet's Day Type card. Shown under the type band in the calendar cell, in the Stripboard day header, and in the month PDF (both the grid cell and the breakdown page, which now also gives a card to a noted day that has no scenes, badged with its day type).

- **Month PDF export options** — the calendar's "Export Month (PDF)" button now opens a dialog choosing what the breakdown pages print for every scene: page count, estimated shooting time, and any of the breakdown fields (cast, real location, scene summary, special equipment, props, vehicles, stunts, and the rest — the same list the Stripboard Fields picker offers). The default matches what the PDF always printed (page count, cast, location), and the selection is remembered between exports.
- **Redesigned breakdown scene blocks** — each scene on the breakdown pages is now built to be read at a glance: a strip-color swatch and bold slugline heading with the page count and estimated time right-aligned, the synopsis on its own italic line, and the remaining details as emoji-tagged pills (📍 location in blue, 🎥 special equipment in amber, 👥 cast and the other breakdown fields in neutral gray). A pill too wide for one row becomes a full-width wrapped pill so a long cast list keeps every name.

### Fixed
- **The month PDF breakdown now paginates instead of silently dropping days.** The "Schedule & Breakdown" section used to be a single page that quietly cut off once full; it now continues across as many pages as the month needs, with "(cont.)" headers and page numbers. Day cards also grew honest heights: the call-times line is budgeted for (it used to push scene lines past the card border), and long scene lines wrap up to three lines instead of clipping mid-word. On the calendar grid page, day cells now print the scene number and shooting location ("36 · HOLLYWOOD (2/8)") in a slightly smaller font instead of the full slugline, since the full detail follows on the breakdown pages.
- **Updating the production range no longer wipes call sheets and unavailable days.** Regenerating the day list rebuilt every day from scratch, so any change to the start or end date silently discarded every call sheet and every "Unavailable" flag. Call sheets, day types, day notes, and calendar events now all follow the shoot (shifting with the scenes in shift mode), and anything that lands outside the new range is kept on its date rather than dropped.
- **Stripboard gap rows** — runs of days with no scenes now fold into a single slim row ("14 empty days · Nov 8 – Nov 21", with weekend and unavailable counts) instead of a full empty day section each, so a shoot with blocks months apart no longer needs scrolling past the break. Click a gap row to open it when you want to drop scenes onto those dates; an opened run shows a "Hide empty days" button in its day headers to fold it back. Scrolling to a date inside a collapsed gap opens the gap first. An "All days" checkbox on the Stripboard toolbar (and View ▸ Show All Days on Stripboard) restores the full date list; it is an app preference, off by default. The Calendar view is unchanged and always shows every date.
- **Month PDF no longer prints Spanish abbreviations in English.** The breakdown page's scene lines hardcoded "Esc" (Escena) and "págs" regardless of language; they now print "Sc" and "pgs" in English like the rest of the page.
- **Stripboard Fields** — a "Fields" button on the Stripboard toolbar (and View ▸ Stripboard Fields…) opens a picker for which scene fields each strip shows beside the heading: Cast, Real Location / Set, Scene Summary, and every breakdown tag (Extras, Props, Set Dressing, Wardrobe, Hair & Makeup, Vehicles, Special Equipment, Stunts, SFX, VFX, Breakdown Notes). Each enabled field prints as a small icon-tagged chip in the same muted style Cast always used, so strips can be grouped by real location or special gear at a glance. The selection is an app preference; Cast alone is the default, matching the previous board.

## [4.5.1] - 2026 (Monthly Calendar & Vector Export Edition)
### Added
- **Full Monthly Calendar View (Vista por Mes)** — Intuitive month-by-month calendar navigation with system theme matching, shoot range highlighting, and month-level scheduling.
- **Interactive Day Detail Modal (DayDetailSheet)** — Double-click any day in the month view to open a rich modal inspector with production day numbers, page/scene statistics, call sheet schedule badges (Call, Lunch, Snack, Wrap, Basecamp), and agenda event management.
- **Adaptive Day Inspector** — Context-aware presentation: shoot days show full call sheet and scene breakdown actions; off-days and prep days display an uncluttered agenda management view.
- **Shoot Days Only View Mode** — Filter out non-production days and off-range calendar events to focus strictly on scheduled shoot days.
- **Boneyard to Calendar Drag-and-Drop** — Seamlessly drag script scenes directly from the Boneyard (`allScenes`) into any calendar cell or empty date tile.
- **Calendar Event Deletion & Management** — Direct delete buttons (trash icon) in the day detail sheet and right-click context menu (`Eliminar Evento` / `Delete Event`) on event chips.
- **2-Page High-Resolution Monthly PDF Exporter**:
  - **Page 1 (Full-Height Calendar Grid)**: 100% of the page height is dedicated to the calendar grid, ensuring tall, spacious day cells with legible scene numbers, titles, octavos, and start times without compression.
  - **Page 2 (Detailed Monthly Breakdown & Schedule)**: Generates a second page with comprehensive structured cards for every active day of the month, displaying complete scene synopses, INT/EXT headings, cast list, real locations, call sheet times, and agenda events.

### Improved
- **Anti-Data-Loss Safety Net in "Update Calendar"** — When adjusting or trimming the production date range, all displaced script scenes automatically return to the Boneyard (`allScenes`) rather than being discarded.
- **Anchored Calendar Events** — Agenda events (`isCalendarEvent`) are permanently locked to their absolute calendar dates and are excluded from "Shift Schedule" scene displacements.
- **Clean Event Typography** — Removed redundant calendar emoji icons from event chips in favor of crisp time-prefixed badges (`10:00 AM · Lectura de guion`).
- **Production Day Numbering Integrity** — Calendar-only events outside the shooting schedule do not increment production day numbers (`Día #1`, `Día #2`).

## [4.5.0] - 2026 (D.G.D Edition)
### Added
- **Dynamic Shooting Schedule (Plan de Rodaje) Vector PDF Exporter** — standard vector PDF exporter with 4 bounded columns (Time, Scene and Full Slugline, Script Page, Eighths) with zero text collisions and dynamic milestone badges.
- **Automated Timeline Cascade & Quick Time Editor** — dynamic hour calculation from call to wrap, dual-mode fixed/cascade selector, duration stepper controls, and double-click time editing directly on stripboard rows.
- **100% Full Multilingual Localization (Español / English)** — reactive UI translations for all windows, sheets, menus, date formatters, and export reports.
- **Fixed 7-Column Production Calendar** — uniform Monday-to-Sunday production grid with exact weekday alignment.
- **Decoupled Calendar Events** — independent non-scene calendar events (travel, rehearsal, rest days) that do not enter the Boneyard or alter scene breakdown statistics.
- **Notice & Milestone Banners** — customizable banner strips with color presets and dynamic call sheet synchronization.

## [4.0] - 2026
### Added
- **Call Sheet Reference Redesign** — industry-standard layout in 100% English with clean light gray header, prominent general call time, quote of the day, 12h meal/milestone times (Ready to Shoot, Lunch, Snack, Wrap), nearest hospital, full scene breakdown with clean decorado sluglines, cast call, crew call times, and unified general notes.
- **Production Contacts Sync** — Director, Producer, and 1st AD names and phone numbers in Production Setup automatically populate Call Sheet shooting contacts across every shoot day.
- **Real Location with Live Autocomplete** — enter real set/location names when creating or editing scenes with predictive autocomplete suggestions from all project locations.
- **Location Sync Without Duplicates** — distinct locations from scheduled scenes automatically populate the Call Sheet location list (LOC 1, LOC 2...) without repeats.
- **Fountain & Highland Script Importer** — import industry standard `.fountain` and `.highland` script archives with full page pagination and character breakdown.
- **Stripboard PDF Exporter** — export strip schedules directly to clean PDF sheets.

## [3.2] - 2026
### Added
- **Custom scene type** — a third strip type alongside Day and Night, displayed in red. Use it for company moves, meal breaks, or any non-scene entry. Custom strips only require a title — page count and time estimate are optional
- **Boneyard sort** — sort the Boneyard by Location, INT/EXT, Cast, Day/Night, or Default order. Location sort groups scenes by place name, intelligently ignoring INT./EXT. prefixes and scene numbers. Sorting is display-only and does not affect the underlying scene order
- **Daily crew defaults** — each crew member in Production Setup now has a "Daily" checkbox. Crew marked as daily are pre-populated on every call sheet automatically
- **Per-day crew selection** — the call sheet editor now shows your full crew roster as checkboxes. Daily defaults arrive pre-checked; specialty crew are unchecked and can be added as needed. Uncheck any daily crew member who isn't needed that day. One-off crew not in the roster can still be added by typing their name directly
- **Crew on call sheet PDF** reflects exactly who was selected for that day — not the full roster

### Improved
- Boneyard now shows "D" and "N" instead of "DAY" and "NIGHT" for day/night indicators, giving more room for scene titles
- Scene type label in SceneEditSheet changed from "Time of Day" to "Type" to better reflect the addition of the Custom type
- Custom strips with zero page count or time display blank fields in the editor rather than "0"

## [3.1] - 2026
### Added
- Drag entire shoot days to reschedule — grip icon (☰) on each date header lets you drag a day's scenes and call sheet to any other date; swaps content if the target day is occupied

### Improved
- Grip icon now responds to a single click-and-drag (no longer requires a prior activation click)
- Production Setup button moved before Import Script in the toolbar
- "New" fully resets the project — now also clears call sheets, project title, and production info
- Confirmation dialog for "New" accurately describes what will be cleared

## [3.0] - 2026
### Added
- **Call sheets** — click any date header in the calendar to open the call sheet editor for that day
- Per-day call sheet editor with general call time, multiple locations (add/remove), cast, and free-form notes
- Call sheet PDF export in US Letter portrait — professional layout with header, locations, scene breakdown, cast, crew, and notes
- **Production Setup** — project-wide panel (toolbar button) for company name, director, contact number, cast list, and crew list
- Actor → character mapping in Production Setup: enter `Jake Nuttbrock — Blake` once, and the call sheet automatically resolves character names from scenes to full actor credits
- Cast list on scenes now stores individual names as an array (previously a single string) — existing saves migrate automatically
- Blue dot indicator on calendar date headers when a call sheet has data entered
- General call time displayed prominently bold and right-aligned on call sheet PDF
- Grip icon (☰) on date headers — click and drag to move an entire day's scenes and call sheet to another date, swapping content if the target day has scenes
- "New" now fully resets the project — clears scenes, call sheets, project title, and production info

### Improved
- All file operations (Load, Import Script, Export PDF, Export Call Sheet) now use native macOS panels — more reliable than SwiftUI's fileExporter/fileImporter on macOS 13
- Auto-save reworked with a dirty-flag + debounce pattern — no more timer objects
- `createdDate` on projects now correctly preserved across saves (was being reset on every save)
- Scene edit sheet text area has improved internal padding
- General call time stands out on call sheet PDF — bold, larger, right-aligned
- Cast on call sheet displayed as a single-column list matching crew style
- Notes in call sheet PDF now correctly render below the NOTES header
- Production Setup button moved before Import Script in the toolbar
- Code split into focused single-responsibility files — ContentView reduced from 2,800 lines to ~450

### Fixed
- Calendar date header popup occasionally showing as a blank square — fixed by switching to `sheet(item:)` pattern
- Load button silently doing nothing — fixed by replacing fileImporter with NSOpenPanel
- PDF export not triggering — fixed by replacing fileExporter with NSSavePanel
- Day drag handle requiring two clicks — fixed with `simultaneousGesture` and `contentShape`
- "New" leaving call sheet data behind on calendar days

## [2.5] - 2026
### Added
- Final Draft `.fdx` script import — parse scene headings directly from your screenplay
- Automatic scene number extraction from FDX files
- Auto-detection of time of day (DAY / NIGHT / MORNING / EVENING / DUSK / DAWN)
- Location parsing (INT. / EXT.) from scene headings
- All imported scene headings automatically capitalized
- Imported scenes land in the Boneyard with default values ready to edit

## [2.0] - 2026
### Added
- Drag-and-drop scene scheduling with precise drop positioning between scenes
- Day/Night classification with color-coded indicators (orange for day, blue for night)
- Visual drop indicators showing exactly where a scene will land
- Duplicate scene from context menu in both calendar and Boneyard
- Cast and scene summary fields on each scene
- Shift Schedule toggle — shift all scenes when changing the start date, or lock them in place
- Dark/Light mode toggle with saved preference
- Compact statistics bar showing shoot days, total scenes, and estimated time
- Native save dialog for exporting project files

### Improved
- PDF export redesigned with tighter, more professional layout
- Scene strips truncate cleanly with ellipsis when titles are long
- Dynamic row heights in PDF based on scene density per week
- Grid lines constrained to actual calendar content area
- Auto-save triggers reliably on all state changes

## [1.0] - 2025
### Added
- Visual weekly calendar grid for scheduling shoot days
- Scene creation with title, page duration (in eighths), and estimated time
- Flexible duration input: eighths, mixed fractions (1 7/8), and decimals
- Flexible time input: hours, minutes, and H:MM format
- Boneyard sidebar for holding unscheduled scenes
- Drag scenes from Boneyard onto calendar days
- Double-click any scene to edit
- Daily totals for page count and estimated shoot time
- PDF export in landscape US Letter format
- Save and load projects as `.json` files
- Auto-save to local storage

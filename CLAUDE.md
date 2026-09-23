# CLAUDE.md

CineSched: a SwiftUI app for film production scheduling. The Mac app is the shipping product;
iOS, iPadOS and visionOS build from the same target and today have the system's document
launch screen (New Project, Import Script…, Import Project…, recents, the document browser),
open, create and autosave `.cinesched` projects from the CineSched folder in iCloud Drive, and
show the sync indicator and the conflict notice (#12–#15, ADR 0006). In regular width (iPad,
Vision Pro) the editor is `ContentView` in its three-column layout with a trailing inspector
(#17, the foundation of milestone 3 of #1); in compact width (iPhone, a narrow iPad pane) the
iPhone editor (#24, the foundation of milestone 4): a tab view whose Days tab is the
Stripboard as a list of day cards under a week strip, with a Day screen that moves (#25)
and edits (#26) everything about a day, whose Production tab (#28) holds every Mac menu
command as rows, whose Boneyard tab (#27) lists the unscheduled scenes with the Mac's
sorts, a filter, multi-select Send to Day and a New Scene form, and whose Search tab (#27)
finds any scene and opens it or shows it in Days or the Boneyard. Nothing else about those
platforms is placeholder.
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
with Xcode 27.0 (27A266a) at the 27.0 floor succeeds with exactly 4 warnings in the app target
(all deprecated one-argument `onChange`: `NewSceneInputView` twice, `StripboardView` twice; the
compiler echoes each once more as a source excerpt), on macOS, the iPhone 17 simulator and
the Apple Vision Pro simulator alike (last checked 2026-09-20, down from 7: #18 dropped one in
`StripboardView`, #19 rewrote `BannerInputSheet` and `LocationAutocompleteField`); do not add
new ones. (The 4 main-actor-isolated `Codable` warnings went with #7:
the model's `Codable` conformances are `nonisolated`.) The test target adds 3 more, all
main-actor isolation (`MonthPDFExporterTests` twice, echoed, and a `@Test(arguments:)` macro
expansion in `ProjectDocumentTests`): 5 warning lines in the log.

Project facts: single scheme `LSVR CineSched`; Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency on; deployment target
27.0 on macOS, iOS and visionOS (one target builds all three; only the Mac ships today);
sandboxed with user-selected file read/write on the Mac, iCloud Documents on the other platforms (ADR 0006);
no SPM packages or other dependencies.

The Xcode target is a **synchronized folder group**. Any file placed in `LSVR CineSched/` is
automatically compiled (`.swift`) or bundled as a resource (everything else). No pbxproj edits are
needed to add a source file, and non-source files should not be put in that folder.

## Where things are

All Swift sources are flat in `LSVR CineSched/`, one responsibility per file (the partial
`Config/Info.plist` and the iOS/visionOS entitlements `Config/CineSched-iOS.entitlements` are
the build inputs outside it, see Working agreements):

- `CineSchedApp.swift`: `@main`; a `DocumentGroup` over `ProjectDocument` on every platform. On
  the Mac one window per document plus the menus, which act on the key window through
  `@FocusedValue(\.projectCommands)`; on iOS and visionOS `ProjectEditor` as the editor
  and the system's `DocumentGroupLaunchScene` (New Project, Import Script…, Import Project…,
  recents, the document browser). The one `menus` builder goes on both scenes (#22): the
  iPad's menu bar shows it with the Mac's shortcuts, and reaches the active window through
  `ActiveProjectCommands` (`ActiveProjectCommands.swift`, an `@Observable` holder the
  non-Mac editor publishes into by `appearsActive`) because `@FocusedValue` is nil on
  iPadOS unless the focus system is engaged; the Mac never sees the holder. The two imports (#13) are `NewDocumentButton`s with a
  `DocumentCreationSource`; `makeDocument` switches on `context.creationSource` and awaits
  `LaunchImportFlow` for the project. The button's `prepareDocumentURL` closure is never
  invoked by the 27.0 launch scene; do not move the flow there.
- `ProjectEditor.swift`: the non-Mac editor choice by `horizontalSizeClass` (#17): regular
  width gets `ContentView(document:layout: .threeColumn)`, compact width `PhoneEditor`
  (#24). Platform-free.
- `PhoneEditor.swift`: the compact-width editor (#24): a `TabView` with Days (`DaysTab`),
  Boneyard (`BoneyardTab`, #27), Production (`ProductionTab`, #28) and a Search tab in the
  search role (`SearchTab`, #27), and the Today control (`TodayControl`,
  `todayTarget`) as the tab bar accessory, with the bar minimizing on scroll, through the
  `phoneTabBar` seam (both APIs are iOS-only in the 27 SDK). Owns what `ContentView` owns
  for the other layouts: the document and `edit(_:_:)` (the same `perform` under an
  `EditGesture`, handed to the tabs as a `ProjectEdit` closure; `edit(_:coalescing:_:)`,
  handed down as `CoalescedProjectEdit`, for a gesture the caller keeps across calls, the
  title's typing burst, a color slot's picks and the Day screen's note;
  `beginEditGesture()` for the multi-write actions, and the "open one if none is open"
  closure the Production tab's character renames and `PhoneDayEdits` take), the
  `SyncMonitor` (its indicator is a toolbar item at the root, which lands in the
  document infrastructure's bar), the `scenePalette` environment at the root, the
  `DerivedScheduleState` cache (for the Boneyard sort it holds as the Mac's app-wide
  `CineSchedBoneyardSort` preference, #27), `.pdfExportPresentation($exportPreview)` with
  the `exportPreview` request `PhoneExports` sets (the phone's one export call site,
  wired here with the preview and the Export Failed alert and handed to the Production
  tab and `PhoneDayEdits`), the range pickers' state (`rangeStart`, `rangeEnd`,
  `seededRange`, seeded from the shoot days' bounds and re-seeded on `restoreCount`;
  the Production tab binds to them and `PhoneDayEdits.clearDayType` reads them as the
  production range), the moves (`PhoneMoves`, `moveSheet`, #25) and the day edits
  (`PhoneDayEdits`, `editSheet`, #26), each presented over the editor by its own
  modifier, the cross-tab jumps (`scrollToDate` into the Days list,
  `revealBoneyardSceneID` into the Boneyard, which the Search tab's Show in Days / Show in
  Boneyard set with the tab switch), the `ProjectEdit` and `CoalescedProjectEdit`
  typealiases (the funnel's two shapes), and the
  `ProjectCommands` for the iPad's menu bar in a narrow window (#22): published as the
  focused scene value and into `ActiveProjectCommands` by `appearsActive`, every closure a
  switch to the Production tab plus a `ProductionCommand` in the `productionCommand`
  binding the tab consumes (the View menu's bindings are constants: no calendar, no cast
  row, no all-days toggle on the phone), and `undoGestures(undoManager)` at the root,
  which puts the same manager `edit` registers with on UIKit's responder chain for shake
  to undo and the three-finger gestures (`PlatformPasteboardResponder`). Platform-free.
- `ProductionTab.swift`: the Production tab (#28): a grouped `List` (no stack of its own,
  nothing pushes) of rows in five sections, each presenting what already exists through
  one `ActiveSheet` enum and `.sheet(item:)`: Production (`ProductionSetupSheet` with the
  character-rename fan-out through `ProjectData.renameCharacter`; Scan for Conflicts →
  `ConflictReportSheet`, whose rows `jumpToDate` into the Days list; Lock / Unlock as one
  row that switches, through `lockSchedule` / `unlockSchedule`; the
  `ScheduleLockReportSheet`; the Breakdown Browser: `SceneEditSheet` driven by id over
  `BreakdownBrowser`, Previous / Next step, Save closes, Delete removes outright and
  steps, a `ContentUnavailableView` sheet for a project without scenes) and Appearance
  (`ColorLegendView`, `SceneColorSettingsSheet` through `editCoalescing` with one token
  per slot, `StripboardFieldsSheet` on the app-wide `@AppStorage` key) in the main file;
  the other three sections are extensions, the `ContentView+*` pattern:
  `ProductionTab+Range.swift` (Project: the title field on a per-focus-session token, the
  two `DatePicker`s bound to `PhoneEditor`'s range state, Shift Schedule, Update Calendar,
  which confirms through `previewProductionRange` when scenes would return to the
  Boneyard — the copy says the call sheets, events, types and notes move or stay by
  `ProductionRangePreview.shifts` — and applies `updateProductionRange` as one `edit`),
  `ProductionTab+Exports.swift` (Export: the six documents through `PhoneExports`, the
  month one through a `Menu` of `productionMonths` and `MonthPDFOptionsSheet` on the
  calendar's `@AppStorage` keys, Include Hold as a row) and `ProductionTab+Import.swift`
  (`fileImporter` → `ScriptImport.parse` → `ImportSummaryView` in its `.existingProject`
  confirmation → one `edit` on Add to Boneyard). Row details (cast count, conflicted
  scenes, lock date, changes, scene count) come from the project and
  `DerivedScheduleState`. `ProductionCommand` is what the menu bar hands it (consumed in
  `onChange` and on appear). Platform-free.
- `PhoneExports.swift`: the iPhone editor's one PDF export call site (the counterpart of
  `ContentView+PDFExports.swift`): `PhoneExports` (the project, where a request goes —
  `PhoneEditor.exportPreview` — and where a failure's message goes), one function per
  document (`scheduleCalendar`, `monthCalendar`, `stripSchedule`, `shootingSchedule`,
  `daysOutOfDays`, `breakdowns`, `callSheet`), each a `PDFExport` request delivered.
  The Production tab and `PhoneDayEdits` (the Day screen's and the call sheet editor's
  Export Call Sheet PDF) call it; nothing else on the phone calls `PDFExport`.
- `ProductionEdits.swift`: the production-wide edits as pure `ProjectData` mutations
  (`ProductionEditsTests`): `renameCharacter(from:to:)` (every scene's cast and every
  call sheet's cast override, case-insensitive; blanks and a case-only change refused),
  `lockSchedule(now:)` (the working-days snapshot into the production info) and
  `unlockSchedule()`. The phone and `ContentView` both call them (the Mac's copies
  went with #35, after tests pinned them).
- `BoneyardTab.swift`: the Boneyard tab (#27): a control row (the filter field, Select /
  Done, "+", the sort `Menu` over the six `BoneyardSort`s, the count of scenes and pages
  listed) over a `List(selection:)` of `PhoneStripRow`s from `derived.sortedBoneyard`
  narrowed by `SceneSearch.filter`; a row's tap opens the scene editor through
  `dayEdits.presentSceneEditor` with the displayed rows as `siblingIDs` (Previous / Next
  step them), its long press is the Mac's Boneyard menu (Edit, Duplicate —
  `dayEdits.duplicateScene`, the one rule — Send to Day…, Delete) with `StripPreview`,
  its trailing swipe Delete, Send to Day and Duplicate; Select puts the
  list in edit mode through `listSelecting` for the multi-selection, whose one Send to Day
  goes to `moves.presentSendToDay` in display order (`BoneyardSelection.ordered`), and the
  selection prunes itself on `changeCount` (Select mode ends when it empties); "+" presents
  `NewSceneSheet` and the added scene is revealed (`revealSceneID`: filter cleared, list
  scrolled). No stack, no toolbar: the document infrastructure's bar is the one bar.
- `SearchTab.swift`: the Search tab (#27): a `NavigationStack` for `.searchable` (its
  bar kept, with the mirrored Back and title removed by `navigationBarBackButtonHidden`
  and `toolbar(removing: .title)`, because hiding the bar hides the field; see the header)
  over a `List` of `SceneSearch.results` in two sections, scheduled (each row naming its
  production day and date) and Boneyard; a row's tap opens the scene editor through
  `dayEdits.presentSceneEditor` with the results shown as `siblingIDs`, its
  trailing button, swipe and menu are Show in Days (`showInDays(date)`) or Show in
  Boneyard (`showInBoneyard(sceneID)`), closures `PhoneEditor` wires to the tab switch
  and the two jump bindings. Empty states for a blank query and for no results.
- `SceneSearch.swift`: the filter and the search (#27, `SceneSearchTests`), pure:
  `SceneSearch.matches(_:query:)` (a script scene every whitespace-separated word of the
  trimmed, lowercased query appears in: number exactly or as a prefix, slugline, a cast
  name trimmed, summary, real location; a banner, an auto-meal or an event never; a
  blank query matches every script scene), `filter(_:query:)` (order kept),
  `results(for:in:)` (`SceneSearchResult`: the scene and its `SceneLocation`, scheduled
  first in schedule order then the Boneyard in script order; a blank query finds
  nothing) and `BoneyardSelection.ordered(_:inDisplayOrder:)`, the multi-selection in
  the list's order for Send to Day.
- `NewSceneSheet.swift`: the New Scene form (#27), an adaptive editor over `NewSceneDraft`
  (EditorDrafts.swift): number, slugline (focused on appear), real location with the
  autocomplete field, pages and estimate with the scene editor's hints, and the type
  picker whose default row reads "From slugline · NIGHT" for the slugline as typed;
  Add Scene hands `draft.makeScene()` to the tab. The Mac's `NewSceneInputView` is untouched.
- `BreakdownBrowser.swift`: the Breakdown Browser's pure part (#28,
  `BreakdownBrowserTests`): `BreakdownBrowser(project:)` (every scene once, Boneyard then
  days, sorted by `scriptOrderKey`: the Mac browser's list, banners included), `first`,
  `position(of:)`, `id(before:)`, `id(after:)`, `successor(of:)` (next, else previous,
  for after a delete), `scenes(in:)` (the scenes in that order: the Mac's `ContentView`
  pages through a snapshot of them, `populateBreakdownBrowserScenes`, #35).
- `DaysTab.swift`: the Days list (#24): a `NavigationStack` (its own bar hidden at the root,
  because the document infrastructure's outer bar is the phone's one bar and it mirrors
  its Back and title into any inner bar) holding the week strip (`WeekStrip`; the month
  popover is a graphical `DatePicker` over the production range; one row in compact
  height) above a `List` of the rows `stripboardRows(for:showAllDays: false,
  expandedDayIDs:)` returns: a gap card that expands on a tap and folds back from a
  "Hide empty days" row in any of its cards, and a day card per day (header from
  `DaySummary` as a `NavigationLink(value: day.id)` to `DayScreen`, event chips,
  `PhoneStripRow`s timed by `dayTimeline`). Scrolling to a date is `dayScrollTarget` plus
  `ScrollViewReader`: a date in a collapsed gap opens it and scrolls on the next turn.
  The week strip follows the earliest day header on screen by appear/disappear. A
  long-press drag reorders a strip within its day (`onMove` → `PhoneMoves.reorder`; the
  rows carry no `.draggable`); a cross-day drop is not possible in a sectioned `List`
  (learnings 2026-09-21 #25), so cross-day moves are the strip's Move to Next / Previous
  Day and Send to Day swipe/menu; the day header's long-press menu is
  `phoneDayMenuItems` (`PhoneDayMenus.swift`, with Open Day). The edits (#26) come
  through the same `PhoneStripActions` as the Day screen (a strip's tap opens its
  editor) and `PhoneDayEdits` (an event chip's tap opens the event, its long press is
  `phoneEventMenuItems`); the Stripboard Fields setting is read here (`@AppStorage`),
  decoded once per body and handed to every row and to the Day screen. A day row's
  `index` (from `stripboardRows`) says whether the strips have a previous or next day.
- `DayScreen.swift`: the Day screen (#24), a navigation destination for one day id, read
  from the document on every body (so it follows edits and shows an empty state if the
  day left the range): the header (`DaySummary`, with the day's ⋯ menu,
  `phoneDayMenuItems` without Open Day — Edit Call Sheet…, Add Banner…, Add Event…
  (#26), Add Scenes…, Swap with Day… (#25)), the day type and note, the call sheet card,
  the calendar events and the strips, one `Section`
  per `MARK`. The Strips section reorders with drag handles (`listReordering`/`onMove`
  → `PhoneMoves.reorder`) behind a Reorder/Done toggle, and has Add Scenes… (#25) and
  Add Banner… rows. The edits (#26), through `PhoneDayEdits`: the type is a menu
  `Picker` (one edit per pick), the note a `TextField` written live through
  `editCoalescing` under one `EditGesture` per focus session (the Production tab's title
  rule; the trimmed note is committed as the session ends), Clear Day Type when either
  is set (an emptied day outside the range pickers' range is dropped, the inspector's
  rule); the call sheet card is one `Button` into `CallSheetEditor` with an Export Call
  Sheet PDF row under it (through `PhoneExports`); an event row opens
  `CalendarEventInputSheet`, swipes to Delete and has `phoneEventMenuItems` on its long
  press, with an Add Event… row; a strip's tap opens its editor (`PhoneStripActions.open`).
- `PhoneDayMenus.swift`: the two menus both phone lists build for a day, one
  `@ViewBuilder` each: `phoneDayMenuItems(dayID:moves:dayEdits:openDay:)` (Open Day when
  given, Edit Call Sheet…, Add Banner…, Add Event…, Add Scenes…, Swap with Day…) and
  `phoneEventMenuItems(_:dayID:dayEdits:)` (Edit Event, Delete Event).
- `PhoneStripRow.swift`: the strip both phone lists draw (#24): `PhoneStripRow` (a script
  scene on its `Scene.stripColor(in:)`, with one chip per field of the app-wide
  Stripboard Fields setting that has a value, `visibleFields`, decoded once per list
  body by `DaysTab` and never per row, #26; a banner or auto-meal on the Mac row's rules,
  `Scene.bannerFillHex` / `bannerDisplayLabel`; `rowColor(for:palette:)` for the list row
  behind it), `PhoneEventChip`, `StripPreview` (the long-press preview: number, slugline,
  cast, summary), and `PhoneStripActions` (day, `moves`, `dayEdits`, `openDay`,
  `hasPreviousDay`, `hasNextDay`) with `open(_:)` (the tap: the scene editor, the banner
  input, Set Time for an auto-meal), `stripContextMenu(for:)`,
  `stripLeadingSwipeActions(for:)` and `stripSwipeActions(for:)`, the one place each
  list's tap, menu items and swipe actions are built, applied by
  `stripInteractions(_:scene:)` (`onTapGesture`, `.contextMenu` with the preview, both
  swipe edges with `allowsFullSwipe: false`). #25 put the moves there (Open Day, Move to
  Next Day / Move to Previous Day when the day has that neighbour, Send to Day…, Return to
  Boneyard in the menu; Boneyard, Next Day and Send to Day on the trailing swipe —
  Previous Day left the swipe with #35, four buttons being what a row shows legibly);
  #26 the edits: Edit Scene / Edit Banner, Set Time…, Duplicate Scene and Delete
  Banner in the menu, Edit and Set Time on the leading swipe, Duplicate (a script scene)
  or Delete (a custom banner) on the trailing one. An auto-meal offers Set Time only: a
  deleted one would return at the next sync while its call sheet time stands.
- `BannerAppearance.swift`: how a banner strip looks, pure (`BannerAppearanceTests`, pinned
  to the Mac row's output): `Scene.bannerFillHex` (an auto-meal by its kind; a meal
  banner — by type or by a meal word in its title, English or the fork's Spanish — and
  the legacy amber near black; else its color, else slate) and `bannerDisplayLabel` (an
  auto-meal's icon and kind; else the title without the "(01:00 PM)" suffix, the default
  notice titles folded to "Notice", the fork's bilingual meal titles to their English
  word), with the suffix's `NSRegularExpression` built once. `BannerStripRow` and
  `PhoneStripRow` both call them.
- `PhoneDayEdits.swift`: the day and strip edits the iPhone makes (#26), one
  `PhoneDayEdits` value `PhoneEditor` wires (`edit`, `beginGesture`, `present`,
  `productionRange`, `exportCallSheet`) and hands the Days list, the Day screen, the
  strip actions, the Boneyard tab and the Search tab: `setDayType`, `clearDayType` (with
  the range pickers' range, so an emptied typed day outside it goes), `saveScene` (by
  id, under the gesture so a Duplicate in the same turn folds in),
  `deleteUnscheduledScene`, `duplicateScene`, `saveNoticeStrip` (a banner or event
  replaced in place or appended), `deleteNoticeStrip`, `applyStripTime`, `saveCallSheet`
  (under the gesture, so Export PDF's save and the preview are one step), each one
  `edit` over `DayEdits`; and the editors a list asks for
  (`presentSceneEditor(sceneID:dayID:siblingIDs:)`, `presentBannerEditor`,
  `presentEventEditor`, `presentSetTime`, `presentCallSheet`, `presentEditor(for:dayID:)`
  for a tap), a `PhoneEditSheet` request `PhoneEditor` holds and `phoneEditSheets`
  presents over the editor, so a sheet outlives the row that asked. The content binds
  every editor by id and reads the document each body; `PhoneSceneEditor` is the phone's
  one scene editor: `SceneEditSheet` with Previous / Next over the day's script scenes
  (live) or over the `siblingIDs` a tab supplied (the Boneyard's displayed rows, a
  search's results), Delete as the Mac's sheets do it (a scheduled scene back to the
  Boneyard through `PhoneMoves.returnToBoneyard`, a Boneyard scene deleted) and
  `onDuplicate`; `PhoneEditorUnavailable` is what any of the sheets shows when its
  subject left the project, through `EditorChrome` and `editorContainer`.
- `DayEdits.swift`: the pure part of those edits (#26, `DayEditsTests`): `Scene.duplicated()`
  (the Mac Stripboard's copy: new id, "(Copy)", the same number, lengths, cast, summary
  and breakdown tags, none of the scheduling state; the Stripboard's `duplicateScene` and
  the Boneyard's `duplicateBoneyardScene` call it) and, on `ProjectData`, `setDayType`,
  `setDayNote` (trimmed),
  `clearDayType(forDayID:productionRange:)` (a plain shoot day with no note; an emptied
  day outside the range — one `updateProductionRange` kept for its type, note, event or
  call sheet — is dropped; nil drops nothing; the same on `[ShootDay]` for the
  calendar, with `removeIfEmptyOutsideRange(dayID:productionRange:)`, the prune the
  calendar runs on a day swap's or a band move's source day; the inspector and the
  calendar call both since #35; `pickerRange(start:end:)`, the range pickers' dates as
  whole days, nil while the end precedes the start, the one way every editor builds it),
  `addNoticeStrip` (a banner or event appended; a script scene refused),
  `deleteNoticeStrip` (removed outright, never through the Boneyard — the Mac's Delete
  Banner leaves an invisible banner in `allScenes`), `applyStripTime` (the strip
  replaced in place; a fixed time on the lunch strip is the call sheet's new lunch, with
  the auto-meal sync in the same edit), `saveCallSheet` (the day replaced by id and
  synced) and `duplicateScene(withID:)`. Each returns false or nil and changes nothing
  when its target is gone.
- `QuickTimeEditSheet.swift`: Set Time (#26), the Stripboard's "Set Time…" rebuilt as an
  adaptive form on a `QuickTimeDraft` (`EditorDrafts.swift`): automatic cascade or a
  fixed start, the estimate as two steppers, the old sheet's preview line; Save is
  disabled until a fixed time parses. The same `QuickTimeEditSheet(scene:onSave:onCancel:)`
  the Mac's Stripboard presents (moved out of `StripboardView.swift`).
- `PhoneMoves.swift`: the schedule moves the iPhone makes (#25), one `PhoneMoves` value
  `PhoneEditor` wires and hands the tabs and the Day screen (and #27's Boneyard tab):
  `reorder` (a list's `onMove` offsets → `ScheduleMoves.reorderStrips`), `sendToDay`,
  `moveToAdjacentDay(_:from:_:)` (Move to Next / Previous Day: `ScheduleMoves.adjacentDayID`
  then one `moveScenes` to that day's end), `addScenes`, `swapDays`, `returnToBoneyard`,
  each one `edit` that also runs the auto-meal sync on the days it touched (learnings
  2026-09-20); and the pickers a move needs (`presentSendToDay(sceneIDs:)`,
  `presentSwapDay(dayID:)`, `presentAddScenes(dayID:)`, presented over the editor by
  `phoneMoveSheets` so a sheet outlives the row or Day screen that asked; Send to Day and
  Swap with Day are `SendToDaySheet` in its `.send` and `.swap` modes). The Boneyard tab
  (#27) calls `presentSendToDay` for one scene or the multi-selection.
- `AddScenesSheet.swift`: Add Scenes on the Day screen (#25), an adaptive form: the
  Boneyard as a checklist in display order with an "Add N Scenes" button; the checked set
  is the sheet's `@State` (no draft), placed at the day's end in Boneyard order in one edit.
- `DaySummaries.swift`: the phone's pure summaries (#24, `DaySummariesTests`):
  `DaySummary` (day number from the `productionDayNumbers` table, type, script scene
  count, strip count, eighths, general call as typed or the cascade's start, event count,
  note, call sheet flag, and `label` / `DaySummary.label(dayNumber:date:)`, "Day 3 · Mon
  Nov 2" or the date alone, the one way the phone names a day in a line), `WeekStrip` (the seven days Sunday-first around a date, from
  the Gregorian weekday so the calendar's `firstWeekday` plays no part; each with its
  `ShootDay` or nil, counts, type, today; `weekStart(containing:calendar:)`, the previous
  and next Sundays), `todayTarget(in:now:calendar:)` (today's day, else the next, else the
  last, else nil) and `dayScrollTarget(for:in:expandedDayIDs:calendar:)` (the day id and
  whether it sits in a collapsed gap). Every function takes its calendar.
- `DayTimeline.swift`: the time cascade (#24, `DayTimelineTests`), moved as-is from
  `StripboardView.computeDayTimeline`: `dayStartMinutes(for:)` (ready-to-shoot, else
  general call, else 07:30 AM) and `dayTimeline(for:scenes:)` → `[UUID:
  DayTimelineEntry]` (range, start, end, duration as clock strings). The Stripboard and
  both phone lists call it; calendar events are never passed in.
- `StoryboardFrame.swift`: a storyboard frame's stored bytes (#38, `StoryboardFrameTests`),
  pure, CoreGraphics and ImageIO only: `StoryboardFrame.encode(_:)` (a `CGImage` to JPEG
  at `jpegQuality` 0.8, the long edge capped at `maxLongEdge` 1200 and never upscaled —
  `storedSize(width:height:)`, the short edge rounded — alpha flattened onto white, sRGB,
  equal pixels giving equal bytes), `encode(data:)` (any ImageIO-readable bytes, upright
  by their EXIF orientation, decoded near the target size through the thumbnail call:
  what every frame source calls), `decode(_:)` (decoded at once and kept in a bounded
  `NSCache` keyed by the bytes), `cachedImage(for:)` (the lookup a view body may make)
  and `pixelSize(of:)` (from the properties, no decode). Nothing else writes frame bytes.
- `StoryboardFrameView.swift`: a frame's bytes shown whole (#38): aspect-fit and never
  cropped on a subtle background (letterboxed), a `photo` placeholder with an optional
  caption for nil, empty or unreadable bytes. Greedy: the container gives it its box.
  The body only reads the decode cache; `.task(id:)` decodes new bytes off the main
  actor, so a list of thumbnails never decodes per redraw. Platform-free.
- `ProjectLaunchBackground.swift`: the launch screen's backdrop (#12), moved out of the
  deleted `MinimalProjectEditor.swift` (#24).
- `EditorSelection.swift`: the inspector's selection (#17), pure: `EditorSelection` (`.scene(id:)`
  or `.day(id:)`), `ProjectData.locate(sceneID:)` → `SceneLocation` (Boneyard index or
  day/scene indices), `scene(withID:)`, `dayIndex(forDayID:)`, `pruned(in:)`, which
  drops a selection whose target left the project, the by-id write-back every editor
  bound by id makes (`replaceScene(_:)`, `removeScene(withID:)`, #28) and
  `knownLocations` (the roster plus every real location in use, sorted: every scene
  editor's suggestions; `knownLocations(shootDays:allScenes:productionInfo:)` for the
  Stripboard, which holds the pieces) (`EditorSelectionTests`).
- `EditorPresentation.swift`: the `editorPresentation` environment value (`.sheet` default,
  `.inspector`, set once by the inspector on its content) and `EditorSheetSize`, what an
  editor asks of its sheet, platform-free (the Mac frame's width and height, the iPhone's
  detents, `fitsHeight` for a short editor). `PlatformEditorContainer.swift` (a seam) is
  the `editorContainer(_:)` modifier every adaptive editor applies at its root: the fixed
  frame on the Mac, detents with a drag indicator on the iPhone (by interface idiom, not
  size class: a sheet's own size class is compact on the iPad too), the system's form
  sizing on iPad and visionOS (at the editor's height when it `fitsHeight`), nothing in
  the inspector.
- `EditorChrome.swift`: what every adaptive editor (#19) wraps its `Form` in, platform-free:
  `EditorChrome` (header, the grouped form, a footer button row, on the grouped
  background), `EditorTitle`, `ColorSwatchRow` (the banner's and the event's colors) and
  `FormTextEditor` (a `TextEditor` row with a prompt). The buttons live in the view, not a
  navigation bar, so the inspector column, the sheets and the Mac show them the same way.
  For an editor whose lists push detail pages (#20): `EditorStackTitle` (the title at the
  root; Back and the page's title on a page), `editorStackPage()` (no system Back, no
  system bar) and `EditorRowSummary` (a row that opens a page: title, detail, caption, badge).
- `EditorDrafts.swift`: the editors' drafts (#19), pure: `SceneDraft` (every field of the
  scene editor as strings, validation, `applied(to:)`), `BannerDraft` (`setType`,
  `makeBanner()`; with #26 `init(banner:)` reads an existing banner back and
  `applied(to:)` keeps its id and fixed start, so the input edits too),
  `CalendarEventDraft` (`makeEvent()` keeps an edited event's id), `NewSceneDraft` (#27:
  the Mac's New Scene fields as strings, its validation, an estimate derived from the
  pages when none is typed, and the time of day read off the slugline through
  `FinalDraftParser.TimeOfDay` when the picker is nil, `makeScene()`) and `QuickTimeDraft`
  (#26: the Set Time sheet's fields, the old sheet's seeding and preview, `isValid`,
  `applied(to:)`). A view holds one in `@State` and writes it back as one assignment
  (`EditorDraftsTests`).
  `CallSheetDrafts.swift` (#20): `CallSheetDraft` (a day's call sheet with the pre-fills
  the old sheet made on appear, the location, cast-call and crew-call list mutations,
  `applied(to:)`) and `ProductionSetupDraft` (the setup, the three rosters, a member's
  unavailable ranges, `renamedCharacters(against:)`, `applied(to:)`); rows left blank are
  dropped on write (`CallSheetDraftsTests`).
- The five adaptive editors (#19): `SceneEditSheet` (the scene editor: every sheet and the
  inspector; Previous / Next in the header when supplied; the trash, Cancel and Save
  Changes row, plus a Duplicate Scene button when `onDuplicate` is supplied (#26, the
  phone; nil at every Mac call site); follows an external change to its scene while
  untouched), `DayDetailSheet` (the day detail: day type and note, the actions as rows,
  call schedule, events, scenes; Done), `BannerInputSheet` (add, or edit with
  `initialBanner`, #26), `CalendarEventInputSheet`, `SendToDaySheet` (a `Mode`:
  `.send(sceneCount:)`, the calendar's and the phone's, or the phone's `.swap(excluding:)`).
  Each is `EditorChrome { header } content: { Form(...).formStyle(.grouped) } footer: {
  buttons }` with `.editorContainer(Self.sheetSize)`; the call sites in `CalendarView`,
  `StripboardView`, `ContentView` and the inspector need nothing per platform.
- The shared settings and reports (#21), the same shape with no draft, because each is
  live or read-only: `StripboardFieldsSheet` (the fields picker; writes the app-wide
  `@AppStorage` selection through its binding as each switch flips, so the board behind
  updates live; `FieldToggleRow`, the icon-label-hint switch the month options share),
  `SceneColorSettingsSheet` (one `ColorPicker` row per palette slot, each pick through
  `onSetColor` into the project's palette via `perform`, one undo step per slot),
  `ColorLegendView` (the nine legend rows, the swatches read from the `scenePalette`
  environment so a customized project shows its own colors), `ConflictReportSheet` and
  `ScheduleLockReportSheet` (rows that jump to a date, `ContentUnavailableView` for the
  empty states), `ImportSummaryView` (below) and `MonthPDFOptionsSheet` (the calendar's
  export options, in `CalendarView`). No fixed frames: the sizes are each view's
  `EditorSheetSize`, applied only by the Mac seam.
- The two list editors (#20), the same shape with a `NavigationStack` around the form:
  `CallSheetEditor` (a day's call sheet: the times, hospital, weather, basecamp, the
  day's locations and the notes as sections; the cast calls and crew calls as rows that
  push a page per entry; Export PDF, Cancel, Save at the root, Remove and Done on a page;
  the same initializer the Mac's call sites in `CalendarView`, `StripboardView` and the
  inspector always had) and `ProductionSetupSheet` (the company, the contacts, the lunch
  default; the cast, crew and location rosters as rows that push a page per member, the
  cast member's with the unavailable date ranges; Save reports the character renames
  through `onCharacterRenamed` before its one write).
- `BoneyardListView.swift`: the Boneyard list (strip rows, drag out, drop back, tooltip,
  double-tap editor, context menu) as a view both layouts draw; every action is a closure
  `ContentView` wires to the selection, the sheets and the funnel.
- `ScheduleDrag.swift`: the one typed drag payload every drag on the schedule carries (#18),
  pure: `ScheduleDragPayload` (a `Transferable` on the exported `UTType.cineschedDragPayload`,
  with kinds scenes/day/dayType/calendarEvent, plus `sceneCopies`, the pasteboard's kind
  with the scenes by value, #22), `SceneDropDestination` (a day and a place —
  `.before(sceneID)` or `.end`), `ScheduleMoves.moveScenes` / `.returnToBoneyard`, and
  the iPhone's moves (#25): `reorderStrips` (a list's `onMove` offsets over the strips it
  shows → one `moveScenes`, no-op judged by the shown order), `addScenes` (the checked
  Boneyard scenes in display order to a day's end, through `BoneyardSelection.ordered`),
  `swapDays` (exchange two days' scenes, call sheet, type and note; the day handle's swap
  as a pure function, which the Stripboard's and the calendar's day drops call too, #35)
  and `adjacentDayID(of:_:in:)` with `DayDirection` (the next or previous
  entry of `shootDays`, what Move to Next / Previous Day lands on). All pure over
  `[ShootDay]` and the Boneyard (`ScheduleDragTests`). The
  calendar, the Stripboard and the Boneyard drag with `.draggable`/`.dropDestination` on this
  type (not the 27 reorder container — it crashes beside a heterogeneous drag container, see
  CalendarView's header and learnings.md 2026-09-20); `CalendarView` holds the shared
  `DropIndicatorView`, `DragSessionTracking` and `DropTargetTracking`.
- `ScheduleClipboard.swift`: Copy, Cut and Paste of scenes (#22), pure: the payload's
  pasteboard bytes (`pasteboardData()`, the drag's JSON), `ScheduleClipboard.scenes(copying:in:)`
  (board order, no auto-meals), `payload(copying:in:)`, `destination(for:in:)` (after the
  selected strip, the end of the selected day, or the Boneyard → `PasteDestination`),
  `paste(_:at:into:)` (new ids, everything else as copied, notice strips kept out of the
  Boneyard, returns the new ids) and `remove(_:from:)` (`ScheduleClipboardTests`).
  `ContentView+Clipboard.swift` wires them: `applyClipboard` puts the `PasteboardResponder`
  (a seam) behind the board (with the window's undo manager in the three-column layout,
  for the iPad's undo gestures; nil in the Mac's), every selection calls `focusEditor()`
  so it takes first responder, and `copyPayload` / `cutPayload` / `paste` act on the
  multi-selection or the inspector's scene through `edit` ("Cut", "Paste"); a paste
  selects what it inserted.
- `InactiveDimming.swift`: `dimsWhenInactive(_:)`, the modifier the board and the Boneyard
  carry (#22): `@Environment(\.appearsActive)` (every platform) fades them in a window that
  is not the active one. Enabled in the three-column layout only; the Mac's board is left
  as it was (#1, Out of Scope).
- `AutoMealSync.swift`: `ShootDay.scenesWithSyncedAutoMeals()`, the auto-meal strips
  brought in line with the call sheet's times (pure, `AutoMealSyncTests`). The Stripboard
  runs it when a day section appears and after its own call sheet editor saves; the
  inspector's call sheet editor runs it inside the save's edit, so the strips and the times
  are one undo step and a visible section never lags.
- `InputPress.swift`: which input pressed the board last (#22): `InputKind` (touch, pencil,
  pointer, other), `InputPress` (kind and modifiers; `selectionModifiers` is the click's for
  a pointer, none for a finger or a Pencil), `InputPressRecorder.shared` and the
  `recordsInputPresses()` modifier, which places `PressObserver` (the
  `PlatformPressObserver` seam) in the editor's background (`InputPressTests`).
  `ModifierKeys.current` reads it on iOS and visionOS, so ⌘-click and ⇧-click multi-select
  with a trackpad or mouse there; the Mac keeps polling `NSEvent` and installs nothing.
  Never a SwiftUI gesture at the root: a `simultaneousGesture(SpatialEventGesture())` over
  the editor swallowed every `Button` under it on iPadOS 27 (toolbar toggles, the segmented
  picker, the calendar's buttons). `draggable` and `DragSession` report no input kind on
  27.0; the distinction is made at the press.
- `ContentView+Inspector.swift`: the three-column layout's trailing column: the project
  statistics when nothing is selected, `SceneEditSheet` bound to the selected scene by id
  (Save is one gesture, Cancel and Delete clear the selection), `DayDetailSheet` for the
  selected day with its edits (day type, note, clear, remove or delete an item) and the
  two sheets it opens (`ActiveSheet.calendarEvent`, `.callSheet`).
- `LaunchImportFlow.swift`: the launch screen's imports (#13). `LaunchImportKind` (script or
  legacy project, with the picker's types), `LaunchImport` (the pure steps: parse a script,
  build the new project from the result, read a legacy `.json` through `ProjectCodec`;
  `LaunchImportTests`), `LaunchImportFlow` (the coordinator `makeDocument` awaits: a
  continuation plus the stage the presentation shows, cancelled by throwing
  `CancellationError`, which leaves the launch screen untouched) and the
  `launchImportPresentation` modifier (the `fileImporter`, the summary sheet and the failure
  alert, hung off the New Project button). Platform-free; the Mac compiles it and never runs it.
- `ScriptImport.swift`: what both script imports share: the screenplay content types, the
  dispatch by extension to `FountainImporter` or `FinalDraftParser`, the Final Draft scene
  mapping, and `parse(at:)`, which returns any format as a `FountainImportResult` for the
  summary sheet. The Mac's menu uses the types and the mapping; the launch screen uses all of it.
- `CineSchedFolder.swift`: the iCloud container identifier, the folder's display name and the
  Mac's derivation of where iCloud Drive keeps it (pure, `CineSchedFolderTests`). The Mac has no
  iCloud entitlement (ADR 0006); `MacAppDelegate` seeds the Open/Save panels' last directory
  with that path once the folder exists.
- `ProjectCommands.swift`: the closure slots (and View-menu bindings) a `ContentView` publishes
  for those menus. `WindowPreference.swift`: `@WindowPreference`, per-window view state (Calendar
  vs Stripboard, cast row, times vs pages, all days, grid vs list) seeded from and written back to
  the last-used value; app-wide preferences (Dark Mode, Theme, Stripboard fields) stay `@AppStorage`.
- `ContentView.swift`: the editor for one document (`ContentView(document:layout:)`): the Mac
  window (`EditorLayout.twoColumn`, the default: sidebar, the detail under the window toolbar —
  the Calendar/Stripboard switcher, the Stripboard's Display menu, Share, `.searchable`, the
  stats as the title's subtitle) and
  the iPad and Vision Pro window in regular width (`.threeColumn`: the same sidebar, the
  schedule under a system toolbar, `.inspector` bound to `selection`). One set of state,
  bindings, sheets and lifecycle; two bodies, the Mac's untouched by the iPad's. It reads
  `document.project` and writes only through `edit(_:_:)` or the bindings built on it. There is
  no view model; UI-only state (range-picker dates, selection, sheets) stays `@State`. The
  schedule views take their touch adaptations as parameters (`onSelectDay`, `selectedDayID`,
  the calendar's `minimumCellWidth`), never through `#if os`.
- `ContentView+ScriptImport.swift`: File ▸ Import Script… into the Boneyard (the formats and
  the Final Draft mapping come from `ScriptImport`). `ImportSummaryView.swift`: the import
  summary sheet, the Mac's Done mode after a Fountain import and, given `onConfirm`, the
  launch screen's Cancel / Create Project mode before one.
  `ContentView+PDFExports.swift`: every PDF export call site of `ContentView` (the Mac,
  the iPad, the Vision Pro; the iPhone editor's are in `PhoneExports.swift`): each builds
  a `PDFExportRequest` and delivers it to the Mac's save panel or, where
  `PlatformExportPresentation.previewsExports` (iOS, visionOS), sets `exportPreview` for
  the preview sheet (#23).
- `PDFExportRequest.swift`: the export request (#23), pure: `PDFExportRequest` (kind, file name
  with `.pdf`, the exporter's bytes; `Equatable` by those, `Identifiable` per presentation) and
  `PDFExport`, one function per document (`scheduleCalendar`, `monthCalendar`, `stripSchedule`,
  `shootingSchedule`, `daysOutOfDays`, `breakdowns`, `callSheet`) from the project and the
  per-export parameters to a request, or a `PDFExportError` with the alert's message. The one
  place the exporters are called with the project's values, so every platform gets the same
  bytes (`PDFExportRequestTests`).
- `PDFExportPresentation.swift`: the preview sheet (`PDFExportPreviewSheet`: the PDF, Done, a
  `ShareLink`), the request's `Transferable` conformance (a file under the export name, written
  on demand into the temporary directory) and the `pdfExportPresentation(_:)` modifier
  `ContentView` hangs off its root on every platform. Platform-free; the Mac never presents it.
- `ProjectCodec.swift`: the one encoder/decoder for project files (pretty JSON, ISO dates, legacy
  shapes). Every save and load path uses it; nothing else constructs a `JSONEncoder` for a project.
- `ProjectDocument.swift`: the project document (ADR 0004) on the 27 `Document` protocol, its URL
  reader/writer, the `perform` undo funnel, `ProjectData.newProject` (the File ▸ New template),
  `UTType.cineschedProject` (ADR 0005) and the palette adoption every project entering a
  document passes through (#11; the device overrides are injected, so tests are any device).
  Project open, save, autosave, Open Recent, Duplicate,
  Rename, Move To and Revert To are the document infrastructure's; nothing in the app implements
  them. A legacy `.json` is never edited in place: `LegacyProjectHandoff` (a Mac seam) moves its
  contents to an untitled document and the writer refuses `.json` destinations, because the
  infrastructure autosaves an opened file within seconds and ignores the readable/writable split.
  `.json` is readable only on the Mac (`PlatformDocumentTypes`, a seam): on iOS and visionOS the
  document browser offers exactly the readable types, and a legacy file is imported instead (#13).
- `SceneColorSettings.swift`: `SceneColorSlot`, `ScenePalette` (the project's strip colors, an
  optional field of the file), `SceneColorSettings.deviceOverrides` (the pre-#11 per-device keys,
  read only for adoption) and the `scenePalette` environment key.
- `Models.swift`: all value types. `Scene` doubles as banner, auto-meal, and calendar event via flags.
- `DerivedScheduleState.swift`: everything `ContentView` shows that is computed from the whole
  project (sorted Boneyard, conflict sets, duplicate numbers, lock drift), the `BoneyardSort`
  enum, and the cache that computes it once per `ProjectDocument.changeCount`. Add new
  whole-project derivations here, not as `@State` recomputed in an `onChange`.
- `ProductionRange.swift`: `ProjectData.updateProductionRange`, the range regeneration (merge or
  shift) that Update Calendar applies as one edit; `previewProductionRange` (the same run
  on a copy: the day count, the script scenes it would send to the Boneyard and whether
  everything slides — `shifts`, shift mode on and the start moved — for the phone's
  confirmation, #28) and `productionMonths` (the months the shoot days span, for
  the month export's choice); pure, tested in `ProductionRangeTests`.
- `LegacyWorkingCopyRecovery.swift`: the first-launch decision over the two UserDefaults keys
  the pre-document builds wrote (`SavedProject`, `CineSchedCurrentFileBookmark`): launch
  normally, open the bookmarked file, or open the working copy untitled; pure, one test per
  row. `MacAppDelegate` (a seam) reads the keys, resolves the bookmark, opens through
  `NSDocumentController` in `applicationDidFinishLaunching` and removes the keys afterward.
- `SyncState.swift`: the sync state shown beside the project title (#14): `SyncState` (the
  five displayed states) and `SyncState.derive(from:networkReachable:conflictResolved:)`, a
  pure function of `UbiquitousResourceSnapshot` (the document URL's ubiquitous resource
  values as plain values, with an initializer from `URLResourceValues`); nil for a file
  outside iCloud. The header lists the precedence.
- `ConflictPolicy.swift`: the conflict decision (#15): `ConflictPolicy.decide(current:others:)`
  over `ConflictVersion` values (id, modification date, device name, optional snapshot);
  newest wins, the rest are `resolved`, the loser is `retained` for the notice and the
  Restore other version action.
- `ConflictNotice.swift`: the notice (`ConflictNotice`, with its `origin`: the policy or the
  fallback) and its lifecycle (`ConflictNoticeState`: raised with the change count of the
  resolution, cleared by any other count, by restore or by dismiss), plus
  `ConflictVersion.current(...)`, how the document's own version is dated (last local edit
  while unsaved, the file's date and saving computer otherwise). Pure.
- `ConflictResolutionPlan.swift`: what the wiring does with a decision (#15, ADR 0004's
  2026-09-19 amendment): `ConflictResolutionPlan.make(for:canRegisterEdits:)` says which
  conflict versions are resolved and removed at once (the losers), which one waits for the
  write that carries its contents (the winner's own, `removeAfterWrite`), and returns nil
  when another version wins but no undo manager is attached (nothing is applied or
  resolved then). `PendingConflictRemoval.isDue(writtenChangeCount:)` is the wait. Pure.
- `SyncMonitor.swift`: the wiring of both, one `@Observable` per editor (`@State` in
  `ContentView` and `PhoneEditor`, run by the `syncMonitored(_:document:)` modifier
  at the end of the file: attach the undo manager, start and stop with the view, feed
  `changeCount`, `restoreCount`, `writtenChangeCount` and the scene phase). Reads the
  document URL's resource values on every trigger and on a poll (2 s in iCloud, 10 s
  outside), runs an `NSMetadataQuery` on the file (reports only with the container
  entitlement, so iOS and visionOS) and an `NWPathMonitor` (every platform), and publishes
  `state` and `notice`. Where `PlatformConflictResolution` says the app resolves (iOS,
  visionOS) it lists `NSFileVersion`'s unresolved conflict versions, reads them under a
  coordinated read through `document.makeFileCoordinator()`, applies a winning other
  version through `perform`, follows the plan for the versions (losers resolved and removed
  under a coordinated metadata-only write at once; the winner's own version only once
  `ProjectDocument.writtenChangeCount` says the file holds its contents, the writer's
  `didWrite` report), and retains the loser for Restore other version (through `perform`,
  undoable). The fallback: `ProjectDocument.apply` over unsaved edits records them
  (`replacedUnsavedEdits`), and the monitor turns that into a notice with the edits
  restorable; that is the path that fires on the Mac, where NSDocument's own conflict
  sheet resolves the versions. The header says which path fires where.
- `SyncStateIndicator.swift`: the symbol-and-caption view beside the title (nothing for nil
  state) and `ConflictNoticeView`, the popover with Restore Other Version and Dismiss.
- `CalendarView.swift`, `StripboardView.swift`: the two schedule views.
- `*Sheet.swift`: modal editors. `*Exporter.swift`: PDF generators; every call site is in
  `ContentView+PDFExports.swift` or `PhoneExports.swift`. `PDFCanvas.swift` is the shared drawing helper (CoreGraphics +
  CoreText, no AppKit); all six exporters (`StripboardPDFExporter`, `ShootingSchedulePDFExporter`,
  `PDFExporter` (the month calendar), `CallSheetExporter`, `BreakdownExporter`,
  `DaysOutOfDaysExporter`) draw on it and build everywhere (its header comment is the recipe
  for writing one). `Fountain*`, `FinalDraftParser`, `HighlandArchiveReader`: importers.
- Platform seams (ADR 0003): `FilePanels`, `SelectAllTextField`, `WindowAccessor`, `ModifierKeys`
  (the Mac polls `NSEvent`; the others read the recorded press), `PlatformPressObserver`
  (how that press is recorded: a `UIGestureRecognizer` on the window that reads each
  touch's type and the event's modifier flags in `touchesBegan` and fails at once, so it
  never claims a touch; nothing on the Mac), `PlatformPasteboardResponder` (the first
  responder behind the editor: it answers Edit ▸ Cut, Copy and Paste for scenes with
  `NSPasteboard` or `UIPasteboard` — SwiftUI's `copyable` family needs the focus system,
  which the iPad engages only for a hardware keyboard, #22 — and on iOS carries the
  document's undo manager for shake to undo and the three-finger gestures, which ask
  the first responder, taking the status whenever nothing else holds it through a
  run-loop observer; `undoGestures(_:)` installs it with inert actions at the iPhone
  editor's root, `applyClipboard` hands it the manager in the three-column layout only,
  and the Mac side has no undo duty),
  `PlatformControlStyles` (the Mac-only control styles, `insetGroupedListStyle()`,
  the phone lists' card style that macOS lacks, #24, and the toolbar's
  `windowSubtitle(_:)` and `withoutSharedToolbarBackground()`, which visionOS lacks), `PlatformListEditing`
  (`listReordering(_:)`, the Day screen's edit mode for its strips' drag handles, and
  `listSelecting(_:)`, the Boneyard tab's for its selection circles (#27), both via the
  `editMode` environment key that is `@available(macOS, unavailable)`; nothing on macOS, #25),
  `PlatformTabAccessory`
  (`phoneTabBar(accessory:)`: the iPhone editor's tab bar minimizing on scroll with the
  Today control as its accessory, both iOS-only APIs; nothing on macOS and visionOS,
  whose windows are never compact, #24), `PlatformColors`, `PlatformDocumentTypes`, `PlatformConflictResolution`
  (whether the system presents its own conflict UI: the Mac's NSDocument sheet, so the app
  resolves only on iOS and visionOS), `PlatformInspector` (the three-column layout's
  trailing column: `.inspector` where it exists, a trailing pane on visionOS, which has no
  such modifier), `PlatformExportPresentation` (whether an export opens the preview sheet
  with Share or the Mac's save panel, and PDFKit's `PDFView` wrapped for SwiftUI on each
  view layer), `PlatformEditorContainer` (an adaptive editor's sheet: the Mac's fixed
  frame, the iPhone's detents, form sizing on iPad and visionOS; and
  `editorNavigationBarHidden()`, which hides the bar of an editor's own navigation stack
  where there is one), `LegacyProjectHandoff`,
  `MacAppDelegate`, plus the
  editor/launch-scene choice, the tabbing choice, the Dark Mode menu item (the Mac's
  only) and the delegate adaptor in `CineSchedApp`.
  These are the only files allowed to contain `#if os(...)`.

## Conventions

- **Adding a menu command touches three places**: a closure slot in `ProjectCommands`, the `Button`
  in `CineSchedApp.swift` (calling `commands?.slot()` and `.disabled(commands == nil)`), and the
  slot's assignment in `ContentView.projectCommands`. Do not add `Notification.Name`s for menus:
  a notification reaches every open window. A View-menu toggle for window state is a `Binding`
  slot bound to a `@WindowPreference`, not an `@AppStorage`, or it flips every open project.
  The same `menus` serve the iPad's menu bar (#22): keep them free of platform APIs, and
  never add a Button with ⌘C, ⌘X or ⌘V (it would replace the system's Edit items and take
  them from every text field; scenes answer those through the pasteboard responder).
- **Adding a sheet**: add a case to `ContentView.ActiveSheet` and to the `switch` in `applySheets`.
  Sheets take `@Binding var isPresented` and an `onSave` closure; editors copy the model into local
  `@State` on appear and write back in an explicit save function.
- **Adding or rewriting an editor (#19)**: it is an adaptive form, the same view in every
  container. The fields are a pure draft value in `EditorDrafts.swift` (read from the model,
  validate, write back), tested in `EditorDraftsTests`; the view is `EditorChrome { header }
  content: { Form { … }.formStyle(.grouped) } footer: { Cancel and the primary action, a
  destructive one leading } .editorContainer(Self.sheetSize)` with an `EditorSheetSize`
  (the Mac frame, the iPhone detents, `fitsHeight` for a short one). Save assigns the draft's
  result to the binding **once**. No navigation bar, no `#if os`, no fixed frame in the view:
  the seam sizes the sheet and the inspector shows the form as it is. Labelled short fields
  are `LabeledContent(label) { TextField(...).multilineTextAlignment(.trailing) }` with no
  width cap (a capped field leaves a dead zone in the row on touch); full-width text fields
  carry their label as the `TextField` label and their example as the `prompt`. A list
  whose entries have more fields than a row can show (#20) is a `ForEach` of
  `NavigationLink(value:)` rows (`EditorRowSummary`) inside a `NavigationStack(path:)`
  that wraps only the form, with the page's fields bound by id (never a captured index);
  the header is `EditorStackTitle` (Back and the page's title while a page is up), the
  footer switches to Remove and Done, every page gets `editorStackPage()`, and an Add row
  appends a blank entry and pushes its page, with the draft dropping rows left blank.
  No `.toolbar`, `.navigationTitle` or `navigationBarTitleDisplayMode` in an editor.
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
- **Platform ownership of the document**: one `DocumentGroup` per platform in `CineSchedApp` (a
  seam file), both over `ProjectDocument` made the same way (`.newProject()`, the configuration,
  `SceneColorSettings.deviceOverrides()`). `ContentView`, `ProjectEditor`, `PhoneEditor`
  and the phone's views compile on every platform and must stay free of `#if os`; the Mac
  passes `ContentView` its default layout, the others choose by size class. A per-platform
  difference in what the document reads goes in `PlatformDocumentTypes`, not in `ProjectDocument`.
- **Touch and the inspector (#17)**: a schedule view offers touch affordances through
  optional parameters the Mac leaves nil (`onSelectDay`, `selectedDayID`), not through
  `#if os`; a single tap selects into `ContentView.selection` (scenes through the
  `lastSelectedSceneID` binding, days through `onSelectDay`), a double tap opens the full
  editor sheet, and `.contextMenu` is the long-press menu on touch, so a new strip action goes
  in the context menu and nowhere else. An editor shown in the inspector reads
  `@Environment(\.editorPresentation)` (through `editorContainer`, and for its auto-focus)
  to skip its sheet sizing and its keyboard-raising focus. Per-window
  view state on the iPad (the inspector's visibility) is a `@WindowPreference` like the rest.
- **Drag and drop (#18)**: every drag on the schedule carries one `ScheduleDragPayload`
  (`ScheduleDrag.swift`), never a text encoding, and a drop switches on its kind. Strips,
  the day handle, the day-type band and event chips are `.draggable(payload)`; cells and day
  sections are `.dropDestination(for: ScheduleDragPayload.self)`, with a per-strip drop zone
  for the exact insertion point. A scene move goes through `ScheduleMoves.moveScenes` in one
  `edit`/gesture; a drop back to the Boneyard through `ScheduleMoves.returnToBoneyard`. Do
  not add a `dragContainer`/`reorderContainer`: on 27.0 a drag container captures every
  same-typed plain draggable in the window and the reorder container crashes beside it
  (learnings.md 2026-09-20). Multi-select drags carry `selectedSceneIDs` widened in the
  payload closure; clear drop highlight on exit, on drop and on `dragStateResetToken` (undo).
- **The iPhone editor (#24)**: a tab's view takes the document, what it needs from
  `DerivedScheduleState` and the `edit: ProjectEdit` closure; it never holds the undo
  manager or calls `perform`. A strip's menu item or swipe action goes in
  `PhoneStripActions.stripContextMenu(for:)` / `stripSwipeActions(for:)` and nowhere
  else, so both lists get it. The Days list's rows are `stripboardRows` with
  `showAllDays: false` (never a fork); a Day screen edit is a `Section` there, not a
  sheet of its own. No `navigationTitle` or toolbar on the Days root: the document
  infrastructure's bar is the one bar, and a root toolbar item on `PhoneEditor` lands in
  it. Nothing per row builds a formatter (`formattedDate(_:pattern:)` caches; the
  weekday letter is the `"EEEEE"` pattern). A command the phone answers from the menu
  bar (#28) is a `ProductionCommand` case, a closure in `PhoneEditor.projectCommands`
  that sets it with the tab switch, and a line in `ProductionTab.run`; a write that must
  coalesce across calls under a token the view owns goes through `editCoalescing`, never
  `document.perform`. In a tinted `List` row button, `Color.primary` (the color), not the
  hierarchical `.primary`, which resolves to the tint. A tab that opens the scene editor
  calls `dayEdits.presentSceneEditor(sceneID:dayID:siblingIDs:)` (the phone's one
  `PhoneSceneEditor`, by id), never its own `SceneEditSheet` binding; a phone export
  goes through `PhoneExports`; a rule the Mac applies in `ContentView` that the phone
  needs is a pure `ProjectData` function (`ProductionEdits`, `DayEdits`) with a test, not
  a copy; a banner's fill and label are `Scene.bannerFillHex` / `bannerDisplayLabel`; a
  multi-selection reaches a move in the list's display order
  (`BoneyardSelection.ordered`), never widened from the `Set`; a jump from one tab into
  another is a binding `PhoneEditor` owns (`scrollToDate`, `revealBoneyardSceneID`), set
  with the tab switch and cleared by the tab that acts on it.
- **Colors**: resolve scene colors only via `Scene.stripColor(in:)`, with the project's palette
  (`ProjectData.resolvedPalette`): views read `@Environment(\.scenePalette)`, which `ContentView`
  sets once at its root; an exporter that draws strips takes `palette:` with the project. Nothing
  reads `SceneColorSettings.deviceOverrides` except the document constructors (adoption, #11).
  Exporters must not hardcode strip colors.
- **Adding a PDF export**: a function in `PDFExport` (the exporter call, the file name, the
  failure message) with a `PDFExportRequestTests` row, a `Kind` case with its title, and a call
  site in `ContentView+PDFExports.swift` (which `deliver`s the request) and, for the phone,
  one in `PhoneExports.swift`; never a direct exporter call from a view, and never a
  platform check at the call site (the seam decides).
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
`ShootDay.scenesWithSyncedAutoMeals` (`AutoMealSyncTests`),
`LegacyWorkingCopyRecovery.decide` (`LegacyWorkingCopyRecoveryTests`),
`SyncState.derive` and the resource snapshot (`SyncStateTests`, one per state and per precedence
choice), `ConflictPolicy.decide` (`ConflictPolicyTests`, one per row of the decision),
`ConflictNoticeState`, `ConflictNotice(decision:)`, `ConflictVersion.current`,
`ConflictResolutionPlan`, `PendingConflictRemoval` (against a real document and writer) and the
monitor's pure parts (`SyncMonitor.state(for:…)`, `readSnapshot(of:)` on a local file, the palette
carried across a resolution) in `ConflictNoticeTests`; the document's unsaved-edits record
(`hasUnsavedEdits`, `replacedUnsavedEdits`) and `writtenChangeCount` in `ProjectDocumentTests`. `NSFileVersion`, the
coordinated accesses, the metadata query and the path monitor have no unit seam: they need a
signed-in device (the manual two-device test in issue #15),
`CineSchedFolder` (`CineSchedFolderTests`),
`dayTimeline` and `dayStartMinutes` (`DayTimelineTests`: the default, the precedence, the
cascade, custom starts, the 15-minute default, banners, a zero-length strip, midnight),
`DaySummary` (with its `label`), `WeekStrip`, `todayTarget` and `dayScrollTarget`
(`DaySummariesTests`, in a fixed UTC calendar; the views themselves have no unit seam: the iPhone probe recipe is in
learnings.md 2026-09-21 #24),
`BreakdownBrowser` and the by-id write-back (`BreakdownBrowserTests`: the order across
Boneyard and days with letter suffixes, de-duplication, stepping, the successor after a
delete, replace and remove), `previewProductionRange` (with `shifts`) and
`productionMonths` (in `ProductionRangeTests`; the Production tab's rows, sheets and the
narrow-iPad menu bar have no unit seam: learnings.md 2026-09-21 #28 has the probe,
including how to get a compact iPad window),
`ProjectData.renameCharacter`, `lockSchedule` and `unlockSchedule` (`ProductionEditsTests`),
`Scene.bannerFillHex` and `bannerDisplayLabel` (`BannerAppearanceTests`, pinned to the
Mac row's output before the rules moved),
`EditorSelection`, `ProjectData.locate(sceneID:)`, the pruning and `knownLocations`
(`EditorSelectionTests`),
`ScheduleDragPayload` (round-trip per kind, including multi-scene) and `ScheduleMoves`
(from the Boneyard, within a day, across days, before a strip or at the end, back to the
Boneyard; the iPhone's `reorderStrips` from `onMove` offsets, `addScenes` in display
order, `swapDays` and its inverse, `adjacentDayID`, #25) in `ScheduleDragTests`,
`Scene.duplicated()` and the `ProjectData` day edits (`DayEditsTests`: the Mac's copy
pinned field by field, the type and note, Clear Day Type inside and outside the range, a
notice strip added, replaced and deleted, Set Time with the lunch rule, the call sheet
save with its sync, each refusing a gone target),
`SceneDraft`, `BannerDraft` (reading an existing banner back, `applied(to:)` keeping its
id), `CalendarEventDraft`, `NewSceneDraft` and `QuickTimeDraft` (`EditorDraftsTests`: what each reads,
validation, the value written back, the Custom type's blank-means-none rule, the new
scene's estimate from its pages and its type from the slugline),
`StoryboardFrame` (`StoryboardFrameTests`: images synthesized with a `CGContext`; the
long-edge cap, landscape and portrait, no upscale, the result read back as JPEG, equal
bytes twice, no source metadata, alpha flattened onto white, PNG bytes by the same rule,
an EXIF-rotated JPEG upright, the decode cache by content; the view has no unit seam:
learnings.md 2026-09-23 #38 renders it with `ImageRenderer` in a throwaway test),
`SceneSearch` and `BoneyardSelection` (`SceneSearchTests`: the blank query, every field,
the number's exact-or-prefix rule, cast trimmed and case-insensitive, notice strips never,
the results' order and locations, the selection's display order; the tabs themselves have
no unit seam: learnings.md 2026-09-21 #27 has the probe),
`CallSheetDraft` and `ProductionSetupDraft` (`CallSheetDraftsTests`: every pre-fill on
opening, each list mutation, the character renames reported, every field written back with
the unshown ones carried, an untouched draft writing an equal value, blank rows dropped),
`ScheduleClipboard` (what Copy carries, where a paste lands, what a paste inserts into this
or another project, what Cut removes, the pasteboard bytes against the drag's) in
`ScheduleClipboardTests`, `InputPress` and the recorder in `InputPressTests`; the pasteboard
responder, the menu bar and the dimming have no unit seam (learnings.md 2026-09-20 #22 has
the iPad probe recipe: `typeKey` after a warm-up key, windows tiled through SpringBoard's
Zoom menu), and neither do the undo gestures (learnings.md 2026-09-21, the shake entry:
`simctl spawn <sim> notifyutil -p com.apple.UIKit.SimulatorShake` is Simulator.app's own
Device ▸ Shake, and the alert's buttons are `app.alerts.firstMatch.buttons`),
`ScriptImport.parse`, `LaunchImport` and `LaunchImportFlow` driven through its callbacks
(`LaunchImportTests`: one parse per format, the script → new project step, the legacy `.json`
read against `ProjectCodec` with the source bytes pinned, and every cancellation path),
`DerivedScheduleState` and its cache (`DerivedScheduleStateTests`),
`ScenePalette`, `Scene.stripColor(in:)` and the device-overrides reader (`ScenePaletteTests`; adoption
and per-slot undo are in `ProjectDocumentTests`, the file shape in `ProjectCodecTests`),
`L(_:)` (`LocalizationTests`),
`DaysOutOfDaysExporter.buildRows`, `PDFCanvas`, `ProjectCodec` (`ProjectCodecTests`),
`PDFExport` and `PDFExportRequest` (`PDFExportRequestTests`: each request against its exporter's
output with the PDF's time-derived bytes masked, the file names, the failure messages, the
shared temporary file),
`ProjectDocument` with its reader, writer, type and undo funnel (`ProjectDocumentTests`, against a
real `UndoManager` with `groupsByEvent` off), and all six exporters (rendered from the shared
fixture in `PDFTestSupport.swift` and read back through PDFKit in `SchedulePDFExporterTests`,
`MonthPDFExporterTests`, `CallSheetPDFExporterTests`, `BreakdownPDFExporterTests` and
`DaysOutOfDaysPDFExporterTests`; set `CINESCHED_PDF_DUMP_DIR` to keep the PDFs for a visual
diff, see `PDFTestSupport`'s header). Prefer adding tests there over UI tests. The document
lifecycle itself (Open panel types, Finder association, autosave, the viewer role of `.json`)
has no unit seam; check it by running the app (learnings.md, 2026-09-16 #8 has a recipe that
works without screen access; 2026-09-17 #10 has one for launch behaviour with seeded defaults
under a throwaway bundle identifier; 2026-09-18 #12 has one for the iOS simulator: `simctl openurl` a
`.cinesched` placed in the app's data container, then a throwaway XCUITest that attaches and types;
2026-09-19 #13 has one for the launch screen's imports: seed scripts into the container's Documents,
drive More… ▸ Import Script…, the picker and the summary from a throwaway XCUITest). Any change to
`PDFCanvas` gets the pixel comparison: dump every fixture before and after, rasterize and
diff (learnings.md, 2026-09-16 #6 has the recipe); expectations that depend on the Mac's SF
metrics or wrapping are guarded by `PDFFixture.hasMacSystemFace`.

## Working agreements

- Log anything non-obvious you learn in `learnings.md` (newest first). Promote durable rules here or to an ADR.
- Update `LSVR CineSched/CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- Keep the `.app.zip` bundles, `1024.png`, and other non-source files out of `LSVR CineSched/`; they get copied into the app.
- The `Info.plist` is generated from build settings (`GENERATE_INFOPLIST_FILE = YES`) and merged with the partial
  `Config/Info.plist`, which holds only keys that cannot be `INFOPLIST_KEY_` settings (today the exported
  `.cinesched` type, ADR 0005, the in-app `.drag-payload` type, #18, and the
  `NSUbiquitousContainers` dictionary, ADR 0006). Never put a plist in the
  source folder: it would be bundled as a resource and collide with the generated plist in the flat iOS bundle.
  Version and bundle identifier live in build settings; an iOS-only key is a per-SDK `INFOPLIST_KEY_…[sdk=…]`
  setting. Entitlements are per platform: `LSVR CineSched/CineSched.entitlements` for the Mac (sandbox and
  user-selected files, no iCloud) and `Config/CineSched-iOS.entitlements` for the four non-Mac SDKs (iCloud
  Documents in `iCloud.com.lsvr.LSVR-CineSched`). Any edit to the container keys needs a `CURRENT_PROJECT_VERSION`
  bump before iCloud rereads them. A device build signs only once that container exists on the App ID in the
  developer portal, and Xcode's Signing & Capabilities tab edits the Mac's file, not the iOS one (learnings.md,
  2026-09-19 #12).

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `lightsailvr/LSVR-CineSched`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the root plus ADRs in `docs/adr/`. See `docs/agents/domain.md`.

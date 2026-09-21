# Learnings

A running log of non-obvious things learned while building CineSched. Add an entry whenever
something cost real time, surprised you, or would surprise the next person. Newest first.

Format: date, one-line title, then what happened / why / what to do instead. Keep entries short.
If a learning becomes a rule for the whole codebase, promote it into `CLAUDE.md` or an ADR in
`docs/adr/` and leave a pointer here.

---

## 2026-09-20 — The iPad's menu bar, copy and paste and the inactive window: `@FocusedValue` is nil without the focus system, SwiftUI's `copyable` needs it too, and the first key of a session only attaches the keyboard (#22)

Putting the Mac's `.commands` on the iOS document scene and wiring Edit ▸ Copy/Cut/Paste
for scenes, on the iPad Pro 13-inch simulator:

- **`.commands` shows in the iPad's menu bar and its shortcuts fire, but
  `@FocusedValue(\.projectCommands)` in the `App` stays nil on iPadOS 27** although the
  editor publishes it with `.focusedSceneValue` at its root (a throwaway ⌘8 item logged
  `commands nil = true` with a strip selected and with a text field focused). The focused
  scene value follows the UIKit focus system, which the iPad engages only for a hardware
  keyboard in use, and the menu bar is reachable by touch too. `ActiveProjectCommands`
  is the fallback: an `@Observable` holder in the App's environment (non-Mac only) that
  the editor publishes into on `appearsActive` and retires by owner id, and the menu
  reads `focusedCommands ?? activeProject.commands`. With it every shortcut acts on the
  window (⇧⌘P, ⇧⌘K, ⇧⌘B, ⇧⌘L, ⌘E, ⇧⌘E, ⌥⌘E all verified). ⌘N on the simulator did not
  open a second document; New, Open and Save are the system's items there.
- **SwiftUI's `copyable` / `cuttable` / `pasteDestination` never fired on the iPad**, with
  `.focusable()` and `.focusable(true, interactions: .edit)` plus a programmatic
  `@FocusState` on the editor's root: they hang off the same focus system. What works on
  both platforms is the classic responder: a zero-sized `UIView`/`NSView` behind the board
  that `becomeFirstResponder()`s on every selection (which also ends a text field's
  editing) and answers `copy:`, `cut:`, `paste:` with `canPerformAction` /
  `validateUserInterfaceItem` (`PlatformPasteboardResponder`). The bytes are the drag
  payload's JSON under its own UTI, so `UIPasteboard.general.contains(pasteboardTypes:)`
  enables Paste without reading (no paste prompt; a user-initiated `paste:` reads freely).
  Never add a `Button` with ⌘C to `.commands`: it replaces the system item for text fields.
- **The first hardware key event of a simulator session is swallowed**: with the responder
  in place, the first ⌘C after a tap did nothing and every later ⌘C, ⌘X, ⌘V worked; a
  ⌘Z pressed first (nothing to undo) made the first ⌘C land. XCUITest's `typeKey` attaches
  the keyboard with that first press. Probes start with a throwaway key. `typeKey` does
  deliver menu shortcuts and the edit actions; `.escape` does not dismiss a sheet on the
  iPad (tap Close/Cancel/Done), and the menu bar itself is not in the accessibility tree
  (a swipe from the top edge raised the keyboard, not the bar).
- **`@Environment(\.appearsActive)` is the one active-state value on every platform**
  (`controlActiveState` is the Mac's and deprecated for it): a second window brought to
  front dims the first window's board and Boneyard (`dimsWhenInactive`, opacity 0.55).
  Two iPad windows for the check: iPadOS 27's windowed apps mode is on in the simulator
  (a resize grabber at the bottom-right); the window's dots are at `BackButton.minX - 40`,
  and a 1.2 s press on SpringBoard's `Zoom-button` opens the tiling menu (Left, Right,
  Top, Bottom, Fill, Left and Right, Arrange thirds, Quarters, Enter Slide Over), which
  XCUITest can tap. `simctl openurl` of a second `.cinesched` then opens a second window
  (compact by default, the minimal editor). Dragging the grabber from XCUITest did not
  resize, the default 375 pt window is compact while the half-screen tile (688 pt) is
  regular, and one SpringBoard crash later `simctl erase` was the way back to full
  screen; the app's window layout persists across reinstalls otherwise.
- **The input kind of a drag is not exposed**: `draggable` and `DragSession` carry none
  on 27.0, and `GestureInputKinds` (`TapGesture(count:inputKinds:)`,
  `LongPressGesture(inputKinds:)`, `DragGesture(inputKinds:)`) only filters which inputs
  a gesture accepts. `SpatialEventGesture` (iOS 18) reports each press's `kind` (`.touch`,
  `.pencil`, `.pointer`; `.pencil` is `@available(iOS)` only, so the mapping sits in the
  `ModifierKeys` seam) and `modifierKeys`, so one simultaneous gesture at the editor's root
  records the latest press and `ModifierKeys.current` reads its modifiers on iOS: the
  iPad's ⌘-click and ⇧-click multi-select. It took nothing from the drags: the #18 touch
  probe (Boneyard → day, strip → day, strip → Boneyard, `press(forDuration: 0.5,
  thenDragTo:)`) passed with it in place. The simulator's XCUITest presses are touches, so
  the pointer path is on the device checklist.
- **A `nonisolated` `Hashable` on `ScheduleDragPayload.Kind` holding `[Scene]` warned**
  "main actor-isolated conformance of 'Scene' to 'Equatable' cannot be used in nonisolated
  context" at `<unknown>:0` (the 2026-09-18 #14 note); `Scene: nonisolated Hashable` was
  the one-word cascade, with no further one (its enums' conformances were already fine).
- **`xcodebuild test` needs the runner launched by SpringBoard**; on the Mac it fails
  headless with "System authentication is running" (Automation consent), so the Mac's
  Edit menu path is on the human checklist.

---

## 2026-09-20 — List editors: a `NavigationStack` around the form alone keeps the chrome, the header owns Back, and an XCUITest's `buttons["Back"]` is the window's (#20)

Rebuilding the call sheet editor and Production Setup as forms whose cast, crew and roster
rows push a detail page, verified on the iPad Pro 13-inch simulator through a throwaway
XCUITest (`.dd/I20Probe.swift`, the #19 recipe: `build-for-testing`, terminate, `simctl
install`, `openurl` the fixture, `test-without-building` with `-parallel-testing-enabled
NO`):

- **Wrap only the `Form` in the `NavigationStack`, not the chrome.** `EditorChrome`'s
  header and footer then stay put while a page slides in under them, so Back lives in the
  header (`EditorStackTitle`) and the footer switches to Remove / Done. That is also what
  makes it platform-free: the Mac draws no navigation bar inside a sheet (a pushed page
  there would have no Back at all), and on iOS the bar is hidden through the seam
  (`editorNavigationBarHidden`, `.toolbar(.hidden, for: .navigationBar)`; the placement
  does not exist on macOS) so the document infrastructure cannot mirror its own Back
  into it (#23) and the two never double up. `navigationBarBackButtonHidden(true)` is
  cross-platform and goes on every page as well.
- **A form sheet on iPadOS 27 with a hidden bar and a stack inside sizes itself normally**
  (`presentationSizing(.form)` unchanged); the push animation runs inside the sheet.
- **`app.buttons["Back"].firstMatch` in the probe hit the window's mirrored Back**, not the
  editor's, and dismissed the sheet (the editor is a sheet over a `NavigationSplitView`
  whose columns all carry a mirrored Back, 2026-09-20 #17). The header's Back carries
  `accessibilityIdentifier("EditorStackBack")` for that; label-only queries are ambiguous
  in a document window.
- **`simctl` tests write into a clone.** `xcodebuild test` on the iPad ran on "Clone 1 of
  iPad Pro 13-inch (M5) #20" and the fixture the test wrote into the app's Documents
  vanished with it; `-parallel-testing-enabled NO` keeps the run (and the file) on the
  named device. The device is shut down when the run ends; boot it again before
  `get_app_container` or `openurl`.
- **The keyboard stays up after typing into a form row** and the sheet shifts to keep the
  field visible, so a swipe on the app hits the wrong scroll view; tap
  `app.keyboards.buttons["Hide keyboard"]` (the iPad's dismiss key), then swipe the
  form's own `collectionViews.firstMatch` with `.slow` velocity (a fast swipe scrolled
  past the rows, and rows off-screen are not in the tree).
- **The one-step undo held**: a lunch time typed in the Stripboard's call sheet editor
  moved the auto LUNCH strip (01:00 PM → 02:15 PM, the header's meal time with it), and
  one Undo restored both with Undo then disabled; the Stripboard's `onSave` sync writes
  in the gesture the binding's write opened, as before.
- **`CastMember`, `CrewMember`, `Location` have a `let id` minted in `init`**, so a draft
  cannot reconstruct one with an old id; the pages bind by looking the id up on every get
  and set, and a removal under an open page reads back as a blank placeholder until the
  pop. `renamedCharacters(against:)` matches the roster by those ids, so a member added
  and named in the same session is never a "rename".

---

## 2026-09-20 — Settings and reports as forms: a live editor needs no draft, a `Toggle` row's label is not a tap target on iOS, and `ViewThatFits` keeps a five-button footer a row on the Mac and a menu on a phone (#21)

Rebuilding the Stripboard fields picker, Customize Scene Colors, the Color Legend, the
conflict report, the Schedule Lock Report, the import summary and the Month PDF Options
on the #19 chrome (`EditorChrome` + `editorContainer`), verified on the iPad Pro 13-inch
simulator through a throwaway XCUITest (`.dd/I21Probe.swift`, the #19 recipe) and the
Vision Pro and Mac unit suites:

- **Not every adaptive editor has a draft.** The #19 rule (draft in `@State`, one
  assignment on Save) is for editors with a Save. These seven are live (every switch or
  color pick writes at once, through `@AppStorage` or `perform`) or read-only (the
  reports, the legend, the summary), so the view binds straight to what it was handed
  and the chrome, the grouped `Form` and `editorContainer` are the whole change. Nothing
  new in `EditorDrafts.swift`; no new pure logic, so no new tests, only the existing ones
  (the palette's per-slot undo in `ProjectDocumentTests`, `LaunchImportTests`).
- **A `Toggle` row in an iOS grouped form flips only on the switch control**; a tap on
  its label does nothing, as in Settings. XCUITest's `tap()` on the combined `Switch`
  element (the whole row, 548 pt wide) landed on the label twice and changed nothing;
  `coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()` hits the control.
  The live update behind the sheet is checkable from the tree: the strip's "Downtown
  Tower" chip is absent before the flip and present after it.
- **`ViewThatFits(in: .horizontal)` with the full button row first and a `Menu` of the
  bulk actions second** is a footer that stays the Mac's four or five buttons where they
  fit and folds to one menu where they do not, with no `#if os` and no size class. The
  chrome's 20 pt side padding is 4 pt more per side than the old sheets' 16, so the Month
  PDF Options row (five bordered buttons) went from "fits at 520" to borderline; that
  sheet's Mac frame is 560 wide rather than trusting the fallback.
- **`ContentUnavailableView` inside a `Section` with `.listRowBackground(Color.clear)`**
  is the empty state for a report in a grouped form (no conflicts, no lock, no changes):
  the system's placeholder, centred in the sheet's content area on the iPad.
- **The launch screen's summary sheet loses its `.presentationSizing(.form)` at the call
  site**: `editorContainer` applies the form sizing on iPad and Vision Pro (and detents on
  iPhone) itself, and a second `presentationSizing` on the presenting side would fight it.
  The Mac branch of the seam never runs there (the Mac compiles the flow and never shows
  it), so `EditorSheetSize(width: 460, height: 460)` is the Mac's Done-mode frame only.
- **`ColorPicker(label, selection:)` as a form row** is the native per-slot editor on every
  platform: a labelled row with the well at the trailing edge on iPad and Vision Pro, a
  label with a color well on the Mac; the `Binding<Color>` over `palette.color(for:)` and
  `onSetColor(slot, hex)` is unchanged, so the per-slot undo gesture in `ContentView` and
  its tests are untouched.
- **`app.launch()` from the probe lands on the launch screen** (the document is not
  restored), which is what the import summary needs; the #13 picker path (`DOC.sidebar.item.On My iPad`
  ▸ `CineSched, Container` ▸ the file's cell by label) still holds on 27.0, and Cancel on
  the summary leaves the launch screen as it was.

---

## 2026-09-20 — Adaptive editors: a sheet's own size class is compact on the iPad, a fitted form sheet collapses around a `Form`, and a width-capped field is a dead zone on touch (#19)

Rebuilding the scene editor, the day detail, the banner and calendar event inputs and Send
to Day as one grouped `Form` per editor, shown in the iPad inspector, the iPad's sheets and
the Mac's sheets, verified on the iPad Pro 13-inch simulator through a throwaway XCUITest
(`.dd/I19Probe.swift`, run with `test-without-building` against the app `openurl` opened;
the #17 recipe):

- **`horizontalSizeClass` read inside a sheet on the iPad is `.compact`**, whatever the
  window's. The first container seam chose detents for compact and form sizing for
  regular, and every iPad sheet took the detents branch (the `[.medium, .large]` event
  sheet came up as a half-height bottom sheet). The seam tells the iPhone apart by
  `UIDevice.current.userInterfaceIdiom == .phone` instead; the size class is the wrong
  signal for "which device is this sheet on".
- **`presentationSizing(.form.fitted(vertical: true))` around a `Form` collapses to the
  chrome alone**: a form is a scroll view with no intrinsic height, so the fitted sheet
  showed the title and the buttons with nothing between. The short editors (event,
  banner) keep the fitted form width and give the content an explicit `frame(height:)`,
  the same number the Mac's frame uses (`EditorSheetSize.height`, `fitsHeight`). Plain
  `.form` works for the tall editors but leaves half a sheet empty under a short one.
- **iPadOS 27 honours `presentationDetents` on a sheet**: `[.large]` looked like a form
  sheet with a drag indicator, `[.medium, .large]` a bottom sheet. Do not rely on
  "detents are ignored on the iPad" from earlier releases.
- **A `TextField` capped with `.frame(maxWidth:)` inside `LabeledContent` reports the whole
  trailing area as its frame but takes touches only in the cap.** XCUITest's tap at the
  element's centre focused nothing (twice), while a tap at the trailing edge did; a finger
  in the row's empty middle would do the same. Uncapped, trailing-aligned text fields fill
  the row and any tap in the content area focuses them.
- **Save writes the scene once now.** The old scene sheet assigned ~30 properties through
  its `Binding<Scene>`, i.e. ~30 `perform`s (thirty change counts, one undo step only by
  the window's run-loop grouping); the draft's `applied(to:)` assigned once is one
  `perform` by construction, which the probe confirmed: Save, one Undo, the Boneyard row
  back to its number and Undo disabled.
- **An inspector editor that ignores changes to its scene shows stale fields after an
  undo.** The old populate-on-id-change rule left "777903" in the inspector after the undo
  restored "903" in the Boneyard. The editor now follows a change to the same scene while
  its draft equals the previous scene's draft (nothing typed), and never replaces typing.
- **The `XCUIScreen` screenshot of a landscape iPad comes out upright** in this run (2064 x
  2752 pixels, but the framebuffer already rotated); `sips -Z 1200` for reading was enough,
  no `-r 270`. `simctl clone` refused the booted iPad again; `simctl create` with the
  12GB M5 device type and the 27.0 runtime is the equivalent.
- **The probe file breaks the Mac `test` action**: `XCUIDevice.orientation` does not exist
  on macOS, and `xcodebuild test` builds the UI test target too. Move the probe out of
  `LSVR CineSchedUITests/` (a synchronized folder) before a Mac test run.

---

## 2026-09-20 — Typed drag and drop: the 27 reorder container crashes beside a heterogeneous drag container, and a same-typed drag container captures every plain draggable in the window (#18)

Replacing the three `NSString` drag encodings and the two `DropDelegate`s with one
`Transferable` payload (`ScheduleDrag.swift`), on the iPad Pro 13-inch simulator:

- **`reorderContainer(for:in:)` + `reorderable(collectionID:)` is the API the spec names for
  strips within and across days, and it crashes at lift when the same view also needs a
  heterogeneous drag container.** A reorderable strip must still leave its container two
  ways the reorder API cannot express — out to the Boneyard, and the day handle and the
  day-type band, which are not strips — so those need a `dragContainer(for: ScheduleDragPayload.self)`
  / `dropDestination`. With both present, lifting a reorderable strip trapped in
  `SwiftUI.DragContainerStorage.payload(for:)` (`EXC_BREAKPOINT`, a `preconditionFailure`),
  because a reorderable item is not a registered *item* of that drag container. Apple's own
  example unifies the type (reorder, drag and drop all `for: Account.self`); a heterogeneous
  payload can't. Fell back to `draggable`/`dropDestination` for the strips, as the brief
  sanctions: each strip is `.draggable(payload)`, a thin `.dropDestination` before each strip
  gives the exact insertion point (`.before(sceneID)`, by id so a concurrent move can't
  invalidate an index), and a `DropIndicatorView` marks the target — the pre-27 structure,
  with the payload swapped from `NSString` to the typed value.
- **A `dragContainer(for: T.self)` captures every plain `.draggable(T)` in the same window,
  not just its own container's items.** The Boneyard first used the drag container with
  selection the spec asks for (`dragContainer` + `draggable(containerItemID:)` +
  `dragContainerSelection`), which worked for the Boneyard's own rows — but then *lifting a
  schedule strip* (a sibling subtree, a plain `.draggable(ScheduleDragPayload)`) crashed in
  the same `DragContainerStorage.payload(for:)`, because the container claimed it by payload
  type and had no item id for it. So the Boneyard is plain `.draggable` too, widening to the
  multi-selection in the payload closure; no `dragContainer` survives anywhere. If a later
  ticket wants the drag-container API, every draggable of that payload type in the window has
  to be a container item of it, or the types have to differ.
- **`draggable`/`dropDestination(for:)` moved to a `CodableRepresentation` payload need
  `import CoreTransferable` in the test file** (`exported(as:)` / `init(importing:)`), and the
  `Transferable` conformance itself must be `nonisolated extension` — an extension does not
  inherit the value type's `nonisolated`, so the conformance otherwise "crosses into main
  actor-isolated code" (a warning now, an error in Swift 6; same shape as the 2026-09-19 #15
  `ConflictVersion` note).
- **A second exported UTI goes in the same `Config/Info.plist` block as the project type**
  (`com.lsvr.cinesched.drag-payload`, conforming to `public.data`, no filename extension so
  nothing on disk is ever of that type). It resolves at runtime the same way — a test
  `#require(UTType("com.lsvr.cinesched.drag-payload"))` passes on Mac and simulator.
- **The touch-drag probe recipe (extends 2026-09-17 #10 / 2026-09-20 #17):** `press(forDuration:
  thenDragTo:withVelocity:.slow, thenHoldForDuration:)` performs a touch drag, but a **1.0 s**
  press opens the strip's `.contextMenu` before the lift fires; **0.5 s** lifts cleanly. The
  day-grip handle is a real element — an `Image` with `identifier: "line.3.horizontal", label:
  "Drag"` — so target it by identifier and filter by frame, not by a pixel offset from the date
  (which missed). Attach to the already-open document with `activate()`, dismiss any menu a
  prior probe left open by tapping the month title, and rotate the portrait framebuffer with
  `sips -r 270`.

---

## 2026-09-20 — PDF export on the iPad: a `Transferable` file names the share, PDFKit's view previews on visionOS, and the document's Back button is mirrored into a sheet's bar too (#23)

Building the preview sheet with Share over the existing exporters:

- **`ShareLink` on a `Transferable` with a `FileRepresentation` is what puts the file name
  in the share sheet** ("The_Long_Way_Home_StripSchedule.pdf" in its header, in Save to
  Files and as the attachment); a `DataRepresentation` shares nameless "PDF document"
  bytes. The exporting closure writes the bytes into
  `temporaryDirectory/PDFExports/<request id>/<name>` on demand, so nothing is written
  before the user taps Share and two exports of the same document never collide.
  `Transferable` requires `Sendable`, and a conformance declared in another file than the
  struct warns ("conformance to 'Sendable' must occur in the same source file"): the
  request declares `Sendable` where it is defined and is `nonisolated`, with the one
  main-actor member (`Kind.title`, which calls `L()`) marked `@MainActor`.
- **PDFKit's `PDFView` renders on the visionOS simulator inside a `UIViewRepresentable`**,
  the same wrapper as the iPad's; the share sheet there lists Copy, Markup, Print, Save
  to Files and More. Quick Look was the alternative and takes a file URL, owns its
  toolbar and opens in its own window on visionOS, so the app's Done and Share would
  have been lost. `.presentationSizing(.page)` makes the sheet page-sized on iPad and
  Vision Pro (the default form sheet shows a letter page at a third of its width) and
  is full-screen in compact width. The share sheet's thumbnail is blank in the
  simulator (no thumbnail service); the `SharePreview` image is only the fallback icon.
- **The document infrastructure mirrors its Back button into a sheet's navigation bar
  as well**, not just into every split-view column (2026-09-20 #17): the preview's
  `NavigationStack` showed a chevron beside Done. Unlike in the columns,
  `.navigationBarBackButtonHidden(true)` does remove it in a sheet.
- **Presenting the preview while another sheet dismisses works without a delay** on the
  27.0 iPad simulator: the month options sheet, the Day Detail sheet and the call sheet
  editor each dismiss themselves and call the export closure synchronously, and the
  root's `.sheet(item:)` still presents (SwiftUI queues the presentation). Nothing to
  defer.
- **Two renders of one PDF differ only in `/CreationDate`, `/ModDate` and the trailer
  `/ID`** (2026-09-19 #32's 74 bytes), and Quartz breaks the line *between* the date key
  and its value, so a mask that expects `/CreationDate (` never matches: match `\s+`.
  `PDFExportRequestTests` pins each request to its exporter's output through that mask,
  and a self-check test asserts the mask actually hit both dates and the ID.
- **Probing the iPad's export paths from a throwaway XCUITest**: the toolbar `Menu`'s
  items are `app.buttons["Strip Schedule…"]`, `ShareLink`'s button is labelled "Share…",
  the calendar's "Export Month (PDF)" button is hidden beside the inspector in portrait
  (rotate with `XCUIDevice.shared.orientation = .landscapeLeft`, iOS only), and
  `app.staticTexts["2"].firstMatch` is the inspector's "2 unscheduled", not the day
  cell: pick the match with the smallest `frame.minY`. On visionOS the toolbar's
  buttons (an ornament) are absent from the app's accessibility tree, so the Export
  menu there can only be checked by eye; the calendar's own button reaches the same
  sheet. The Stripboard day header's icon buttons read "Plain Text Document", "Plus
  Rectangle On In A Rectangle" and "Next Page" to accessibility (their `.help` is not a
  label); tap them by SF Symbol identifier (`arrow.down.doc`). Worth a label pass in
  the polish milestone.

---

## 2026-09-20 — The iPad's three columns: a principal toolbar item becomes the document's title menu, the calendar needs its cells narrower than the Mac's, and an XCUITest probe attaches to whatever build is running (#17)

Building the three-column editor (`ContentView(layout: .threeColumn)` with `.inspector`)
on the iPad Pro 13-inch simulator:

- **One `ContentView`, two bodies, not a second editor.** The Mac's editor owns every
  piece the iPad needs (the funnel, the bindings, the sheets, the alerts, the commands,
  the sync monitor), and none of it can live in a view model without a rewrite. So the
  layout is a parameter, `body` is `if layout == .twoColumn { twoColumnBody } else {
  threeColumnBody }`, and the Mac branch is the old body verbatim. The pieces both draw
  are factored out where that was mechanical (`BoneyardListView`, `scheduleContent`).
- **A `.principal` toolbar item inside a `DocumentGroup` on iPadOS is wrapped in the
  document title's menu.** The accessibility tree showed the segmented picker *inside* a
  `StaticText 'The Long Way Home'`, and an XCUITest tap on the "Stripboard" segment opened
  the Rename / share popover instead of switching views (twice, with and without a
  `navigationTitle` on the column). `.navigation` placement (leading) is free of it.
  The infrastructure also mirrors its Back button and title chevron into every column's
  bar of a `NavigationSplitView`; `navigationBarBackButtonHidden(true)` does not remove
  the mirror, and `.toolbar(removing: .title)` removes the principal item along with the
  title, so both are left alone (the mirrored Back closes the document, harmlessly).
- **The month grid does not fit three columns at the Mac's minimum.** Seven columns of
  `GridItem(.flexible(minimum: 100))` need 780 pt; a 13-inch iPad in landscape is 1376 pt,
  and a 300 pt sidebar plus a 380 pt inspector (the width the scene editor's button row
  needs as it is) leave ~700. The grid then centres and clips both edges rather than
  shrinking, so the minimum is a parameter (`minimumCellWidth`, 100 on the Mac, 72 on the
  iPad). At that width the day-cell header truncates its "Day N" badge and the month row
  its buttons; `fixedSize()` on the badge made the whole cell overflow its column, so it
  is `lineLimit(1)` + `minimumScaleFactor`, and the user collapses a column for full
  cells. The badge and the month row want a narrow-width pass (polish milestone).
- **The scene editor's auto-focus raises the keyboard on every tap in the inspector**
  (`focusDurationField` on appear), and the keyboard then squeezes the sidebar, a fixed
  `VStack`, into the space above it. The focus is gated on `editorPresentation`, and the
  sidebar column gets `.ignoresSafeArea(.keyboard, edges: .bottom)`.
- **`SceneEditSheet` closes itself after Save as well as Cancel.** In the inspector the
  `isPresented` binding maps "false" to "clear the selection", which would empty the
  inspector on every Save; `onSave` sets a one-shot flag the next close consumes. The
  binding's scene is looked up by id on every get and set (`ProjectData.scene(withID:)`,
  `locate(sceneID:)`), never by a captured index, so a delete or a drag under the open
  editor cannot index out of range; the ~30 writes of one Save fold into one gesture.
- **`xcodebuild test` does not restart an app that is already running**, and the probe's
  `activate()` attached to the *previous* build twice (the state, the typed text and the
  old layout were all still there). Terminate, `simctl install` the new bundle, `openurl`
  the fixture, then `test-without-building` (`.dd/reopen.sh` was the throwaway helper).
  `XCUIScreen.main.screenshot()` in landscape writes the portrait framebuffer; `sips -r
  270` turns it upright. `simctl clone` refuses a booted device (another agent had the
  iPad booted); `simctl create` with the same device type and runtime is the equivalent.
- **Long press.** `.contextMenu` is the long-press menu on iOS with no change: the
  strips', the event chips' and the day header's menus all opened from
  `press(forDuration:)` in the probe. Except through a `Button`: a long press on the
  day cell's date `Button` fired the button on release and never showed the header's
  menu, so with an inspector the date is a label with `onTapGesture` (the Mac keeps the
  Button). An XCUITest `press` on an element the layout truncated to zero width (the
  weekday beside a narrow cell's badge) hangs the run in "scroll to visible"; press a
  neighbour or a coordinate instead.

---

## 2026-09-19 — Conflict versions after review: a `perform` is not a write, the writer is where "written" is known, and an extension does not inherit `nonisolated` (#15)

Applying the review of the #15 wiring (ADR 0004, amendment of 2026-09-19):

- **A `perform` puts the winner in memory only; the file follows on the next autosave,
  and never when the undo manager was nil.** The first wiring marked and removed every
  conflict version right after the `perform`, which left up to a minute (iOS) in which the
  winning contents existed nowhere on disk, and forever when no manager was attached (a
  `perform` without one registers nothing, and the infrastructure autosaves only from
  registered actions). Now the losers go at once, the winner's own version waits for the
  write, and a nil manager defers the whole decision (`ConflictResolutionPlan`).
- **`snapshot(contentType:)` is not the write.** It is the infrastructure asking for the
  bytes; the atomic write happens afterwards in the `@concurrent` writer and can throw and
  be retried. The document learns that the bytes landed from the writer itself:
  `ProjectDocumentWriter.didWrite`, a `@MainActor @Sendable` closure the document hands
  its writer in `writer(configuration:)` (a `@MainActor` closure is Sendable by isolation,
  so the nonisolated writer can hold it and `await` it after the write). That is what
  `writtenChangeCount` follows; `hasUnsavedEdits` keeps following the request.
- **The winner's version is left unresolved, not merely unremoved, until the write.** The
  header's "set `isResolved`, then remove" reads as one step, but marking the winner
  resolved before its contents are in the file would, on a kill, leave them in a version
  the system no longer reports and the app never looks at; left unresolved, the next
  launch re-lists it and the policy applies it again. The monitor skips the pending
  version on re-checks (by `url`) so it is not decided twice, and re-lists at removal time
  rather than trusting the earlier object, in case another presenter resolved it meanwhile.
- **`extension ConflictVersion { static let currentID }` was main-actor isolated even
  though the struct is `nonisolated`**: an extension's members take the default isolation,
  not the type's modifier, and the read from the new `nonisolated` plan warned ("main
  actor-isolated static property can not be referenced from a nonisolated context"). Mark
  such members `nonisolated` themselves.
- **`UndoManager` is not `Equatable`**, so a view cannot `onChange(of: undoManager)`;
  `onChange(of: undoManager.map(ObjectIdentifier.init))` follows the environment's
  manager by identity, which is what the `syncMonitored` modifier uses to re-attach.
- The template XCUITests (`testExample`, `testLaunch`, `testLaunchPerformance`) fail in an
  agent shell with "Failed to activate application" (no screen); the unit target is what
  to read the totals from.

---

## 2026-09-19 — Signing the iOS build for a device: automatic signing never creates the iCloud container, and Xcode's capabilities tab edits the Mac's entitlements file (#12)

Getting the first device build of the iPhone/iPad app to sign, with the per-SDK entitlements
of ADR 0006 in place:

- **Automatic signing turns the iCloud capability on for the App ID but never creates an
  iCloud container.** So a device build fails with "Provisioning profile … doesn't match the
  entitlements file's values for the com.apple.developer.icloud-container-identifiers and
  com.apple.developer.ubiquity-container-identifiers entitlements" until the container
  `iCloud.com.lsvr.LSVR-CineSched` exists in the developer portal *and* is ticked on the
  App ID `com.lsvr.LSVR-CineSched`. Nothing in the repo can do that step.
- **Xcode's Signing & Capabilities tab edits the base `CODE_SIGN_ENTITLEMENTS` file**, the
  Mac's `LSVR CineSched/CineSched.entitlements`, not the per-SDK
  `Config/CineSched-iOS.entitlements`. Ticking the container there wrote the iCloud keys into
  the Mac's file (twice, once per tick), which would have given the Mac build the entitlement
  ADR 0006 keeps it free of; reverted with `git checkout -- "LSVR CineSched/CineSched.entitlements"`.
- **What worked**: tick the container in the tab's iCloud section anyway, because that is what
  creates it in the portal and assigns it to the App ID; rebuild for the device; then revert
  the Mac's entitlements file as above. The iOS file already named the container and needs no
  edit. Check the Mac build afterwards (`codesign -d --entitlements - --xml`, no `icloud` or
  `ubiquity` key).
- **Reading what a profile actually grants**: `security cms -D -i <profile> | plutil -p -`
  prints its plist, `Entitlements` included; the profiles Xcode downloaded live in
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles`. That is how to tell "the App ID
  lacks the capability" (the 2026-09-18 #12 entry) from "the capability is on but the
  container is not" (this one) without another build.

---

## 2026-09-19 — Launch-screen imports: the creation source reaches `makeDocument`, `prepareDocumentURL` never runs, a throwing `makeDocument` is a silent no-op, and a sheet presents from the launch scene's actions (#13)

Adding Import Script… and Import Project… to the iOS/visionOS `DocumentGroupLaunchScene`:

- **`NewDocumentButton(_:contentType:source:prepareDocumentURL:)` is the SDK's documented
  hook for "present a picker, return a prepared document URL, or throw on cancellation", and
  the 27.0 launch scene never calls it.** Traced on the iPhone 17 and iPad Pro simulators,
  with the button folded into the More… menu and as a directly visible action: the closure's
  first line never logged, while `makeDocument` ran with `context.creationSource` set to the
  button's source and `configuration.fileURL` = `<container>/tmp/Untitled.cinesched`. So the
  source is the only thing that arrives, and the flow has to live in `makeDocument`, which is
  `@MainActor async throws` and may await a continuation for as long as the picker and the
  summary take. Do not move it back to `prepareDocumentURL` without re-tracing on a newer SDK.
- **A `makeDocument` that throws leaves the launch screen exactly as it was**: no document,
  no file in Documents (the system creates in `tmp/` and moves after `makeDocument` returns),
  no alert. Observed for `CancellationError` on the iPad; the same for a picker cancel, a
  summary cancel and a dismissed failure alert on both simulators. That is what makes
  "cancelling leaves nothing behind" free: every cancellation is one throw.
- **How the system creates from a source**: `makeDocument(source: importScript, url:
  tmp/Untitled.cinesched)` → the snapshot is written there → the file moves to
  `Documents/Untitled.cinesched` → a second `makeDocument(source: nil, url: Documents/…)` and
  the reader/`apply` load it. The project handed to the first document is what lands in the
  file; the name is always "Untitled" (no API names it), which the user renames in the title
  bar.
- **A `fileImporter` and a `.sheet` hung off a `NewDocumentButton` in the launch scene's
  actions present fine while `makeDocument` is suspended**, on iPhone and iPad, including
  when the tapped button was a More… menu item: the launch screen stays up until the closure
  returns. The modifier needs a view to hang on; the New Project button is that view. The
  launch scene shows two actions and folds the rest into More… on every width, iPad too.
- **`fileImporter`'s `isPresented` binding is cleared before `onCompletion` arrives**, so a
  setter that treated "false" as a cancel raced a successful pick. The flow defers the check
  one run-loop turn (`pickerDismissed`) and lets `onCompletion` / `onCancellation` decide.
- **`ImportSummaryView`'s Mac frame (`.frame(width: 460, height: 460)`) does not fit an
  iPhone sheet**; in the confirmation mode the frame is nil and the sheet takes
  `.presentationSizing(.form)`, which is a form sheet on iPad and full-width on iPhone.
- **Driving the launch screen from a throwaway XCUITest** (the #12 recipe, extended): the
  More… menu's items exist twice in the tree (the hidden originals at 20 pt tall and the
  menu's items at 38 pt), so match by label and take the widest; the picker's Cancel is
  `app.buttons["Cancel"]` (label, not identifier), the sidebar row is
  `app.cells["DOC.sidebar.item.On My iPad"]` (on iPhone tap the picker's own Browse tab
  first, the last "Browse" match) and the app's folder is `app.cells["CineSched, Container"]`;
  a predicate on `label == 'CineSched'` hits the launch title behind the picker and dismisses
  it. Every `simctl install` migrates the app's data container to a new UUID (the files
  survive); re-query `get_app_container` after installing, not before. `simctl launch` on
  a warm app resumes the previous state, so terminate first to land on the launch screen.
- **`BreakdownPDFExporterTests/breakdownPrintsOneSheetPerSceneInScriptOrder` fails on the
  iPhone 17 simulator at the branch tip (`6c329fb`), before this change**: PDFKit's text
  extraction there joins "1" and the title ("SHEET #\n1 The Long Way HomeSCENE #"). It
  passes on the Mac; not touched here. (Fixed afterwards, #33: the PDF is the same on
  every platform, only PDFKit's extracted-text layout differs, so a pin that ends a cell
  with `\n` is Mac-only. The test now matches `SHEET #\n1` followed by any whitespace,
  which still rejects "10"; pin the cell's content, never the break after it.)

---

## 2026-09-19 — Wiring the sync state and the conflict notice: the entitlement-free Mac reads ubiquity keys, its metadata query reads nothing, a missing file is "not in iCloud", and the Mac's conflict sheet means two paths (#14, #15)

Building `SyncMonitor`, `SyncStateIndicator` and the `NSFileVersion` pipeline around the
pure halves:

- **The Mac needs no iCloud entitlement to read the ubiquitous resource keys.** A plain
  `swiftc` probe (no entitlements, no sandbox) on files under `~/Library/Mobile Documents`
  got `isUbiquitousItem == true`, `isUploaded`, `downloadingStatus` (an evicted PDF read
  `notDownloaded`) and `ubiquitousItemContainerDisplayName` ("iCloud Drive"; the CineSched
  container reported "LSVR CineSched", so the App ID's container name, not
  `NSUbiquitousContainerName`, is what the Mac sees). A `/tmp` file read nil for every key.
  So the Mac's indicator is a poll of `url.resourceValues(forKeys:)` on the document's URL,
  which the sandbox may read once the user opened the file; 2 s while the file is in
  iCloud, 10 s otherwise.
- **`NSMetadataQuery` over `NSMetadataQueryUbiquitousDocumentsScope` gathers zero results
  without the entitlement** (`start()` returns true, the gather finishes empty, no error),
  and a directory-scoped query over `Mobile Documents` also finds nothing (Spotlight does
  not index it). The monitor still starts the query everywhere, since it is what reports
  promptly on iOS and visionOS, and treats its notifications as "re-read the resource
  values" rather than as a second source of truth.
- **`resourceValues(forKeys:)` for a file that does not exist does not throw for the
  ubiquity keys**; they come back unset, i.e. "not in iCloud". A test that expected nil
  for a missing file failed; the outcome (no indicator) is the same either way.
- **The 27 `Document` protocol has no presenter callbacks**, so nothing tells the document
  that a version arrived or why an `apply` came; the monitor asks `NSFileVersion` on every
  `restoreCount` change (and on activation and on the query's updates). What
  `URLDocumentConfiguration` does give is the URL, `lastContentModificationDate` and
  `makeFileCoordinator()`; `ProjectDocument` now exposes all three. ADR 0004 has the
  amendment.
- **Two conflict paths, by platform.** NSDocument (which the Mac scene runs on) presents
  its own conflict sheet and Versions browser when the item gains a conflict version, and
  issue #15 wants that dialog on the Mac, so an app-side resolution there would race it.
  `PlatformConflictResolution` (a new seam) says the Mac observes only; iOS and visionOS
  run `ConflictPolicy`. The pre-agreed fallback covers what the system resolves first:
  `ProjectDocument.apply` over unsaved edits (`changeCount` past the count the last
  `snapshot(contentType:)` or `apply` saw) records the replaced project, and the monitor
  raises the notice from it on the restore. Since those edits are in hand, the fallback
  offers Restore other version as well; that is one step beyond the agreed "notice without
  restore", and `canRestore` is where to switch it off if the human prefers the agreement.
  The fallback also fires for a Mac Revert To on an iCloud file whose edits had not
  autosaved yet, which is rare (autosave lands within seconds) and harmless (Dismiss).
- **Removing conflict versions: `isResolved = true`, then `remove()`, under a coordinated
  metadata-only write.** The `NSFileVersion` header says so twice ("you must then remove
  any versions of the file that are no longer useful"; "always remove file versions as
  part of a coordinated write"). `removeOtherVersionsOfItem(at:)` would also take the
  Mac's own saved versions, so the monitor removes exactly the versions it listed. The
  coordinated read of each version's URL (which downloads a nonlocal version) and the
  write run through `coordinate(with:queue:)` on a private `OperationQueue`, never
  blocking the main actor: NSDocument relinquishes on its own queue, but a synchronous
  coordinate on main while the presenter wants main is how a document app deadlocks.
- **Dating the current version.** While the document has unsaved edits the policy gets
  `lastEditDate` and no device name (the system only names saved versions); otherwise the
  file's `NSFileVersion.currentVersionOfItem(at:)` date and `localizedNameOfSavingComputer`,
  which matters when the system already applied another device's version as current: the
  "current" the policy sees is then that device's, and the notice can still name it.
- **A `var` array filled inside a `@Sendable` accessor and read by a `Task` after it is a
  new warning** ("reference to captured var in concurrently-executing code"); build the
  array with `map` into a `let`. Grep the whole log for `warning:`; the app target is
  still at 7.
- **The two-device conflict test and airplane-mode checks were not run**: this agent has
  no signed-in devices, the simulators have no iCloud account, and a synthetic conflict
  cannot be made (`addVersionOfItem` makes a local version, never a conflict version).
  The manual steps are in the issue comments; the Mac's indicator was checked against a
  local file only (nothing drawn).

---

## 2026-09-18 — The CineSched iCloud folder: per-SDK entitlements, a merged plist that will not take NO, the panels' remembered directory, and a simulator that autosaves a minute later (#12)

Giving iOS and visionOS the document lifecycle with iCloud Documents while the Mac stays
entitlement-free:

- **The Mac had no `CODE_SIGN_ENTITLEMENTS` at all.** `LSVR CineSched/CineSched.entitlements`
  sat in the synchronized folder unreferenced (Xcode does not bundle `.entitlements` as a
  resource, so it did no harm); the Mac's sandbox entitlements came from `ENABLE_APP_SANDBOX`
  and `ENABLE_USER_SELECTED_FILES`. Wiring the file unconditionally and the iOS one per SDK
  (`"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]"`, `iphonesimulator`, `xros`, `xrsimulator`)
  gives the Mac exactly what it had (`app-sandbox`, `files.user-selected.read-write`,
  `get-task-allow` in Debug), checked with `codesign -d --entitlements - --xml`.
- **A per-SDK boolean `INFOPLIST_KEY_` lands in the other SDKs' plists as `false`, and a
  per-SDK string as `""`**, not as an absent key: the Mac's plist got
  `UISupportsDocumentBrowser = false` (harmless) and `CFBundleDisplayName = ""` (not
  harmless; Finder would show an empty name), so the unconditional display name is set to
  the Mac's existing "LSVR CineSched". And `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace`
  set per SDK fails the *Mac* build ("'LSSupportsOpeningDocumentsInPlace = NO' is not
  supported on macOS"); it is unconditional YES. The three keys are typed in
  `CoreBuildSystem.xcspec` (grep the spec under `SharedFrameworks/SwiftBuild.framework`
  before inventing an `INFOPLIST_KEY_`); an unknown key would be emitted as a string.
- **`NSUbiquitousContainers` in the shared partial plist reaches the Mac's plist too.** It
  grants nothing without the entitlement, and a per-SDK `INFOPLIST_FILE` would mean two
  copies of the type declarations, so it stays shared and the Mac carries an inert key.
- **A simulator build with signing on embeds the iCloud entitlements as a `__TEXT,
  __entitlements` section (`…-Simulated.xcent`), and `codesign -d --entitlements` shows
  `{}`.** Read the `.xcent` in `Intermediates.noindex/…/LSVR CineSched.build/` to check
  them. The device build (`generic/platform=iOS`, no `-allowProvisioningUpdates`) fails
  with "Provisioning profile … doesn't include the iCloud capability" and "doesn't support
  the iCloud.com.lsvr.LSVR-CineSched iCloud Identifier": the App ID needs the capability
  from a logged-in Xcode or the portal; nothing in the repo can do that.
- **The 27 SDK spellings** (from `SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`;
  there is no `arm64-apple-ios` file, and the XROS one matches):
  `DocumentGroupLaunchScene(_ title: LocalizedStringKey, _ actions:, background:)` (plus
  `backgroundAccessoryView:` / `overlayAccessoryView:` taking a `DocumentLaunchGeometryProxy`),
  `NewDocumentButton(_ title:, contentType: UTType? = nil)` and, for #13,
  `NewDocumentButton(_:contentType:source: DocumentCreationSource(id:))`, which arrives in
  `DocumentGroup(editor:makeDocument:)`'s second parameter as `context.creationSource` (also
  on `configuration.creationSource`). `makeDocument` is `@MainActor async throws`. The
  environment's `newDocument(_:)` for a `ReadableDocument` is **macOS-only**; on iOS a
  creation source is the way to hand a `ProjectData` to a new document.
- **The system's Open/Save panels start in `NSNavLastRootDirectory`** (a plain path string
  in the app's defaults), and honour it only when the process has a bundle identifier (a
  bare `swiftc` binary always got `~/Documents`). Verified with a sandboxed throwaway
  bundle: an existing folder under `~/Library/Mobile Documents` outside the container is
  honoured (the panel runs out of process), a nonexistent one falls back to `~/Documents`,
  `~`-relative forms are not expanded, and each confirmed panel rewrites the key. The app
  may `stat` that folder from inside the sandbox (`fileExists` true, `access(R_OK)` false).
  `NSHomeDirectory()` in a sandboxed app is the container; `getpwuid` gives the real home.
  The panel's own `directoryURL` on the app side never reflects what the remote panel
  shows, and `NSSavePanel.ok(nil)` is "not implemented" for the remote panel, so read the
  panel service's log (`Open Sync Started` / `OpenSync: Begin` lines from
  `com.apple.appkit.xpc.openAndSavePanelService`) or `panel.urls` after `cancel`.
- **`getpwuid` in the simulator is the host's password database**, so a test on it is a
  test of the Mac; `realHomeDirectoryIsAnAbsoluteDirectory` is `#if os(macOS)`.
- **The iOS document infrastructure autosaves about a minute after the edit** (the Mac
  writes within seconds): the file's mtime moved 65 s after the typed title, with the app
  in the foreground. Kill the app before that and the edit is gone; the human check for
  "survives killing and relaunching" has to wait it out or background the app first.
- **Checking the iOS document lifecycle without tapping**: `simctl openurl <device>
  file://<the app's data container>/Documents/X.cinesched` opens the document in the app
  on a cold launch (a warm `openurl` on the launch screen did nothing), and a throwaway
  XCUITest that calls `XCUIApplication().activate()` (not `launch()`, which would relaunch
  to the launch screen) can then type into the title field and read it back. A tap on the
  launch screen's New Project from XCUITest registered but opened nothing, twice; the
  document browser runs in a remote view service (`DocumentManagerUICore.Service`) that
  the automation touch reaches but the creation never follows. `app.buttons["New Project"]`
  also matches the button *and* its label (use `.matching(identifier:).firstMatch`), and
  `-parallel-testing-enabled NO` keeps the test on the real device, whose log survives.
- **Nothing in the app's data container is `.cinesched` before the first save**, and with
  no iCloud account in the simulator the launch screen's Browse shows "On My iPhone"; the
  CineSched folder itself needs a signed-in simulator or a device.

---

## 2026-09-18 — Sync state and conflict policy as pure values: `nonisolated Codable, Equatable` leaves `Equatable` on the main actor, and the warning it causes has no file (#14, #15)

Building `SyncState.derive` and `ConflictPolicy.decide` as `nonisolated` pure-core types:

- **`struct ProjectData: nonisolated Codable, Equatable` makes only `Codable` nonisolated.**
  The modifier applies to the one conformance it precedes; `Equatable` stays inferred
  `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A `nonisolated struct`
  holding a `ProjectData?` and synthesizing its own `Equatable` then warns "main
  actor-isolated conformance of 'ProjectData' to 'Equatable' cannot be used in nonisolated
  context", and the warning is reported at `<unknown>:0:` (synthesized code), so a grep
  by file name misses it; grep the whole log for `warning:` and count. Making the model's
  `Equatable` nonisolated would cascade through every type it contains (`ShootDay`,
  `Scene`'s `Hashable`, `CallSheetData`, `ProductionInfo`, …); `ConflictVersion` instead
  hand-writes `==` over its identity (id, date, device) and treats the snapshot as payload,
  which is the comparison the decision wants anyway. Worth doing the cascade once a second
  nonisolated type needs to compare projects.
- **The resource values carry no "waiting" state.** `URLResourceValues` says uploading,
  uploaded, downloading and a downloading status; whether the item is *waiting* is the
  network's, so the mapping takes reachability as its own input and puts it above every
  transfer flag (a stale `isUploading` offline is not to be believed). The acceptance test
  for airplane mode expects "waiting" with nothing pending, which settles the precedence.
- **`URLUbiquitousItemDownloadingStatus` is a struct of static constants, not an enum**;
  a `switch` over `.current` / `.downloaded` / `.notDownloaded` needs a `default`. The
  snapshot's own `DownloadingStatus` enum exists so tests and the mapping never touch it.

---

## 2026-09-18 — Call sheet pagination: a closure that captures the outer `y` is stale on both sides, and Quartz stamps every PDF with a fresh date and ID (#32)

Fixing the call sheet's blank continuation pages (`ensureRoom` reset an outer `y` that each
section shadowed with its own `var y = y`):

- **The stale capture broke the check as well as the reset.** `ensureRoom` compared the
  *outer* `y`, frozen at the section's starting position, against the bottom margin, so the
  scenes table never broke at all: all 27 rows of the long fixture went onto page 1, the last
  eleven below the margin and off the media box, and the three extra pages were opened only
  because the following sections were handed a negative `y`. The issue's first suggestion —
  return the current `y` from the closure — would have fixed the reset and left the check
  stale. The section's running `y` has to reach the closure, hence `inout`
  (`ensureRoom(rowH, &y)`, the closure typed `(CGFloat, inout CGFloat) -> Void`; the shooting
  schedule already passes `yPosition: inout`). With the check honest the fixture is 3 pages,
  not 4, and page 1 ends at scene 311, not 313.
- **"Byte-for-byte" needs a mask.** Two exports of the same call sheet seconds apart differ in
  74 bytes: the `CreationDate` / `ModDate` digits in the Info dictionary and the 32-byte
  trailer `/ID`, which Quartz derives from the time. Every object and the xref table were
  identical (same size, same `startxref`), so `cmp -l` plus a look at the offsets settles it;
  the pixel diff (#4–#6's scratch tool, rebuilt in a few dozen lines on PDFKit + CoreGraphics)
  is the cleaner statement and is what the report should quote.
- **The general-call banner overdraws itself when both a quote and a schedule line are set**:
  the 26pt call time sits on the italic "Schedule:" line (see the long fixture's page 1, and
  `CallSheet.pdf`). Pre-existing, pixel-identical before and after; not #32's.

---

## 2026-09-18 — Checking whether a PDF label fits is a five-line CoreText script, and a taller label box is not a fix (#33)

The breakdown sheet's "BREAKDOWN SHEET #" wrapped because 9pt bold SF measures 104.4pt
against the cell's 103pt label area; 8.5pt is 99.1pt. `CTLineGetTypographicBounds` on a
`CTLineCreateWithAttributedString` of `CTFontCreateUIFontForLanguage(.emphasizedSystem, …)`
gives the width `PDFCanvas` will lay out (tracking included), so a `swift` script answers
"does this label fit?" without dumping and rasterizing a PDF. Of the three fixes the issue
offered, the label box cannot simply grow: `drawCell` takes the value's height from what
the label leaves, so a two-line label in the 44pt top row leaves the 13pt sheet number
11pt and the auto-scaling loop shrinks it to the 7pt floor. A smaller size changes
`labelHeight` (`labelSize + 5`) and moves the value half a point; the shorter "SHEET #"
keeps every metric in the cell where it was, and the masthead already carries the full
name. The scene number now follows `ShootingSchedulePDFExporter`'s order (`sceneNumber`,
then the title's prefix); `Scene.extractedSceneNumber` was not used because its "1"
fallback would number every banner and event.

---

## 2026-09-18 — The palette in the file: adoption cannot mark the document edited, `JSONEncoder` orders keys its own way, and an environment value is the cheap way to reach every strip (#11)

Moving the strip colors from per-device `UserDefaults` keys into `ProjectData.palette`:

- **A document cannot mark itself edited.** The 27 `Document` protocol has `apply(snapshot:)`
  and `snapshot(contentType:)` and nothing else; the infrastructure autosaves only from undo
  actions registered with the window's `UndoManager`, which only `ContentView` has. So the
  adoption of a device's overrides into a paletteless project (story 19 of #1) happens in the
  document's constructors and `apply`, in memory, and reaches the file with the project's
  next `perform`. The alternative, an `edit` from the view on load, would put "Undo Adopt
  Scene Colors" in the Edit menu the moment a file opens, and could not run in the document
  tests. Until that next edit, reopening on the same device adopts the same colors again;
  on another device the file still has no palette. Recorded in the CHANGELOG.
- **The device overrides are injected, not read, by `ProjectDocument`.** Its default is
  `nil` (no device overrides); only the app's two constructors (`makeDocument` in
  CineSchedApp and `LegacyProjectHandoff`) pass `SceneColorSettings.deviceOverrides()`. A
  default that read `UserDefaults.standard` would have made `applyReplacesTheWholeSnapshot`
  fail on any Mac whose colors were customized, since the test host is the app.
- **`JSONEncoder` without `.sortedKeys` writes a keyed container's keys in hash order, not
  encoding order**, and `ProjectCodec` sets no `sortedKeys` (the whole file has always been
  ordered that way: `productionInfo` comes first). A test that pinned `"palette" : {
  "intDay" …, "extDay" …` in slot order failed; pin key presence, not order.
- **`nonisolated struct` / `nonisolated enum` work for a pure-core type** under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (the reader and writer already used it). A
  member that touches a main-actor API (`Color(hex:)` in ThemeManager.swift) is then a
  warning ("call to main actor-isolated initializer in a synchronous nonisolated context");
  mark that one member `@MainActor` rather than the whole type. The reverse trap: a plain
  `enum` of static functions is main-actor by default, and calling one from the system's
  off-main-actor document factory (`LegacyProjectHandoff`'s `init(untitled:)` path) is
  the same warning; `SceneColorSettings` is `nonisolated` for that reason. Grep the
  whole build log for `warning:` before claiming the count, not just the files touched.
- **A strip's color can be read back from a PDF without PDFKit's help**: rasterize the
  page into a `CGBitmapContext` (sRGB, 1 pt per pixel, antialiasing off) with
  `drawPDFPage` and scan for the exact RGB triple; a flat rectangle fill lands exact
  pixels on every platform. `pdfPage(_:_:containsColorHex:)` in PDFTestSupport is the
  helper, and the exporter tests use a magenta no standard slot has so the check cannot
  pass by accident.
- **Threading a per-document value to every strip is one `.environment` at the editor's
  root** (`@Entry var scenePalette`), read with `@Environment` in the four views that call
  `stripColor(in:)`; the explicit alternative was a new `let` through `CompactMonthCalendarView
  → DayCellView → SceneCardView` and `StripboardView → SceneStripRow`, plus every preview
  and sheet. Sheets inherit the presenting view's environment, so the Day Detail sheet gets
  it for free. Exporters are pure functions and take `palette:` explicitly.
- **The color editor coalesces per slot**: a `ColorPicker` writes its binding on every
  movement of the color wheel, so `ContentView` keeps one `EditGesture` per slot being
  edited (`paletteGesture`), new token when the slot changes, cleared when the sheet closes.
  One token for the whole sheet session would have made "change two colors, undo" revert
  both. Reset is untokened, its own step.

---

## 2026-09-17 — Recovering the UserDefaults working copy: no view exists at launch, `makeDocument` runs after `openUntitledDocumentAndDisplay` returns, and a foreign security-scoped bookmark is "not in the correct format" (#10)

Recovering the pre-document builds' `SavedProject` blob and `CineSchedCurrentFileBookmark`
on the first launch of the document model:

- **There is no SwiftUI view to run a launch-time recovery from.** With iCloud Drive on the
  app shows the Open panel at launch (no window, no `DocumentGroup` editor), and the
  `openDocument` / `newDocument` environment actions need a view. So it is an
  `@NSApplicationDelegateAdaptor` (`MacAppDelegate`, a seam) driving `NSDocumentController`,
  which is what those actions use anyway, from `applicationDidFinishLaunching`. That runs
  before AppKit's "open untitled" step, and a document open (or opening) by then suppresses
  the Open panel and the blank window; no second window appeared in any case tried.
- **SwiftUI's own app delegate does not forward `applicationShouldOpenUntitledFile`** to the
  adaptor's delegate (never called across six launches, including one where the Open panel
  did appear). Do not make a launch decision depend on it.
- **`NSDocumentController.openUntitledDocumentAndDisplay(true)` returns before
  `DocumentGroup`'s `makeDocument` closure runs**; the infrastructure builds the SwiftUI
  document lazily. A "set the seed, open, clear the seed" sequence hands `makeDocument` nil.
  The seed (`MacAppDelegate.pendingUntitledProject`) therefore stays set until
  `makeDocument` takes it, which is the next document made; on the first launch nothing
  else is making one. Taking the seed is also what removes the legacy keys, so "after a
  successful open" means after the project is in a document, not after the
  `NSDocumentController` call returned.
- **`updateChangeCount(.changeDone)` on the returned `NSDocument` is enough for "edited"**:
  closing raised the Save sheet (Delete / Cancel / Save, the autosave-in-place form) and the
  document reported `isDocumentEdited`. The window's own edited flag reads false within a
  second, the same as after any real edit (the draft autosaves at once and the title's
  "Edited" clears; 2026-09-16 #8). A seeded project registers no undo action, so without
  this call the recovered window would close silently.
- **A security-scoped bookmark resolves only in the app that made it.** One made by a
  helper tool, or to a file since deleted, fails with `NSCocoaErrorDomain 259` ("isn't in
  the correct format"), not "no such file". Seed a test bookmark from inside the app under
  test (a temporary env-gated branch that calls `bookmarkData(options: .withSecurityScope)`
  and writes the key), never from a script.
- **The oldest lineage's file shape can never compare equal to anything**: `ProjectCodec`
  gives it `createdDate = Date()` on every decode. Only matters for a fixture; a real
  working copy is the current shape.
- **An undecodable blob is left in place, not deleted.** The spec removes the keys "after a
  successful open", and nothing opened; the check on every later launch is one defaults
  read and a failed decode. With no blob at all, the bookmark key alone is removed.
- **Checking launch behaviour without touching the real container**: the shell cannot read
  `~/Library/Containers/com.lsvr.LSVR-CineSched` (TCC), so build with
  `PRODUCT_BUNDLE_IDENTIFIER=com.lsvr.CineSched-recoverytest ENABLE_APP_SANDBOX=NO
  CODE_SIGNING_ALLOWED=NO`, seed with `defaults write <id> SavedProject -data <hex>`, launch
  with `open -n … --args -ApplePersistenceIgnoreState YES`, and read the outcome from a
  temporary `os.Logger` trace (`/usr/bin/log show --predicate 'subsystem == "<id>"'`; the
  delegate's subsystem is the bundle identifier) that lists
  `NSDocumentController.shared.documents` (`isDocumentEdited`, `fileURL`) and `NSApp.windows`
  (`attachedSheet`) and calls `performClose(nil)` on the first window. `NSApp.terminate` is
  blocked by the Save sheet; end the trace with `exit(0)`. Every row was run this way,
  plus a launch with the keys already gone (the second launch: the Open panel, nothing
  touched). What this does not cover: the sandboxed container's prefs and a panel-made
  bookmark under the real bundle identifier, which need the human's Mac.
- **Closing the untitled document a legacy `.json` hands off to is silent** (pre-existing,
  #8): it is not marked edited, so the window closes without a Save prompt and the copy is
  gone (the `.json` on disk is untouched). The "equal" recovery row goes through that path.

---

## 2026-09-17 — Undo coverage on the document model: the funnel was already complete, the gaps were editors writing a field at a time (#9)

Auditing every edit path for #9 after #8 and #34:

- **Every write already reached `perform`**; nothing bypassed it and the manual snapshot
  stack was gone. What #8 left was two editors writing their value back one property at a
  time through their binding: `CallSheetEditor.saveToDay` made 19 binding writes and
  `ProductionSetupSheet`'s Save 11, i.e. 19 and 11 `perform`s (each a whole-project
  compare and an undo registration). In the app they still undid as one step only because
  the window's `UndoManager` groups by run-loop event; with `groupsByEvent` off (the tests)
  they were 19 and 11 steps. Build the whole value locally and assign it once. Any new
  editor should write its value back as **one assignment** to its binding.
- **A pure `ProjectData` mutation that lives as a `private func` on a SwiftUI view is
  untestable through the funnel.** The range regeneration was one; it moved to
  `ProjectData.updateProductionRange` (ProductionRange.swift) unchanged apart from the
  Boneyard return order, which used to come from iterating a `[UUID: Scene]`, i.e.
  arbitrary. Iterating the days instead is deterministic and lets a test pin it.
- **The regeneration appends a day's calendar events after its script scenes** (it buckets
  the two separately), so a day that held an event before its last strip comes back with
  the event last. Long-standing; the Stripboard and calendar draw events in their own row
  anyway, so nothing visible changes. A test comparing whole scene arrays across a
  regeneration must compare script scenes and events separately.
- **The Stripboard had no `onBeforeSceneChange` at all**, so its drops (`shootDays` then
  `allScenes`), its quick-time sheet (scene then lunch time) and its call sheet Save
  (the day, then the auto-meal sync) were one undo step only by run-loop grouping. It now
  takes the same closure as the calendar and opens the gesture in `editSchedule`, the
  quick-time save and a wrapping binding for the call sheet editor (the editor writes
  before `onSave` runs, so the binding's setter is the place to open it). Likewise a
  Production Setup save that renames characters: `renameCastCharacter` opens the gesture
  (once) so the roster write that follows folds in. Any new child-view action that writes
  a binding more than once must call `onBeforeSceneChange()` first.
- **Child-view edits (calendar and Stripboard bindings) carry no action name**, so a drag
  or a call sheet Save shows as plain "Undo" in the Edit menu, while `ContentView`'s own
  edits are labelled. Naming them means `onBeforeSceneChange` carrying a name through ~18
  call sites; not done in #9.

## 2026-09-16 — Measuring the document model's lag: the funnel was innocent, `L()` built its 250-entry table per call, and every drop drew the calendar twice (#34)

Every hypothesis in #34 pointed at `perform`, the whole-project `!=` compare and the binding
writes. Measured (a 300-scene, 200-day project, main-thread CPU per operation, Debug), the
funnel was 2–10 ms of a 125 ms drop. What the profile actually showed, in order:

- **`L(_:lang:)` built a `[String: [AppLanguage: String]]` literal of ~250 entries on every
  call**, and a calendar redraw calls it from every day cell's context menu, tooltip and
  "Day N" badge, and from every Boneyard row's context menu: 20–30 ms of every drop, in
  Release too (allocation, not code, dominates). It is a lookup in a global `let` now.
- **SwiftUI evaluates `.contextMenu { … }` builders eagerly** on every body pass of the
  view they hang off, not when the menu opens. `View.contextMenu<A>(menuItems:)` was 429 ms
  of a 1.5 s profile. Anything inside one is body cost.
- **A drop cost two full body passes**: the edit invalidated `ContentView`, then
  `onChange(of: document.project)` (a whole-project compare per pass) wrote five `@State`
  values, one a tuple array that is never `Equatable`, so the calendar and Boneyard drew
  again. Undo the same. `DerivedScheduleState` + a cache keyed on `ProjectDocument.changeCount`
  makes the derivation part of the one pass, and the compare is gone. `pruneSelection` only
  writes the selection when it actually shrinks (SwiftUI does compare `Equatable` state on
  write — the pre-#8 profile showed `ShootDay ==` under `ContentView.shootDays.setter`).
- Not on the profile at all: the fresh `ProjectCommands` published per body pass (one
  `FocusedValues` assign sample in a 1.5 s trace, no `Commands` or `NSMenu` frames), the
  `perform` compare, and the `@Observable` granularity of `document.project`. Left alone.
- Smaller: three `DateFormatter()`s per day cell (35 ms/run; now `formattedDate(_:pattern:)`
  caches them), `productionDayNumbers` and a `firstIndex(where: isDate(inSameDayAs:))` per
  cell, `ConflictScanner.scan` trimming and comparing every roster name for every character
  of every scene (a normalized dictionary now), and the calendar's cross-day move writing
  the `shootDays` binding once per day in the range (a local copy, written once).

Numbers (main-thread CPU per operation, 300 scenes / 200 days, Release; Debug in brackets):
pre-#8 `2f48f5c` drop 106 [123], move 84 [101], undo 68 [74], redo 71 [70]; `document-model`
tip `20d06d2` drop 108 [129], move 104 [125], undo 107 [123], redo 103 [136]; after this
change drop 73 [72], move 72 [80], undo 60–70 [76], redo 65 [66]. What is left is SwiftUI's
own update of ~4–6k attributes per redraw (every `DayCellView` and `SceneCardView` takes
closures, so none is skipped); the next step, if ever needed, is Equatable cells.

How it was measured, since none of it needs a screen (the harness lived in a temporary
`PerfFixture.swift` + an env-gated `.task` in `applyLifecycle`, removed before commit):

- **Drive the editor from inside**: a `.task` gated on `CINESCHED_PERF` that loads a
  generated project through `edit`, then replays the calendar's exact binding-write
  sequences (`allScenesBinding.wrappedValue.removeAll…`, `shootDaysBinding.wrappedValue[i]
  .scenes.insert…` under `beginEditGesture`/`endEditGesture`) and `undoManager?.undo()`.
  The pre-#8 worktree got the same script against its `@State` and `performUndo()`.
- **"Lag" = main-thread time until the run loop sleeps**: a `CFRunLoopObserver` on
  `beforeWaiting` with order `CFIndex.max` (after Core Animation's commit) records the first
  and last wake within 400 ms of the edit; `thread_info(THREAD_BASIC_INFO)` on the main
  thread gives its CPU over the same span. Both agreed to the millisecond, so the lag is CPU.
- **`xctrace record --launch` runs the copy LaunchServices knows**, i.e. the human's
  DerivedData build, not the scratch one (the trace's `<process path>` tells). Launch the
  scratch binary yourself (`open -n --env K=V app --args …`, or the executable directly with
  the env in the shell) and `--attach <pid>`; an unsigned scratch build attaches fine.
  `xctrace export --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'`
  gives XML with `ref`-deduplicated frames (resolve `id`/`ref` yourself); frames carry
  `<source line=…>`, which is how `L()` at `contextMenu` call sites was pinned. The Time
  Profiler template only records signposts in the `PointsOfInterest` category, so window
  each operation with `OSSignposter(subsystem:category: .pointsOfInterest)`. The `SwiftUI`
  template's `swiftui-updates` table gives per-view update counts and durations.
- **Harness pitfalls**: state restoration reopened the previous run's window, so the `.task`
  ran in two documents (`-ApplePersistenceIgnoreState YES` as a launch argument); the
  window's `NSUndoManager` does not close its per-event group between Swift-concurrency
  continuations, so every scripted edit folded into one undo step until the script posted an
  `.applicationDefined` `NSEvent` between operations; `open` with `--args <file>` silently did
  nothing for the pre-#8 (non-document) app, whose binary had to be run directly; and the
  pre-#8 build must run under its own `PRODUCT_BUNDLE_IDENTIFIER`, or its two-second
  autosave overwrites the human's UserDefaults working copy.

## 2026-09-16 — The Mac as a document app: `makeDocument` gets no URL, the Open panel follows `readableContentTypes`, LaunchServices ignores apps in /tmp, and how to check any of it without a screen (#8)

Wiring `DocumentGroup(editor:makeDocument:)` around `ProjectDocument` and moving every
mutation in `ContentView` onto `perform`:

- **`makeDocument`'s `configuration.fileURL` is nil even when a file is being opened**
  (observed for File ▸ Open, LaunchServices and state restoration alike; it was set for one
  `open file.cinesched` and nil for the others). The URL is settable on the configuration and
  arrives by the time `apply(snapshot:previous:)` runs, so the document keeps the
  configuration and reads `fileURL` live rather than copying it at construction. Do not
  branch on the URL in `makeDocument`; give every document the blank template and let
  `apply` replace it.
- **The system Open panel offers exactly `readableContentTypes`** (`com.lsvr.cinesched.project`
  and `public.json`, read straight off `NSOpenPanel`'s log line) with no `CFBundleDocumentTypes`
  entry for JSON. So the viewer role for a legacy `.json` needs nothing in the plist, which is
  what keeps iOS from claiming every JSON later. The plist declares only the native type, as
  Editor with `LSHandlerRank` Owner, which is what Finder's kind string ("CineSched Project")
  and double-click come from.
- **With iCloud Drive on, a document app launched with nothing to open shows the Open panel,
  not an untitled window** (the `NSShowAppCentricOpenPanelInsteadOfUntitledFile` behaviour
  TextEdit has). ⌘N still makes the untitled window; the AC's "New Project opens an untitled
  window" is about that, not launch.
- **LaunchServices will not make an app under `/private/tmp` (so a scratch `-derivedDataPath`)
  the handler for anything**: `lsregister -dump` shows the claim, `NSWorkspace
  .urlsForApplications(toOpen:)` leaves the app out, and `open file.cinesched` goes to
  TextEdit. Copy the build to `~/Applications` (then remove it and `lsregister -u`) to test
  the association.
- **Checking the lifecycle from an agent shell that has no screen-recording or automation
  permission** (screenshots come back black, `osascript` to System Events hangs on the consent
  prompt): temporary `os.Logger(subsystem: "cinesched.trace", …).notice("… \(x, privacy:
  .public)")` lines in `makeDocument`, `apply` and `snapshot`, launch with `open -n`, drive it
  with `open -a App file` / `open file`, and read `/usr/bin/log show --info --predicate
  'subsystem == "cinesched.trace"'`. `print` is block-buffered off a tty and `NSLog` payloads
  show as `<private>`; and `log` is a zsh builtin, so spell out `/usr/bin/log`. What this
  cannot check is Save/autosave/undo through the menus; that stays a human step.
- **The infrastructure autosaves an opened file within seconds of the first edit and does
  not honour the readable/writable split as a viewer role.** A `.json` opened through
  `readableContentTypes` was rewritten in place by the writer (checksum changed, no panel)
  after one scripted edit, and File ▸ Save did the same; `configuration.fileURL = nil` from
  `apply` changed nothing. NSDocument's "Save As for an unwritable type" does not exist
  here. The fix is the spec's own design: `LegacyProjectHandoff` hands the contents to
  `newDocument(ProjectDocument(untitled:))` and `dismiss()`es the `.json` window; the Save
  panel then opens with `currentContentType: com.lsvr.cinesched.project`, and the writer
  throws on any `.json` destination as a backstop. `newDocument`'s factory closure is
  `@Sendable`, hence the `nonisolated init(untitled:)` that writes the Observation backing
  store (`_project`) directly. Also: the "Edited" title state clears as soon as autosave
  has written, which is Lion-style behaviour, not a missing dirty flag.
- **What a headless harness could and could not reproduce from the human test.** With a
  temporary env-gated script in `onAppear` (edit through `edit`, `undoManager.undo()`, then
  `menu.delegate?.menuNeedsUpdate?(menu)` + `performActionForItem(at:)` on the real Edit ▸
  Undo and Production ▸ Production Setup… items): undo and redo revert through the window's
  undo manager whether the first responder is the window or a SwiftUI field editor; the
  focused scene value reaches the `Commands` body once the window is key and routes to
  whichever of two windows is key. Reading `NSMenuItem.isEnabled` / `action` without
  `menuNeedsUpdate` shows stale (disabled, nil) items — SwiftUI refreshes them when the menu
  opens — so do not judge command enablement from a raw item snapshot. Launching with a file
  path as argv in the sandboxed build makes the file unwritable ("You don't own the file…
  Duplicate?"); use `ENABLE_APP_SANDBOX=NO` for the harness build. And `pkill -f "LSVR
  CineSched"` also hits a copy the human is running from Xcode; kill by PID.
- **An `@AppStorage` view toggle is an app preference, and the moment there are two windows
  it flips both.** Human testing caught Calendar/Stripboard, cast row, times-vs-pages and
  all-days switching every open project. `@WindowPreference` (a `DynamicProperty` around
  `@State`, seeded from the defaults key once per window and written back on change) keeps
  the last-used behaviour with per-window state, and the View menu binds to the key window's
  values through `ProjectCommands` (`commands?.x ?? .constant(…)`, disabled when nil).
  Appearance (Dark Mode, Theme) is deliberately still app-wide.
- **`onBeforeSceneChange` cannot be a strict undo bracket.** Several calendar paths call it and
  then finish through `assign`/`removeScene` without `onSceneChanged`, so an `EditGesture`
  opened there is also closed at the end of the run-loop turn (`DispatchQueue.main.async`);
  otherwise the next unrelated edit would fold into the drag's undo step. The window's
  `UndoManager` groups by event anyway, so the token only matters for gestures that span
  turns.
- **A no-op `perform` must not register**: the editors write their whole value back on Save,
  and with bindings now funnelling into `perform` that would dirty the document (and add a
  blank undo step) every time a sheet is dismissed with Save. `perform` compares before and
  after and returns early.

## 2026-09-16 — The project document: `nonisolated Codable` is a two-word fix, UndoManager needs a run loop or a group, a partial Info.plist merges (#7)

Building `ProjectDocument` on the 27 `Document` protocol and extracting `ProjectCodec`:

- **The 27 document protocols are `Document = ReadableDocument & WritableDocument`, with
  `DocumentReader` / `DocumentWriter` as separate `@concurrent` types** whose `read` /
  `write` take a `consuming Subprogress` (the new `ProgressManager` API: `progress.start(
  totalCount:)` gives the manager to `complete(count:)` on). `DocumentReadConfiguration`
  and `DocumentWriteConfiguration` have no public initializer, so a test cannot call
  `document.reader(configuration:)`; it constructs `ProjectDocumentReader()` directly.
  `DocumentGroup(editor:makeDocument:)` hands the document a `URLDocumentConfiguration`
  (file URL, modification date, file coordinator) — for the next ticket.
- **A main-actor-isolated `Codable` conformance is a one-line change to make nonisolated:**
  `struct Scene: Identifiable, nonisolated Codable, Hashable`, plus `nonisolated` on any
  hand-written `init(from:)` / `encode(to:)` and on anything they touch (`ShootDay.
  isBlackout`, `ProjectData.init`). Synthesized witnesses follow the conformance. Under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` every conformance is inferred `@MainActor`,
  which is why the baseline had 4 "isolated conformance cannot be used in nonisolated
  context" warnings at the old `ProjectFile` call sites; the codec would have carried them
  over. Scratch-checking the syntax with `swiftc -typecheck -Xfrontend -default-isolation
  -Xfrontend MainActor -enable-upcoming-feature InferIsolatedConformances` took a minute
  and saved a build cycle.
- **`UndoManager.registerUndo` with `groupsByEvent` on and no run loop folds every
  registration into one step**, so a test that performs two edits and undoes gets both back.
  With `groupsByEvent = false` and no open group it throws (`must begin a group before
  registering undo`). `perform` therefore opens and closes an explicit group around each
  registration — invisible in the app, where it nests inside the event group — and the tests
  turn `groupsByEvent` off. Re-registering inside the undo handler (the redo) needs no
  group of its own: `undo()` opens one.
- **`GENERATE_INFOPLIST_FILE = YES` plus `INFOPLIST_FILE = Config/Info.plist` merges**: the
  built `Info.plist` carries the generated keys (bundle id, version, the iOS scene manifest)
  and the file's `UTExportedTypeDeclarations`. Keep the file outside the synchronized
  folder. The exported type resolves at runtime in the test host on the Mac and on both
  simulators (`UTType("com.lsvr.cinesched.project")` is non-nil, `preferredFilenameExtension`
  is `cinesched`), so the plist really is registered when the host launches.
- **The date formatter writes the machine's zone and locale.** `yyyy-MM-dd'T'HH:mm:ssZ` on
  a default `DateFormatter` produces `-0700` here and `+0000` on a UTC machine, and a
  non-Gregorian device calendar would write a different year. Left as is for byte-for-byte
  compatibility (ADR 0005), the test pins the shape only; worth fixing to `en_US_POSIX` +
  UTC before two devices with different locales share a file (M2 sync).
- **The fixtures mint fresh UUIDs on every access.** `PDFFixture.days` is a computed
  property, so a test comparing "the project" against itself must store the fixture once
  (`let project = ProjectCodecTests.project`), or two reads never compare equal.
- `-only-testing:"LSVR CineSchedTests/ProjectDocumentTests"` works at suite level without
  parentheses; the #5 note about needing them applies to individual test functions.

---

## 2026-09-16 — Breakdown and DOOD off AppKit: `boundingRect` is a point short of `draw(in:)`, TextKit drops lines by their top edge, `calibratedWhite` is a different gray, system colors follow the theme (#6)

The last two exporters, same method as #4 and #5 (dump every fixture PDF before and after,
rasterize, pixel-diff). Every fixture — the two migrated and the four already on the helper —
came out identical at 288 dpi. The measuring was done up front with scratch AppKit scripts
(`NSAttributedString` into a `CGContext` PDF, then reading the `Tm` operators back out of the
inflated content stream), which is much faster than fixing pixel diffs one at a time:

- **`NSAttributedString.boundingRect(with:options:)` measures a line as `round(ascent) +
  round(descent)` but `draw(in:)` advances `round(ascent) + ceil(descent)`.** They only agree
  where SF's descent rounds up; at 7, 9.5, 10, 11, 11.5 and 15pt the measurement is one
  point per line short of what is drawn (11pt: 13 vs 14; three 9.5pt lines with 1.71pt
  spacing measure 36.42 but occupy 39.42). `boundingRect` equals
  `NSLayoutManager.defaultLineHeight`; `size().height` equals the drawn height. The #4 note
  that `boundingRect` "reports the same whole numbers" was only true at the sizes it checked.
  The breakdown sheet's auto-scaling loop compares `boundingRect` against its cell, so
  `PDFFont.boundingLineHeight` / `PDFCanvas.boundingHeight(of:)` carry the smaller number for
  that comparison and `height(of:)` keeps the drawn one. `PDFCanvasTests` pins both tables.
- **TextKit lays out a line only if its top edge is above the rect's bottom, and clips only
  when the text overran.** Line *i* (0-based) is drawn iff `rect.height > i × (lineHeight +
  lineSpacing)`, whole and unclipped-at-the-line; if the text as a whole is taller than the
  rect a `re W n` clip to the rect is emitted (so the "#" of the breakdown sheet's
  "BREAKDOWN SHEET #" label, which wraps, shows as a sliver, #33). `draw(_:in:)` now does
  exactly this; it made no difference to the four earlier exporters' fixtures, which never
  overflow, and is what a wrapped name in a one-line DOOD cell needs.
- **`NSColor(calibratedWhite:alpha:)` is the legacy generic gray (gamma 1.8), not the
  gamma-2.2 gray that `NSColor(white:alpha:)`, `.gray`, `.lightGray` and `.darkGray` are.**
  The PDF carries a separate ICC profile for it and 0.35 renders 19/255 lighter than
  `gray(0.35)`. `CGColor.calibratedGray` keeps the space; `kCGColorSpaceGenericGray` is
  `nonswift` in the API notes, so it is looked up by name.
- **`NSColor.systemBlue` / `.systemYellow` / `.systemRed` resolve against the current
  appearance even when drawing into a PDF context**, so the DOOD's status cells came out a
  shade lighter when the app (or, in tests, the machine) was in dark mode. Pinned to the
  light values (sRGB 0/136/255, 255/204/0, 255/56/60); noted in the changelog. The baseline
  for the pixel diff was dumped with the old code wrapped in
  `NSAppearance(named: .aqua).performAsCurrentDrawingAppearance`.
- **`NSAttributedString.size().height` matches `PDFFont.lineHeight` at 7, 8 and 9pt** (9,
  10, 11), which is all the DOOD centres with; the ≥ 26pt mismatch from #5 still stands.
- **iOS's narrower SF fits "BREAKDOWN SHEET #" on one line**, so the wrap is pinned only
  under `PDFFixture.hasMacSystemFace` (moved to `PDFTestSupport` for every suite to use).
- **`Scene.scriptOrderKey` ties for unnumbered scenes** (events, banners, the untitled
  company-move line), and `sort` is not stable, so a test must not assume which of them
  comes last.
- **Test-target warnings from `#expect((x ?? "").contains(…))`**: the macro's rewrite
  complains about the `??`. Hoist the string into a `let` first.
- The scratch tools (a PDF→bitmap pixel differ on PDFKit + CoreGraphics, a PDF→PNG
  rasterizer, a text dumper) are a few dozen lines each; `learnings.md` #4 and #5 describe
  the same ones. There is still no ImageMagick on the machine.

## 2026-09-16 — Month calendar and call sheet off AppKit: named fonts get a synthetic gap, `draw(at:)` is a line box, emoji change nothing (#5)

Same method as #4 (dump the fixture PDFs before and after, rasterize, pixel-diff — the
tools were a scratch Swift CLI on PDFKit + CoreGraphics, no ImageMagick on the machine).
Everything came out identical except the known ellipsis lines, but a few things had to be
measured first, all with a scratch AppKit script driving `NSLayoutManager` and reading the
`Tm` operators back out of the PDF stream:

- **Non-system faces get a synthetic leading in TextKit.** SF follows the #4 rule
  (baseline `round(ascent)`, line `+ ceil(descent)`), but Helvetica, Times and Courier, which
  report zero leading, are laid out with `round(0.2 × size)` added *above* the ascent and
  `round(descent)` below: Helvetica-Oblique 8.5pt is an 11pt line with the baseline 9pt
  down, where the SF rule would say 9 and 7. It fits every size 6–30 for those three faces;
  faces that carry their own leading (Arial, Helvetica Neue) follow yet another rule that is
  not modelled because nothing uses them. `PDFFont.named` encodes the gap; `PDFCanvasTests`
  pins the numbers. The one Helvetica line in the app (the call sheet quote) sits exactly
  where it did. (#5 asked for "font descriptor traits" in place of the `NSFontManager`
  lookups; that is what the schedule line gets, but the quote was never the system italic,
  so it keeps its Helvetica by name — traits would have changed its face.)
- **`NSAttributedString.draw(at:)` is `draw(in:)` with a one-line-tall rect.** The point is
  the bottom-left of the line box, so the baseline lands `lineHeight - baselineOffset`
  (the rounded descent) above it — not at the point. `PDFCanvas.draw(_:lineOrigin:…)`.
- **Emoji do not make a TextKit line taller.** `size().height` for "📍 HOLLYWOOD" equals
  the plain line's at every size tried (the fallback face is used for the glyph, not for the
  line metrics), so the old `PDFExporter` comment that pills had to measure their own line
  height "because emoji sit taller" was wrong; `PDFFont.lineHeight` is the height.
- **`NSParagraphStyle.lineSpacing` goes between lines only**, never after the last (two
  8.5pt lines with 3pt spacing measure 23, not 26), and `.usesFontLeading` changes nothing
  for SF (leading 0). `draw(in:lineSpacing:)` / `height(of:lineSpacing:)`.
- **`NSFont.systemFont(ofSize:weight: .semibold)` is the system face with CoreText's
  weight trait 0.3** (`.SFNS-Semibold`); `CTFontCreateCopyWithAttributes` on the UI font keeps
  its tracking, and the pixel diff on the breakdown headings is clean.
- **`NSColor(red:green:blue:alpha:)` is sRGB; `NSColor.gray` / `.lightGray` / `.darkGray`
  are calibrated whites 1/2, 2/3, 1/3.** `CGColor.srgb` and the `pdf*Gray` statics.
- **`PDFExporter.generatePDF` (File ▸ Export Schedule PDF) rides along** in the same file
  and was diffed too: identical except its truncated titles and a 1/255 shade on the grid
  lines (one path stroked once vs. one stroke per line).
- **`NSAttributedString.size()` disagrees with `NSLayoutManager.defaultLineHeight(for:)` for
  SF** at several sizes (11pt: 14 vs 13; 26pt: 30 vs 30 but the #4 rule says 31). The
  exporters only ever place a single 26pt line by its baseline, so the mismatch at ≥ 26pt is
  harmless today, but `height(of:)` at those sizes is not verified against TextKit.
- **The call sheet already loses everything after its first page break** (#32): each
  section keeps a local `var y` that `ensureRoom`'s page reset never reaches. Reproduced
  faithfully here (the page count is pinned by a test); fix it separately.
- **`-only-testing:` with a Swift Testing function needs the parentheses**
  (`Suite/test()`); without them nothing runs and xcodebuild still reports success.

## 2026-09-16 — Moving two exporters off AppKit: TextKit's layout is reproducible, its truncation is not (#4)

`PDFCanvas` replaces `NSAttributedString.draw(in:)` with CoreText. What it took to keep the
strip schedule pixel-identical, measured by dumping the fixture PDFs before and after
(`SchedulePDFExporterTests` + `TEST_RUNNER_CINESCHED_PDF_DUMP_DIR`, decompressing the content
streams and rasterizing both for a pixel diff):

- **TextKit rounds line metrics; CoreText does not.** `draw(in:)` puts the first baseline
  `round(ascent)` below the top of the rect and advances `round(ascent) + ceil(descent) +
  ceil(leading)` per line (SF 18pt: 17 + 4 = 21, not 21.2; 11pt: 11 + 3 = 14, not 12.95;
  SF's leading is 0). `boundingRect` reports
  the same whole numbers. `PDFFont.baselineOffset` / `lineHeight` encode that rule and
  `PDFCanvasTests` pins the measured table, so nothing moved by a fraction of a point.
- **The system font is the same font.** `CTFontCreateUIFontForLanguage(.system / .emphasizedSystem)`
  is exactly `NSFont.systemFont` / `boldSystemFont`: same glyphs, same metrics, and CoreText
  applies SF's optical tracking (the `Tc` operator in the PDF) on its own, so plain lines came
  out byte-for-byte equal.
- **Colors convert exactly.** `Color.resolve(in: EnvironmentValues()).cgColor` gives the same
  extended-sRGB components as `NSColor(Color)`, and `CGColor(genericGrayGamma2_2Gray:)` is the
  space `NSColor(white:alpha:)` used.
- **TextKit draws truncated lines tighter than everything else.** A line it cut with "…" was
  tracked about 13/1000 em tighter than the untruncated line above it (the PDF shows `Tc 0.0013`
  where its neighbours have `0.0152`), and the ellipsis was appended un-kerned. Nothing in
  CoreText reproduces that (`kCTTrackingAttributeName: 0` and `kCTKernAttributeName: 0` both
  give the normal width), and it looks like a quirk rather than a design, so `PDFCanvas` does
  not try: truncated lines keep their neighbours' tracking, which means a strip-schedule title
  may now end one character before the ellipsis where it used to squeeze one more in.
  Deliberate; noted in the changelog. `CTLineCreateTruncatedLine` (what the shooting schedule
  used directly) was also rejected because it measures the prefix and the token separately and
  so gives up a character early; the helper binary-searches the longest prefix whose width
  *with* the ellipsis fits, so on the shooting schedule the change runs the other way — a
  truncated title now keeps one more character when it fits, and the ellipsis is kerned to it.
- **iOS has a different SF.** The same point sizes give different ascents and widths on the
  simulator (18pt line height 22, not 21; the wrap fixture takes two lines, not three), so the
  Mac-measured tables in `PDFCanvasTests` are `.enabled(if:)` the Mac face is present, and
  everything else asserts the rule, not the numbers. iOS output is therefore not pixel-equal
  to the Mac's, which no ticket asked for.
- **Dumping files from tests on the Mac needs `ENABLE_APP_SANDBOX=NO`**, and the env var must
  be a real environment variable (`TEST_RUNNER_X=… xcodebuild …`), not a build-setting
  argument after `xcodebuild`. The test host is the sandboxed app, which cannot write outside
  its container, and the terminal cannot read inside it (TCC), so the two never meet otherwise.

## 2026-09-16 — Getting the target to build for iOS was mostly a plist collision and AppKit hunting (#3)

Three things that surprised, in the order they bit:

- **A stray `Info.plist` in the synchronized folder breaks the iOS build, not the Mac one.**
  `ProcessInfoPlistFile … Multiple commands produce …/LSVR CineSched.app/Info.plist`. The
  hand-written plist was documented as unused, but a synchronized folder copies it into the
  bundle as a resource; on the Mac that lands in `Contents/Resources/` and nobody notices,
  in a flat iOS bundle it is the same path as the generated plist. Deleted it; do not add one.
- **`URL.BookmarkCreationOptions.withSecurityScope` is macOS-only.** iOS bookmarks are
  implicitly security-scoped, so the option simply does not exist there. `FilePanels` owns
  the options now; grep for `withSecurityScope` should only hit that file.
- **The compiler stops at the first missing module, one file at a time.** `import AppKit`
  in one file hides every other error in the build, so "fix, rebuild, repeat" is slow.
  `grep -ln "^import AppKit"` plus a grep for `NSEvent|NSColor|NSSavePanel|NSOpenPanel|
  \.checkbox|\.radioGroup|borderlessButton|withSecurityScope` up front found everything
  the compiler later would have, in one pass. After that the whole UI compiled unchanged on
  iOS and visionOS: `.help`, `.onHover`, `.keyboardShortcut`, `.commands`, `NSItemProvider`
  and `DropDelegate` are all cross-platform.
- **Simulator names drift from the spec.** #3 asked for "iPhone 17 Pro" and "iPad Pro
  13-inch (M4)"; the installed 27.0 runtime has iPhone 17 and iPad Pro 13-inch (M5).
  Check `xcrun simctl list devices available` before copying a destination string. Also,
  `xcodebuild test` on a simulator runs in a *clone* and reboots the original device, so a
  `simctl launch` right after a test run can hit a device that is still booting (black
  screen with an Apple logo in the screenshot); `simctl bootstatus <device> -b` first.

## 2026-09-16 — Moving to the release Xcode 27 SDK at a 27.0 floor was a one-warning affair (#2)

The spec for the 27 baseline (#2) expected source fixes for "the state property wrapper
became a macro; the view builders were unified". Neither surfaced: the whole app compiles
unchanged against the 27.0 SDKs (Xcode 27.0, 27A266a). The *only* thing the raised floor
exposed was `NSItemProvider.loadItem(forTypeIdentifier:options:completionHandler:)`, deprecated
in macOS 27.0, at the two `DropDelegate.performDrop` sites in `CalendarView.swift`. Fixed by
loading with `loadObject(ofClass: NSString.self)`, which `ContentView`'s Boneyard drop already
used; every drag payload in the app is built with `NSItemProvider(object: … as NSString)`, so
the string round-trips the same way. Warning count: the release Xcode 27 gives 11 app-target
warnings at the old 26.5 floor (the "~20" `CLAUDE.md` used to record was the beta compiler's
count), and still 11 at 27.0 once those two drop sites were fixed.
Rule of thumb: when raising the deployment floor, diff the sorted `: warning:` lines of a clean
build before and after — deprecations gated on the *new* floor are the only class of warning a
floor bump can add, and they hide inside an otherwise green build.

## 2026-09-16 — The 27 beta is gone; build with the release `/Applications/Xcode.app`

Supersedes the 2026-09-02 entry below. `/Applications/Xcode-beta.app` no longer exists on the
dev machine; the shipped Xcode 27.0 lives at `/Applications/Xcode.app`. `xcode-select -p` now
points at `/Library/Developer/CommandLineTools`, so a bare `xcodebuild` errors with
"requires Xcode, but active developer directory … is a command line tools instance". Keep
passing `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command (the scripts in
`scripts/` default to it). Do not change `xcode-select`.

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

## 2026-09-02 — Build with the Xcode beta, not the release Xcode *(superseded 2026-09-16)*

Historical: until Xcode 27 shipped, `xcode-select -p` pointed at the release Xcode (26.5) and
this project had to be built with `/Applications/Xcode-beta.app` (27.0 beta) via
`DEVELOPER_DIR`. The beta is gone; see the 2026-09-16 entry above for the current command.
The durable part still holds: never change the system-wide `xcode-select`, pass
`DEVELOPER_DIR` per invocation.

## 2026-09-02 — The Xcode target is a synchronized folder, so *everything* in `LSVR CineSched/` is in the target

The project uses `PBXFileSystemSynchronizedRootGroup`: there is no per-file membership list in
`project.pbxproj`. Any file dropped into `LSVR CineSched/` is automatically compiled (if `.swift`)
or copied into the app bundle as a resource (anything else). Two consequences:

- New Swift files need no project-file edits. Just create them in the folder.
- Non-source files in that folder (README, CHANGELOG, `1024.png`, the old `*.app.zip` bundles)
  get copied into the built `.app`. Keep large or unrelated files out of that folder.

## 2026-09-02 — `Info.plist` in the source folder is not the one the target uses *(superseded 2026-09-16)*

Historical: the target has `GENERATE_INFOPLIST_FILE = YES` and no `INFOPLIST_FILE` setting, so
Xcode synthesizes its own Info.plist and the hand-written `LSVR CineSched/Info.plist` was a plain
resource, not merged. That file is gone (see the 2026-09-16 entry on #3: it collided with the
generated plist in the flat iOS bundle). If document types need to take effect, use
`INFOPLIST_KEY_*` build settings; do not reintroduce a plist in the source folder.

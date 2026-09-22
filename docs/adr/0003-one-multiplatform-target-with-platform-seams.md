# 0003 — One multiplatform target with explicit platform seams

Status: Accepted (2026-09-16, #3, part of #1)

## Context

CineSched is becoming one app for Mac, iPad, iPhone and Vision Pro (#1). The Xcode target
already listed all four platforms, but the sources only compiled for the Mac: AppKit was
imported by the models, the color helpers, both schedule views, the importers, the persistence
layer and every exporter. The alternatives were separate targets per platform (a shared
framework plus three app targets) or one target whose sources build everywhere.

## Decision

Keep the single `LSVR CineSched` target and make its sources compile on every platform it
lists. Platform differences are confined to a small set of **seam files**, each of which
starts with a header comment saying why the seam exists and what the non-Mac side does:

| Seam | File | Mac side | iOS / visionOS side |
|---|---|---|---|
| File panels and bookmarks | `FilePanels.swift` | `NSOpenPanel` / `NSSavePanel`, `.withSecurityScope` bookmarks | Inert panels, plain bookmarks (document browser arrives in M2) |
| Text-field wrapper | `SelectAllTextField.swift` | `NSTextField` that selects all on focus | Plain `TextField` honouring the focus trigger |
| Window accessor | `WindowAccessor.swift` | Tints the `NSWindow` and title bar | Renders nothing |
| Modifier-key polling | `ModifierKeys.swift` | `NSEvent.modifierFlags` as `EventModifiers` | The latest press recorded at the editor's root (`InputPress`, #22): a pointer click's ⌘ and ⇧, none for a finger or a Pencil |
| Press observer | `PlatformPressObserver.swift` | An empty `NSView`; the Mac polls the event | A `UIGestureRecognizer` on the window that records each touch's `type` and the event's `modifierFlags` in `touchesBegan` and fails at once, never claiming a touch. Replaced a `SpatialEventGesture` over the editor, which swallowed every `Button` under it on iPadOS 27 |
| Mac-only control styles | `PlatformControlStyles.swift` | `.checkbox`, `.radioGroup`, `.borderlessButton`; `.inset` for the phone lists | Platform defaults; `.insetGrouped` for the iPhone editor's lists (#24) |
| Tab bar accessory | `PlatformTabAccessory.swift` | Nothing (the Mac's window is never compact) | iOS: `tabBarMinimizeBehavior(.onScrollDown)` and `tabViewBottomAccessory` carrying the iPhone editor's Today control (#24); visionOS: nothing, both are unavailable there and its windows are never compact |
| List edit mode | `PlatformListEditing.swift` | Nothing (the phone's lists never show) | `listReordering(_:)` and `listSelecting(_:)`: the `editMode` environment key, `@available(macOS, unavailable)`, so the Day screen's Strips list shows drag handles for its `onMove` reorder (#25) and the Boneyard tab's list shows selection circles for its multi-select Send to Day (#27) |
| Semantic backgrounds | `PlatformColors.swift` | `windowBackgroundColor` / `controlBackgroundColor` | UIKit system backgrounds |
| Window tabbing and root view | `CineSchedApp.swift` | `allowsAutomaticWindowTabbing = false`, `ContentView` and the menus (the Dark Mode item is the Mac's), the app delegate; the same `menus` builder serves both scenes (#22) | `ProjectEditor` (#17: `ContentView`'s three-column layout in regular width, `PhoneEditor` in compact, #24) and the system's `DocumentGroupLaunchScene` (#12; `PlatformPlaceholderView` until then) |
| Readable document types | `PlatformDocumentTypes.swift` | `.cinesched` and legacy `.json` (the viewer role, ADR 0005) | `.cinesched` only (ADR 0006) |
| Legacy `.json` handoff | `LegacyProjectHandoff.swift` | Moves a `.json`'s contents to an untitled document | Not built (#13 imports instead) |
| Conflict resolution owner | `PlatformConflictResolution.swift` | `systemPresentsConflictUI` true: NSDocument's conflict sheet resolves iCloud versions, `SyncMonitor` only observes (#15) | False: `SyncMonitor` runs `ConflictPolicy` over `NSFileVersion`'s conflict versions |
| Application delegate | `MacAppDelegate.swift` | Legacy working-copy recovery (#10), panel directory seeding (#12) | Not built |
| Export presentation | `PlatformExportPresentation.swift` | `previewsExports` false: the save panels in `ContentView+PDFExports.swift` (#23); PDFKit's `PDFView` as an `NSViewRepresentable`, compiled and never shown | True: the preview sheet with Done and Share (`PDFExportPresentation`); `PDFView` as a `UIViewRepresentable` for the iPad and the Vision Pro alike |
| Pasteboard responder | `PlatformPasteboardResponder.swift` | An `NSView` first responder answering `copy:`, `cut:`, `paste:` with `NSPasteboard` and validating the Edit items (#22); no undo duty, the window answers Edit ▸ Undo through NSDocument | A `UIView` first responder answering the same through `UIPasteboard` and `canPerformAction`; taken on every selection because SwiftUI's `copyable` family needs the focus system, which iPadOS engages only for a hardware keyboard. It also carries the document's undo manager for shake to undo and the three-finger gestures (they ask the first responder; the window's own manager is empty) and takes the status back whenever nothing holds it, through a run-loop observer; the iPhone editor installs it with inert actions (`undoGestures(_:)`) |
| Inspector column | `PlatformInspector.swift` | `.inspector(isPresented:)` (#17; the Mac never shows the three-column layout today) | iPadOS: `.inspector`; visionOS, where the modifier is unavailable: a trailing pane in an `HStack` |
| Editor sheet container | `PlatformEditorContainer.swift` | The editor's fixed frame (`EditorSheetSize`; a Mac sheet is sized by its content) (#19) | iPhone (by interface idiom): `presentationDetents` with a drag indicator; iPad and visionOS: `presentationSizing(.form)`, at the editor's own height for a short one; nothing in the inspector |

(Until #6 the two AppKit-drawn exporters and `ContentView+PDFExports.swift` (then `ProjectStore+PDFExports.swift`) were a temporary
seam, gated out of the non-Mac builds; that row is gone.)

Issue #3 also named "the hover modifier" as a seam. None was needed: `.onHover`, `.help`,
`.keyboardShortcut`, `.commands`, `NSItemProvider` and `DropDelegate` all compile on iOS and
visionOS, so `HoverTooltip.swift` builds everywhere unchanged and no seam file exists for it.

Rules that follow from this:

- The **pure core** (models, parsers, importers including the Highland zip reader, scanners,
  formatting, row logic, palette settings) contains no `#if os` at all. If a pure-core file
  needs a platform API, the API moves behind a seam instead.
- Views call the seam (`ModifierKeys.current`, `.checkboxToggleStyle()`,
  `Color.controlBackground`, `FilePanels.chooseFile`) rather than the platform API, so the
  views themselves carry no conditionals.
- Color arithmetic goes through SwiftUI's `Color.Resolved`, not `NSColor` / `UIColor`.
- Every exporter call site lives in `ContentView+PDFExports.swift` (the Mac, the iPad and
  the Vision Pro editor) or `PhoneExports.swift` (the iPhone editor, M4), so lifting the
  exporter gate later is a change to the exporters and those two files. (Since #23 each call
  site builds a `PDFExportRequest` and the seam says where it goes, so the same bytes reach
  the Mac's panel and the iPad's share sheet.)

## Consequences

- iOS, iPadOS and visionOS build and launch from the same sources as the Mac; the Mac's
  behavior and warning count are unchanged.
- The Swift Testing suite, exporter tests included, runs on the iOS and visionOS simulators
  as well as the Mac.
- No exporter is a seam any more. ADR 0002's "shared in-repo PDF drawing helper" is
  `PDFCanvas` (#4): CoreGraphics + CoreText with platform-neutral fonts and colors, laying
  text out the way TextKit did so migrated output stays where it was. `StripboardPDFExporter`
  and `ShootingSchedulePDFExporter` (#4), `PDFExporter` and `CallSheetExporter` (#5), and
  `BreakdownExporter` and `DaysOutOfDaysExporter` (#6) are on it, every exporter is verified
  pixel-identical to its AppKit output on the Mac, and `ContentView+PDFExports.swift` builds
  everywhere (its save panel is the `FilePanels` seam). An exporter must not grow an
  `#if os`; it draws through the helper or the helper grows.
- `FilePanels` is inert off the Mac by design; the document infrastructure of milestone 2
  replaced it for the project's own files, and the preview sheet with Share (#23,
  `PlatformExportPresentation`) for the PDF exports, rather than growing an iOS document
  picker inside it.
- The hand-written `LSVR CineSched/Info.plist` was deleted: it was never used by the target
  (`GENERATE_INFOPLIST_FILE = YES`) and, because the folder is synchronized, it was copied
  into the bundle as a resource, which collides with the generated `Info.plist` in a flat iOS
  bundle.

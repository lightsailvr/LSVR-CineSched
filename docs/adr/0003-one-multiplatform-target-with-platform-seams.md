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
| Modifier-key polling | `ModifierKeys.swift` | `NSEvent.modifierFlags` as `EventModifiers` | Always empty |
| Mac-only control styles | `PlatformControlStyles.swift` | `.checkbox`, `.radioGroup`, `.borderlessButton` | Platform defaults |
| Semantic backgrounds | `PlatformColors.swift` | `windowBackgroundColor` / `controlBackgroundColor` | UIKit system backgrounds |
| Window tabbing and root view | `CineSchedApp.swift` | `allowsAutomaticWindowTabbing = false`, `ContentView` | `PlatformPlaceholderView` |
| Placeholder root | `PlatformPlaceholderView.swift` | Not built | Names the platform as in progress |
| Exporters (temporary) | `*Exporter.swift`, `ProjectStore+PDFExports.swift` | The six AppKit-drawn PDF generators and their save actions | Gated out; the same entry points raise an alert |

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
- Every exporter call site lives in `ProjectStore+PDFExports.swift`, so lifting the exporter
  gate later is a change to the exporters and that one file.

## Consequences

- iOS, iPadOS and visionOS build and launch from the same sources as the Mac; the Mac's
  behavior and warning count are unchanged.
- The Swift Testing suite runs on an iOS simulator as well as the Mac; only the exporter tests
  are gated with the exporters.
- The exporter gate is a debt: ADR 0002's "shared in-repo PDF drawing helper" is what removes
  it (CoreGraphics + CoreText with platform-neutral fonts and colors), per the exporter tickets
  under #1.
- `FilePanels` is inert off the Mac by design; the document infrastructure of milestone 2
  replaces it rather than growing an iOS document picker inside it.
- The hand-written `LSVR CineSched/Info.plist` was deleted: it was never used by the target
  (`GENERATE_INFOPLIST_FILE = YES`) and, because the folder is synchronized, it was copied
  into the bundle as a resource, which collides with the generated `Info.plist` in a flat iOS
  bundle.

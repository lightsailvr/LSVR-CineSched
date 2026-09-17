# 0004 — One project document on every platform

Status: Accepted (2026-09-16, #7, part of #1). The Mac adopted it in #8 (same day): the
"next ticket" below is done; `DocumentGroup` in CineSchedApp owns one document per window,
menus reach it through `ProjectCommands` (a focused scene value), and the manual undo stack,
the recent-files bookmarks and the two-second autosave are gone. The first-launch recovery
of the UserDefaults working copy landed in #10 (2026-09-17): `LegacyWorkingCopyRecovery` is
the pure decision, `MacAppDelegate` opens through `NSDocumentController` and removes the keys.

## Context

The Mac app keeps the whole project as `@State` in `ContentView`: a `.json` file is only
written on a manual Save, the working copy is a UserDefaults blob autosaved two seconds
after the last change, and undo is a hand-rolled 30-deep stack of `(allScenes, shootDays)`
that does not cover call sheets, production info or the title. None of that can be the
source of truth for a project that iPad, iPhone and Vision Pro also edit through iCloud
Drive (#1): the file on disk is routinely behind the real state, and there is no seam a
second platform could plug into.

macOS 27, iOS 27 and visionOS 27 add a document API to SwiftUI (`Document`,
`ReadableDocument`, `WritableDocument`, `DocumentReader`, `DocumentWriter`,
`URLDocumentConfiguration`) whose document is an observable reference type with an
explicit snapshot type, whose reading and writing run off the main actor, and whose
autosave is driven by registered undo actions. The older `FileDocument` /
`ReferenceFileDocument` protocols are not deprecated, but they carry no snapshot type
and no undo-driven autosave.

## Decision

Every platform reads, writes and edits the same **project document**, `ProjectDocument`
(`ProjectDocument.swift`):

- An `@Observable` final class conforming to the 27 `Document` protocol. Its snapshot
  type is `ProjectData` itself (Boneyard scenes, shoot days, title, created date, shift
  mode, production info), so reading, writing, undo and the coming conflict decisions all
  speak one value type. There is no second "document model"; `ProjectData` is the model.
- Its reader and writer (`ProjectDocumentReader`, `ProjectDocumentWriter`) work over
  URLs and are `@concurrent`. They go through `ProjectCodec`, the one encoder/decoder
  (pretty-printed JSON, ISO dates, the two legacy shapes), which was extracted from the
  old `FileDocument` wrapper so the manual Save, the UserDefaults working copy and the
  document all write identical bytes. The model's `Codable` conformances are
  `nonisolated` for that reason: the codec must be callable off the main actor without
  isolation warnings.
- Readable types are the native `.cinesched` (ADR 0005) and `.json`; the only writable
  type is the native one. A legacy `.json` opens; its first save goes to a `.cinesched`.
- Applying a snapshot replaces the model wholesale. Correctness first; a field-level
  merge is a later optimisation, not a requirement.
- There is **one edit funnel**: `perform(_:coalescing:undoManager:_:)`. It mutates the
  snapshot in place, registers an undo action with the supplied `UndoManager` that
  restores the whole previous `ProjectData` (undo re-registers the reverse, which is
  redo), and opens an explicit undo group per edit. Edits that share an `EditGesture`
  token (a drag, a typing burst) fold into the first edit's step, provided they arrive
  with the same undo manager. The environment's manager also groups by run-loop event, so
  untokened edits made in one event undo together in the app anyway; the token exists
  for gestures that span events. Every mutation path in the app will route through it,
  because the document infrastructure autosaves only from registered undo actions; a
  mutation that bypasses `perform` is a mutation that never saves and cannot be undone.

This ticket builds the document and its tests; the Mac keeps its `@State` ownership until
the next ticket wires `DocumentGroup`, focused-value menus and the migration from the
UserDefaults working copy. The manual undo stack, the recent-files bookmarks and the
two-second autosave are retired then, not now.

## Consequences

- The file format does not change (ADR 0001 stands): the document writes the same JSON
  the app always has, so every lineage still opens the file after renaming it to `.json`.
- Undo now covers everything in the snapshot, including call sheets, production info and
  the title, with no per-field bookkeeping. The cost is a full `ProjectData` copy per undo
  step, which is a value-type copy of a few hundred scenes; acceptable, and measurable if
  it ever is not.
- `ProjectData`, `ShootDay` and `CallSheetData` are `Equatable` so tests (and later the
  migration and conflict decisions) can compare whole snapshots.
- The Mac's test host resolves the exported type at runtime, so the document tests run on
  the Mac and on the iOS and visionOS simulators alike; they drive the reader, writer,
  type and funnel from outside with a real `UndoManager` (`groupsByEvent` off, because a
  test never turns the run loop).
- `FileDocument` is gone from the codebase. Do not bring it back for a second document
  type; extend `ProjectDocument` or add another `Document`.

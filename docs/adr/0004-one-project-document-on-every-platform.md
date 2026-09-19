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

## Amendment (2026-09-18, #11)

One write bypasses `perform` by design: a project that arrives without a palette (every
file from before #11, and File ▸ New) takes the device's legacy strip color overrides as
its own in the document's constructors and in `apply`. The document has no undo manager
to register with there, and an adoption must not appear as an Undo step the moment a file
opens, so it lives in memory until the project's next registered edit autosaves it. The
rule stands for everything the user does; this is the one seam-owned exception, tested
in `ProjectDocumentTests`.

## Amendment (2026-09-19, #14, #15)

Two limitations of the document surfaced while wiring the sync state and the conflict
notice, and shape how they are built:

- **The document is not told about a conflict.** The 27 `Document` protocol has no
  presenter callbacks (`presentedItemDidGainVersion`, `presentedItemDidChangeUbiquityAttributes`
  are NSDocument's and UIDocument's, not the SwiftUI document's), and nothing in the
  protocol says why an `apply` arrived. So the sync state is observed from outside the
  document (`SyncMonitor` reads the URL's resource values on the document's own counters,
  a poll, a metadata query and the path monitor), and a conflict is discovered by asking
  `NSFileVersion` for unresolved conflict versions on every restore rather than by being
  told. `URLDocumentConfiguration` does provide what the resolution needs — the URL, the
  last content modification date and a file coordinator that knows the document is the
  presenter — and `ProjectDocument` exposes those three.
- **The Mac's infrastructure resolves conflicts itself, before the app can look.** The Mac
  scene runs on NSDocument, whose conflict sheet and Versions browser handle a conflict
  version the moment the window is main; an app-side resolution there would race the
  sheet, and issue #15 wants the sheet. Hence the `PlatformConflictResolution` seam: the
  app resolves only on iOS and visionOS. Where the system chooses first, the only thing
  the document can still observe is that a snapshot from disk replaced edits it had not
  written: `apply` records them (`replacedUnsavedEdits`, from the `snapshot(contentType:)`
  and `apply` bookkeeping that defines `hasUnsavedEdits`), and the pre-agreed fallback
  notice is raised from that record. The record is one field more than the protocol's
  contract asks for, kept in the document because only `apply` sees the project it is
  about to replace.

Neither changes the decision: one document, one snapshot type, one funnel. The resolution
and the restore are both `perform`s, so they autosave and undo like any edit.

## Amendment (2026-09-19, #15 review): a conflict version outlives the `perform` that applied it

A `perform` puts the winning version's snapshot in memory; the file gets it when the
infrastructure autosaves from the registered undo action, seconds later on the Mac and up
to a minute later on iOS. Removing the winner's conflict version at resolution time, as the
first wiring did, left that window in which the winning contents existed nowhere on disk
(the file still held the loser's), and a `perform` without an undo manager registers
nothing, so the window never closed. Two rules follow, both in `ConflictResolutionPlan`
(pure, tested) and wired by `SyncMonitor`:

- **The document reports what the file holds.** `ProjectDocument.writtenChangeCount` is
  the change count of the last snapshot whose write the writer reported complete
  (`ProjectDocumentWriter.didWrite`, after the atomic write, not when the snapshot was
  asked for), or the count a snapshot from disk arrived at. It is the one thing the
  document keeps that the protocol does not ask for and that only the writer can supply;
  it exists so the monitor can tell "applied" from "written".
- **Losers go at once, the winner's version goes after the write, and nothing goes
  without an undo manager.** The losing conflict versions are marked resolved and removed
  under a coordinated metadata-only write as soon as the policy decides: their contents
  are retained in memory for the session (Restore other version) or discarded by the
  policy's own rule, and the file never needed them. The winner's own conflict version,
  when another version won, is left unresolved and untouched (`PendingConflictRemoval`)
  until `writtenChangeCount` reaches the change count the `perform` produced, then
  resolved and removed; the monitor's checks skip it meanwhile so it is not decided
  twice. When no undo manager is attached (the editor's environment has not supplied one
  yet) the decision is not acted on at all: no `perform`, nothing resolved, no notice,
  logged, and retried when `attach(undoManager:)` brings one.

The residual, on every platform that runs the policy (iOS, visionOS; the Mac observes
only): if the app is killed between the `perform` and the write, the file still holds the
loser's contents and the winner's version is still listed as an unresolved conflict, so
the next launch's check runs the policy again, applies the winner again and raises the
notice again, now naming the file's saving device as the version set aside. Nothing is
lost and nothing is left for the user to find; the cost is that the resolution happens
twice. That is preferable to marking the winner's version resolved at once (which would
leave the winning contents in a version the system no longer reports and the app never
looks at, i.e. lost on iOS) and to removing it at once (lost outright). The losers' early
removal has no residual: an editor closed or killed after the decision has already
retained or discarded them by the policy's rule, and a version a check has read but not
decided is untouched.

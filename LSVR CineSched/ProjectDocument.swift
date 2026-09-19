// ProjectDocument.swift
// The one project document every platform reads, writes and edits (#7, ADR 0004). An
// observable reference type on the 27 `Document` protocol whose snapshot is `ProjectData`
// itself, so reading, writing, undo and (later) conflict decisions all speak one value
// type. `DocumentGroup` in CineSchedApp makes one per window on the Mac (#8), where
// `ContentView` edits it, and one per open file on iOS and visionOS (#12), where
// `MinimalProjectEditor` does until the full editors land.
//
// Three seams, each testable on its own:
//   - `ProjectDocumentReader` / `ProjectDocumentWriter`: URL in, `ProjectData` out (and
//     back) through `ProjectCodec`, off the main actor. The only writable type is the
//     native `.cinesched`; on the Mac `.json` is readable so legacy files still open
//     (`PlatformDocumentTypes`, a seam, decides per platform).
//   - `perform(_:coalescing:undoManager:_:)`: the single edit funnel. Every mutation of the
//     project goes through it, which is what registers the undo action holding the previous
//     snapshot; the document infrastructure autosaves only from registered undo actions.
//   - `UTType.cineschedProject`: the exported type declared in Config/Info.plist (ADR 0005).
//
// It is also where a project without a palette adopts the device's legacy color
// overrides (#11): every project entering a document, whether made new or read from disk,
// passes through `adoptingDevicePalette`.
//
// For the sync state and the conflict notice (#14, #15, `SyncMonitor`) it exposes what
// the configuration knows (`fileURL`, `lastContentModificationDate`, `makeFileCoordinator`)
// and keeps three things the protocol does not ask for: when the project last changed
// here (`lastEditDate`), whether it holds edits the file lacks (`hasUnsavedEdits`, from
// the counts at the last `snapshot(contentType:)` and `apply`), and the edits an `apply`
// replaced before they were written (`replacedUnsavedEdits`), which only `apply` can see.

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content type

extension UTType {
    /// `com.lsvr.cinesched.project`, extension `.cinesched`, conforming to JSON. Declared
    /// in Config/Info.plist so the system resolves it; the fallback here only matters if
    /// a host has not registered the bundle.
    nonisolated static let cineschedProject = UTType(exportedAs: "com.lsvr.cinesched.project", conformingTo: .json)
}

// MARK: - Edit gesture

/// A token that groups the edits of one user gesture (a drag, a typing burst) into a
/// single undo step. Make one when the gesture starts and pass it to every `perform`
/// the gesture makes; the first edit registers the undo action and the rest ride on it.
struct EditGesture: Hashable {
    private let id = UUID()
    init() {}
}

// MARK: - New project

extension ProjectData {
    /// What File ▸ New opens: no scenes, the default title, and an empty run of shoot days
    /// from three days before `date` to thirty after it, the span the Mac window has always
    /// started with. The range picker in the sidebar reads its dates from these days.
    static func newProject(around date: Date = Date(), calendar: Calendar = .current) -> ProjectData {
        let start = calendar.date(byAdding: .day, value: -3, to: date) ?? date
        let end   = calendar.date(byAdding: .day, value: 30, to: date) ?? date
        return ProjectData(allScenes: [], shootDays: generateDays(from: start, to: end, calendar: calendar), createdDate: date)
    }
}

// MARK: - Document

@Observable
final class ProjectDocument: Document {

    /// The whole project: Boneyard scenes, shoot days, title, created date, shift mode
    /// and production info. Read freely; change it only through `perform`.
    private(set) var project: ProjectData

    /// Bumped on every change to `project`, however it arrives: an edit through `perform`,
    /// an undo or redo, or a snapshot from disk. An edit that leaves the project equal does
    /// not count, except one folded into an open gesture, which is applied without the
    /// compare and counts regardless. The editor keys what it derives from the project
    /// (sorted Boneyard, conflict sets, lock drift) on this, so a body pass never has to
    /// compare two whole projects to learn whether anything moved (#34).
    private(set) var changeCount = 0

    /// Bumped every time the project is replaced wholesale — an undo, a redo, or a
    /// snapshot arriving from disk — as opposed to edited through `perform`. Views that
    /// keep drag state keyed to the old model (a highlighted drop target, say) watch it,
    /// because nothing else tells them the strips under the pointer just changed.
    private(set) var restoreCount = 0

    /// Where the document lives, when the system opened or saved it somewhere; nil for an
    /// untitled window. Read for conveniences such as where a PDF export panel opens, and
    /// by `SyncMonitor` for the file's ubiquitous resource values (#14).
    var fileURL: URL? { configuration?.fileURL }

    /// The file's content modification date as the infrastructure last saw it; nil for an
    /// untitled window or a document built in a test. The conflict policy dates the
    /// current version by it when the document holds nothing the file lacks (#15).
    var lastContentModificationDate: Date? { configuration?.lastContentModificationDate }

    /// The coordinator to read the file's other versions and remove them with (#15): the
    /// infrastructure's own, which knows the document is the file's presenter and so will
    /// not wait on it; a plain coordinator for a document with no configuration. Nothing
    /// touches a version's URL outside a coordinated access.
    func makeFileCoordinator() -> NSFileCoordinator {
        configuration?.makeFileCoordinator() ?? NSFileCoordinator(filePresenter: nil)
    }

    /// True once the file's contents have arrived through `apply`; false for a document
    /// still showing its construction-time project.
    var hasLoadedSnapshot: Bool { restoreCount > 0 }

    /// When the project last changed on this device (an edit, an undo, a redo); nil until
    /// it has. Dates the current version in a conflict decision (#15).
    private(set) var lastEditDate: Date?

    /// The change count the infrastructure last wrote (it asks for `snapshot(contentType:)`
    /// to write) or applied; while `changeCount` is past it the document holds edits the
    /// file does not.
    private var savedChangeCount = 0

    /// Whether the project holds changes the file has not received yet.
    var hasUnsavedEdits: Bool { changeCount != savedChangeCount }

    /// Edits a snapshot from disk replaced before they were written: the project as it was
    /// the moment `apply` ran over a document with unsaved edits, and when they were made.
    /// Nothing else can see them go, and the fallback conflict notice (#15) is about
    /// exactly this; `SyncMonitor` takes the record on the restore that produced it.
    struct ReplacedEdits {
        var project:  ProjectData
        var editedAt: Date?
    }

    private(set) var replacedUnsavedEdits: ReplacedEdits?

    /// Hands over and clears the record of the edits the last `apply` replaced, if any.
    func takeReplacedUnsavedEdits() -> ReplacedEdits? {
        defer { replacedUnsavedEdits = nil }
        return replacedUnsavedEdits
    }

    /// Whether an opened file is a legacy `.json` rather than the native type. The document
    /// infrastructure autosaves an opened file in place within seconds of an edit and does
    /// not treat a readable-but-unwritable type as read-only, so the Mac never edits such a
    /// file: `LegacyProjectHandoff` hands its contents to a fresh untitled document and
    /// closes the window (story 13 of #1: the original is left untouched, the first Save
    /// asks for a `.cinesched` destination).
    nonisolated static func isLegacySource(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.pathExtension.lowercased() != (UTType.cineschedProject.preferredFilenameExtension ?? "cinesched")
    }

    /// The file URL and coordinator the document infrastructure hands `DocumentGroup`'s
    /// `makeDocument`; nil for a document built in a test or in memory.
    private let configuration: URLDocumentConfiguration?

    /// The pre-#11 per-device strip color overrides (`SceneColorSettings.deviceOverrides`),
    /// handed in by whoever makes the document so a test can be any device; nil when this
    /// device never customized a color. A project that arrives without a palette takes
    /// them as its own, once (story 19 of #1); a project that has one ignores them.
    private let deviceOverrides: ScenePalette?

    /// The gesture whose undo action is currently open, and the manager it was registered
    /// with, so a further edit with the same token and manager merges into it instead of
    /// registering another. Closed by an edit with a different (or no) token or manager,
    /// by undo or redo, and by a snapshot arriving from disk.
    private var openGesture: (token: EditGesture, undoManager: UndoManager)?

    init(
        _ project: ProjectData = ProjectData(allScenes: [], shootDays: []),
        configuration: URLDocumentConfiguration? = nil,
        deviceOverrides: ScenePalette? = nil
    ) {
        self.deviceOverrides = deviceOverrides
        self.project         = Self.adoptingDevicePalette(project, from: deviceOverrides)
        self.configuration   = configuration
    }

    /// For the system's new-document action, whose factory closure runs off the main
    /// actor: an untitled document holding `project` (the legacy handoff uses it).
    nonisolated init(untitled project: ProjectData, deviceOverrides: ScenePalette? = nil) {
        // The Observation macro's backing storage: the tracked setter is main-actor-only.
        self.deviceOverrides = deviceOverrides
        self._project        = Self.adoptingDevicePalette(project, from: deviceOverrides)
        self.configuration   = nil
    }

    /// `project` with the device's overrides as its palette when it had none and the
    /// device has some; otherwise `project` as it came. The adoption lives only in the
    /// document until its next registered edit autosaves it: the document infrastructure
    /// writes from undo actions, and this is not one (it must not show up as an Undo step
    /// the moment a file opens). Until then, reopening on this device adopts the same
    /// colors again, so nothing visible changes.
    nonisolated private static func adoptingDevicePalette(_ project: ProjectData, from deviceOverrides: ScenePalette?) -> ProjectData {
        guard project.palette == nil, let deviceOverrides else { return project }
        var adopted = project
        adopted.palette = deviceOverrides
        return adopted
    }

    // MARK: - Reading

    /// The native type everywhere; `.json` too on the Mac, whose viewer role for a legacy
    /// file (`isLegacySource`, `LegacyProjectHandoff`) the other platforms do not have.
    nonisolated static var readableContentTypes: [UTType] { PlatformDocumentTypes.readable }

    func reader(configuration: ReadConfiguration) -> ProjectDocumentReader {
        ProjectDocumentReader()
    }

    /// Replaces the model wholesale: correctness first, incrementality later (#1). A
    /// snapshot without a palette (every file from before #11) adopts this device's
    /// legacy overrides on the way in; see `adoptingDevicePalette`. A snapshot that lands
    /// on edits the file never received (iCloud brought a newer version, or the Mac's
    /// conflict sheet chose one) keeps those edits in `replacedUnsavedEdits` for the
    /// fallback notice (#15); the first load of a fresh document replaces nothing.
    func apply(snapshot: ProjectData, previous: ProjectData?) async throws {
        if hasUnsavedEdits {
            replacedUnsavedEdits = ReplacedEdits(project: project, editedAt: lastEditDate)
        }
        openGesture      = nil
        project          = Self.adoptingDevicePalette(snapshot, from: deviceOverrides)
        changeCount     += 1
        restoreCount    += 1
        savedChangeCount = changeCount
    }

    // MARK: - Writing

    nonisolated static var writableContentTypes: [UTType] { [.cineschedProject] }

    func writer(configuration: WriteConfiguration) -> ProjectDocumentWriter {
        ProjectDocumentWriter()
    }

    /// What the infrastructure writes; asking for it is the write, as far as the unsaved
    /// edits record is concerned (a write that then fails is the infrastructure's to
    /// retry, and it asks again).
    func snapshot(contentType: UTType) async throws -> ProjectData {
        savedChangeCount = changeCount
        return project
    }

    // MARK: - Edit funnel

    /// Applies `edit` to the project and registers an undo action that restores the
    /// snapshot from before it (redo re-registers the same way). Passing the same
    /// `gesture` token as the previous call, with the same undo manager, folds this edit
    /// into that call's undo step. `actionName` labels the Undo and Redo menu items. With
    /// no undo manager the edit still happens, just without a way back. An edit that
    /// leaves the project equal registers nothing: editors write their whole value back on
    /// Save whether or not the user changed it, and that must not dirty the document.
    ///
    /// The manager also groups by run-loop event in the app, so two untokened edits made
    /// in one event (one drop handler, say) undo together there; the token is for edits
    /// that span events, which is what a drag or a typing burst is.
    func perform(
        _ actionName: String? = nil,
        coalescing gesture: EditGesture? = nil,
        undoManager: UndoManager?,
        _ edit: (inout ProjectData) -> Void
    ) {
        if let gesture, let open = openGesture, open.token == gesture, open.undoManager === undoManager {
            edit(&project)
            changeCount  += 1
            lastEditDate  = Date()
            return
        }
        let before = project
        edit(&project)
        guard project != before else {
            // Nothing to register; this edit still closes the open gesture, as any edit
            // that reaches this point (another token, or none) would have.
            openGesture = nil
            return
        }
        changeCount  += 1
        lastEditDate  = Date()
        guard let undoManager else {
            openGesture = nil
            return
        }
        // One explicit group per edit, so a step is a step whether or not the manager
        // groups by run-loop event (the tests turn that off).
        undoManager.beginUndoGrouping()
        registerUndo(restoring: before, named: actionName, with: undoManager)
        undoManager.endUndoGrouping()
        openGesture = gesture.map { ($0, undoManager) }
    }

    /// Undo swaps the whole snapshot back and registers the reverse, which is the redo;
    /// registering while the manager is undoing lands on the redo stack by itself. The
    /// action name rides along so Undo and Redo keep their labels across the swap.
    private func registerUndo(restoring snapshot: ProjectData, named actionName: String?, with undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { document in
            let current = document.project
            document.openGesture   = nil
            document.project       = snapshot
            document.changeCount  += 1
            document.restoreCount += 1
            document.lastEditDate  = Date()
            document.registerUndo(restoring: current, named: actionName, with: undoManager)
        }
        if let actionName { undoManager.setActionName(actionName) }
    }
}

// MARK: - Reader and writer

/// Reads a `.cinesched` or legacy `.json` file into a `ProjectData` off the main actor.
nonisolated struct ProjectDocumentReader: DocumentReader {
    @concurrent
    func read(from source: URL, progress: consuming Subprogress) async throws -> sending ProjectData {
        let manager = progress.start(totalCount: 1)
        defer { manager.complete(count: 1) }
        let data = try Data(contentsOf: source)
        do {
            return try ProjectCodec.decode(data)
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSURLErrorKey:        source,
                NSUnderlyingErrorKey: error,
            ])
        }
    }
}

/// Writes a `ProjectData` as the codec's JSON, atomically, off the main actor. Never to a
/// legacy `.json`: that file is opened in a viewer role and must stay byte-identical, and
/// the writer is the last line of defence should any path try (see `isLegacySource`).
nonisolated struct ProjectDocumentWriter: DocumentWriter {
    @concurrent
    func write(snapshot: ProjectData, to destination: URL, previous: ProjectData?, progress: consuming Subprogress) async throws {
        let manager = progress.start(totalCount: 1)
        defer { manager.complete(count: 1) }
        guard !ProjectDocument.isLegacySource(destination) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [
                NSURLErrorKey: destination,
                NSLocalizedDescriptionKey: "CineSched does not write legacy .json project files. Save the project as a .cinesched file instead.",
            ])
        }
        try ProjectCodec.encode(snapshot).write(to: destination, options: .atomic)
    }
}

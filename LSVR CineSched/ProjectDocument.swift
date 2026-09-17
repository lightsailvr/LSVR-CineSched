// ProjectDocument.swift
// The one project document every platform reads, writes and edits (#7, ADR 0004). An
// observable reference type on the 27 `Document` protocol whose snapshot is `ProjectData`
// itself, so reading, writing, undo and (later) conflict decisions all speak one value
// type. On the Mac, `DocumentGroup` in CineSchedApp makes one per window (#8) and
// `ContentView` edits it; the other platforms adopt it with their own scenes (#12).
//
// Three seams, each testable on its own:
//   - `ProjectDocumentReader` / `ProjectDocumentWriter`: URL in, `ProjectData` out (and
//     back) through `ProjectCodec`, off the main actor. The only writable type is the
//     native `.cinesched`; `.json` is readable so legacy files still open.
//   - `perform(_:coalescing:undoManager:_:)`: the single edit funnel. Every mutation of the
//     project goes through it, which is what registers the undo action holding the previous
//     snapshot; the document infrastructure autosaves only from registered undo actions.
//   - `UTType.cineschedProject`: the exported type declared in Config/Info.plist (ADR 0005).

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
    /// untitled window. Only read for conveniences such as where a PDF export panel opens.
    var fileURL: URL? { configuration?.fileURL }

    /// True once the file's contents have arrived through `apply`; false for a document
    /// still showing its construction-time project.
    var hasLoadedSnapshot: Bool { restoreCount > 0 }

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

    /// The gesture whose undo action is currently open, and the manager it was registered
    /// with, so a further edit with the same token and manager merges into it instead of
    /// registering another. Closed by an edit with a different (or no) token or manager,
    /// by undo or redo, and by a snapshot arriving from disk.
    private var openGesture: (token: EditGesture, undoManager: UndoManager)?

    init(_ project: ProjectData = ProjectData(allScenes: [], shootDays: []), configuration: URLDocumentConfiguration? = nil) {
        self.project       = project
        self.configuration = configuration
    }

    /// For the system's new-document action, whose factory closure runs off the main
    /// actor: an untitled document holding `project` (the legacy handoff uses it).
    nonisolated init(untitled project: ProjectData) {
        // The Observation macro's backing storage: the tracked setter is main-actor-only.
        self._project      = project
        self.configuration = nil
    }

    // MARK: - Reading

    nonisolated static var readableContentTypes: [UTType] { [.cineschedProject, .json] }

    func reader(configuration: ReadConfiguration) -> ProjectDocumentReader {
        ProjectDocumentReader()
    }

    /// Replaces the model wholesale: correctness first, incrementality later (#1).
    func apply(snapshot: ProjectData, previous: ProjectData?) async throws {
        openGesture   = nil
        project       = snapshot
        changeCount  += 1
        restoreCount += 1
    }

    // MARK: - Writing

    nonisolated static var writableContentTypes: [UTType] { [.cineschedProject] }

    func writer(configuration: WriteConfiguration) -> ProjectDocumentWriter {
        ProjectDocumentWriter()
    }

    func snapshot(contentType: UTType) async throws -> ProjectData {
        project
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
            changeCount += 1
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
        changeCount += 1
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

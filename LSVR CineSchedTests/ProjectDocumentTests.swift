//
//  ProjectDocumentTests.swift
//  LSVR CineSchedTests
//
//  ProjectDocument is the one project document every platform reads, writes and edits
//  (#7). These tests drive its three seams from outside: the reader and writer over a
//  temporary directory, the native `.cinesched` type, and the `perform` edit funnel
//  against a real UndoManager.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import LSVR_CineSched

@MainActor
struct ProjectDocumentTests {

    /// Built once per test: the fixture mints fresh scene and day IDs every time.
    private let project = ProjectCodecTests.project

    /// The app's undo manager closes a group at the end of every run-loop event; a test
    /// never turns the run loop, so it would fold every edit into one step. Turning that
    /// off leaves only the groups `perform` opens itself, which is what is under test.
    private func makeUndoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    /// A fresh directory per test; removed when the test ends.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectDocumentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// What the document infrastructure hands a reader or writer to report into.
    private func subprogress() -> Subprogress {
        ProgressManager(totalCount: 1).subprogress(assigningCount: 1)
    }

    // MARK: - Content types

    @Test func nativeTypeResolvesAtRuntimeAndConformsToJSON() throws {
        let declared = try #require(UTType("com.lsvr.cinesched.project"))
        #expect(declared == .cineschedProject)
        #expect(declared.conforms(to: .json))
        #expect(declared.preferredFilenameExtension == "cinesched")
        #expect(UTType(filenameExtension: "cinesched") == .cineschedProject)
    }

    @Test func readsNativeAndJSONButWritesOnlyNative() {
        #expect(ProjectDocument.readableContentTypes == [.cineschedProject, .json])
        #expect(ProjectDocument.writableContentTypes == [.cineschedProject])
    }

    // MARK: - New document

    @Test func aNewProjectIsUntitledAndSpansAMonthAroundToday() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let today = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 15)))

        let fresh = ProjectData.newProject(around: today, calendar: utc)
        #expect(fresh.projectTitle == "Untitled Movie")
        #expect(fresh.allScenes.isEmpty)
        #expect(fresh.isShiftModeEnabled == false)
        #expect(fresh.productionInfo == nil)
        #expect(fresh.shootDays.count == 34)
        #expect(fresh.shootDays.first?.date == utc.date(from: DateComponents(year: 2026, month: 9, day: 13)))
        #expect(fresh.shootDays.last?.date  == utc.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        #expect(fresh.shootDays.allSatisfy { $0.scenes.isEmpty && !$0.hasCallSheetData && $0.dayType == .shoot })
        #expect(utc.isDate(fresh.createdDate, inSameDayAs: today))
    }

    // MARK: - Reader and writer

    @Test func writingThenReadingANativeFileYieldsAnEqualProject() async throws {
        try await withTemporaryDirectory { dir in
            let url      = dir.appendingPathComponent("Long Way Home.cinesched")
            let document = ProjectDocument(project)
            let snapshot = try await document.snapshot(contentType: .cineschedProject)
            try await ProjectDocumentWriter().write(snapshot: snapshot, to: url, previous: nil, progress: subprogress())

            let read = try await ProjectDocumentReader().read(from: url, progress: subprogress())
            #expect(read == project)

            // The bytes are the codec's, so a legacy build renaming it to .json still opens it.
            #expect(try ProjectCodec.decode(Data(contentsOf: url)) == project)
        }
    }

    @Test func readerOpensCurrentAndLegacyJSONFixtures() async throws {
        try await withTemporaryDirectory { dir in
            let current = dir.appendingPathComponent("current.json")
            try ProjectCodec.encode(project).write(to: current)
            let legacy = dir.appendingPathComponent("legacy.json")
            try Data(ProjectCodecTests.legacyJSON.utf8).write(to: legacy)

            let reader = ProjectDocumentReader()
            let fromCurrent = try await reader.read(from: current, progress: subprogress())
            #expect(fromCurrent == project)
            let fromLegacy = try await reader.read(from: legacy, progress: subprogress())
            #expect(fromLegacy.projectTitle == ProjectCodec.legacyProjectTitle)
            #expect(fromLegacy.allScenes.map(\.title) == ["2. EXT. PLAYA. DIA"])
        }
    }

    @Test func applyReplacesTheWholeSnapshot() async throws {
        let document = ProjectDocument(ProjectData(allScenes: [], shootDays: []))
        try await document.apply(snapshot: project, previous: nil)
        #expect(document.project == project)
    }

    // MARK: - Edit funnel

    @Test func performUndoAndRedoRestoreTheWholeSnapshot() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let before      = document.project

        document.perform(undoManager: undoManager) { data in
            data.projectTitle = "Renamed"
            data.productionInfo?.directorName = "Someone Else"
            data.shootDays[3].callSheet.generalCallTime = "5:00 AM"
            data.shootDays[3].callSheet.castCallEntries.removeLast()
            data.allScenes.removeFirst()
            data.shootDays[1].scenes.append(PDFFixture.makeScene(99))
            data.isShiftModeEnabled = false
        }
        let after = document.project
        #expect(after != before)
        #expect(after.projectTitle == "Renamed")
        #expect(undoManager.canUndo)
        #expect(!undoManager.canRedo)

        undoManager.undo()
        #expect(document.project == before)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(document.project == after)
        #expect(undoManager.canUndo)
    }

    @Test func editsWithoutATokenAreSeparateUndoSteps() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let original    = document.project

        document.perform(undoManager: undoManager) { $0.projectTitle = "One" }
        document.perform(undoManager: undoManager) { $0.projectTitle = "Two" }
        #expect(document.project.projectTitle == "Two")

        undoManager.undo()
        #expect(document.project.projectTitle == "One")
        undoManager.undo()
        #expect(document.project == original)
        #expect(!undoManager.canUndo)
    }

    @Test func editsSharingAGestureTokenUndoAsOneStep() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let original    = document.project
        let drag        = EditGesture()

        document.perform(coalescing: drag, undoManager: undoManager) { $0.shootDays[0].dayNote = "F" }
        document.perform(coalescing: drag, undoManager: undoManager) { $0.shootDays[0].dayNote = "Fl" }
        document.perform(coalescing: drag, undoManager: undoManager) { $0.shootDays[0].dayNote = "Fly" }
        #expect(document.project.shootDays[0].dayNote == "Fly")

        undoManager.undo()
        #expect(document.project == original)
        #expect(!undoManager.canUndo)

        undoManager.redo()
        #expect(document.project.shootDays[0].dayNote == "Fly")
    }

    @Test func aNewTokenOrNoTokenClosesTheOpenGesture() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let original    = document.project
        let first       = EditGesture()
        let second      = EditGesture()

        document.perform(coalescing: first, undoManager: undoManager)  { $0.projectTitle = "A" }
        document.perform(coalescing: first, undoManager: undoManager)  { $0.projectTitle = "AB" }
        document.perform(coalescing: second, undoManager: undoManager) { $0.projectTitle = "ABC" }
        document.perform(undoManager: undoManager)                     { $0.projectTitle = "ABCD" }
        // Reusing the first token after it was closed starts a fresh step, not a merge.
        document.perform(coalescing: first, undoManager: undoManager)  { $0.projectTitle = "ABCDE" }

        undoManager.undo(); #expect(document.project.projectTitle == "ABCD")
        undoManager.undo(); #expect(document.project.projectTitle == "ABC")
        undoManager.undo(); #expect(document.project.projectTitle == "AB")
        undoManager.undo(); #expect(document.project == original)
        #expect(!undoManager.canUndo)
    }

    @Test func undoClosesTheOpenGesture() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let drag        = EditGesture()

        document.perform(coalescing: drag, undoManager: undoManager) { $0.projectTitle = "A" }
        undoManager.undo()
        #expect(document.project == project)
        // The same token after an undo is a new step whose "before" is the restored state.
        document.perform(coalescing: drag, undoManager: undoManager) { $0.projectTitle = "B" }
        #expect(!undoManager.canRedo)
        undoManager.undo()
        #expect(document.project == project)
    }

    @Test func actionNameLabelsUndoAndRedo() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        document.perform("Rename Project", undoManager: undoManager) { $0.projectTitle = "New" }
        #expect(undoManager.undoActionName == "Rename Project")
        undoManager.undo()
        #expect(undoManager.redoActionName == "Rename Project")
        undoManager.redo()
        #expect(undoManager.undoActionName == "Rename Project")
    }

    /// A token only merges into a step registered with the same manager: a gesture that
    /// continues under another manager (or none) must not ride on the old one's action.
    @Test func anOpenGestureDoesNotMergeAcrossUndoManagers() throws {
        let first    = makeUndoManager()
        let second   = makeUndoManager()
        let document = ProjectDocument(project)
        let drag     = EditGesture()

        document.perform(coalescing: drag, undoManager: first)  { $0.projectTitle = "A" }
        document.perform(coalescing: drag, undoManager: second) { $0.projectTitle = "AB" }
        #expect(second.canUndo)
        second.undo()
        #expect(document.project.projectTitle == "A")
        first.undo()
        #expect(document.project == project)

        document.perform(coalescing: drag, undoManager: first) { $0.projectTitle = "C" }
        document.perform(coalescing: drag, undoManager: nil)   { $0.projectTitle = "CD" }
        // The nil-manager edit closed the gesture; the same token now opens a new step.
        document.perform(coalescing: drag, undoManager: first) { $0.projectTitle = "CDE" }
        first.undo()
        #expect(document.project.projectTitle == "CD")
    }

    /// Views that keep drag state keyed to the model watch this counter: an undo, a redo or
    /// a snapshot from disk replaces the project under them, an ordinary edit does not.
    @Test func restoreCountTicksOnUndoRedoAndApplyButNotOnPerform() async throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        #expect(document.restoreCount == 0)

        document.perform(undoManager: undoManager) { $0.projectTitle = "Edited" }
        #expect(document.restoreCount == 0)

        undoManager.undo()
        #expect(document.restoreCount == 1)
        undoManager.redo()
        #expect(document.restoreCount == 2)

        try await document.apply(snapshot: project, previous: nil)
        #expect(document.restoreCount == 3)
    }

    /// An editor's Save writes its whole value back whether or not anything changed; a
    /// write that leaves the project equal must not dirty the document or add an undo step.
    @Test func anEditThatChangesNothingRegistersNoUndoStep() throws {
        let undoManager = makeUndoManager()
        let document    = ProjectDocument(project)
        let drag        = EditGesture()

        document.perform(undoManager: undoManager) { $0.projectTitle = $0.projectTitle }
        #expect(!undoManager.canUndo)

        // A no-op first edit opens no gesture, so the next edit with the token is a real step.
        document.perform(coalescing: drag, undoManager: undoManager) { _ in }
        document.perform(coalescing: drag, undoManager: undoManager) { $0.projectTitle = "Changed" }
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(document.project == project)
        #expect(!undoManager.canUndo)
    }

    @Test func performWithoutAnUndoManagerStillEdits() throws {
        let document = ProjectDocument(project)
        document.perform(undoManager: nil) { $0.projectTitle = "No Undo" }
        #expect(document.project.projectTitle == "No Undo")
    }
}

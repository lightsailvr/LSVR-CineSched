//
//  ConflictNoticeTests.swift
//  LSVR CineSchedTests
//
//  The conflict notice's lifecycle (#15) and the sync monitor's pure parts (#14): the
//  notice is raised by a resolution, survives the resolution's own change count, and
//  clears on the next edit, on restore and on dismiss; the monitor's state is
//  `SyncState.derive` over the snapshot it holds, nil with none; the current version the
//  policy is handed is dated by the last local edit while there are unsaved edits and by
//  the file otherwise. `NSFileVersion`, the coordinator and the query are not tested here.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ConflictNoticeTests {

    private let noon    = Date(timeIntervalSince1970: 1_700_000_000)
    private let project = ProjectCodecTests.project

    private func policyNotice(device: String? = "Matt's iPad") -> ConflictNotice {
        ConflictNotice(origin: .policy, deviceName: device, modificationDate: noon, canRestore: true)
    }

    // MARK: - Lifecycle

    @Test func startsWithNoNotice() {
        let state = ConflictNoticeState()
        #expect(state.notice == nil)
        #expect(!state.isShowing)
    }

    @Test func raisingShowsTheNoticeAndRecordsTheResolutionCount() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(), changeCount: 7)
        #expect(state.isShowing)
        #expect(state.notice == policyNotice())
        #expect(state.changeCountAtResolution == 7)
    }

    /// The resolution's own `perform` moves the change count once; the editor reports
    /// that count back, and it must not retire the notice it produced.
    @Test func theResolutionsOwnChangeCountKeepsTheNotice() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(), changeCount: 7)
        state.documentDidChange(changeCount: 7)
        #expect(state.isShowing)
    }

    @Test func theNextEditClearsTheNotice() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(), changeCount: 7)
        state.documentDidChange(changeCount: 8)
        #expect(!state.isShowing)
        #expect(state.changeCountAtResolution == nil)
    }

    @Test func restoreClearsTheNotice() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(), changeCount: 3)
        state.restored()
        #expect(!state.isShowing)
    }

    @Test func dismissClearsTheNotice() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(), changeCount: 3)
        state.dismiss()
        #expect(!state.isShowing)
    }

    @Test func aChangeWithNoNoticeIsIgnored() {
        var state = ConflictNoticeState()
        state.documentDidChange(changeCount: 42)
        #expect(state == ConflictNoticeState())
    }

    /// A second resolution while a notice stands replaces it and re-anchors the count.
    @Test func aLaterResolutionReplacesTheNotice() {
        var state = ConflictNoticeState()
        state.raise(policyNotice(device: "Matt's iPad"), changeCount: 3)
        state.raise(policyNotice(device: "Matt's iPhone"), changeCount: 9)
        #expect(state.notice?.deviceName == "Matt's iPhone")
        state.documentDidChange(changeCount: 9)
        #expect(state.isShowing)
        state.documentDidChange(changeCount: 3)
        #expect(!state.isShowing)
    }

    // MARK: - From a decision

    @Test func aDecisionWithALoserMakesAPolicyNotice() {
        let current  = ConflictVersion(id: "current", modificationDate: noon, snapshot: project)
        let other    = ConflictVersion(id: "v1", modificationDate: noon.addingTimeInterval(60), deviceName: "Matt's iPhone", snapshot: project)
        let decision = ConflictPolicy.decide(current: current, others: [other])
        let notice   = ConflictNotice(decision: decision)
        #expect(notice?.origin == .policy)
        #expect(notice?.deviceName == nil)            // the current version lost; it is unnamed
        #expect(notice?.modificationDate == noon)
        #expect(notice?.canRestore == true)
    }

    @Test func aSingleVersionMakesNoNotice() {
        let current  = ConflictVersion(id: "current", modificationDate: noon, snapshot: project)
        let decision = ConflictPolicy.decide(current: current, others: [])
        #expect(ConflictNotice(decision: decision) == nil)
    }

    /// A retained version whose contents never arrived cannot be restored.
    @Test func aRetainedVersionWithoutASnapshotIsNotRestorable() {
        let current  = ConflictVersion(id: "current", modificationDate: noon.addingTimeInterval(60), snapshot: project)
        let other    = ConflictVersion(id: "v1", modificationDate: noon, deviceName: "Matt's iPhone", snapshot: nil)
        let decision = ConflictPolicy.decide(current: current, others: [other])
        #expect(ConflictNotice(decision: decision)?.canRestore == false)
    }

    // MARK: - The monitor's state

    @Test func monitorStateIsNilWithoutASnapshot() {
        #expect(SyncMonitor.state(for: nil, networkReachable: true, noticeShowing: false) == nil)
        #expect(SyncMonitor.state(for: nil, networkReachable: false, noticeShowing: true) == nil)
    }

    @Test func monitorStateFollowsTheSnapshotTheNetworkAndTheNotice() {
        let settled = UbiquitousResourceSnapshot(isUbiquitousItem: true)
        #expect(SyncMonitor.state(for: settled, networkReachable: true,  noticeShowing: false) == .upToDate)
        #expect(SyncMonitor.state(for: settled, networkReachable: false, noticeShowing: false) == .waitingForNetwork)
        #expect(SyncMonitor.state(for: settled, networkReachable: false, noticeShowing: true)  == .conflictResolved)
        let local = UbiquitousResourceSnapshot(isUbiquitousItem: false)
        #expect(SyncMonitor.state(for: local, networkReachable: true, noticeShowing: true) == nil)
    }

    /// A URL outside iCloud reads as a non-ubiquitous snapshot (no indicator), and so
    /// does a URL that does not exist: the ubiquity keys come back unset rather than the
    /// read failing.
    @Test func readingResourceValuesOfALocalFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConflictNoticeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Local.cinesched")
        try ProjectCodec.encode(project).write(to: file)
        let snapshot = try #require(SyncMonitor.readSnapshot(of: file))
        #expect(!snapshot.isUbiquitousItem)
        #expect(SyncMonitor.state(for: snapshot, networkReachable: true, noticeShowing: false) == nil)
        let missing = SyncMonitor.readSnapshot(of: dir.appendingPathComponent("Missing.cinesched"))
        #expect(missing?.isUbiquitousItem != true)
        #expect(SyncMonitor.state(for: missing, networkReachable: true, noticeShowing: false) == nil)
    }

    // MARK: - The current version

    @Test func currentVersionIsDatedByTheLastEditWhileUnsaved() {
        let edited  = noon.addingTimeInterval(300)
        let current = ConflictVersion.current(project: project, fileModificationDate: noon, fileDeviceName: "Matt's Mac", hasUnsavedEdits: true, lastEditDate: edited, now: noon.addingTimeInterval(900))
        #expect(current.id == ConflictVersion.currentID)
        #expect(current.modificationDate == edited)
        #expect(current.deviceName == nil)
        #expect(current.snapshot != nil)
    }

    @Test func currentVersionIsTheFilesWhenClean() {
        let current = ConflictVersion.current(project: project, fileModificationDate: noon, fileDeviceName: "Matt's Mac", hasUnsavedEdits: false, lastEditDate: noon.addingTimeInterval(-60), now: noon.addingTimeInterval(900))
        #expect(current.modificationDate == noon)
        #expect(current.deviceName == "Matt's Mac")
    }

    @Test func currentVersionFallsBackToNow() {
        let now     = noon.addingTimeInterval(900)
        let current = ConflictVersion.current(project: project, fileModificationDate: nil, fileDeviceName: nil, hasUnsavedEdits: true, lastEditDate: nil, now: now)
        #expect(current.modificationDate == now)
    }

    // MARK: - The palette across a resolution

    @Test func aWinnerWithoutAPaletteKeepsTheDocuments() {
        var mine = project
        mine.palette = ScenePalette.standard
        var theirs = project
        theirs.palette = nil
        #expect(SyncMonitor.adopting(theirs, paletteOf: mine).palette == ScenePalette.standard)
        var ownPalette = ScenePalette.standard
        ownPalette.setHex("FF00FF", for: .intDay)
        var theirsWithOwn = project
        theirsWithOwn.palette = ownPalette
        #expect(SyncMonitor.adopting(theirsWithOwn, paletteOf: mine).palette == ownPalette)
    }
}

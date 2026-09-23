//
//  ScheduleClipboardTests.swift
//  LSVR CineSchedTests
//
//  Copy, cut and paste of scenes (#22), the pure part: what Copy puts on the pasteboard
//  for a selection (the scenes by value, in board order), where a paste lands for the
//  editor's selection, what a paste inserts (new scenes with new ids, everything else as
//  copied, into this project or another), what Cut removes, and that the copies payload
//  round-trips through its transfer representation like the drag kinds do.
//

import CoreTransferable
import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ScheduleClipboardTests {

    // MARK: - Fixture

    private let a = Scene(title: "INT. KITCHEN - DAY",  sceneNumber: "1", cast: ["ANNA"], customStartTime: "9:00 AM", isCompleted: true)
    private let b = Scene(title: "EXT. YARD - DAY",     sceneNumber: "2")
    private let c = Scene(title: "INT. GARAGE - NIGHT", sceneNumber: "3")
    private let d = Scene(title: "EXT. STREET - DUSK",  sceneNumber: "4")
    private let e = Scene(title: "INT. BAR - NIGHT",    sceneNumber: "5")
    private let event = Scene.createCalendarEvent(title: "Tech scout", time: "9:00 AM")
    private let meal  = Scene.createAutoMeal(kind: .lunch, timeString: "1:00 PM")

    /// Day 1 holds a, b, the event, the lunch and c; day 2 holds d; e is in the Boneyard.
    private func project() -> ProjectData {
        var day1 = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day1.scenes = [a, b, event, meal, c]
        var day2 = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400))
        day2.scenes = [d]
        return ProjectData(allScenes: [e], shootDays: [day1, day2], projectTitle: "Fixture")
    }

    private func sceneCount(_ project: ProjectData) -> Int {
        project.allScenes.count + project.shootDays.reduce(0) { $0 + $1.scenes.count }
    }

    // MARK: - What Copy carries

    @Test func copiesComeInBoardOrderBoneyardFirstAndIgnoreUnknownIDs() {
        let copies = ScheduleClipboard.scenes(copying: [d.id, a.id, e.id, UUID()], in: project())
        #expect(copies == [e, a, d])
    }

    @Test func copiesLeaveAutoMealsBehind() {
        // The Stripboard writes the meal strips from the call sheet; a pasted one would
        // be a stray. Banners and calendar events are copied like scenes.
        let copies = ScheduleClipboard.scenes(copying: [meal.id, event.id, b.id], in: project())
        #expect(copies.map(\.id) == [b.id, event.id])
    }

    @Test func thePayloadIsNilWhenNothingCopiable() {
        #expect(ScheduleClipboard.payload(copying: [], in: project()) == nil)
        #expect(ScheduleClipboard.payload(copying: [UUID()], in: project()) == nil)
        #expect(ScheduleClipboard.payload(copying: [meal.id], in: project()) == nil)
    }

    @Test func thePayloadCarriesTheScenesByValue() throws {
        let payload = try #require(ScheduleClipboard.payload(copying: [c.id, a.id], in: project()))
        #expect(payload.kind == .sceneCopies([a, c]))
        #expect(payload.copiedScenes == [a, c])
        #expect(payload.sceneIDs.isEmpty)
        #expect(payload.id == a.id)
    }

    @Test func theCopiesPayloadRoundTrips() async throws {
        let payload = ScheduleDragPayload(.sceneCopies([a, event]))
        let data = try await payload.exported(as: .cineschedDragPayload)
        let back = try await ScheduleDragPayload(importing: data, contentType: .cineschedDragPayload)
        #expect(back == payload)
        #expect(back.copiedScenes == [a, event])
    }

    @Test func thePasteboardBytesAreTheDragBytes() async throws {
        // Copy writes `pasteboardData()`; a drop of the same payload would carry the
        // transfer representation. One shape, so either side reads the other.
        let payload = ScheduleDragPayload(.sceneCopies([a, c]))
        let bytes = try payload.pasteboardData()
        #expect(try ScheduleDragPayload(pasteboardData: bytes) == payload)
        #expect(try await ScheduleDragPayload(importing: bytes, contentType: .cineschedDragPayload) == payload)
        let dragBytes = try await payload.exported(as: .cineschedDragPayload)
        #expect(try ScheduleDragPayload(pasteboardData: dragBytes) == payload)
    }

    // MARK: - Where a paste lands

    @Test func nothingSelectedPastesIntoTheBoneyard() {
        #expect(ScheduleClipboard.destination(for: nil, in: project()) == .boneyard)
    }

    @Test func aSelectedDayPastesAtItsEnd() {
        let project = project()
        let day2 = project.shootDays[1]
        #expect(ScheduleClipboard.destination(for: .day(id: day2.id), in: project) == .day(SceneDropDestination(dayID: day2.id)))
    }

    @Test func aSelectedStripPastesRightAfterIt() {
        let project = project()
        let day1 = project.shootDays[0]
        #expect(ScheduleClipboard.destination(for: .scene(id: a.id), in: project)
                == .day(SceneDropDestination(dayID: day1.id, position: .before(b.id))))
        // The last strip of a day: at the end.
        #expect(ScheduleClipboard.destination(for: .scene(id: c.id), in: project)
                == .day(SceneDropDestination(dayID: day1.id)))
    }

    @Test func aSelectedBoneyardSceneOrAGoneSelectionPastesIntoTheBoneyard() {
        let project = project()
        #expect(ScheduleClipboard.destination(for: .scene(id: e.id), in: project) == .boneyard)
        #expect(ScheduleClipboard.destination(for: .scene(id: UUID()), in: project) == .boneyard)
        #expect(ScheduleClipboard.destination(for: .day(id: UUID()), in: project) == .boneyard)
    }

    // MARK: - What a paste inserts

    @Test func aPasteOnADayInsertsNewScenesWithNewIDsAndEverythingElseAsCopied() {
        var project = project()
        let day2 = project.shootDays[1]
        let before = project
        let inserted = ScheduleClipboard.paste([a, c], at: .day(SceneDropDestination(dayID: day2.id)), into: &project)

        #expect(inserted.count == 2)
        #expect(!inserted.contains(a.id) && !inserted.contains(c.id))
        let pasted = project.shootDays[1].scenes.suffix(2)
        #expect(pasted.map(\.id) == inserted)
        #expect(pasted.map(\.title) == [a.title, c.title])
        #expect(pasted.first?.cast == ["ANNA"])
        #expect(pasted.first?.isCompleted == true)
        #expect(pasted.first?.customStartTime == "9:00 AM")
        // The originals are where they were: a paste is not a move.
        #expect(project.shootDays[0] == before.shootDays[0])
        #expect(project.allScenes == before.allScenes)
        #expect(sceneCount(project) == sceneCount(before) + 2)
    }

    /// The shots travel with the scene value; a paste gives each one a fresh id, as it
    /// does the scene, and keeps its contents and frame (#37).
    @Test func aPasteGivesEveryShotAFreshIDAndKeepsItsContents() throws {
        var project = project()
        var shotScene = b
        shotScene.shots = [
            Shot(details: "Wide",  durationMinutes: 20, frame: Data([0xFF, 0xD8, 0xFF, 0xD9])),
            Shot(details: "Close", durationMinutes: 10, sfx: ["Rain"]),
        ]
        let inserted = ScheduleClipboard.paste([shotScene], at: .boneyard, into: &project)
        let pastedID = try #require(inserted.first)
        let pasted   = try #require(project.scene(withID: pastedID))
        #expect(Set(pasted.shots.map(\.id)).isDisjoint(with: shotScene.shots.map(\.id)))
        #expect(pasted.shots.map(\.details) == ["Wide", "Close"])
        #expect(pasted.shots.map(\.frame)   == shotScene.shots.map(\.frame))
        #expect(pasted.shots.map(\.sfx)     == [[], ["Rain"]])
    }

    @Test func aPasteBeforeAStripLandsThere() {
        var project = project()
        let day1 = project.shootDays[0]
        let inserted = ScheduleClipboard.paste([d], at: .day(SceneDropDestination(dayID: day1.id, position: .before(b.id))), into: &project)
        #expect(project.shootDays[0].scenes.map(\.id) == [a.id] + inserted + [b.id, event.id, meal.id, c.id])
    }

    @Test func twoPastesOfTheSameCopiesAreTwoScenes() {
        var project = project()
        let day2 = project.shootDays[1]
        let first  = ScheduleClipboard.paste([a], at: .day(SceneDropDestination(dayID: day2.id)), into: &project)
        let second = ScheduleClipboard.paste([a], at: .day(SceneDropDestination(dayID: day2.id)), into: &project)
        #expect(first != second)
        #expect(project.shootDays[1].scenes.count == 3)
        #expect(Set(project.shootDays[1].scenes.map(\.id)).count == 3)
    }

    @Test func aPasteIntoTheBoneyardAppendsScenesAndSkipsNoticeStrips() {
        var project = project()
        let inserted = ScheduleClipboard.paste([event, a, meal, Scene.createBanner(type: .companyMove, title: "Move")], at: .boneyard, into: &project)
        #expect(inserted.count == 1)
        #expect(project.allScenes.map(\.title) == [e.title, a.title])
        #expect(project.allScenes.last?.id == inserted.first)
    }

    @Test func aPasteIntoAnotherProjectWorksTheSameWay() {
        // The ids come from the fixture project; the other project has never seen them.
        var other = ProjectData(allScenes: [], shootDays: [ShootDay(date: Date(timeIntervalSince1970: 1_900_000_000))], projectTitle: "Other")
        let day = other.shootDays[0]
        let inserted = ScheduleClipboard.paste([a, b], at: .day(SceneDropDestination(dayID: day.id)), into: &other)
        #expect(other.shootDays[0].scenes.map(\.id) == inserted)
        #expect(other.shootDays[0].scenes.map(\.title) == [a.title, b.title])
        #expect(ScheduleClipboard.paste([c], at: .boneyard, into: &other).count == 1)
        #expect(other.allScenes.map(\.title) == [c.title])
    }

    @Test func aPasteOnAGoneDayOrOfNothingChangesNothing() {
        var project = project()
        let before = project
        #expect(ScheduleClipboard.paste([a], at: .day(SceneDropDestination(dayID: UUID())), into: &project).isEmpty)
        #expect(ScheduleClipboard.paste([], at: .boneyard, into: &project).isEmpty)
        #expect(project == before)
    }

    // MARK: - What Cut removes

    @Test func cutRemovesTheScenesFromTheBoneyardAndTheDays() {
        var project = project()
        #expect(ScheduleClipboard.remove([e.id, b.id, d.id], from: &project))
        #expect(project.allScenes.isEmpty)
        #expect(project.shootDays[0].scenes.map(\.id) == [a.id, event.id, meal.id, c.id])
        #expect(project.shootDays[1].scenes.isEmpty)
    }

    @Test func cutOfNothingKnownChangesNothing() {
        var project = project()
        let before = project
        #expect(!ScheduleClipboard.remove([UUID()], from: &project))
        #expect(!ScheduleClipboard.remove([], from: &project))
        #expect(project == before)
    }

    @Test func cutThenPasteMovesASceneUnderANewID() throws {
        var project = project()
        let payload = try #require(ScheduleClipboard.payload(copying: [a.id], in: project))
        #expect(ScheduleClipboard.remove([a.id], from: &project))
        let day2 = project.shootDays[1]
        let inserted = ScheduleClipboard.paste(payload.copiedScenes, at: .day(SceneDropDestination(dayID: day2.id)), into: &project)
        #expect(sceneCount(project) == sceneCount(self.project()))
        #expect(project.locate(sceneID: a.id) == nil)
        #expect(project.shootDays[1].scenes.last?.id == inserted.first)
        #expect(project.shootDays[1].scenes.last?.title == a.title)
    }
}

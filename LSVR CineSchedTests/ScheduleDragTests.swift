//
//  ScheduleDragTests.swift
//  LSVR CineSchedTests
//
//  The typed drag payload (#18): every kind round-trips through its transfer
//  representation, the type it travels as is the one the bundle declares, and the moves a
//  drop makes (`ScheduleMoves`) place scenes the way the calendar and the Stripboard need:
//  from the Boneyard, within a day, across days, before a strip or at the end, back to the
//  Boneyard. The iPhone's moves (#25) ride on the same functions: a list's `onMove`
//  offsets become one move (`reorderStrips`), Add Scenes lands the checked Boneyard scenes
//  in their display order (`addScenes`), and Swap with Day exchanges everything two days
//  hold while their dates and ids stay (`swapDays`).
//

import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import LSVR_CineSched

@MainActor
struct ScheduleDragTests {

    // MARK: - Fixture

    private let a = Scene(title: "INT. KITCHEN - DAY",  sceneNumber: "1")
    private let b = Scene(title: "EXT. YARD - DAY",     sceneNumber: "2")
    private let c = Scene(title: "INT. GARAGE - NIGHT", sceneNumber: "3")
    private let d = Scene(title: "EXT. STREET - DUSK",  sceneNumber: "4")
    private let e = Scene(title: "INT. BAR - NIGHT",    sceneNumber: "5")
    private let event = Scene.createCalendarEvent(title: "Tech scout", time: "9:00 AM")

    /// Day 1 holds a, b, c (and the event); day 2 holds d; e is in the Boneyard.
    private func board() -> (days: [ShootDay], boneyard: [Scene]) {
        var day1 = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day1.scenes = [a, b, event, c]
        var day2 = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400))
        day2.scenes = [d]
        return ([day1, day2], [e])
    }

    private func ids(_ scenes: [Scene]) -> [UUID] { scenes.map(\.id) }

    private func roundTrip(_ payload: ScheduleDragPayload) async throws -> ScheduleDragPayload {
        let data = try await payload.exported(as: .cineschedDragPayload)
        return try await ScheduleDragPayload(importing: data, contentType: .cineschedDragPayload)
    }

    // MARK: - The type

    @Test func theDragPayloadTypeIsDeclaredByTheBundle() throws {
        let declared = try #require(UTType("com.lsvr.cinesched.drag-payload"))
        #expect(declared == .cineschedDragPayload)
        #expect(declared.conforms(to: .data))
        #expect(!declared.conforms(to: .json))
        #expect(UTType.cineschedDragPayload.preferredFilenameExtension == nil)
    }

    // MARK: - Round trips, one per kind

    @Test func aSingleSceneFromTheBoneyardRoundTrips() async throws {
        let payload = ScheduleDragPayload.scenes([a.id], from: nil)
        #expect(try await roundTrip(payload) == payload)
        #expect(payload.id == a.id)
        #expect(payload.sceneIDs == [a.id])
    }

    @Test func aMultiSceneSelectionFromADayRoundTripsInOrder() async throws {
        let dayID = UUID()
        let payload = ScheduleDragPayload.scenes([c.id, a.id, b.id], from: dayID)
        let back = try await roundTrip(payload)
        #expect(back == payload)
        #expect(back.sceneIDs == [c.id, a.id, b.id])
        if case .scenes(let ids, let origin) = back.kind {
            #expect(ids == [c.id, a.id, b.id])
            #expect(origin == dayID)
        } else {
            Issue.record("expected a scenes payload, got \(back.kind)")
        }
        #expect(back.id == c.id)
    }

    @Test func aWholeDayRoundTrips() async throws {
        let dayID = UUID()
        let payload = ScheduleDragPayload(.day(id: dayID))
        #expect(try await roundTrip(payload) == payload)
        #expect(payload.id == dayID)
        #expect(payload.sceneIDs.isEmpty)
    }

    @Test func aDayTypeBandRoundTrips() async throws {
        let dayID = UUID()
        let payload = ScheduleDragPayload(.dayType(dayID: dayID))
        #expect(try await roundTrip(payload) == payload)
        #expect(payload.id == dayID)
        #expect(payload.sceneIDs.isEmpty)
    }

    @Test func aCalendarEventRoundTrips() async throws {
        let dayID = UUID()
        let payload = ScheduleDragPayload(.calendarEvent(id: event.id, dayID: dayID))
        #expect(try await roundTrip(payload) == payload)
        #expect(payload.id == event.id)
        #expect(payload.sceneIDs == [event.id])
    }

    // MARK: - The shot kind (#42)

    @Test func theShotDragTypeIsDeclaredByTheBundle() throws {
        let declared = try #require(UTType("com.lsvr.cinesched.shot-drag-payload"))
        #expect(declared == .cineschedShotDragPayload)
        #expect(declared.conforms(to: .data))
        #expect(declared != .cineschedDragPayload)
        #expect(UTType.cineschedShotDragPayload.preferredFilenameExtension == nil)
    }

    @Test func aShotRoundTripsThroughItsOwnType() async throws {
        let shotID = UUID()
        let item   = ShotDragPayload(shotID: shotID, sceneID: a.id)
        let data   = try await item.exported(as: .cineschedShotDragPayload)
        let back   = try await ShotDragPayload(importing: data, contentType: .cineschedShotDragPayload)
        #expect(back == item)
        #expect(back.payload.kind == .shot(id: shotID, sceneID: a.id))
        #expect(item.payload.id == shotID)
        #expect(item.payload.isShot)
        #expect(item.payload.sceneIDs.isEmpty)
        // The same JSON as the payload itself, so a shot reads like every other kind.
        #expect(try JSONDecoder().decode(ScheduleDragPayload.self, from: data) == item.payload)
    }

    /// What keeps a shot out of every strip, day and Boneyard destination: a destination
    /// is chosen by type while the drag hovers, and the two payloads share none.
    @Test func aShotAndTheSceneKindsTravelOnDifferentTypes() {
        #expect(ShotDragPayload.exportedContentTypes() == [.cineschedShotDragPayload])
        #expect(ShotDragPayload.importedContentTypes() == [.cineschedShotDragPayload])
        #expect(!ScheduleDragPayload.importedContentTypes().contains(.cineschedShotDragPayload))
        #expect(!ScheduleDragPayload.exportedContentTypes().contains(.cineschedShotDragPayload))
        #expect(!ScheduleDragPayload.scenes([a.id], from: nil).isShot)
    }

    // MARK: - Where a shot lands (#42)

    @Test func aShotDroppedOnASubRowOfItsSceneLandsBeforeThatShot() {
        let shotID = UUID(), anchorID = UUID()
        let payload = ScheduleDragPayload(.shot(id: shotID, sceneID: a.id))
        #expect(ShotDrop.position(for: payload, onto: .shot(id: anchorID, sceneID: a.id)) == .before(anchorID))
    }

    @Test func aShotDroppedBelowItsScenesLastSubRowLandsAtTheEnd() {
        let payload = ScheduleDragPayload(.shot(id: UUID(), sceneID: a.id))
        #expect(ShotDrop.position(for: payload, onto: .sceneEnd(sceneID: a.id)) == .end)
    }

    @Test func aShotDroppedAnywhereElseLandsNowhere() {
        let payload = ScheduleDragPayload(.shot(id: UUID(), sceneID: a.id))
        #expect(ShotDrop.position(for: payload, onto: .shot(id: UUID(), sceneID: b.id)) == nil)
        #expect(ShotDrop.position(for: payload, onto: .sceneEnd(sceneID: b.id)) == nil)
        #expect(ShotDrop.position(for: payload, onto: .strip(sceneID: a.id)) == nil)
        #expect(ShotDrop.position(for: payload, onto: .strip(sceneID: b.id)) == nil)
        #expect(ShotDrop.position(for: payload, onto: .day(id: UUID())) == nil)
        #expect(ShotDrop.position(for: payload, onto: .boneyard) == nil)
    }

    @Test func noOtherKindLandsOnASubRow() {
        let anchor = ShotDropTarget.shot(id: UUID(), sceneID: a.id)
        let others: [ScheduleDragPayload] = [
            .scenes([a.id], from: nil),
            ScheduleDragPayload(.day(id: UUID())),
            ScheduleDragPayload(.dayType(dayID: UUID())),
            ScheduleDragPayload(.calendarEvent(id: event.id, dayID: UUID())),
            ScheduleDragPayload(.sceneCopies([a])),
        ]
        for payload in others {
            #expect(ShotDrop.position(for: payload, onto: anchor) == nil)
            #expect(ShotDrop.position(for: payload, onto: .sceneEnd(sceneID: a.id)) == nil)
        }
    }

    /// The resolution feeds #37's move: C dropped on A's sub-row reads C, A, B, and the
    /// scene's estimate (the strip's time) stays the sum.
    @Test func aResolvedShotDropReordersTheSceneAndKeepsItsEstimate() throws {
        var scene = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "12")
        let shotA = Shot(details: "Wide", durationMinutes: 20)
        let shotB = Shot(details: "Two", durationMinutes: 10)
        let shotC = Shot(details: "Insert", durationMinutes: 5)
        scene.addShot(shotA)
        scene.addShot(shotB)
        scene.addShot(shotC)
        var day = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day.scenes = [scene]
        var project = ProjectData.newProject()
        project.shootDays = [day]

        let payload  = ScheduleDragPayload(.shot(id: shotC.id, sceneID: scene.id))
        let position = try #require(ShotDrop.position(for: payload, onto: .shot(id: shotA.id, sceneID: scene.id)))
        let moved    = project.moveShot(withID: shotC.id, inSceneID: scene.id, to: position)
        #expect(moved)
        let after = try #require(project.scene(withID: scene.id))
        #expect(after.shots.map(\.id) == [shotC.id, shotA.id, shotB.id])
        #expect(after.shotNumber(forShotID: shotC.id) == "12A")
        #expect(after.estimatedTime == 35)
    }

    @Test func kindsAreDistinctAfterARoundTrip() async throws {
        let id = UUID()
        let day     = try await roundTrip(ScheduleDragPayload(.day(id: id)))
        let dayType = try await roundTrip(ScheduleDragPayload(.dayType(dayID: id)))
        #expect(day != dayType)
    }

    // MARK: - Moves: from the Boneyard

    @Test func aBoneyardSceneDroppedOnADayLandsAtItsEnd() {
        var (days, boneyard) = board()
        let moved = ScheduleMoves.moveScenes([e.id], to: SceneDropDestination(dayID: days[1].id), days: &days, boneyard: &boneyard)
        #expect(moved)
        #expect(boneyard.isEmpty)
        #expect(ids(days[1].scenes) == [d.id, e.id])
        #expect(ids(days[0].scenes) == [a.id, b.id, event.id, c.id])
    }

    @Test func aBoneyardSceneDroppedBeforeAStripLandsThere() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([e.id], to: SceneDropDestination(dayID: days[0].id, position: .before(b.id)), days: &days, boneyard: &boneyard)
        #expect(boneyard.isEmpty)
        #expect(ids(days[0].scenes) == [a.id, e.id, b.id, event.id, c.id])
    }

    @Test func severalBoneyardScenesKeepThePayloadsOrder() {
        var (days, boneyard) = board()
        let f = Scene(title: "INT. HALL - DAY", sceneNumber: "6")
        boneyard.append(f)
        ScheduleMoves.moveScenes([f.id, e.id], to: SceneDropDestination(dayID: days[1].id, position: .before(d.id)), days: &days, boneyard: &boneyard)
        #expect(boneyard.isEmpty)
        #expect(ids(days[1].scenes) == [f.id, e.id, d.id])
    }

    // MARK: - Moves: within and across days

    @Test func aStripMovesDownWithinItsDay() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([a.id], to: SceneDropDestination(dayID: days[0].id, position: .before(c.id)), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [b.id, event.id, a.id, c.id])
    }

    @Test func aStripMovesUpWithinItsDay() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([c.id], to: SceneDropDestination(dayID: days[0].id, position: .before(a.id)), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [c.id, a.id, b.id, event.id])
    }

    @Test func aStripMovesToTheEndOfItsDay() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([a.id], to: SceneDropDestination(dayID: days[0].id, position: .end), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [b.id, event.id, c.id, a.id])
    }

    @Test func aStripMovesToAnotherDay() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([b.id], to: SceneDropDestination(dayID: days[1].id, position: .before(d.id)), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [a.id, event.id, c.id])
        #expect(ids(days[1].scenes) == [b.id, d.id])
        #expect(boneyard.map(\.id) == [e.id])
    }

    @Test func aMultiSelectionAcrossDaysMovesInBoardOrder() {
        var (days, boneyard) = board()
        // The selection set's order is arbitrary; the board's is what lands.
        ScheduleMoves.moveScenes([d.id, c.id, a.id], to: SceneDropDestination(dayID: days[1].id, position: .end), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [b.id, event.id])
        #expect(ids(days[1].scenes) == [a.id, c.id, d.id])
    }

    @Test func droppingBeforeAMovingStripLandsBeforeTheNextStayingOne() {
        var (days, boneyard) = board()
        // a and b move "before b": b is moving, so the anchor is the event after it.
        ScheduleMoves.moveScenes([a.id, b.id], to: SceneDropDestination(dayID: days[0].id, position: .before(b.id)), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [a.id, b.id, event.id, c.id])
    }

    @Test func droppingBeforeAMovingLastStripLandsAtTheEnd() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([a.id, c.id], to: SceneDropDestination(dayID: days[0].id, position: .before(c.id)), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [b.id, event.id, a.id, c.id])
    }

    @Test func aCalendarEventMovesLikeAStrip() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([event.id], to: SceneDropDestination(dayID: days[1].id), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [a.id, b.id, c.id])
        #expect(ids(days[1].scenes) == [d.id, event.id])
    }

    @Test func anUnknownAnchorMeansTheEnd() {
        var (days, boneyard) = board()
        ScheduleMoves.moveScenes([e.id], to: SceneDropDestination(dayID: days[0].id, position: .before(UUID())), days: &days, boneyard: &boneyard)
        #expect(ids(days[0].scenes) == [a.id, b.id, event.id, c.id, e.id])
    }

    @Test func aMoveToAnUnknownDayChangesNothing() {
        var (days, boneyard) = board()
        let before = (days, boneyard)
        let moved = ScheduleMoves.moveScenes([e.id, a.id], to: SceneDropDestination(dayID: UUID()), days: &days, boneyard: &boneyard)
        #expect(!moved)
        #expect(days == before.0)
        #expect(boneyard == before.1)
    }

    @Test func aMoveOfUnknownScenesChangesNothing() {
        var (days, boneyard) = board()
        let before = days
        let moved = ScheduleMoves.moveScenes([UUID()], to: SceneDropDestination(dayID: days[0].id), days: &days, boneyard: &boneyard)
        #expect(!moved)
        #expect(days == before)
    }

    // MARK: - Moves: back to the Boneyard

    @Test func scheduledScenesReturnToTheBoneyardInBoardOrder() {
        var (days, boneyard) = board()
        let moved = ScheduleMoves.returnToBoneyard([d.id, c.id, a.id], days: &days, boneyard: &boneyard)
        #expect(moved)
        #expect(ids(days[0].scenes) == [b.id, event.id])
        #expect(days[1].scenes.isEmpty)
        #expect(boneyard.map(\.id) == [e.id, a.id, c.id, d.id])
    }

    @Test func aCalendarEventNeverReturnsToTheBoneyard() {
        var (days, boneyard) = board()
        let moved = ScheduleMoves.returnToBoneyard([event.id], days: &days, boneyard: &boneyard)
        #expect(!moved)
        #expect(ids(days[0].scenes) == [a.id, b.id, event.id, c.id])
        #expect(boneyard.map(\.id) == [e.id])
    }

    @Test func aBoneyardSceneDroppedOnTheBoneyardChangesNothing() {
        var (days, boneyard) = board()
        let moved = ScheduleMoves.returnToBoneyard([e.id], days: &days, boneyard: &boneyard)
        #expect(!moved)
        #expect(boneyard.map(\.id) == [e.id])
    }

    // MARK: - Reorder within a day, from a list's onMove offsets (#25)

    /// The strips the Day screen lists: the day's scenes without its calendar events.
    private func displayed(_ day: ShootDay) -> [UUID] { day.scenes.filter { !$0.isCalendarEvent }.map(\.id) }

    @Test func movingTheFirstStripToTheEndReordersTheDay() {
        var (days, _) = board()
        // onMove: offsets [0] to offset 3 (past the last of three displayed strips).
        let moved = ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 0), toOffset: 3, in: days[0].id, days: &days)
        #expect(moved)
        #expect(ids(days[0].scenes) == [b.id, event.id, c.id, a.id])
    }

    @Test func movingTheLastStripToTheFrontReordersTheDay() {
        var (days, _) = board()
        ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 2), toOffset: 0, in: days[0].id, days: &days)
        #expect(ids(days[0].scenes) == [c.id, a.id, b.id, event.id])
    }

    @Test func movingAMiddleStripDownLandsBeforeTheStripAtTheOffset() {
        var (days, _) = board()
        let hall = Scene(title: "INT. HALL - DAY", sceneNumber: "6")
        days[0].scenes.append(hall)
        // Displayed: a, b, c, hall. b (offset 1) to offset 3: before hall, so after c; the
        // event, which the list does not show, keeps its place.
        ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 1), toOffset: 3, in: days[0].id, days: &days)
        #expect(ids(days[0].scenes) == [a.id, event.id, c.id, b.id, hall.id])
    }

    @Test func aReorderThatChangesNothingReportsNoMove() {
        var (days, _) = board()
        let before = days
        // A drop back onto the strip's own place arrives as offset 1 → 1 or 1 → 2.
        #expect(!ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 1), toOffset: 1, in: days[0].id, days: &days))
        #expect(!ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 1), toOffset: 2, in: days[0].id, days: &days))
        #expect(days == before)
    }

    @Test func aReorderOfSeveralStripsKeepsTheirOrder() {
        var (days, _) = board()
        // a and c (offsets 0 and 2) to offset 1: before b, in their own order.
        ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet([0, 2]), toOffset: 1, in: days[0].id, days: &days)
        #expect(ids(days[0].scenes) == [a.id, c.id, b.id, event.id])
    }

    @Test func aReorderOnAnUnknownDayChangesNothing() {
        var (days, _) = board()
        let before = days
        #expect(!ScheduleMoves.reorderStrips(displayed(days[0]), fromOffsets: IndexSet(integer: 0), toOffset: 3, in: UUID(), days: &days))
        #expect(days == before)
    }

    // MARK: - Add Scenes, in the Boneyard's display order (#25)

    @Test func addScenesLandsTheCheckedScenesAtTheEndInDisplayOrder() {
        var (days, boneyard) = board()
        let yard   = Scene(title: "EXT. YARD - NIGHT",   sceneNumber: "7")
        let attic  = Scene(title: "INT. ATTIC - DAY",    sceneNumber: "9")
        let cellar = Scene(title: "INT. CELLAR - NIGHT", sceneNumber: "8")
        boneyard = [e, yard, attic, cellar]   // e is "INT. BAR - NIGHT", scene 5
        // The Boneyard sorted by location: ATTIC, BAR, CELLAR, YARD.
        let order = DerivedScheduleState.sortedBoneyard(of: boneyard, by: .location).map(\.scene.id)
        #expect(order == [attic.id, e.id, cellar.id, yard.id])

        let moved = ScheduleMoves.addScenes([yard.id, attic.id, cellar.id], inDisplayOrder: order, to: days[1].id, days: &days, boneyard: &boneyard)
        #expect(moved)
        #expect(ids(days[1].scenes) == [d.id, attic.id, cellar.id, yard.id])
        #expect(boneyard.map(\.id) == [e.id])
    }

    @Test func addScenesIgnoresIdsThatAreNotInTheDisplayOrder() {
        var (days, boneyard) = board()
        let order = boneyard.map(\.id)
        // a is on a day, not in the Boneyard's list: only e moves.
        let moved = ScheduleMoves.addScenes([a.id, e.id], inDisplayOrder: order, to: days[1].id, days: &days, boneyard: &boneyard)
        #expect(moved)
        #expect(ids(days[1].scenes) == [d.id, e.id])
        #expect(ids(days[0].scenes) == [a.id, b.id, event.id, c.id])
    }

    @Test func addScenesWithNothingCheckedChangesNothing() {
        var (days, boneyard) = board()
        let before = (days, boneyard)
        #expect(!ScheduleMoves.addScenes([], inDisplayOrder: boneyard.map(\.id), to: days[1].id, days: &days, boneyard: &boneyard))
        #expect(days == before.0)
        #expect(boneyard == before.1)
    }

    // MARK: - Swap with day (#25)

    /// Day 1 with a call sheet, a type and a note, so a swap has everything to exchange.
    private func dressedBoard() -> (days: [ShootDay], boneyard: [Scene]) {
        var (days, boneyard) = board()
        days[0].callSheet.generalCallTime = "06:30 AM"
        days[0].callSheet.lunchTime       = "12:30 PM"
        days[0].dayType                   = .travel
        days[0].dayNote                   = "Fly LAX → ABQ"
        return (days, boneyard)
    }

    @Test func swapDaysExchangesScenesEventsCallSheetTypeAndNote() {
        var (days, _) = dressedBoard()
        let firstID   = days[0].id,   secondID   = days[1].id
        let firstDate = days[0].date, secondDate = days[1].date

        let swapped = ScheduleMoves.swapDays(firstID, secondID, in: &days)
        #expect(swapped)
        // The dates and ids stay: only what the days hold moves.
        #expect(days[0].id == firstID  && days[0].date == firstDate)
        #expect(days[1].id == secondID && days[1].date == secondDate)
        #expect(ids(days[0].scenes) == [d.id])
        #expect(ids(days[1].scenes) == [a.id, b.id, event.id, c.id])
        #expect(days[0].callSheet == CallSheetData())
        #expect(days[1].callSheet.generalCallTime == "06:30 AM")
        #expect(days[1].callSheet.lunchTime == "12:30 PM")
        #expect(days[0].dayType == .shoot && days[0].dayNote.isEmpty)
        #expect(days[1].dayType == .travel && days[1].dayNote == "Fly LAX → ABQ")
    }

    @Test func swapDaysIsItsOwnInverse() {
        var (days, _) = dressedBoard()
        let before = days
        ScheduleMoves.swapDays(days[0].id, days[1].id, in: &days)
        ScheduleMoves.swapDays(days[1].id, days[0].id, in: &days)
        #expect(days == before)
    }

    @Test func swappingADayWithItselfChangesNothing() {
        var (days, _) = dressedBoard()
        let before = days
        #expect(!ScheduleMoves.swapDays(days[0].id, days[0].id, in: &days))
        #expect(days == before)
    }

    @Test func swappingWithAnUnknownDayChangesNothing() {
        var (days, _) = dressedBoard()
        let before = days
        #expect(!ScheduleMoves.swapDays(days[0].id, UUID(), in: &days))
        #expect(!ScheduleMoves.swapDays(UUID(), days[0].id, in: &days))
        #expect(days == before)
    }

    // MARK: - The adjacent day (Move to Next Day / Move to Previous Day)

    @Test func theAdjacentDayIsTheNextOrPreviousEntryOfTheList() {
        var (days, _) = board()
        // An empty typed day between the two is still "tomorrow" to the scheduler.
        let travel = ShootDay(date: Date(timeIntervalSince1970: 1_800_043_200), dayType: .travel)
        days.insert(travel, at: 1)
        #expect(ScheduleMoves.adjacentDayID(of: days[0].id, .next,     in: days) == travel.id)
        #expect(ScheduleMoves.adjacentDayID(of: travel.id,  .next,     in: days) == days[2].id)
        #expect(ScheduleMoves.adjacentDayID(of: days[2].id, .previous, in: days) == travel.id)
    }

    @Test func theFirstDayHasNoPreviousAndTheLastNoNext() {
        let (days, _) = board()
        #expect(ScheduleMoves.adjacentDayID(of: days[0].id, .previous, in: days) == nil)
        #expect(ScheduleMoves.adjacentDayID(of: days[1].id, .next,     in: days) == nil)
        #expect(ScheduleMoves.adjacentDayID(of: UUID(),     .next,     in: days) == nil)
    }

    // MARK: - The Mac's day swaps, pinned (#35)

    // `StripboardView.handleDayRearrange` and `CalendarView.handleDayRearrange` /
    // `swapDayContents` (the calendar's then pruned the source day if it was left empty
    // outside the range) as they stood before both moved to `swapDays`, as oracles.

    private func macStripboardSwap(_ days: inout [ShootDay], sourceDayId: UUID, targetDayId: UUID) {
        guard sourceDayId != targetDayId,
              let sourceIdx = days.firstIndex(where: { $0.id == sourceDayId }),
              let targetIdx = days.firstIndex(where: { $0.id == targetDayId })
        else { return }
        let sourceScenes    = days[sourceIdx].scenes
        let sourceCallSheet = days[sourceIdx].callSheet
        let sourceType      = days[sourceIdx].dayType
        let sourceNote      = days[sourceIdx].dayNote
        let targetScenes    = days[targetIdx].scenes
        let targetCallSheet = days[targetIdx].callSheet
        let targetType      = days[targetIdx].dayType
        let targetNote      = days[targetIdx].dayNote
        days[sourceIdx].scenes    = targetScenes
        days[sourceIdx].callSheet = targetCallSheet
        days[sourceIdx].dayType   = targetType
        days[sourceIdx].dayNote   = targetNote
        days[targetIdx].scenes    = sourceScenes
        days[targetIdx].callSheet = sourceCallSheet
        days[targetIdx].dayType   = sourceType
        days[targetIdx].dayNote   = sourceNote
    }

    private func macCalendarSwapDayContents(_ days: inout [ShootDay], _ a: Int, _ b: Int) {
        let scenes    = days[a].scenes
        let callSheet = days[a].callSheet
        let type      = days[a].dayType
        let note      = days[a].dayNote
        days[a].scenes    = days[b].scenes
        days[a].callSheet = days[b].callSheet
        days[a].dayType   = days[b].dayType
        days[a].dayNote   = days[b].dayNote
        days[b].scenes    = scenes
        days[b].callSheet = callSheet
        days[b].dayType   = type
        days[b].dayNote   = note
    }

    private func macCalendarPrune(_ days: inout [ShootDay], dayId: UUID, startDate: Date, endDate: Date) {
        guard let idx = days.firstIndex(where: { $0.id == dayId }) else { return }
        let day = days[idx]
        let cal = Calendar.current
        let inRange = day.date >= cal.startOfDay(for: startDate) && day.date <= cal.startOfDay(for: endDate)
        if !inRange, day.scenes.isEmpty, day.dayType.isShootable, day.dayNote.isEmpty, !day.hasCallSheetData {
            days.remove(at: idx)
        }
    }

    private func macCalendarRearrange(_ days: inout [ShootDay], sourceDayId: UUID, targetDayId: UUID, startDate: Date, endDate: Date) {
        guard let srcIdx = days.firstIndex(where: { $0.id == sourceDayId }),
              let dstIdx = days.firstIndex(where: { $0.id == targetDayId }),
              srcIdx != dstIdx else { return }
        macCalendarSwapDayContents(&days, srcIdx, dstIdx)
        macCalendarPrune(&days, dayId: sourceDayId, startDate: startDate, endDate: endDate)
    }

    /// The dressed board (day 1 a travel day with a call sheet, day 2 holding d) plus,
    /// past the range, an empty plain day and a scout day holding nothing else.
    private func swapBoard() -> [ShootDay] {
        var (days, _) = dressedBoard()
        let cal = Calendar.current
        for i in days.indices { days[i].date = cal.startOfDay(for: days[i].date) }
        days.append(ShootDay(date: days[1].date.addingTimeInterval(7 * 86_400)))
        days.append(ShootDay(date: days[1].date.addingTimeInterval(8 * 86_400), dayType: .scout, dayNote: "Recce"))
        return days
    }

    @Test func swapDaysMatchesTheStripboardsCopyForEveryPair() {
        let board = swapBoard()
        let ids   = board.map(\.id) + [UUID()]
        for source in ids {
            for target in ids {
                var expected = board
                var actual   = expected
                macStripboardSwap(&expected, sourceDayId: source, targetDayId: target)
                ScheduleMoves.swapDays(source, target, in: &actual)
                #expect(actual == expected)
            }
        }
    }

    @Test func swapDaysThenThePruneMatchesTheCalendarsCopyForEveryPair() {
        let board = swapBoard()
        let start = board[0].date.addingTimeInterval(10 * 3600)
        let end   = board[1].date.addingTimeInterval(10 * 3600)
        let ids   = board.map(\.id) + [UUID()]
        for source in ids {
            for target in ids {
                var expected = board
                var actual   = expected
                macCalendarRearrange(&expected, sourceDayId: source, targetDayId: target, startDate: start, endDate: end)
                if ScheduleMoves.swapDays(source, target, in: &actual) {
                    actual.removeIfEmptyOutsideRange(dayID: source, productionRange: start...end)
                }
                #expect(actual == expected)
            }
        }
        // The scout day swapped onto the empty day past the range: the emptied source goes.
        var days = board
        let scout = days[3].id, empty = days[2].id
        ScheduleMoves.swapDays(scout, empty, in: &days)
        days.removeIfEmptyOutsideRange(dayID: scout, productionRange: start...end)
        #expect(days.map(\.id) == [board[0].id, board[1].id, empty])
        #expect(days[2].dayType == .scout && days[2].dayNote == "Recce")
    }
}

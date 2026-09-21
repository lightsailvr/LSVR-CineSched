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
}

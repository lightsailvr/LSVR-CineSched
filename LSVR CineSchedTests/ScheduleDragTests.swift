//
//  ScheduleDragTests.swift
//  LSVR CineSchedTests
//
//  The typed drag payload (#18): every kind round-trips through its transfer
//  representation, the type it travels as is the one the bundle declares, and the moves a
//  drop makes (`ScheduleMoves`) place scenes the way the calendar and the Stripboard need:
//  from the Boneyard, within a day, across days, before a strip or at the end, back to the
//  Boneyard.
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
}

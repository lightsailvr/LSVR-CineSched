//
//  ShotListPDFOptionsTests.swift
//  LSVR CineSchedTests
//
//  The Shot List's remembered options (#40): the scope's string form round-trips, a
//  remembered day that is gone (another project's, or dropped from the range) or has
//  nothing to print falls back to the whole project, and the day picker offers exactly
//  the days with a scene that prints.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ShotListPDFOptionsTests {

    private let days = PDFFixture.daysWithShots

    @Test func theScopeRoundTripsThroughItsStringForm() {
        let id = days[2].id
        #expect(ShotListPDFOptionSettings.raw(for: .project) == "project")
        #expect(ShotListPDFOptionSettings.scope(fromRaw: ShotListPDFOptionSettings.raw(for: .project), in: days) == .project)
        #expect(ShotListPDFOptionSettings.scope(fromRaw: ShotListPDFOptionSettings.raw(for: .day(id)), in: days) == .day(id))
    }

    @Test func aRememberedDayThatIsGoneIsTheWholeProject() {
        #expect(ShotListPDFOptionSettings.scope(fromRaw: ShotListPDFOptionSettings.raw(for: .day(UUID())), in: days) == .project)
        // The travel day has no scenes: nothing to export, so not a scope either.
        #expect(ShotListPDFOptionSettings.scope(fromRaw: ShotListPDFOptionSettings.raw(for: .day(days[0].id)), in: days) == .project)
        #expect(ShotListPDFOptionSettings.scope(fromRaw: "", in: days) == .project)
        #expect(ShotListPDFOptionSettings.scope(fromRaw: "day:not-a-uuid", in: days) == .project)
    }

    @Test func theDayPickerOffersTheDaysWithScenesThatPrint() {
        var eventsOnly = ShootDay(date: PDFFixture.novemberDate(day: 20))
        eventsOnly.scenes = [Scene.createCalendarEvent(title: "Table read", time: "10:00 AM")]
        let picked = ShotListPDFOptions.pickableDays(in: days + [eventsOnly])
        #expect(picked.map(\.id) == days[1...5].map(\.id))
    }

    @Test func theFirstExportIsTheWholeProjectWithFrames() {
        #expect(ShotListPDFOptions.default == ShotListPDFOptions(scope: .project, includeFrames: true))
    }
}

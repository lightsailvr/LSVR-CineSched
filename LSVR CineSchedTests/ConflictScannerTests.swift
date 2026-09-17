//
//  ConflictScannerTests.swift
//  LSVR CineSchedTests
//
//  The character-name join (case-insensitive, trimmed) between a scene's cast and the
//  cast roster, and the duplicate scene-number rule. Pinned before the scan was made a
//  table lookup (#34) so the join keeps its exact semantics.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ConflictScannerTests {

    private var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 12))! }

    private func scene(_ number: String, cast: [String]) -> Scene {
        Scene(title: "INT. ROOM - DAY", sceneNumber: number, cast: cast)
    }

    @Test func joinsCharactersToTheRosterIgnoringCaseAndWhitespace() {
        var info = ProductionInfo()
        info.castList = [
            CastMember(actorName: "Taylor", characterName: " Alex Morgan ", unavailableRanges: [DateRange(start: day(3), end: day(4))]),
            CastMember(actorName: "Jamie",  characterName: "Sam",           unavailableRanges: []),
        ]
        let clash  = scene("1", cast: ["ALEX MORGAN"])
        let spaced = scene("2", cast: ["alex morgan  "])
        let free   = scene("3", cast: ["Sam", "Nobody On The Roster"])
        let days = [
            ShootDay(date: day(5), scenes: [scene("4", cast: ["Alex Morgan"])]),   // outside the range
            ShootDay(date: day(4), scenes: [clash, free]),
            ShootDay(date: day(3), scenes: [spaced]),
        ]

        let conflicts = ConflictScanner.scan(shootDays: days, productionInfo: info)
        #expect(conflicts.map(\.sceneID) == [spaced.id, clash.id])          // sorted by date
        #expect(conflicts.map(\.character) == ["alex morgan  ", "ALEX MORGAN"]) // the scene's own spelling
        #expect(conflicts.allSatisfy { $0.actorDisplayName == info.castList[0].displayString })
        #expect(ConflictScanner.conflictSceneIDs(conflicts) == [spaced.id, clash.id])
        #expect(ConflictScanner.conflictDates(conflicts) == [cal.startOfDay(for: day(3)), cal.startOfDay(for: day(4))])
    }

    @Test func aSceneListingTheSameCharacterTwiceReportsTwice() {
        var info = ProductionInfo()
        info.castList = [CastMember(actorName: "T", characterName: "Alex", unavailableRanges: [DateRange(start: day(1), end: day(1))])]
        let twice = scene("1", cast: ["Alex", "alex"])
        let conflicts = ConflictScanner.scan(shootDays: [ShootDay(date: day(1), scenes: [twice])], productionInfo: info)
        #expect(conflicts.count == 2)
    }

    @Test func noRosterMeansNoConflicts() {
        let days = [ShootDay(date: day(1), scenes: [scene("1", cast: ["Alex"])])]
        #expect(ConflictScanner.scan(shootDays: days, productionInfo: ProductionInfo()).isEmpty)
    }

    @Test func duplicateSceneNumbersCompareParsedValues() {
        let a = scene("3",  cast: []), b = scene("03", cast: []), c = scene("3A", cast: [])
        let d = scene("",   cast: []), e = scene("",   cast: []), f = scene("12", cast: [])
        let ids = ConflictScanner.duplicateSceneNumberIDs(allScenes: [a, d, f], shootDays: [ShootDay(date: day(1), scenes: [b, c, e])])
        #expect(ids == [a.id, b.id])
    }
}

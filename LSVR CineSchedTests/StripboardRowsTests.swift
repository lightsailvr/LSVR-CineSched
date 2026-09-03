//
//  StripboardRowsTests.swift
//  LSVR CineSchedTests
//
//  Checks how the Stripboard folds runs of empty days into gap rows.
//

import Foundation
import Testing
@testable import LSVR_CineSched

struct StripboardRowsTests {

    // Mon 2026-11-02 .. builds N consecutive days; `scheduled` lists which offsets get a scene.
    private func days(_ count: Int, scheduled: Set<Int>, calendarOnly: Set<Int> = [], blackout: Set<Int> = []) -> [ShootDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        return (0..<count).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: start)!
            var scenes: [Scene] = []
            if scheduled.contains(offset)    { scenes.append(Scene(title: "INT. ROOM - DAY", sceneNumber: "\(offset)")) }
            if calendarOnly.contains(offset) { scenes.append(Scene(title: "Table read", isCalendarEvent: true)) }
            return ShootDay(date: date, scenes: scenes, isBlackout: blackout.contains(offset))
        }
    }

    private func isGap(_ row: StripboardRow) -> Bool {
        if case .gap = row { return true }
        return false
    }

    @Test func consecutiveEmptyDaysCollapseIntoOneGap() {
        let list = days(10, scheduled: [0, 1, 8, 9])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        #expect(rows.count == 5)
        #expect(!isGap(rows[0]) && !isGap(rows[1]))
        guard case .gap(let gap) = rows[2] else { Issue.record("expected a gap at row 2"); return }
        #expect(gap.dayCount == 6)
        #expect(gap.id == list[2].id)
        #expect(gap.days.map { $0.index } == [2, 3, 4, 5, 6, 7])
        #expect(!isGap(rows[3]) && !isGap(rows[4]))
    }

    @Test func leadingAndTrailingEmptyDaysAlsoCollapse() {
        let list = days(6, scheduled: [2, 3])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        #expect(rows.count == 4)
        #expect(isGap(rows[0]) && isGap(rows[3]))
    }

    @Test func calendarOnlyDaysStayVisibleAsDayRows() {
        // A day holding only a table read is a scheduled day on the board, not a gap.
        let list = days(5, scheduled: [0, 4], calendarOnly: [2])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        #expect(rows.count == 5)
        #expect(!isGap(rows[2]))
        #expect(isGap(rows[1]) && isGap(rows[3]))
    }

    @Test func typedOrNotedDaysStayVisibleAsDayRows() {
        var list = days(7, scheduled: [0, 6])
        list[2].dayType = .travel
        list[4].dayNote = "Sunset 4:52 PM"
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        // day0, gap(1), travel(2), gap(3), noted(4), gap(5), day6
        #expect(rows.count == 7)
        #expect(!isGap(rows[2]) && !isGap(rows[4]))
        #expect(isGap(rows[1]) && isGap(rows[3]) && isGap(rows[5]))
    }

    @Test func gapCountsWeekends() {
        // Nov 2 2026 is a Monday, so offsets 5 and 6 are Sat/Sun.
        let list = days(9, scheduled: [0, 8])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        guard case .gap(let gap) = rows[1] else { Issue.record("expected a gap"); return }
        #expect(gap.dayCount == 7)
        #expect(gap.weekendCount == 2)
    }

    @Test func anyExpandedDayExpandsItsWholeGap() {
        let list = days(6, scheduled: [0, 5])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [list[3].id])
        #expect(rows.count == 6)
        #expect(rows.allSatisfy { !isGap($0) })
    }

    @Test func expansionSurvivesAGapSplit() {
        // Expand the gap, then schedule something in its middle: both halves stay expanded.
        var list = days(7, scheduled: [0, 6])
        let expanded = Set(list[1...5].map { $0.id })
        list[3].scenes.append(Scene(title: "EXT. STREET - NIGHT"))
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: expanded)
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { !isGap($0) })
    }

    @Test func showAllDaysNeverProducesGaps() {
        let list = days(10, scheduled: [4], calendarOnly: [1])
        let rows = stripboardRows(for: list, showAllDays: true, expandedDayIDs: [])
        #expect(rows.count == 10)
        #expect(rows.allSatisfy { !isGap($0) })
    }

    @Test func dayRowsKeepTheirIndexIntoShootDays() {
        let list = days(5, scheduled: [1, 3])
        let rows = stripboardRows(for: list, showAllDays: false, expandedDayIDs: [])
        let indices = rows.compactMap { row -> Int? in
            if case .day(let index, _) = row { return index }
            return nil
        }
        #expect(indices == [1, 3])
    }
}

//
//  DaySummariesTests.swift
//  LSVR CineSchedTests
//
//  The iPhone's pure summaries (#24): what a Days list header and the Day screen header
//  say about one day (`DaySummary`), the week strip around a date (`WeekStrip`), where
//  Today lands (`todayTarget`) and how a date becomes a row to scroll to
//  (`dayScrollTarget`). Everything is computed in a fixed UTC calendar so the weekdays
//  and "same day" checks do not depend on the machine's zone.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct DaySummariesTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Noon UTC on the given day of November 2026 (a Sunday-first month: Nov 1 2026 is a Sunday).
    private func november(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func scene(_ number: String, eighths: Int = 8, minutes: Int = 30) -> Scene {
        Scene(title: "INT. ROOM - DAY", sceneNumber: number, duration: eighths, estimatedTime: minutes, cast: ["ANA", "LUIS"], summary: "They talk.")
    }

    /// Nov 2 (Mon) .. Nov 2 + count - 1, with script scenes on the offsets in `scheduled`.
    private func days(_ count: Int, scheduled: Set<Int>, startingOn firstDay: Int = 2) -> [ShootDay] {
        (0..<count).map { offset in
            let scenes = scheduled.contains(offset) ? [scene("\(offset)")] : []
            return ShootDay(date: november(firstDay + offset), scenes: scenes)
        }
    }

    // MARK: - The day's label

    @Test func labelNamesTheDayNumberAndTheDate() {
        let list    = days(3, scheduled: [0, 1, 2])
        let numbers = productionDayNumbers(for: list)
        let summary = DaySummary(day: list[1], dayNumbers: numbers)
        #expect(summary.label == "\(L("Day")) 2 · \(formattedDate(list[1].date))")
        #expect(DaySummary.label(dayNumber: 2, date: list[1].date) == summary.label)
    }

    @Test func labelOfAnUnnumberedDayIsTheDateAlone() {
        let list    = days(2, scheduled: [0])
        let summary = DaySummary(day: list[1], dayNumbers: productionDayNumbers(for: list))
        #expect(summary.productionDayNumber == nil)
        #expect(summary.label == formattedDate(list[1].date))
        #expect(DaySummary.label(dayNumber: nil, date: list[1].date) == formattedDate(list[1].date))
    }

    // MARK: - DaySummary

    @Test func summaryReadsTheDayNumberFromTheTable() {
        var list = days(4, scheduled: [0, 1, 3])
        list[1].dayType = .travel
        let numbers = productionDayNumbers(for: list)
        let summaries = list.map { DaySummary(day: $0, dayNumbers: numbers) }
        // A travel day with scenes is not numbered, and an empty day is not either.
        #expect(summaries.map(\.productionDayNumber) == [1, nil, nil, 2])
        #expect(summaries[1].dayType == .travel)
        #expect(summaries[0].dayID == list[0].id)
        #expect(summaries[0].date == list[0].date)
    }

    @Test func summaryCountsOnlyScriptScenesAndTheirEighths() {
        var d = ShootDay(date: november(3), scenes: [scene("1", eighths: 12), scene("2", eighths: 3)])
        d.scenes.append(Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "0:30"))
        d.scenes.append(Scene.createCalendarEvent(title: "Producer visit", time: "3:00 PM"))
        d.scenes.append(Scene.createCalendarEvent(title: "Table read", time: "6:00 PM"))
        var banner = Scene.createBanner(type: .notice, title: "Safety", estimatedTime: "0:00")
        banner.duration = 5 // a banner with a page count must still not count
        d.scenes.append(banner)
        let summary = DaySummary(day: d, dayNumbers: [d.id: 1])
        #expect(summary.sceneCount   == 2)
        #expect(summary.totalEighths == 15)
        #expect(summary.pagesText    == "1 7/8")
        #expect(summary.eventCount   == 2)
        #expect(summary.stripCount   == 4)   // scenes and banners, not events
    }

    @Test func summaryGeneralCallFallsBackAsTheCascadeDoes() {
        var d = ShootDay(date: november(3), scenes: [scene("1")])
        #expect(DaySummary(day: d, dayNumbers: [:]).generalCall == "07:30 AM")
        d.callSheet.readyToShootTime = "8:00 AM"
        #expect(DaySummary(day: d, dayNumbers: [:]).generalCall == "08:00 AM")
        d.callSheet.generalCallTime = "6:30 AM"
        // Typed as the call sheet has it, not reformatted.
        #expect(DaySummary(day: d, dayNumbers: [:]).generalCall == "6:30 AM")
    }

    @Test func summaryCarriesTheNoteAndTheCallSheetFlag() {
        var d = ShootDay(date: november(3), scenes: [], dayType: .travel, dayNote: "Fly LAX → ABQ")
        var summary = DaySummary(day: d, dayNumbers: [:])
        #expect(summary.note == "Fly LAX → ABQ")
        #expect(summary.hasCallSheet == false)
        d.callSheet.generalCallTime = "6:30 AM"
        summary = DaySummary(day: d, dayNumbers: [:])
        #expect(summary.hasCallSheet == true)
    }

    // MARK: - WeekStrip

    @Test func weekStripCoversSundayToSaturdayAroundAMidweekDate() {
        // Nov 4 2026 is a Wednesday; its week runs Sun Nov 1 .. Sat Nov 7.
        let list = days(6, scheduled: [0, 1, 2, 3, 4, 5])           // Nov 2 .. Nov 7
        let strip = WeekStrip(containing: november(4), shootDays: list, today: november(20), calendar: calendar)
        #expect(strip.days.count == 7)
        #expect(strip.days.map { calendar.component(.day, from: $0.date) } == [1, 2, 3, 4, 5, 6, 7])
        #expect(calendar.component(.weekday, from: strip.days[0].date) == 1)   // Sunday
        #expect(calendar.component(.weekday, from: strip.days[6].date) == 7)   // Saturday
        #expect(strip.days.map(\.isToday) == [false, false, false, false, false, false, false])
    }

    @Test func weekStripMarksDaysOutsideTheRangeAsAbsent() {
        let list = days(3, scheduled: [0, 2])                           // Nov 2, 3, 4
        let strip = WeekStrip(containing: november(4), shootDays: list, today: november(20), calendar: calendar)
        #expect(strip.days[0].day == nil)                                // Nov 1
        #expect(strip.days[1].day?.id == list[0].id)                     // Nov 2
        #expect(strip.days[3].day?.id == list[2].id)                     // Nov 4
        #expect(strip.days[4].day == nil)                                // Nov 5
        #expect(strip.days.map(\.sceneCount) == [0, 1, 0, 1, 0, 0, 0])
        #expect(strip.days[0].dayType == nil)
        #expect(strip.days[1].dayType == .shoot)
    }

    @Test func weekStripCarriesTheDayTypeAndFlagsToday() {
        var list = days(7, scheduled: [1, 2], startingOn: 1)            // Nov 1 .. Nov 7
        list[0].dayType = .travel
        list[5].dayType = .dayOff
        let strip = WeekStrip(containing: november(1), shootDays: list, today: november(3, hour: 23), calendar: calendar)
        #expect(strip.days[0].dayType == .travel)
        #expect(strip.days[5].dayType == .dayOff)
        #expect(strip.days.map(\.isToday) == [false, false, true, false, false, false, false])
    }

    @Test func weekStripStartsOnTheSundayEvenWhenTheReferenceIsOne() {
        // Sunday Nov 8 stays the first day; Saturday Nov 14 is the last.
        let strip = WeekStrip(containing: november(8), shootDays: [], today: november(8), calendar: calendar)
        #expect(calendar.component(.day, from: strip.days[0].date) == 8)
        #expect(calendar.component(.day, from: strip.days[6].date) == 14)
        #expect(strip.days[0].isToday)
        // Saturday Nov 14 belongs to the same week.
        let saturday = WeekStrip(containing: november(14), shootDays: [], today: november(8), calendar: calendar)
        #expect(saturday.days.map(\.date) == strip.days.map(\.date))
    }

    @Test func weekStartIgnoresTheCalendarsFirstWeekday() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        // Wed Nov 4 -> Sun Nov 1, whatever the calendar says a week starts on.
        #expect(calendar.component(.day, from: WeekStrip.weekStart(containing: november(4), calendar: mondayFirst)) == 1)
        #expect(WeekStrip.weekStart(containing: november(1), calendar: mondayFirst) == calendar.startOfDay(for: november(1)))
        #expect(WeekStrip.weekStart(containing: november(7, hour: 23), calendar: mondayFirst) == calendar.startOfDay(for: november(1)))
    }

    @Test func weekStripKnowsThePreviousAndNextWeek() {
        let strip = WeekStrip(containing: november(4), shootDays: [], today: november(4), calendar: calendar)
        #expect(calendar.component(.day, from: strip.previousWeekDate) == 25)   // Oct 25, a Sunday
        #expect(calendar.component(.month, from: strip.previousWeekDate) == 10)
        #expect(calendar.component(.day, from: strip.nextWeekDate) == 8)       // Nov 8, a Sunday
        #expect(strip.days.first?.date == strip.start)
    }

    @Test func weekStripCountsShootDaysOnlyAsWorkingDays() {
        var list = days(7, scheduled: [1, 2, 3], startingOn: 1)
        list[4].scenes = [Scene.createCalendarEvent(title: "Table read", time: "10:00 AM")]
        let strip = WeekStrip(containing: november(1), shootDays: list, today: november(1), calendar: calendar)
        #expect(strip.days[4].sceneCount == 0)
        #expect(strip.days[4].eventCount == 1)
        #expect(strip.days[1].eventCount == 0)
    }

    // MARK: - todayTarget

    @Test func todayLandsOnTheDayDatedToday() {
        let list = days(5, scheduled: [0, 1, 2, 3, 4])
        #expect(todayTarget(in: list, now: november(4, hour: 3), calendar: calendar) == list[2].id)
    }

    @Test func todayBeforeTheRangeLandsOnTheFirstDay() {
        let list = days(5, scheduled: [0, 1, 2, 3, 4])                  // Nov 2 .. Nov 6
        #expect(todayTarget(in: list, now: november(1), calendar: calendar) == list[0].id)
    }

    @Test func todayAfterTheRangeLandsOnTheLastDay() {
        let list = days(5, scheduled: [0, 1, 2, 3, 4])
        #expect(todayTarget(in: list, now: november(20), calendar: calendar) == list[4].id)
    }

    @Test func todayInAGapLandsOnTheGapDay() {
        // The gap day exists in the range (every date has a ShootDay), so Today lands on it
        // and the caller expands its gap.
        let list = days(5, scheduled: [0, 4])
        #expect(todayTarget(in: list, now: november(4), calendar: calendar) == list[2].id)
    }

    @Test func todayBetweenTwoRangesLandsOnTheNextDay() {
        // A project whose days were regenerated with a hole: Nov 2, 3 and Nov 6, 7.
        let list = days(2, scheduled: [0, 1]) + days(2, scheduled: [0, 1], startingOn: 6)
        #expect(todayTarget(in: list, now: november(4), calendar: calendar) == list[2].id)
    }

    @Test func todayInAnEmptyProjectIsNil() {
        #expect(todayTarget(in: [], now: november(4), calendar: calendar) == nil)
    }

    @Test func todayIgnoresTheOrderOfTheDays() {
        let list = Array(days(5, scheduled: [0, 1, 2, 3, 4]).reversed())
        #expect(todayTarget(in: list, now: november(1), calendar: calendar) == list.last?.id)
    }

    // MARK: - dayScrollTarget

    @Test func scrollTargetForADateInACollapsedGapSaysSo() {
        let list = days(5, scheduled: [0, 4])
        let target = dayScrollTarget(for: november(4, hour: 1), in: list, expandedDayIDs: [], calendar: calendar)
        #expect(target?.dayID == list[2].id)
        #expect(target?.isInCollapsedGap == true)
    }

    @Test func scrollTargetForAnExpandedGapDayIsNotCollapsed() {
        let list = days(5, scheduled: [0, 4])
        let target = dayScrollTarget(for: november(4), in: list, expandedDayIDs: [list[2].id], calendar: calendar)
        #expect(target?.isInCollapsedGap == false)
    }

    @Test func scrollTargetForAScheduledOrTypedDayIsNotCollapsed() {
        var list = days(5, scheduled: [0, 4])
        list[2].dayType = .travel
        #expect(dayScrollTarget(for: november(4), in: list, expandedDayIDs: [], calendar: calendar)?.isInCollapsedGap == false)
        #expect(dayScrollTarget(for: november(2), in: list, expandedDayIDs: [], calendar: calendar)?.isInCollapsedGap == false)
    }

    @Test func scrollTargetForADateOutsideTheRangeIsNil() {
        let list = days(5, scheduled: [0, 4])
        #expect(dayScrollTarget(for: november(20), in: list, expandedDayIDs: [], calendar: calendar) == nil)
    }
}

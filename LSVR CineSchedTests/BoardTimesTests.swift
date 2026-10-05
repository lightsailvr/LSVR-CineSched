//
//  BoardTimesTests.swift
//  LSVR CineSchedTests
//
//  The call sheet's lunch and wrap as the Stripboard has them (BoardTimes.swift): a
//  typed time wins; a blank one is read from the board's cascade, the lunch where the
//  day's lunch strip starts and the wrap where its last strip ends.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct BoardTimesTests {

    private func day(generalCall: String = "07:00 AM", lunch: String = "", wrap: String = "", scenes: [Scene]) -> ShootDay {
        var sheet = CallSheetData()
        sheet.generalCallTime = generalCall
        sheet.lunchTime       = lunch
        sheet.wrapTime        = wrap
        return ShootDay(date: Date(timeIntervalSince1970: 0), scenes: scenes, callSheet: sheet)
    }

    private func scene(_ number: String, minutes: Int) -> Scene {
        Scene(title: "INT. ROOM - DAY", sceneNumber: number, estimatedTime: minutes)
    }

    // MARK: - From the board

    @Test func aBlankLunchIsWhereTheBoardsLunchBannerStarts() {
        let lunch = Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "1:00")
        let d = day(scenes: [scene("1", minutes: 90), lunch, scene("2", minutes: 60)])
        #expect(d.boardLunchStrip?.id == lunch.id)
        #expect(d.effectiveLunchTime == "08:30 AM")
    }

    @Test func aBlankWrapIsWhereTheLastStripEnds() {
        let taillights = Scene.createBanner(type: .custom, title: "Taillights", estimatedTime: "0:00")
        let d = day(scenes: [scene("1", minutes: 90), Scene.createBanner(type: .custom, title: "Wrap Out", estimatedTime: "0:45"), taillights])
        #expect(d.effectiveWrapTime == "09:15 AM")
    }

    @Test func theBoardsTimesRunPastMidnight() {
        let lunch = Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "1:00")
        let d = day(generalCall: "07:30 PM", scenes: [scene("1", minutes: 360), lunch, scene("2", minutes: 360)])
        #expect(d.effectiveLunchTime == "01:30 AM")
        #expect(d.effectiveWrapTime  == "08:30 AM")
    }

    @Test func theLunchStripIsTheAutoMealThenALunchTitleThenAMealBreak() {
        let mealBreak = Scene.createBanner(type: .mealBreak, title: "Second meal")
        let titled    = Scene.createBanner(type: .notice, title: "Almuerzo")
        let auto      = Scene.createAutoMeal(kind: .lunch, timeString: "12:00 PM")
        #expect(day(scenes: [mealBreak]).boardLunchStrip?.id == mealBreak.id)
        #expect(day(scenes: [mealBreak, titled]).boardLunchStrip?.id == titled.id)
        #expect(day(scenes: [mealBreak, titled, auto]).boardLunchStrip?.id == auto.id)
        #expect(day(scenes: [Scene.createBanner(type: .notice, title: "Safety")]).boardLunchStrip == nil)
    }

    @Test func calendarEventsAreNotStrips() {
        var event = Scene.createBanner(type: .notice, title: "Lunch with the client", estimatedTime: "2:00")
        event.isCalendarEvent = true
        event.customStartTime = "09:00 PM"
        let d = day(scenes: [scene("1", minutes: 60), event])
        #expect(d.boardLunchStrip == nil)
        #expect(d.effectiveLunchTime == "")
        #expect(d.effectiveWrapTime  == "08:00 AM")
    }

    @Test func aDayWithoutStripsHasNeither() {
        let d = day(scenes: [])
        #expect(d.effectiveLunchTime == "")
        #expect(d.effectiveWrapTime  == "")
    }

    // MARK: - Typed

    @Test func aTypedTimeWins() {
        let lunch = Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "1:00")
        let d = day(lunch: " 12:30 PM ", wrap: "07:00 PM", scenes: [scene("1", minutes: 90), lunch])
        #expect(d.effectiveLunchTime == "12:30 PM")
        #expect(d.effectiveWrapTime  == "07:00 PM")
    }

    // MARK: - The cascade

    /// `dayTimeline` is `dayCascade` formatted: the minutes and the strings agree.
    @Test func theTimelineIsTheCascadeFormatted() {
        let strips = [scene("1", minutes: 45), Scene.createBanner(type: .notice, title: "Note", estimatedTime: "0:00"), scene("2", minutes: 0)]
        let d = day(scenes: strips)
        let timeline = dayTimeline(for: d, scenes: strips)
        for slot in dayCascade(for: d, scenes: strips) {
            #expect(timeline[slot.sceneID]?.startStr == formatMinutesToClock(slot.startMin))
            #expect(timeline[slot.sceneID]?.endStr   == formatMinutesToClock(slot.endMin))
        }
    }
}

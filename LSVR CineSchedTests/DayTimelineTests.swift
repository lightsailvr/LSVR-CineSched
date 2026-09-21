//
//  DayTimelineTests.swift
//  LSVR CineSchedTests
//
//  The time cascade (#24): the start and end times each strip of a day gets from the
//  call sheet's times and the strips' estimates. It was `StripboardView.computeDayTimeline`
//  until the iPhone's Days list needed the same numbers; these pin the behaviour the
//  Stripboard had before the move, so the board's times cannot drift.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct DayTimelineTests {

    private func day(generalCall: String = "", readyToShoot: String = "", scenes: [Scene]) -> ShootDay {
        var sheet = CallSheetData()
        sheet.generalCallTime  = generalCall
        sheet.readyToShootTime = readyToShoot
        return ShootDay(date: Date(timeIntervalSince1970: 0), scenes: scenes, callSheet: sheet)
    }

    private func scene(_ number: String, minutes: Int, startsAt: String = "") -> Scene {
        Scene(title: "INT. ROOM - DAY", sceneNumber: number, estimatedTime: minutes, customStartTime: startsAt)
    }

    // MARK: - Where the day starts

    @Test func startsAtHalfPastSevenWhenTheCallSheetIsBlank() {
        let a = scene("1", minutes: 60)
        let timeline = dayTimeline(for: day(scenes: [a]), scenes: [a])
        #expect(timeline[a.id]?.startStr == "07:30 AM")
        #expect(timeline[a.id]?.endStr   == "08:30 AM")
        #expect(timeline[a.id]?.timeDisplay == "07:30 AM – 08:30 AM")
    }

    @Test func startsAtTheGeneralCallWhenThereIsNoReadyToShootTime() {
        let a = scene("1", minutes: 30)
        let timeline = dayTimeline(for: day(generalCall: "6:30 AM", scenes: [a]), scenes: [a])
        #expect(timeline[a.id]?.startStr == "06:30 AM")
        #expect(timeline[a.id]?.endStr   == "07:00 AM")
    }

    @Test func readyToShootWinsOverTheGeneralCall() {
        let a = scene("1", minutes: 30)
        let timeline = dayTimeline(for: day(generalCall: "6:30 AM", readyToShoot: "8:00 AM", scenes: [a]), scenes: [a])
        #expect(timeline[a.id]?.startStr == "08:00 AM")
    }

    @Test func anUnparseableCallFallsBackToHalfPastSeven() {
        let a = scene("1", minutes: 15)
        let timeline = dayTimeline(for: day(generalCall: "dawn", scenes: [a]), scenes: [a])
        #expect(timeline[a.id]?.startStr == "07:30 AM")
    }

    @Test func dayStartMinutesFollowTheSamePrecedence() {
        #expect(dayStartMinutes(for: day(scenes: [])) == 7 * 60 + 30)
        #expect(dayStartMinutes(for: day(generalCall: "6:30 AM", scenes: [])) == 6 * 60 + 30)
        #expect(dayStartMinutes(for: day(generalCall: "6:30 AM", readyToShoot: "8:00 AM", scenes: [])) == 8 * 60)
        #expect(dayStartMinutes(for: day(generalCall: "dawn", scenes: [])) == 7 * 60 + 30)
    }

    // MARK: - The cascade

    @Test func eachStripStartsWhereThePreviousOneEnded() {
        let a = scene("1", minutes: 45)
        let b = scene("2", minutes: 30)
        let c = scene("3", minutes: 90)
        let timeline = dayTimeline(for: day(generalCall: "7:00 AM", scenes: [a, b, c]), scenes: [a, b, c])
        #expect(timeline[a.id]?.timeDisplay == "07:00 AM – 07:45 AM")
        #expect(timeline[b.id]?.timeDisplay == "07:45 AM – 08:15 AM")
        #expect(timeline[c.id]?.timeDisplay == "08:15 AM – 09:45 AM")
        #expect(timeline[c.id]?.durStr == "1:30")
    }

    @Test func aCustomStartTimeResetsTheCascadeFromThere() {
        let a = scene("1", minutes: 60)
        let b = scene("2", minutes: 30, startsAt: "10:15 AM")
        let c = scene("3", minutes: 30)
        let timeline = dayTimeline(for: day(generalCall: "7:00 AM", scenes: [a, b, c]), scenes: [a, b, c])
        #expect(timeline[a.id]?.timeDisplay == "07:00 AM – 08:00 AM")
        #expect(timeline[b.id]?.timeDisplay == "10:15 AM – 10:45 AM")
        #expect(timeline[c.id]?.timeDisplay == "10:45 AM – 11:15 AM")
    }

    @Test func anUnparseableCustomStartTimeIsIgnored() {
        let a = scene("1", minutes: 60)
        let b = scene("2", minutes: 30, startsAt: "after lunch")
        let timeline = dayTimeline(for: day(generalCall: "7:00 AM", scenes: [a, b]), scenes: [a, b])
        #expect(timeline[b.id]?.timeDisplay == "08:00 AM – 08:30 AM")
    }

    @Test func aSceneWithNoEstimateTakesFifteenMinutes() {
        let a = scene("1", minutes: 0)
        let b = scene("2", minutes: 30)
        let timeline = dayTimeline(for: day(generalCall: "7:00 AM", scenes: [a, b]), scenes: [a, b])
        #expect(timeline[a.id]?.timeDisplay == "07:00 AM – 07:15 AM")
        #expect(timeline[a.id]?.durStr == "0:15")
        #expect(timeline[b.id]?.startStr == "07:15 AM")
    }

    @Test func aBannerKeepsItsOwnEstimateEvenWhenZero() {
        let a = scene("1", minutes: 60)
        let notice = Scene.createBanner(type: .notice, title: "Safety meeting", estimatedTime: "0:00")
        let lunch  = Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "0:30")
        let b = scene("2", minutes: 30)
        let timeline = dayTimeline(for: day(generalCall: "7:00 AM", scenes: [a, notice, lunch, b]), scenes: [a, notice, lunch, b])
        // A zero-duration banner shows a single time and takes no time from the day.
        #expect(timeline[notice.id]?.timeDisplay == "08:00 AM")
        #expect(timeline[notice.id]?.durStr == "0:00")
        #expect(timeline[lunch.id]?.timeDisplay == "08:00 AM – 08:30 AM")
        #expect(timeline[b.id]?.timeDisplay == "08:30 AM – 09:00 AM")
    }

    @Test func onlyTheScenesPassedInAreTimed() {
        // The Stripboard passes the strips without the calendar events, which never join
        // the cascade; the timeline keys only what it was given.
        let a = scene("1", minutes: 60)
        let event = Scene.createCalendarEvent(title: "Producer visit", time: "3:00 PM")
        let d = day(generalCall: "7:00 AM", scenes: [a, event])
        let timeline = dayTimeline(for: d, scenes: d.scenes.filter { !$0.isCalendarEvent })
        #expect(timeline.count == 1)
        #expect(timeline[event.id] == nil)
    }

    @Test func aCascadePastMidnightWrapsTheClock() {
        let a = scene("1", minutes: 120)
        let timeline = dayTimeline(for: day(generalCall: "11:00 PM", scenes: [a]), scenes: [a])
        #expect(timeline[a.id]?.timeDisplay == "11:00 PM – 01:00 AM")
    }
}

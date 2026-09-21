//
//  ProductionRangeTests.swift
//  LSVR CineSchedTests
//
//  Changing the production range regenerates the shoot-day list (#9). The regeneration is
//  a pure edit of `ProjectData`, so these tests run it directly, in both merge and shift
//  mode; that a range change is one undo step like every other edit is pinned by
//  `ProjectDocumentTests.eachEditKindIsOneLabelledUndoStep`.
//
//  The fixture's shoot runs November 1 (a travel day) through November 6, 2026, with
//  script scenes on the 2nd to the 6th and a full call sheet on the 4th.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ProductionRangeTests {

    private let calendar = Calendar.current

    private func project(shiftMode: Bool) -> ProjectData {
        var project = ProjectCodecTests.project
        project.isShiftModeEnabled = shiftMode
        return project
    }

    private func day(_ n: Int) -> Date { PDFFixture.novemberDate(day: n) }

    /// The shoot day on `date`, if the project has one.
    private func shootDay(_ project: ProjectData, on date: Date) -> ShootDay? {
        project.shootDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Scene numbers of the script scenes (not banners, not events) on `date`.
    private func scriptSceneNumbers(_ project: ProjectData, on date: Date) -> [String] {
        shootDay(project, on: date)?.scenes.filter { !$0.isBanner }.map(\.sceneNumber) ?? []
    }

    /// The invariant every regeneration must keep: a script scene ID lives in exactly one
    /// of the Boneyard or some shoot day, and none is dropped.
    private func expectNoSceneLostOrDuplicated(from before: ProjectData, in after: ProjectData) {
        let scriptIDs: (ProjectData) -> [UUID] = { project in
            project.allScenes.map(\.id) + project.shootDays.flatMap { $0.scenes.filter { !$0.isCalendarEvent }.map(\.id) }
        }
        let beforeIDs = scriptIDs(before)
        let afterIDs  = scriptIDs(after)
        #expect(Set(afterIDs) == Set(beforeIDs))
        #expect(afterIDs.count == beforeIDs.count)
    }

    // MARK: - Merge mode (shift off)

    @Test func extendingTheRangeAddsEmptyDaysAndKeepsEverythingWhereItWas() {
        let before = project(shiftMode: false)
        var after  = before
        after.updateProductionRange(from: day(1), to: day(10), calendar: calendar)

        #expect(after.shootDays.count == 10)
        #expect(after.shootDays.map(\.date) == after.shootDays.map(\.date).sorted())
        for n in 2...6 {
            #expect(scriptSceneNumbers(after, on: day(n)) == scriptSceneNumbers(before, on: day(n)))
        }
        for n in 7...10 {
            #expect(shootDay(after, on: day(n))?.scenes.isEmpty == true)
        }
        #expect(shootDay(after, on: day(1))?.dayType == .travel)
        #expect(shootDay(after, on: day(1))?.dayNote == "Fly LAX → ABQ")
        #expect(shootDay(after, on: day(4))?.callSheet == shootDay(before, on: day(4))?.callSheet)
        #expect(after.allScenes == before.allScenes)
        expectNoSceneLostOrDuplicated(from: before, in: after)
    }

    @Test func shrinkingTheRangeReturnsScriptScenesToTheBoneyardAndKeepsTheRestOnTheirDates() {
        let before = project(shiftMode: false)
        var after  = before
        after.updateProductionRange(from: day(3), to: day(4), calendar: calendar)

        // The days in range keep their scenes; the days outside lose their script scenes
        // to the Boneyard but keep their call sheets, events, day types and notes.
        #expect(scriptSceneNumbers(after, on: day(3)) == scriptSceneNumbers(before, on: day(3)))
        #expect(scriptSceneNumbers(after, on: day(4)) == scriptSceneNumbers(before, on: day(4)))
        for n in [2, 5, 6] {
            #expect(scriptSceneNumbers(after, on: day(n)).isEmpty)
            #expect(shootDay(after, on: day(n))?.scenes.contains { $0.isCalendarEvent } == true)
            #expect(shootDay(after, on: day(n))?.callSheet.generalCallTime == "6:30 AM")
            for scene in shootDay(before, on: day(n))!.scenes where !scene.isCalendarEvent {
                #expect(after.allScenes.contains { $0.id == scene.id })
            }
        }
        #expect(shootDay(after, on: day(1))?.dayType == .travel)
        #expect(after.allScenes.prefix(before.allScenes.count) == ArraySlice(before.allScenes))
        expectNoSceneLostOrDuplicated(from: before, in: after)
    }

    @Test func withShiftModeOffMovingTheStartLeavesEverythingOnItsDates() {
        let before = project(shiftMode: false)
        var after  = before
        after.updateProductionRange(from: day(4), to: day(8), calendar: calendar)

        for n in 4...6 {
            #expect(scriptSceneNumbers(after, on: day(n)) == scriptSceneNumbers(before, on: day(n)))
        }
        for n in [2, 3] {
            #expect(scriptSceneNumbers(after, on: day(n)).isEmpty)
        }
        #expect(shootDay(after, on: day(4))?.callSheet == shootDay(before, on: day(4))?.callSheet)
        expectNoSceneLostOrDuplicated(from: before, in: after)
    }

    // MARK: - Shift mode

    @Test func shiftModeSlidesScenesEventsCallSheetsAndDayTypesByTheStartOffset() {
        let before = project(shiftMode: true)
        var after  = before
        // The first script scene was on the 2nd; a start on the 9th is a week later.
        after.updateProductionRange(from: day(9), to: day(13), calendar: calendar)

        for n in 2...6 {
            #expect(scriptSceneNumbers(after, on: day(n + 7)) == scriptSceneNumbers(before, on: day(n)))
            // Script scenes and banners keep their order; the regeneration has always put
            // the day's calendar events after them.
            #expect(shootDay(after, on: day(n + 7))?.scenes.filter { !$0.isCalendarEvent }.map(\.id)
                    == shootDay(before, on: day(n))?.scenes.filter { !$0.isCalendarEvent }.map(\.id))
            #expect(shootDay(after, on: day(n + 7))?.scenes.filter(\.isCalendarEvent).map(\.id)
                    == shootDay(before, on: day(n))?.scenes.filter(\.isCalendarEvent).map(\.id))
            #expect(shootDay(after, on: day(n + 7))?.callSheet == shootDay(before, on: day(n))?.callSheet)
        }
        // The travel day slid too, to the day before the new Day 1, outside the range but kept.
        #expect(shootDay(after, on: day(8))?.dayType == .travel)
        #expect(shootDay(after, on: day(8))?.dayNote == "Fly LAX → ABQ")
        #expect(shootDay(after, on: day(1)) == nil)
        #expect(after.shootDays.map(\.date) == after.shootDays.map(\.date).sorted())
        #expect(after.allScenes == before.allScenes)
        expectNoSceneLostOrDuplicated(from: before, in: after)
    }

    @Test func shiftModeWithAnUnchangedStartIsAMerge() {
        let before = project(shiftMode: true)
        var after  = before
        after.updateProductionRange(from: day(2), to: day(9), calendar: calendar)

        for n in 2...6 {
            #expect(scriptSceneNumbers(after, on: day(n)) == scriptSceneNumbers(before, on: day(n)))
        }
        #expect(shootDay(after, on: day(1))?.dayType == .travel)
        expectNoSceneLostOrDuplicated(from: before, in: after)
    }

    // MARK: - Preview (the phone's confirmation, #28)

    @Test func previewCountsTheScenesAShorterRangeSendsToTheBoneyard() {
        let before  = project(shiftMode: false)
        let preview = before.previewProductionRange(from: day(3), to: day(4), calendar: calendar)
        var after   = before
        after.updateProductionRange(from: day(3), to: day(4), calendar: calendar)
        // The banners of the dropped days go to the Boneyard too, but are not "scenes" here.
        let scriptScenes = { (project: ProjectData) in project.allScenes.filter { !$0.isBanner }.count }
        #expect(preview.displacedSceneCount == scriptScenes(after) - scriptScenes(before))
        #expect(preview.displacedSceneCount > 0)
        #expect(preview.dayCount == 2)
    }

    @Test func previewOfAWiderRangeDisplacesNothing() {
        let preview = project(shiftMode: false).previewProductionRange(from: day(1), to: day(10), calendar: calendar)
        #expect(preview.displacedSceneCount == 0)
        #expect(preview.dayCount == 10)
    }

    @Test func previewInShiftModeFollowsTheShiftedScenes() {
        // The scenes slide with the start, so a same-length range later displaces nothing.
        let before  = project(shiftMode: true)
        let preview = before.previewProductionRange(from: day(9), to: day(13), calendar: calendar)
        #expect(preview.displacedSceneCount == 0)
        #expect(preview.dayCount == 5)
    }

    @Test func previewSaysWhetherTheScheduleSlides() {
        // Shift on and the start moved: everything slides. Shift off, or the start
        // unchanged: everything stays on its date.
        #expect(project(shiftMode: true).previewProductionRange(from: day(9), to: day(13), calendar: calendar).shifts)
        #expect(!project(shiftMode: true).previewProductionRange(from: day(2), to: day(10), calendar: calendar).shifts)
        #expect(!project(shiftMode: false).previewProductionRange(from: day(9), to: day(13), calendar: calendar).shifts)
    }

    // MARK: - Months spanned

    @Test func productionMonthsRunFromTheFirstDayToTheLast() {
        var project = self.project(shiftMode: false)
        // November 1–6 is one month; stretch the range into January.
        project.updateProductionRange(from: day(1), to: calendar.date(byAdding: .day, value: 70, to: day(1))!, calendar: calendar)
        let months = project.productionMonths(calendar: calendar)
        #expect(months.count == 3)
        #expect(months.map { calendar.component(.month, from: $0) } == [11, 12, 1])
        #expect(months.allSatisfy { calendar.component(.day, from: $0) == 1 })
        #expect(ProjectData(allScenes: [], shootDays: []).productionMonths(calendar: calendar).isEmpty)
    }
}

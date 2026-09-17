//
//  DerivedScheduleStateTests.swift
//  LSVR CineSchedTests
//
//  The state the Mac editor derives from the whole project (the sorted Boneyard, the
//  conflict sets, duplicate scene numbers, schedule-lock drift) and the cache that keeps
//  it from being recomputed more than once per project change (#34).
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct DerivedScheduleStateTests {

    private func scene(_ number: String, _ title: String, cast: [String] = [], dayNight: DayNightType = .day) -> Scene {
        Scene(title: title, sceneNumber: number, dayNightType: dayNight, cast: cast)
    }

    // MARK: - Boneyard sort

    @Test func showOrderSortsByScriptOrderAndSkipsBanners() {
        let project = ProjectData(
            allScenes: [scene("12A", "INT. A - DAY"), scene("3", "EXT. B - DAY"), Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "0:30"), scene("12", "INT. C - DAY")],
            shootDays: []
        )
        let derived = DerivedScheduleState(project: project, boneyardSort: .showOrder)
        #expect(derived.sortedBoneyard.map(\.scene.sceneNumber) == ["3", "12", "12A"])
        // Each entry remembers its position in `allScenes`, which is what the editors index by.
        #expect(derived.sortedBoneyard.map(\.index) == [1, 3, 0])
    }

    @Test func defaultOrderKeepsBoneyardOrder() {
        let project = ProjectData(allScenes: [scene("9", "INT. Z - DAY"), scene("1", "INT. A - DAY")], shootDays: [])
        let derived = DerivedScheduleState(project: project, boneyardSort: .defaultOrder)
        #expect(derived.sortedBoneyard.map(\.index) == [0, 1])
    }

    @Test func locationIntExtCastAndDayNightSorts() {
        let scenes = [
            scene("1", "EXT. ZOO - NIGHT",      cast: ["Zed"],  dayNight: .night),
            scene("2", "INT. ATTIC - DAY",      cast: ["Bo"]),
            scene("3", "3. INT. MARKET - DAY",  cast: ["Al"]),
        ]
        let project = ProjectData(allScenes: scenes, shootDays: [])

        #expect(DerivedScheduleState(project: project, boneyardSort: .location).sortedBoneyard.map(\.index) == [1, 2, 0])
        #expect(DerivedScheduleState(project: project, boneyardSort: .intExt).sortedBoneyard.map(\.index)   == [0, 1, 2])
        #expect(DerivedScheduleState(project: project, boneyardSort: .cast).sortedBoneyard.map(\.index)     == [2, 1, 0])
        #expect(DerivedScheduleState(project: project, boneyardSort: .dayNight).sortedBoneyard.map(\.index) == [1, 2, 0])
    }

    // MARK: - Conflicts, duplicates, lock drift

    @Test func derivesConflictsDuplicatesAndLockDriftFromTheProject() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let monday  = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday)!

        let clash    = scene("7", "INT. BAR - DAY", cast: ["Alex"])
        let dupA     = scene("7", "EXT. LOT - DAY")
        let harmless = scene("8", "INT. CAR - DAY", cast: ["Alex"])
        var info = ProductionInfo()
        info.castList = [CastMember(actorName: "Taylor", characterName: "Alex", unavailableRanges: [DateRange(start: monday, end: monday)])]
        // The lock recorded Alex working Tuesday only; Monday's scene is drift. The
        // scanner keys days on the machine's calendar, as the app does when it locks.
        info.scheduleLock = ScheduleLock(lockedAt: monday, workingDays: ["Alex": [Calendar.current.startOfDay(for: tuesday)]])

        let project = ProjectData(
            allScenes: [dupA],
            shootDays: [ShootDay(date: monday, scenes: [clash]), ShootDay(date: tuesday, scenes: [harmless])],
            productionInfo: info
        )
        let derived = DerivedScheduleState(project: project, boneyardSort: .showOrder)

        #expect(derived.conflictSceneIDs == [clash.id])
        #expect(derived.conflictDates == [Calendar.current.startOfDay(for: monday)])
        #expect(derived.duplicateSceneNumberIDs == [clash.id, dupA.id])
        #expect(derived.scheduleLockChanges.map(\.character) == ["Alex"])
        #expect(derived.scheduleLockChangedDates == [Calendar.current.startOfDay(for: monday)])
    }

    // MARK: - Cache

    /// The cache is keyed on the document's change count and the sort, never on the
    /// project's contents: a body pass that reads it after an unrelated state change gets
    /// the stored value back without a recomputation.
    @Test func cacheRecomputesOnlyWhenTheChangeCountOrSortMoves() {
        let cache   = DerivedScheduleStateCache()
        let first   = ProjectData(allScenes: [scene("2", "INT. B - DAY"), scene("1", "INT. A - DAY")], shootDays: [])
        let second  = ProjectData(allScenes: [scene("5", "INT. E - DAY")], shootDays: [])

        let a = cache.state(for: first, changeCount: 0, boneyardSort: .showOrder)
        #expect(a.sortedBoneyard.map(\.scene.sceneNumber) == ["1", "2"])

        // Same key, different project: the cached value is what comes back.
        let b = cache.state(for: second, changeCount: 0, boneyardSort: .showOrder)
        #expect(b.sortedBoneyard.map(\.scene.sceneNumber) == ["1", "2"])

        let c = cache.state(for: second, changeCount: 1, boneyardSort: .showOrder)
        #expect(c.sortedBoneyard.map(\.scene.sceneNumber) == ["5"])

        let d = cache.state(for: first, changeCount: 1, boneyardSort: .defaultOrder)
        #expect(d.sortedBoneyard.map(\.scene.sceneNumber) == ["2", "1"])
    }
}

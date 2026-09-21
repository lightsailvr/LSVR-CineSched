//
//  ProductionEditsTests.swift
//  LSVR CineSchedTests
//
//  The production-wide edits the iPhone's Production tab makes (ProductionEdits.swift),
//  as pure mutations of `ProjectData`: a character rename that reaches every scene's cast
//  and every call sheet's cast override (the character name join, CONTEXT.md), and Lock /
//  Unlock Schedule, which store and clear the working-days snapshot the lock report
//  compares against. Each is the rule `ContentView` applies on the Mac (its copies stay
//  where they are); the phone calls these.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ProductionEditsTests {

    // MARK: - Fixture

    private func project() -> ProjectData {
        var day1 = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day1.scenes = [
            Scene(title: "INT. KITCHEN - DAY", sceneNumber: "1", cast: ["Alex", "Sam"]),
            Scene.createBanner(type: .companyMove, title: "Move to the yard"),
        ]
        day1.callSheet.castOverride = ["alex", "Riley"]
        var day2 = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400))
        day2.scenes = [Scene(title: "EXT. YARD - DAY", sceneNumber: "2", cast: ["Sam"])]
        let boneyard = [Scene(title: "INT. BAR - NIGHT", sceneNumber: "3", cast: ["ALEX", "Jo"])]
        return ProjectData(allScenes: boneyard, shootDays: [day1, day2], projectTitle: "Fixture")
    }

    // MARK: - Character rename

    @Test func renameReachesEverySceneAndCallSheetCaseInsensitively() {
        var data = project()
        let ok = data.renameCharacter(from: " alex ", to: "Alexandra")
        #expect(ok)
        #expect(data.shootDays[0].scenes[0].cast == ["Alexandra", "Sam"])
        #expect(data.shootDays[0].callSheet.castOverride == ["Alexandra", "Riley"])
        #expect(data.shootDays[1].scenes[0].cast == ["Sam"])
        #expect(data.allScenes[0].cast == ["Alexandra", "Jo"])
    }

    @Test func renameLeavesEverythingElseAlone() {
        let before = project()
        var data   = before
        _ = data.renameCharacter(from: "Alex", to: "Alexandra")
        #expect(data.shootDays.map(\.id) == before.shootDays.map(\.id))
        #expect(data.shootDays[0].scenes[1] == before.shootDays[0].scenes[1], "the banner is untouched")
        #expect(data.shootDays[1].callSheet.castOverride == nil, "a day with no override gains none")
        #expect(data.projectTitle == before.projectTitle)
    }

    @Test func renameRefusesBlanksAndACaseOnlyChange() {
        let before = project()
        var data   = before
        let blankOld = data.renameCharacter(from: "  ", to: "Alexandra")
        let blankNew = data.renameCharacter(from: "Alex", to: "")
        let sameName = data.renameCharacter(from: "Alex", to: "ALEX")
        #expect(!blankOld)
        #expect(!blankNew)
        #expect(!sameName)
        #expect(data == before)
    }

    @Test func renameOfAnUnknownCharacterChangesNothingButReportsSuccess() {
        // The Mac's rule: a valid rename is applied wherever it matches, which may be nowhere.
        let before = project()
        var data   = before
        let ok = data.renameCharacter(from: "Nobody", to: "Somebody")
        #expect(ok)
        #expect(data == before)
    }

    // MARK: - Lock and unlock

    @Test func lockStoresTheWorkingDaysSnapshotAndTheTime() {
        var data = project()
        let now  = Date(timeIntervalSince1970: 1_800_500_000)
        data.lockSchedule(now: now)
        let lock = data.productionInfo?.scheduleLock
        #expect(lock?.lockedAt == now)
        let expected = ScheduleLockScanner.currentWorkingDays(shootDays: data.shootDays)
        #expect(lock?.workingDays.keys.sorted() == expected.keys.sorted())
        for (character, dates) in expected {
            #expect(lock?.workingDays[character] == dates.sorted(), Comment(rawValue: character))
        }
    }

    @Test func lockCreatesTheProductionInfoWhenTheProjectHasNone() {
        var data = project()
        #expect(data.productionInfo == nil)
        data.lockSchedule(now: Date(timeIntervalSince1970: 1_800_500_000))
        #expect(data.productionInfo?.scheduleLock != nil)
    }

    @Test func lockKeepsTheRestOfTheProductionInfo() {
        var data = project()
        data.productionInfo = ProductionInfo(companyName: "LSVR")
        data.lockSchedule(now: Date(timeIntervalSince1970: 1_800_500_000))
        #expect(data.productionInfo?.companyName == "LSVR")
        #expect(data.productionInfo?.scheduleLock != nil)
    }

    @Test func unlockClearsTheLockAndReportsWhetherThereWasOne() {
        var data = project()
        let nothing = data.unlockSchedule()
        #expect(!nothing)
        data.lockSchedule(now: Date(timeIntervalSince1970: 1_800_500_000))
        let cleared = data.unlockSchedule()
        #expect(cleared)
        #expect(data.productionInfo?.scheduleLock == nil)
    }
}

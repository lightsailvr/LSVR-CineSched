// AutoMealSyncTests.swift
// `ShootDay.scenesWithSyncedAutoMeals()`: the auto-meal strips follow the call sheet.

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct AutoMealSyncTests {

    private func day(_ configure: (inout CallSheetData) -> Void = { _ in }, scenes: [Scene] = []) -> ShootDay {
        var day = ShootDay(date: Date(timeIntervalSince1970: 0), scenes: scenes)
        configure(&day.callSheet)
        return day
    }

    private func scene(_ number: String) -> Scene {
        var scene = Scene(title: "Scene \(number)")
        scene.sceneNumber = number
        return scene
    }

    @Test func aDayWithoutTimesIsUnchanged() {
        let day = day(scenes: [scene("1"), scene("2")])
        #expect(day.scenesWithSyncedAutoMeals() == day.scenes)
    }

    @Test func aLunchTimeAddsALunchStripAtTheEnd() {
        let day = day({ $0.lunchTime = "01:00 PM" }, scenes: [scene("1")])
        let synced = day.scenesWithSyncedAutoMeals()
        #expect(synced.count == 2)
        #expect(synced.last?.isAutoMeal == true)
        #expect(synced.last?.mealKind == .lunch)
        #expect(synced.last?.customStartTime == "01:00 PM")
    }

    @Test func aChangedLunchTimeRetitlesTheExistingStripInPlace() {
        var day = day({ $0.lunchTime = "01:00 PM" }, scenes: [scene("1"), scene("2")])
        day.scenes = day.scenesWithSyncedAutoMeals()
        day.scenes.swapAt(1, 2)                       // lunch between the two scenes
        let lunchID = day.scenes[1].id
        day.callSheet.lunchTime = "02:15 PM"
        let synced = day.scenesWithSyncedAutoMeals()
        #expect(synced.count == 3)
        #expect(synced[1].id == lunchID)
        #expect(synced[1].customStartTime == "02:15 PM")
        #expect(synced[1].title.contains("02:15 PM"))
    }

    @Test func aClearedTimeRemovesItsStrip() {
        var day = day({ $0.wrapTime = "07:00 PM" }, scenes: [scene("1")])
        day.scenes = day.scenesWithSyncedAutoMeals()
        #expect(day.scenes.count == 2)
        day.callSheet.wrapTime = ""
        #expect(day.scenesWithSyncedAutoMeals() == [day.scenes[0]])
    }

    @Test func generalCallLeadsAndReadyToShootFollowsIt() {
        let day = day({ $0.generalCallTime = "07:00 AM"; $0.readyToShootTime = "08:00 AM" }, scenes: [scene("1")])
        let synced = day.scenesWithSyncedAutoMeals()
        #expect(synced.map(\.mealKind) == [.generalCall, .readyToShoot, nil])
    }

    @Test func syncingTwiceIsIdempotent() {
        var day = day({ $0.generalCallTime = "07:00 AM"; $0.lunchTime = "01:00 PM"; $0.wrapTime = "07:00 PM" }, scenes: [scene("1")])
        day.scenes = day.scenesWithSyncedAutoMeals()
        #expect(day.scenesWithSyncedAutoMeals() == day.scenes)
    }
}

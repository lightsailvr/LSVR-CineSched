//
//  DayEditsTests.swift
//  LSVR CineSchedTests
//
//  The iPhone's day edits (#26) are pure mutations of `ProjectData` (DayEdits.swift):
//  the day type and note, the notice strips a day gains and loses (banners and calendar
//  events, never Boneyard material), a strip's time with the Mac's lunch rule, the call
//  sheet with its auto-meals, and Duplicate Scene, whose copy is what the Mac's
//  Stripboard makes (`Scene.duplicated()`, pinned here before the Mac call site moved
//  to it). Each returns false and changes nothing when the target is gone.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct DayEditsTests {

    // MARK: - Fixture

    private let a = Scene(title: "INT. KITCHEN - DAY",  sceneNumber: "1", duration: 8,  estimatedTime: 60)
    private let b = Scene(title: "EXT. YARD - DAY",     sceneNumber: "2", duration: 4,  estimatedTime: 30)
    private let c = Scene(title: "INT. BAR - NIGHT",    sceneNumber: "3", duration: 12, estimatedTime: 90)
    private let banner = Scene.createBanner(type: .companyMove, title: "Move to the yard", estimatedTime: "0:45", colorHex: "14B8A6")
    private let event  = Scene.createCalendarEvent(title: "Tech scout", time: "9:00 AM")

    /// Day 1 holds a, the banner, b and the event; day 2 holds nothing; c is in the Boneyard.
    /// The dates are whole days in the current calendar, as the app's shoot days are.
    private func project() -> ProjectData {
        var day1 = ShootDay(date: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)))
        day1.scenes = [a, banner, b, event]
        day1.callSheet.generalCallTime = "07:00 AM"
        let day2 = ShootDay(date: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_086_400)))
        return ProjectData(allScenes: [c], shootDays: [day1, day2], projectTitle: "Fixture")
    }

    private func ids(_ scenes: [Scene]) -> [UUID] { scenes.map(\.id) }

    // MARK: - Duplicate Scene (the Mac's copy, pinned)

    @Test func duplicatedIsANewSceneTitledCopyWithTheSameFields() {
        var original = Scene(
            title:            "INT. KITCHEN - NIGHT",
            sceneNumber:      "12A",
            duration:         15,
            estimatedTime:    150,
            dayNightType:     .night,
            cast:             ["Alex Morgan", "Sam Rivera"],
            summary:          "Alex finds the letter.",
            realLocation:     "Stage 4",
            locationAddress:  "100 Universal City Plaza",
            extras:           ["Diners"],
            props:            ["Letter", "Knife"],
            setDressing:      ["Curtains"],
            wardrobe:         ["Apron"],
            makeupHair:       ["Scar"],
            vehicles:         ["Taxi"],
            specialEquipment: ["Crane"],
            stunts:           ["Fall"],
            sfx:              ["Smoke"],
            vfx:              ["Fire"],
            breakdownNotes:   "Watch the continuity.",
            customStartTime:  "9:00 AM",
            isCompleted:      true
        )
        original.isCompleted = true

        let copy = original.duplicated()

        #expect(copy.id != original.id)
        #expect(copy.title            == "INT. KITCHEN - NIGHT (Copy)")
        #expect(copy.sceneNumber      == "12A")
        #expect(copy.duration         == 15)
        #expect(copy.estimatedTime    == 150)
        #expect(copy.dayNightType     == .night)
        #expect(copy.cast             == ["Alex Morgan", "Sam Rivera"])
        #expect(copy.summary          == "Alex finds the letter.")
        #expect(copy.extras           == ["Diners"])
        #expect(copy.props            == ["Letter", "Knife"])
        #expect(copy.setDressing      == ["Curtains"])
        #expect(copy.wardrobe         == ["Apron"])
        #expect(copy.makeupHair       == ["Scar"])
        #expect(copy.vehicles         == ["Taxi"])
        #expect(copy.specialEquipment == ["Crane"])
        #expect(copy.stunts           == ["Fall"])
        #expect(copy.sfx              == ["Smoke"])
        #expect(copy.vfx              == ["Fire"])
        #expect(copy.breakdownNotes   == "Watch the continuity.")
        // What the Mac's Stripboard never carried into a copy: the copy is a fresh,
        // unscheduled scene with no set, no fixed time and no completion.
        #expect(copy.realLocation.isEmpty)
        #expect(copy.locationAddress.isEmpty)
        #expect(copy.customStartTime.isEmpty)
        #expect(!copy.isCompleted)
        #expect(!copy.isBanner && !copy.isCalendarEvent)
    }

    @Test func duplicateSceneAppendsTheCopyToTheBoneyardAndReturnsItsID() throws {
        var data = project()
        let minted = data.duplicateScene(withID: a.id)
        let copyID = try #require(minted)
        let copy   = try #require(data.scene(withID: copyID))
        #expect(copy.title == "INT. KITCHEN - DAY (Copy)")
        #expect(ids(data.allScenes) == [c.id, copyID])
        // The original stays where it was.
        #expect(ids(data.shootDays[0].scenes) == [a.id, banner.id, b.id, event.id])
    }

    @Test func duplicateSceneRefusesNoticeStripsAndUnknownIDs() {
        let before = project()
        var data   = before
        let id1 = data.duplicateScene(withID: banner.id)
        #expect(id1 == nil)
        let id2 = data.duplicateScene(withID: event.id)
        #expect(id2 == nil)
        let strangerCopy = data.duplicateScene(withID: UUID())
        #expect(strangerCopy == nil)
        #expect(data == before)
    }

    // MARK: - Day type and note

    @Test func setDayTypeChangesTheTypeAndNothingElse() {
        var data = project()
        let dayID = data.shootDays[1].id
        let ok3 = data.setDayType(.travel, forDayID: dayID)
        #expect(ok3)
        #expect(data.shootDays[1].dayType == .travel)
        #expect(data.shootDays[0].dayType == .shoot)
        #expect(data.shootDays[1].dayNote.isEmpty)
    }

    @Test func setDayNoteTrimsAndWritesTheNote() {
        var data = project()
        let dayID = data.shootDays[1].id
        let ok4 = data.setDayNote("  Fly LAX → ABQ \n", forDayID: dayID)
        #expect(ok4)
        #expect(data.shootDays[1].dayNote == "Fly LAX → ABQ")
    }

    /// The fixture's two days as the production range (the pickers' range on the phone).
    private var fixtureRange: ClosedRange<Date> {
        let data = project()
        return data.shootDays[0].date...data.shootDays[1].date
    }

    @Test func clearDayTypeReturnsTheDayToAPlainShootDayWithNoNote() {
        var data = project()
        let dayID = data.shootDays[1].id
        _ = data.setDayType(.holiday, forDayID: dayID)
        _ = data.setDayNote("Labor Day", forDayID: dayID)
        let ok5 = data.clearDayType(forDayID: dayID, productionRange: fixtureRange)
        #expect(ok5)
        #expect(data.shootDays[1].dayType == .shoot)
        #expect(data.shootDays[1].dayNote.isEmpty)
        #expect(data.shootDays.count == 2, "a day inside the range stays, empty or not")
    }

    /// A day outside the pickers' range exists only to hold something (a type, a note, an
    /// event, a call sheet); once the type and note are cleared and nothing else is on it,
    /// it goes, as the inspector's and the calendar's Clear Day Type do.
    @Test func clearDayTypeDropsAnEmptiedTypedDayOutsideTheRange() {
        var data = project()
        let range = fixtureRange
        let later = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400 + 14 * 86_400), dayType: .travel, dayNote: "Fly home")
        data.shootDays.append(later)
        let ok = data.clearDayType(forDayID: later.id, productionRange: range)
        #expect(ok)
        #expect(data.shootDays.count == 2)
        #expect(!data.shootDays.contains { $0.id == later.id })
    }

    @Test func clearDayTypeKeepsAnOutsideDayThatStillHoldsSomething() {
        var data = project()
        let range = fixtureRange
        var withEvent = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400 + 14 * 86_400), dayType: .travel)
        withEvent.scenes = [event]
        var withCallSheet = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400 + 15 * 86_400), dayType: .scout)
        withCallSheet.callSheet.generalCallTime = "06:00 AM"
        data.shootDays.append(contentsOf: [withEvent, withCallSheet])

        _ = data.clearDayType(forDayID: withEvent.id, productionRange: range)
        _ = data.clearDayType(forDayID: withCallSheet.id, productionRange: range)

        #expect(data.shootDays.count == 4)
        #expect(data.shootDays[2].dayType == .shoot)
        #expect(data.shootDays[3].dayType == .shoot)
    }

    @Test func clearDayTypeWithoutARangeDropsNothing() {
        var data = project()
        let later = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400 + 14 * 86_400), dayType: .travel)
        data.shootDays.append(later)
        _ = data.clearDayType(forDayID: later.id, productionRange: nil)
        #expect(data.shootDays.count == 3)
        #expect(data.shootDays[2].dayType == .shoot)
    }

    @Test func clearDayTypeComparesWholeDays() {
        // A range whose bounds carry a time of day still covers the day's date (the
        // inspector normalizes both bounds to the start of their day).
        let calendar = Calendar.current
        var data = project()
        for index in data.shootDays.indices {
            data.shootDays[index].date = calendar.startOfDay(for: data.shootDays[index].date)
        }
        let dayID = data.shootDays[1].id
        _ = data.setDayType(.holiday, forDayID: dayID)
        let noon = data.shootDays[0].date.addingTimeInterval(12 * 3600)...data.shootDays[1].date.addingTimeInterval(12 * 3600)
        _ = data.clearDayType(forDayID: dayID, productionRange: noon, calendar: calendar)
        #expect(data.shootDays.count == 2)
    }

    @Test func dayEditsRefuseAnUnknownDay() {
        let before = project()
        var data   = before
        let stranger = UUID()
        let ok6 = data.setDayType(.travel, forDayID: stranger)
        #expect(!ok6)
        let ok7 = data.setDayNote("x", forDayID: stranger)
        #expect(!ok7)
        let ok8 = data.clearDayType(forDayID: stranger, productionRange: nil)
        #expect(!ok8)
        #expect(data == before)
    }

    // MARK: - Notice strips: banners and calendar events

    @Test func addNoticeStripAppendsABannerToTheDay() {
        var data = project()
        let dayID = data.shootDays[0].id
        let meal  = Scene.createBanner(type: .mealBreak, title: "Second meal")
        let ok9 = data.addNoticeStrip(meal, toDayID: dayID)
        #expect(ok9)
        #expect(ids(data.shootDays[0].scenes) == [a.id, banner.id, b.id, event.id, meal.id])
        #expect(ids(data.allScenes) == [c.id], "a banner never enters the Boneyard")
    }

    @Test func addNoticeStripAppendsACalendarEvent() {
        var data = project()
        let dayID = data.shootDays[1].id
        let read  = Scene.createCalendarEvent(title: "Table read", time: "10:00 AM")
        let ok10 = data.addNoticeStrip(read, toDayID: dayID)
        #expect(ok10)
        #expect(ids(data.shootDays[1].scenes) == [read.id])
    }

    @Test func addNoticeStripRefusesAScriptSceneAndAnUnknownDay() {
        let before = project()
        var data   = before
        let dayID  = data.shootDays[0].id
        let ok11 = data.addNoticeStrip(c, toDayID: dayID)
        #expect(!ok11, "a script scene is a move, not a notice")
        let ok12 = data.addNoticeStrip(banner, toDayID: UUID())
        #expect(!ok12)
        #expect(data == before)
    }

    @Test func replaceSceneKeepsAnEditedBannerInItsPlace() {
        var data = project()
        var edited = banner
        edited.bannerTitle = "Move to the beach"
        edited.title       = "Move to the beach"
        let ok13 = data.replaceScene(edited)
        #expect(ok13)
        #expect(ids(data.shootDays[0].scenes) == [a.id, banner.id, b.id, event.id])
        #expect(data.shootDays[0].scenes[1].bannerTitle == "Move to the beach")
    }

    @Test func deleteNoticeStripRemovesABannerOutright() {
        var data = project()
        let ok14 = data.deleteNoticeStrip(withID: banner.id)
        #expect(ok14)
        #expect(ids(data.shootDays[0].scenes) == [a.id, b.id, event.id])
        #expect(ids(data.allScenes) == [c.id], "a deleted banner does not go to the Boneyard")
    }

    @Test func deleteNoticeStripRemovesACalendarEventOutright() {
        var data = project()
        let ok15 = data.deleteNoticeStrip(withID: event.id)
        #expect(ok15)
        #expect(ids(data.shootDays[0].scenes) == [a.id, banner.id, b.id])
        #expect(ids(data.allScenes) == [c.id])
    }

    @Test func deleteNoticeStripRefusesAScriptSceneAndAnUnknownID() {
        let before = project()
        var data   = before
        let ok16 = data.deleteNoticeStrip(withID: a.id)
        #expect(!ok16, "a script scene returns to the Boneyard through the moves")
        let ok17 = data.deleteNoticeStrip(withID: c.id)
        #expect(!ok17)
        let ok18 = data.deleteNoticeStrip(withID: UUID())
        #expect(!ok18)
        #expect(data == before)
    }

    // MARK: - Set Time

    @Test func applyStripTimeReplacesTheStripInPlace() {
        var data = project()
        let dayID = data.shootDays[0].id
        var timed = b
        timed.customStartTime = "11:00 AM"
        timed.estimatedTime   = 45
        let ok19 = data.applyStripTime(timed, dayID: dayID)
        #expect(ok19)
        #expect(ids(data.shootDays[0].scenes) == [a.id, banner.id, b.id, event.id])
        #expect(data.shootDays[0].scenes[2].customStartTime == "11:00 AM")
        #expect(data.shootDays[0].scenes[2].estimatedTime == 45)
        #expect(data.shootDays[0].callSheet.lunchTime.isEmpty, "only the lunch strip writes the call sheet")
    }

    @Test func applyStripTimeOnTheLunchStripMovesTheCallSheetsLunchAndTheStripFollows() throws {
        var data = project()
        let dayID = data.shootDays[0].id
        data.shootDays[0].callSheet.lunchTime = "12:30 PM"
        data.shootDays[0].scenes = data.shootDays[0].scenesWithSyncedAutoMeals()
        let lunch = try #require(data.shootDays[0].scenes.first { $0.isAutoMeal && $0.mealKind == .lunch })

        var timed = lunch
        timed.customStartTime = "01:15 PM"
        timed.estimatedTime   = 30
        let ok20 = data.applyStripTime(timed, dayID: dayID)
        #expect(ok20)

        let synced = try #require(data.shootDays[0].scenes.first { $0.id == lunch.id })
        #expect(data.shootDays[0].callSheet.lunchTime == "01:15 PM", "the Mac's Set Time rule for a lunch strip")
        #expect(synced.customStartTime == "01:15 PM")
        #expect(synced.title.contains("01:15 PM"), "the auto-meal strip is retitled for the new time in the same edit")
        #expect(synced.estimatedTime == 30, "the sync keeps the duration set")
    }

    @Test func applyStripTimeClearedOnTheLunchStripLeavesTheCallSheetAlone() throws {
        var data = project()
        let dayID = data.shootDays[0].id
        data.shootDays[0].callSheet.lunchTime = "12:30 PM"
        data.shootDays[0].scenes = data.shootDays[0].scenesWithSyncedAutoMeals()
        let lunch = try #require(data.shootDays[0].scenes.first { $0.isAutoMeal && $0.mealKind == .lunch })

        var cleared = lunch
        cleared.customStartTime = ""
        let ok21 = data.applyStripTime(cleared, dayID: dayID)
        #expect(ok21)
        #expect(data.shootDays[0].callSheet.lunchTime == "12:30 PM")
    }

    @Test func applyStripTimeRefusesAStripNotOnThatDay() {
        let before = project()
        var data   = before
        let dayID  = data.shootDays[1].id
        var timed  = b
        timed.customStartTime = "11:00 AM"
        let ok22 = data.applyStripTime(timed, dayID: dayID)
        #expect(!ok22)
        #expect(data == before)
    }

    // MARK: - Call sheet

    @Test func saveCallSheetReplacesTheDayAndSyncsItsAutoMeals() {
        var data = project()
        var day  = data.shootDays[0]
        day.callSheet.generalCallTime = "06:30 AM"
        day.callSheet.lunchTime       = "12:00 PM"
        let ok23 = data.saveCallSheet(day)
        #expect(ok23)

        let saved = data.shootDays[0]
        #expect(saved.id == day.id)
        #expect(saved.callSheet.generalCallTime == "06:30 AM")
        #expect(saved.callSheet.lunchTime == "12:00 PM")
        #expect(saved.scenes.contains { $0.isAutoMeal && $0.mealKind == .generalCall && $0.customStartTime == "06:30 AM" })
        #expect(saved.scenes.contains { $0.isAutoMeal && $0.mealKind == .lunch && $0.customStartTime == "12:00 PM" })
        #expect(saved.scenes.filter { !$0.isAutoMeal }.map(\.id) == [a.id, banner.id, b.id, event.id], "the strips keep their order")
    }

    @Test func saveCallSheetRefusesAnUnknownDay() {
        let before = project()
        var data   = before
        let stranger = ShootDay(date: Date(timeIntervalSince1970: 1_800_172_800))
        let ok24 = data.saveCallSheet(stranger)
        #expect(!ok24)
        #expect(data == before)
    }
}

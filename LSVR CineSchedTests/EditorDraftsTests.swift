//
//  EditorDraftsTests.swift
//  LSVR CineSchedTests
//
//  The adaptive editors (#19) edit plain draft values between opening and Save: what a
//  scene, a banner or a calendar event reads into its fields, how the fields validate,
//  and the one value written back. These pin each conversion without a view; the sheets,
//  the inspector and the one-assignment write-back are checked by running the app.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct EditorDraftsTests {

    // MARK: - Fixtures

    private static func scene() -> Scene {
        var scene = Scene(
            title:          "INT. KITCHEN - NIGHT",
            sceneNumber:    "12A",
            duration:       15,
            estimatedTime:  150,
            dayNightType:   .night,
            cast:           ["Alex Morgan", "Sam Rivera"],
            summary:        "Alex finds the letter.",
            realLocation:   "Stage 4",
            locationAddress: "100 Universal City Plaza",
            extras:         ["Diners"],
            props:          ["Letter", "Knife"],
            setDressing:    ["Curtains"],
            wardrobe:       ["Apron"],
            makeupHair:     ["Scar"],
            vehicles:       ["Taxi"],
            specialEquipment: ["Crane"],
            stunts:         ["Fall"],
            sfx:            ["Smoke"],
            vfx:            ["Fire"],
            breakdownNotes: "Watch the continuity.",
            customStartTime: "9:00 AM"
        )
        scene.isCompleted = true
        return scene
    }

    // MARK: - Scene draft: reading

    @Test func sceneDraftReadsEveryEditedField() {
        let draft = SceneDraft(scene: Self.scene())
        #expect(draft.sceneNumber      == "12A")
        #expect(draft.title            == "INT. KITCHEN - NIGHT")
        #expect(draft.realLocation     == "Stage 4")
        #expect(draft.duration         == "1 7/8")
        #expect(draft.estimatedTime    == "2:30")
        #expect(draft.dayNightType     == .night)
        #expect(draft.castText         == "Alex Morgan, Sam Rivera")
        #expect(draft.summary          == "Alex finds the letter.")
        #expect(draft.extras           == "Diners")
        #expect(draft.props            == "Letter, Knife")
        #expect(draft.setDressing      == "Curtains")
        #expect(draft.wardrobe         == "Apron")
        #expect(draft.makeupHair       == "Scar")
        #expect(draft.vehicles         == "Taxi")
        #expect(draft.specialEquipment == "Crane")
        #expect(draft.stunts           == "Fall")
        #expect(draft.sfx              == "Smoke")
        #expect(draft.vfx              == "Fire")
        #expect(draft.breakdownNotes   == "Watch the continuity.")
    }

    @Test func sceneDraftShowsBlanksForZeroLengths() {
        var scene = Self.scene()
        scene.duration      = 0
        scene.estimatedTime = 0
        let draft = SceneDraft(scene: scene)
        #expect(draft.duration      == "")
        #expect(draft.estimatedTime == "")
        #expect(draft.isValid, "a blank length is valid; only a malformed one is not")
    }

    @Test func sceneDraftFormatsMinutesWithoutUnits() {
        #expect(SceneDraft.minutesForEditing(45)  == "45")
        #expect(SceneDraft.minutesForEditing(120) == "2")
        #expect(SceneDraft.minutesForEditing(125) == "2:05")
    }

    /// A scene whose number is still at the front of its title (the pre-field shape)
    /// opens with the number split out, as the old editor did.
    @Test func sceneDraftExtractsALeadingSceneNumber() {
        var scene = Self.scene()
        scene.sceneNumber = ""
        scene.title       = "7. EXT. BEACH - DAY"
        let draft = SceneDraft(scene: scene)
        #expect(draft.sceneNumber == "7")
        #expect(draft.title       == "EXT. BEACH - DAY")
    }

    // MARK: - Scene draft: validation

    @Test func sceneDraftValidatesLengths() {
        var draft = SceneDraft(scene: Self.scene())
        #expect(draft.durationIsValid)
        #expect(draft.estimatedTimeIsValid)
        #expect(draft.isValid)

        draft.duration = "one page"
        #expect(!draft.durationIsValid)
        #expect(!draft.isValid)
        draft.duration = "2 3/8"
        #expect(draft.durationIsValid)
        #expect(draft.parsedEighths == 19)

        draft.estimatedTime = "2:75"
        #expect(!draft.estimatedTimeIsValid)
        #expect(!draft.isValid)
        draft.estimatedTime = "1:15"
        #expect(draft.estimatedTimeIsValid)
        #expect(draft.parsedMinutes == 75)
    }

    @Test func sceneDraftNeedsATitle() {
        var draft = SceneDraft(scene: Self.scene())
        draft.title = "   "
        #expect(!draft.isValid)
        draft.title = "EXT. ROAD - DAY"
        #expect(draft.isValid)
    }

    // MARK: - Scene draft: writing

    @Test func sceneDraftAppliesEveryFieldAndKeepsTheRest() {
        let original = Self.scene()
        var draft    = SceneDraft(scene: original)
        draft.sceneNumber      = " 13 "
        draft.title            = "EXT. ROAD - DAY"
        draft.realLocation     = " Route 66 "
        draft.duration         = "2 1/8"
        draft.estimatedTime    = "45"
        draft.dayNightType     = .day
        draft.castText         = "Casey Kim, , Riley Chen "
        draft.summary          = "The chase."
        draft.extras           = "Crowd, Police"
        draft.props            = ""
        draft.setDressing      = "Cones"
        draft.wardrobe         = "Uniform"
        draft.makeupHair       = "Dust"
        draft.vehicles         = "Cruiser, Bike"
        draft.specialEquipment = "Russian arm"
        draft.stunts           = "Skid"
        draft.sfx              = "Dust"
        draft.vfx              = "Wire removal"
        draft.breakdownNotes   = "Close the road."

        let saved = draft.applied(to: original)
        #expect(saved.id               == original.id)
        #expect(saved.sceneNumber      == "13")
        #expect(saved.title            == "EXT. ROAD - DAY")
        #expect(saved.realLocation     == "Route 66")
        #expect(saved.duration         == 17)
        #expect(saved.estimatedTime    == 45)
        #expect(saved.dayNightType     == .day)
        #expect(saved.cast             == ["Casey Kim", "Riley Chen"])
        #expect(saved.summary          == "The chase.")
        #expect(saved.extras           == ["Crowd", "Police"])
        #expect(saved.props            == [])
        #expect(saved.setDressing      == ["Cones"])
        #expect(saved.wardrobe         == ["Uniform"])
        #expect(saved.makeupHair       == ["Dust"])
        #expect(saved.vehicles         == ["Cruiser", "Bike"])
        #expect(saved.specialEquipment == ["Russian arm"])
        #expect(saved.stunts           == ["Skid"])
        #expect(saved.sfx              == ["Dust"])
        #expect(saved.vfx              == ["Wire removal"])
        #expect(saved.breakdownNotes   == "Close the road.")
        // Not edited by the form, carried through untouched.
        #expect(saved.locationAddress  == original.locationAddress)
        #expect(saved.customStartTime  == original.customStartTime)
        #expect(saved.isCompleted      == original.isCompleted)
    }

    /// An unchanged draft writes back the scene it read, so a Save with no edits is a
    /// no-op `perform` (which registers nothing).
    @Test func sceneDraftRoundTripsUnchanged() {
        let original = Self.scene()
        #expect(SceneDraft(scene: original).applied(to: original) == original)
    }

    /// A blank length keeps the stored value, except on a Custom scene, where blank
    /// means none (the old editor's rule for banners edited as scenes).
    @Test func sceneDraftBlankLengthsKeepOrClearByType() {
        let original = Self.scene()
        var draft    = SceneDraft(scene: original)
        draft.duration      = ""
        draft.estimatedTime = ""
        let kept = draft.applied(to: original)
        #expect(kept.duration      == 15)
        #expect(kept.estimatedTime == 150)

        draft.dayNightType = .custom
        let cleared = draft.applied(to: original)
        #expect(cleared.duration      == 0)
        #expect(cleared.estimatedTime == 0)
    }

    @Test func commaListsTrimAndDropBlanks() {
        #expect(SceneDraft.commaList(" a , b,,c ") == ["a", "b", "c"])
        #expect(SceneDraft.commaList("")           == [])
    }

    // MARK: - Banner draft

    @Test func bannerDraftStartsWithTheTypeDefaults() {
        let draft = BannerDraft()
        #expect(draft.type          == .notice)
        #expect(draft.title         == "Notice")
        #expect(draft.startTime     == "12:00 PM")
        #expect(draft.estimatedTime == "0:30")
        #expect(draft.note          == "")
        #expect(draft.colorHex      == "8B5CF6")
    }

    /// Changing the type renames a title still at its default and leaves a typed one.
    @Test func bannerDraftRetitlesOnTypeChangeOnlyWhileDefault() {
        var draft = BannerDraft()
        draft.setType(.mealBreak)
        #expect(draft.title == "Meal Break")

        draft.title = "Lunch at the pier"
        draft.setType(.companyMove)
        #expect(draft.title == "Lunch at the pier")

        draft.title = ""
        draft.setType(.custom)
        #expect(draft.title == "Custom Banner")
    }

    @Test func bannerDraftMakesTheBannerTheOldSheetMade() {
        var draft = BannerDraft()
        draft.setType(.companyMove)
        draft.title         = "  Move to the pier  "
        draft.startTime     = " 1:30 PM "
        draft.note          = "Trucks leave at 1"
        draft.estimatedTime = "1:15"
        draft.colorHex      = "EF4444"
        let banner = draft.makeBanner()
        #expect(banner.isBanner)
        #expect(!banner.isCalendarEvent)
        #expect(banner.bannerType      == .companyMove)
        #expect(banner.title           == "Move to the pier")
        #expect(banner.bannerTitle     == "Move to the pier")
        #expect(banner.estimatedTime   == 75)
        #expect(banner.dayNightType    == .custom)
        #expect(banner.bannerColorHex  == "EF4444")
        // The old sheet's quirk, kept: the start time rides in `bannerNote` and, when
        // present, in `summary`, which is what the strip shows.
        #expect(banner.bannerNote      == "1:30 PM")
        #expect(banner.summary         == "1:30 PM")
    }

    @Test func bannerDraftFallsBackToTheDefaultTitleAndTheNote() {
        var draft = BannerDraft()
        draft.title     = "   "
        draft.startTime = ""
        draft.note      = "Generator swap"
        #expect(!draft.canSave)
        let banner = draft.makeBanner()
        #expect(banner.title      == "Notice")
        #expect(banner.summary    == "Generator swap")
        #expect(banner.bannerNote == "")
    }

    // MARK: - Calendar event draft

    @Test func calendarEventDraftStartsBlankForANewEvent() {
        let draft = CalendarEventDraft(event: nil)
        #expect(draft.title    == "")
        #expect(draft.time     == "10:00 AM")
        #expect(draft.colorHex == "6366F1")
        #expect(!draft.isEditing)
        #expect(!draft.canSave)
        #expect(draft.makeEvent() == nil)
    }

    @Test func calendarEventDraftReadsAnExistingEvent() {
        var event = Scene.createCalendarEvent(title: "Table read", time: "2:00 PM", colorHex: "F43F5E")
        event.bannerTitle = ""
        let draft = CalendarEventDraft(event: event)
        #expect(draft.title    == "Table read", "falls back to the title when the banner title is blank")
        #expect(draft.time     == "2:00 PM")
        #expect(draft.colorHex == "F43F5E")
        #expect(draft.isEditing)
    }

    @Test func calendarEventDraftReadsABlankColorAsIndigo() {
        var event = Scene.createCalendarEvent(title: "Fitting", time: "", colorHex: "")
        event.bannerColorHex = ""
        #expect(CalendarEventDraft(event: event).colorHex == "6366F1")
    }

    @Test func calendarEventDraftKeepsTheIdOnEdit() {
        let event = Scene.createCalendarEvent(title: "Scout", time: "9:00 AM")
        var draft = CalendarEventDraft(event: event)
        draft.title    = " Location scout "
        draft.time     = " 9:30 AM "
        draft.colorHex = "10B981"
        let saved = draft.makeEvent()
        #expect(saved?.id              == event.id)
        #expect(saved?.isCalendarEvent == true)
        #expect(saved?.title           == "Location scout")
        #expect(saved?.customStartTime == "9:30 AM")
        #expect(saved?.summary         == "9:30 AM")
        #expect(saved?.bannerColorHex  == "10B981")
    }

    @Test func calendarEventDraftMakesANewIdForANewEvent() {
        var draft = CalendarEventDraft(event: nil)
        draft.title = "Wrap party"
        let a = draft.makeEvent()
        let b = draft.makeEvent()
        #expect(a != nil)
        #expect(a?.id != b?.id)
    }
}

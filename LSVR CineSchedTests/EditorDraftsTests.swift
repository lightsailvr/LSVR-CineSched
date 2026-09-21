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

    /// A whole number of pages shows as "1" or "2", which the parser reads as eighths
    /// (the New Scene rule: a bare integer is eighths); an untouched pages field must
    /// still write the stored length back, not one eighth (found by the M4 fix-up probe).
    @Test func sceneDraftRoundTripsWholePagesUntouched() {
        var original = Self.scene()
        original.duration = 16
        let draft = SceneDraft(scene: original)
        #expect(draft.duration == "2")
        #expect(draft.applied(to: original).duration == 16)
        // Typed over, the field means what it says: "2" is two eighths.
        var typed = draft
        typed.duration = "2 "
        #expect(typed.applied(to: original).duration == 2)
        var retyped = draft
        retyped.duration = "3 4/8"
        #expect(retyped.applied(to: original).duration == 28)
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

    // MARK: - Banner draft: editing (#26)

    @Test func bannerDraftReadsAnExistingBannersFields() {
        var draft = BannerDraft()
        draft.setType(.companyMove)
        draft.title         = "Move to the pier"
        draft.startTime     = "1:30 PM"
        draft.estimatedTime = "1:15"
        draft.colorHex      = "EF4444"
        let banner = draft.makeBanner()

        let reread = BannerDraft(banner: banner)
        #expect(reread.isEditing)
        #expect(reread.type          == .companyMove)
        #expect(reread.title         == "Move to the pier")
        #expect(reread.startTime     == "1:30 PM")
        #expect(reread.note          == "", "with a start time the old sheet kept no note")
        #expect(reread.estimatedTime == "1:15")
        #expect(reread.colorHex      == "EF4444")
        #expect(!BannerDraft().isEditing)
    }

    @Test func bannerDraftReadsTheNoteOfABannerWithoutAStartTime() {
        var draft = BannerDraft()
        draft.startTime     = ""
        draft.note          = "Generator swap"
        draft.estimatedTime = "0:45"
        let banner = draft.makeBanner()

        let reread = BannerDraft(banner: banner)
        #expect(reread.startTime     == "")
        #expect(reread.note          == "Generator swap")
        #expect(reread.estimatedTime == "0:45")
    }

    @Test func bannerDraftReadsABlankColorAsViolet() {
        var banner = Scene.createBanner(type: .notice, title: "Notice", colorHex: "")
        banner.bannerColorHex = ""
        #expect(BannerDraft(banner: banner).colorHex == "8B5CF6")
    }

    @Test func bannerDraftAppliedKeepsTheIdAndTheFixedTime() {
        var banner = Scene.createBanner(type: .notice, title: "Notice")
        banner.customStartTime = "02:00 PM"
        var draft = BannerDraft(banner: banner)
        draft.setType(.mealBreak)
        draft.title     = "Second meal"
        draft.startTime = "6:00 PM"
        draft.colorHex  = "D97706"
        let saved = draft.applied(to: banner)
        #expect(saved.id              == banner.id)
        #expect(saved.customStartTime == "02:00 PM", "Set Time's fixed start survives an edit of the other fields")
        #expect(saved.bannerType      == .mealBreak)
        #expect(saved.title           == "Second meal")
        #expect(saved.bannerTitle     == "Second meal")
        #expect(saved.bannerNote      == "6:00 PM")
        #expect(saved.bannerColorHex  == "D97706")
        #expect(saved.isBanner && !saved.isCalendarEvent && !saved.isAutoMeal)
    }

    @Test func bannerDraftMakeBannerMintsANewIdForANewBanner() {
        var draft = BannerDraft()
        draft.title = "Notice"
        #expect(draft.makeBanner().id != draft.makeBanner().id)
    }

    // MARK: - Quick time draft (#26)

    @Test func quickTimeDraftSeedsFromASceneWithNoFixedTime() {
        let scene = Scene(title: "INT. KITCHEN - DAY", estimatedTime: 0)
        let draft = QuickTimeDraft(scene: scene)
        #expect(!draft.isCustomTime)
        #expect(draft.customTimeText == "08:00 AM", "the old sheet's example start")
        #expect(draft.hours == 0 && draft.minutes == 15, "a script scene with no estimate is the cascade's 15 minutes")
        #expect(draft.isValid)
    }

    @Test func quickTimeDraftSeedsABannerWithThirtyMinutes() {
        var banner = Scene.createBanner(type: .notice, title: "Notice")
        banner.estimatedTime = 0
        let draft = QuickTimeDraft(scene: banner)
        #expect(draft.hours == 0 && draft.minutes == 30)
    }

    @Test func quickTimeDraftSeedsFromASceneWithAFixedTimeAndEstimate() {
        var scene = Scene(title: "INT. KITCHEN - DAY", estimatedTime: 135)
        scene.customStartTime = " 11:00 AM "
        let draft = QuickTimeDraft(scene: scene)
        #expect(draft.isCustomTime)
        #expect(draft.customTimeText == "11:00 AM")
        #expect(draft.hours == 2 && draft.minutes == 15)
    }

    @Test func quickTimeDraftValidatesOnlyAFixedTimeThatParses() {
        var draft = QuickTimeDraft(scene: Scene(title: "X"))
        draft.isCustomTime   = true
        draft.customTimeText = "eleven"
        #expect(!draft.isValid)
        draft.customTimeText = "11:00 AM"
        #expect(draft.isValid)
        draft.isCustomTime = false
        draft.customTimeText = "eleven"
        #expect(draft.isValid, "the cascade ignores the text when the time is automatic")
    }

    @Test func quickTimeDraftPreviewsTheRangeOrTheDuration() {
        var draft = QuickTimeDraft(scene: Scene(title: "X"))
        draft.hours   = 1
        draft.minutes = 30
        #expect(draft.previewText == "Duration: 1:30 (cascades by day order)")
        draft.isCustomTime   = true
        draft.customTimeText = "11:00 AM"
        #expect(draft.previewText == "11:00 AM ➔ 12:30 PM (1:30)")
    }

    @Test func quickTimeDraftAppliedWritesTheFixedTimeAndTheEstimate() {
        var scene = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "7", estimatedTime: 15, cast: ["Alex"])
        scene.isCompleted = true
        var draft = QuickTimeDraft(scene: scene)
        draft.isCustomTime   = true
        draft.customTimeText = " 11:00 AM "
        draft.hours          = 1
        draft.minutes        = 5
        let saved = draft.applied(to: scene)
        #expect(saved.id              == scene.id)
        #expect(saved.customStartTime == "11:00 AM")
        #expect(saved.estimatedTime   == 65)
        #expect(saved.sceneNumber == "7" && saved.cast == ["Alex"] && saved.isCompleted, "everything else is carried")
    }

    @Test func quickTimeDraftAppliedClearsTheFixedTimeWhenAutomatic() {
        var scene = Scene(title: "INT. KITCHEN - DAY", estimatedTime: 15)
        scene.customStartTime = "11:00 AM"
        var draft = QuickTimeDraft(scene: scene)
        draft.isCustomTime = false
        draft.minutes      = 45
        let saved = draft.applied(to: scene)
        #expect(saved.customStartTime.isEmpty)
        #expect(saved.estimatedTime == 45)
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

    // MARK: - New scene draft (#27)

    @Test func newSceneDraftStartsBlankWithTheTypeFromTheSlugline() {
        let draft = NewSceneDraft()
        #expect(draft.sceneNumber   == "")
        #expect(draft.title         == "")
        #expect(draft.realLocation  == "")
        #expect(draft.duration      == "")
        #expect(draft.estimatedTime == "")
        #expect(draft.dayNightType  == nil, "nil is the picker's default: the type read from the slugline")
        #expect(!draft.isValid, "a blank title cannot be added")
    }

    /// The Mac's form needs a title and well-formed lengths; the number may be blank
    /// (the Mac allows it) and a blank length is fine.
    @Test func newSceneDraftValidatesLikeTheMacsForm() {
        var draft = NewSceneDraft()
        draft.title = "INT. KITCHEN - NIGHT"
        #expect(draft.isValid, "a title alone is enough; number and lengths may be blank")

        draft.duration = "one page"
        #expect(!draft.durationIsValid)
        #expect(!draft.isValid)
        draft.duration = "1 7/8"
        #expect(draft.durationIsValid)
        #expect(draft.parsedEighths == 15)

        draft.estimatedTime = "2:75"
        #expect(!draft.estimatedTimeIsValid)
        #expect(!draft.isValid)
        draft.estimatedTime = "2:30"
        #expect(draft.estimatedTimeIsValid)
        #expect(draft.parsedMinutes == 150)
        #expect(draft.isValid)

        draft.title = "   "
        #expect(!draft.isValid)
    }

    @Test func newSceneDraftMakesTheSceneTheMacsFormMakes() {
        var draft = NewSceneDraft()
        draft.sceneNumber   = " 12A "
        draft.title         = "EXT. YARD - DAY"
        draft.realLocation  = " Back lot "
        draft.duration      = "2 1/8"
        draft.estimatedTime = "45"
        draft.dayNightType  = .night
        let scene = draft.makeScene()
        #expect(scene.sceneNumber   == "12A")
        #expect(scene.title         == "EXT. YARD - DAY")
        #expect(scene.realLocation  == "Back lot")
        #expect(scene.duration      == 17)
        #expect(scene.estimatedTime == 45)
        #expect(scene.dayNightType  == .night, "the picker's explicit choice wins over the slugline")
        #expect(scene.cast.isEmpty)
        #expect(!scene.isBanner)
        #expect(!scene.isCalendarEvent)
        #expect(draft.makeScene().id != scene.id, "every make is a new scene")
    }

    /// With no estimate typed, the Mac's form estimates from the page count (fifteen
    /// minutes an eighth; a bare number is eighths, so "8" is one page); with no pages
    /// either, the scene has no estimate.
    @Test func newSceneDraftEstimatesFromThePagesWhenNoTimeIsTyped() {
        var draft = NewSceneDraft()
        draft.title    = "INT. BAR - NIGHT"
        draft.duration = "8"
        #expect(draft.makeScene().estimatedTime == TimeParser.estimatedMinutes(forEighths: 8))
        #expect(draft.makeScene().estimatedTime == 120)
        #expect(draft.makeScene().duration      == 8)

        draft.duration = ""
        #expect(draft.makeScene().estimatedTime == 0)
        #expect(draft.makeScene().duration      == 0)

        draft.duration      = "8"
        draft.estimatedTime = "20"
        #expect(draft.makeScene().estimatedTime == 20, "a typed estimate is taken as typed")
    }

    /// The picker at its default reads the time of day off the slugline the way the
    /// script importers do; a slugline that names none reads as day.
    @Test func newSceneDraftReadsTheTimeOfDayOffTheSlugline() {
        var draft = NewSceneDraft()
        draft.title = "INT. KITCHEN - NIGHT"
        #expect(draft.resolvedDayNightType == .night)
        #expect(draft.makeScene().dayNightType == .night)
        draft.title = "EXT. BEACH - DAWN"
        #expect(draft.resolvedDayNightType == .dawn)
        draft.title = "EXT. PIER - DUSK"
        #expect(draft.resolvedDayNightType == .dusk)
        draft.title = "INT. OFFICE - AFTERNOON"
        #expect(draft.resolvedDayNightType == .afternoon)
        draft.title = "INT. OFFICE - DAY"
        #expect(draft.resolvedDayNightType == .day)
        draft.title = "INT. OFFICE - CONTINUOUS"
        #expect(draft.resolvedDayNightType == .day, "unknown reads as day, the importers' rule")
        draft.title = "ext. street - night"
        #expect(draft.resolvedDayNightType == .night, "case does not matter")

        // The picker's choice, once made, is what the scene gets.
        draft.dayNightType = .custom
        #expect(draft.resolvedDayNightType == .custom)
        #expect(draft.makeScene().dayNightType == .custom)
    }
}

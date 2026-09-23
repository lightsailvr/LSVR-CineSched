//
//  SceneSearchTests.swift
//  LSVR CineSchedTests
//
//  The iPhone's Boneyard filter and Search tab (#27), the pure part: which scenes a query
//  matches (number, slugline, cast, summary, real location; never a banner, an auto-meal
//  or a calendar event), how the query is read (trimmed, case-insensitive, every word
//  somewhere), what the search returns for a whole project (each hit with where it is,
//  scheduled first in schedule order, then the Boneyard in script order), and the display
//  order the Boneyard tab hands a multi-selection to Send to Day in.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct SceneSearchTests {

    // MARK: - Fixture

    private let kitchen = Scene(title: "INT. KITCHEN - NIGHT", sceneNumber: "12",  cast: ["Alex Morgan", " Sam Rivera "], summary: "Alex finds the letter.", realLocation: "Stage 4")
    private let yard    = Scene(title: "EXT. YARD - DAY",      sceneNumber: "12A", cast: ["Sam Rivera"],                   summary: "The dog digs.")
    private let garage  = Scene(title: "INT. GARAGE - NIGHT",  sceneNumber: "120", cast: [],                               summary: "")
    private let street  = Scene(title: "EXT. STREET - DUSK",   sceneNumber: "3",   cast: ["Casey Kim"],                    summary: "A chase through the market.")
    private let bar     = Scene(title: "INT. BAR - NIGHT",     sceneNumber: "1",   cast: ["ALEX MORGAN"],                  summary: "Last call.")
    private let banner  = Scene.createBanner(type: .notice, title: "Company move to the KITCHEN set", note: "", estimatedTime: "0:30", colorHex: "")
    private let meal    = Scene.createAutoMeal(kind: .lunch, timeString: "1:00 PM")
    private let event   = Scene.createCalendarEvent(title: "Tech scout, Alex", time: "9:00 AM")

    /// Day 1 holds the kitchen, the banner, the meal, the event and the garage; day 2 the
    /// street; the Boneyard holds the yard and the bar (the bar's number sorts it first).
    private func project() -> ProjectData {
        var day1 = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day1.scenes = [kitchen, banner, meal, event, garage]
        var day2 = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400))
        day2.scenes = [street]
        return ProjectData(allScenes: [yard, bar], shootDays: [day1, day2], projectTitle: "Fixture")
    }

    private var scenes: [Scene] { [kitchen, yard, garage, street, bar] }

    // MARK: - The query

    @Test func aBlankQueryMatchesEveryScriptSceneAndFiltersNothing() {
        #expect(SceneSearch.matches(kitchen, query: ""))
        #expect(SceneSearch.matches(kitchen, query: "   "))
        #expect(SceneSearch.filter(scenes, query: "").map(\.id) == scenes.map(\.id))
        #expect(SceneSearch.filter(scenes, query: "\n").map(\.id) == scenes.map(\.id))
    }

    @Test func aBlankQuerySearchesNothing() {
        #expect(SceneSearch.results(for: "", in: project()).isEmpty)
        #expect(SceneSearch.results(for: "  ", in: project()).isEmpty)
    }

    @Test func theQueryIsTrimmedAndCaseInsensitive() {
        #expect(SceneSearch.matches(kitchen, query: "  kitchen "))
        #expect(SceneSearch.matches(kitchen, query: "KITCHEN"))
        #expect(SceneSearch.matches(kitchen, query: "Kitchen"))
    }

    @Test func everyWordOfTheQueryMustMatchSomewhere() {
        // "alex" is in the cast and "letter" in the summary: two fields, one scene.
        #expect(SceneSearch.matches(kitchen, query: "alex letter"))
        // "alex" matches, "dog" does not.
        #expect(!SceneSearch.matches(kitchen, query: "alex dog"))
        // Any amount of whitespace between the words.
        #expect(SceneSearch.matches(kitchen, query: "alex \t  letter"))
    }

    // MARK: - The fields

    @Test func matchesTheSluglineByContainment() {
        #expect(SceneSearch.matches(yard, query: "yard"))
        #expect(SceneSearch.matches(yard, query: "ext. yard"))
        #expect(SceneSearch.matches(yard, query: "ard - d"))
        #expect(!SceneSearch.matches(yard, query: "garage"))
    }

    /// A number matches exactly or as a prefix ("12" finds 12, 12A and 120; "2" finds
    /// neither 12 nor 120), so typing a number narrows the way a scene list reads.
    @Test func matchesTheSceneNumberExactlyOrAsAPrefix() {
        #expect(SceneSearch.matches(kitchen, query: "12"))
        #expect(SceneSearch.matches(yard,    query: "12"))
        #expect(SceneSearch.matches(garage,  query: "12"))
        #expect(SceneSearch.matches(yard,    query: "12a"), "case-insensitive on the letter")
        #expect(SceneSearch.matches(yard,    query: "12A"))
        #expect(!SceneSearch.matches(kitchen, query: "2"))
        #expect(!SceneSearch.matches(garage,  query: "2"))
        #expect(!SceneSearch.matches(kitchen, query: "12A"))
    }

    /// Cast matches on the character name join's terms: case-insensitive and trimmed,
    /// so " Sam Rivera " and "ALEX MORGAN" are found by "sam rivera" and "alex".
    @Test func matchesTheCastCaseInsensitivelyAndTrimmed() {
        #expect(SceneSearch.matches(kitchen, query: "sam rivera"))
        #expect(SceneSearch.matches(kitchen, query: "Sam Rivera"))
        #expect(SceneSearch.matches(bar,     query: "alex"))
        #expect(SceneSearch.matches(bar,     query: "Alex Morgan"))
        #expect(SceneSearch.matches(kitchen, query: "rivera"))
        #expect(!SceneSearch.matches(street, query: "alex"))
    }

    @Test func matchesTheSummaryAndTheRealLocation() {
        #expect(SceneSearch.matches(street,  query: "market"))
        #expect(SceneSearch.matches(kitchen, query: "letter"))
        #expect(SceneSearch.matches(kitchen, query: "stage 4"))
        #expect(!SceneSearch.matches(garage, query: "letter"))
    }

    /// A shot's description, equipment, props and SFX are searched like the scene's own
    /// fields (#37); a result names the shot that found it (below).
    @Test func matchesAShotsDescriptionEquipmentPropsAndSFX() {
        var scene = garage
        scene.shots = [
            Shot(details: "Dolly in towards Astrid", equipment: ["Technocrane"]),
            Shot(details: "Insert", props: ["Truck keys"], sfx: ["Sparks"]),
        ]
        for query in ["dolly", "ASTRID", "technocrane", "truck keys", "sparks", "dolly sparks"] {
            #expect(SceneSearch.matches(scene, query: query), "\(query)")
        }
        #expect(!SceneSearch.matches(scene, query: "steadicam"))
        #expect(!SceneSearch.matches(garage, query: "dolly"))
    }

    /// A result names the shot that found it (#43): the first shot, in shot order, holding
    /// a word of the query the scene's own fields do not; nil when the scene's own fields
    /// hold every word, so a shot is named only when the match came from one.
    @Test func aResultNamesTheShotThatMatchedWhenOneDid() {
        var withShots = garage                       // scene 120, no cast, no summary
        withShots.shots = [
            Shot(details: "Wide on the workbench"),
            Shot(details: "Dolly in towards Astrid", equipment: ["Dolly"]),
            Shot(details: "Insert", sfx: ["Sparks"]),
        ]
        var day = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day.scenes = [withShots]
        let data = ProjectData(allScenes: [kitchen], shootDays: [day], projectTitle: "Shots")

        let dolly = SceneSearch.results(for: "dolly", in: data)
        #expect(dolly.map(\.scene.id) == [withShots.id])
        #expect(dolly.first?.matchedShotID     == withShots.shots[1].id)
        #expect(dolly.first?.matchedShotNumber == "120B")

        // The first shot holding any of the shot-only words: "sparks" is shot C's, but
        // "dolly" comes first in shot order.
        let both = SceneSearch.results(for: "sparks dolly", in: data)
        #expect(both.first?.matchedShotNumber == "120B")

        // A word the slugline holds and one only a shot holds: the shot is named.
        #expect(SceneSearch.results(for: "garage sparks", in: data).first?.matchedShotNumber == "120C")

        // Found by its own fields, the scene names no shot, even when a shot also says it.
        let byNumber = SceneSearch.results(for: "120", in: data)
        #expect(byNumber.first?.matchedShotID == nil)
        #expect(byNumber.first?.matchedShotNumber == nil)
        #expect(SceneSearch.results(for: "workbench garage", in: data).first?.matchedShotNumber == "120A")
        #expect(SceneSearch.results(for: "night", in: data).allSatisfy { $0.matchedShotNumber == nil })

        // A shotless scene in the Boneyard: no shot, whatever matched.
        #expect(SceneSearch.results(for: "kitchen", in: data).first?.matchedShotNumber == nil)
    }

    @Test func bannersAutoMealsAndEventsNeverMatch() {
        // Each carries a word the query names; none is a scene.
        #expect(!SceneSearch.matches(banner, query: "kitchen"))
        #expect(!SceneSearch.matches(banner, query: "company"))
        #expect(!SceneSearch.matches(meal,   query: "lunch"))
        #expect(!SceneSearch.matches(event,  query: "alex"))
        #expect(!SceneSearch.matches(event,  query: "scout"))
        // And a blank query, which matches every script scene, still passes them over.
        #expect(!SceneSearch.matches(banner, query: ""))
        #expect(SceneSearch.filter([kitchen, banner, meal, event], query: "").map(\.id) == [kitchen.id])
    }

    // MARK: - The filter

    @Test func theFilterKeepsTheOrderItWasGiven() {
        let filtered = SceneSearch.filter([street, kitchen, yard, garage], query: "12")
        #expect(filtered.map(\.id) == [kitchen.id, yard.id, garage.id])
    }

    // MARK: - The search

    @Test func resultsSayWhereEachSceneIsScheduledFirstThenTheBoneyard() {
        let results = SceneSearch.results(for: "night", in: project())
        // Day 1's kitchen and garage in day order, then the Boneyard's bar.
        #expect(results.map(\.scene.id) == [kitchen.id, garage.id, bar.id])
        #expect(results[0].location == .scheduled(dayIndex: 0, sceneIndex: 0))
        #expect(results[1].location == .scheduled(dayIndex: 0, sceneIndex: 4))
        #expect(results[2].location == .boneyard(index: 1))
        #expect(results[0].dayIndex == 0)
        #expect(results[2].dayIndex == nil)
        #expect(!results[0].isInBoneyard)
        #expect(results[2].isInBoneyard)
    }

    @Test func resultsAcrossDaysFollowTheScheduleOrder() {
        let results = SceneSearch.results(for: "ext", in: project())
        // Day 2's street before the Boneyard's yard.
        #expect(results.map(\.scene.id) == [street.id, yard.id])
        #expect(results[0].location == .scheduled(dayIndex: 1, sceneIndex: 0))
        #expect(results[1].location == .boneyard(index: 0))
    }

    @Test func boneyardResultsComeInScriptOrder() {
        // The Boneyard holds [yard (12A), bar (1)]; both are found by "-" (every slugline
        // has one) and the bar's lower number puts it first.
        let results = SceneSearch.results(for: "-", in: project()).filter(\.isInBoneyard)
        #expect(results.map(\.scene.id) == [bar.id, yard.id])
    }

    @Test func resultsFindByCastAcrossTheWholeProject() {
        let results = SceneSearch.results(for: "alex", in: project())
        #expect(results.map(\.scene.id) == [kitchen.id, bar.id])
        // The event named Alex is not a result.
        #expect(!results.contains { $0.scene.id == event.id })
    }

    @Test func noResultsForAQueryNothingMatches() {
        #expect(SceneSearch.results(for: "zeppelin", in: project()).isEmpty)
    }

    @Test func aResultIsIdentifiedByItsScene() {
        let results = SceneSearch.results(for: "kitchen", in: project())
        #expect(results.count == 1)
        #expect(results[0].id == kitchen.id)
    }

    // MARK: - The Boneyard selection's display order

    @Test func aSelectionIsHandedOverInDisplayOrderWithoutStrays() {
        let displayed = [bar.id, yard.id, kitchen.id]
        let stray     = UUID()
        #expect(BoneyardSelection.ordered([kitchen.id, bar.id, stray], inDisplayOrder: displayed) == [bar.id, kitchen.id])
        #expect(BoneyardSelection.ordered([], inDisplayOrder: displayed).isEmpty)
        #expect(BoneyardSelection.ordered([stray], inDisplayOrder: displayed).isEmpty)
    }

    // MARK: - The Mac toolbar's search (#36 review)

    /// The Mac's phrase rule as it always was (title, summary, cast; any strip; the query
    /// as one phrase), plus a shot's description, equipment, props and SFX.
    @Test func theToolbarSearchMatchesThePhraseInTheSceneAndItsShots() {
        var scene = garage
        scene.shots = [
            Shot(details: "Dolly in towards Astrid", equipment: ["Technocrane"]),
            Shot(details: "Insert", props: ["Truck keys"], sfx: ["Sparks"]),
        ]
        for query in ["dolly in", "  TECHNOCRANE ", "truck keys", "sparks"] {
            #expect(SceneSearch.toolbarMatches(scene, query: query), "\(query)")
        }
        #expect(!SceneSearch.toolbarMatches(garage, query: "dolly"))
        // One phrase, not words: "dolly sparks" is in no single field.
        #expect(!SceneSearch.toolbarMatches(scene, query: "dolly sparks"))
        #expect(!SceneSearch.toolbarMatches(scene, query: "   "))
        // What it found before is found as before: the title, the summary, a cast name, and
        // a banner by its title.
        #expect(SceneSearch.toolbarMatches(street, query: street.title.lowercased()))
        #expect(SceneSearch.toolbarMatches(kitchen, query: "letter"))
        #expect(SceneSearch.toolbarMatches(banner, query: "company move"))
    }
}

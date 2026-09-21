//
//  CallSheetDraftsTests.swift
//  LSVR CineSchedTests
//
//  The call sheet editor and the production setup (#20) edit plain drafts: what each
//  reads from the day or the project (with the old sheets' pre-fills), the list
//  mutations the rows and detail pages make, and the one value written back. These pin
//  every rule without a view; the forms, the pushed detail pages and the one-assignment
//  write-back are checked by running the app.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct CallSheetDraftsTests {

    // MARK: - Fixtures

    private static func productionInfo() -> ProductionInfo {
        ProductionInfo(
            companyName:      "Tempel Films",
            directorName:     "Dana Reyes",
            directorPhone:    "555-0100",
            producerName:     "Lee Park",
            producerPhone:    "555-0101",
            adName:           "Sam Ortiz",
            adPhone:          "555-0102",
            contactNumber:    "555-0199",
            defaultLunchTime: "01:00 PM",
            crew: [
                CrewMember(name: "Ana Cruz",   role: "DP",     phone: "555-0201", isDailyDefault: true),
                CrewMember(name: "Ben Silva",  role: "Gaffer", phone: "555-0202")
            ],
            castList: [
                CastMember(actorName: "Jordan Lee", characterName: "ALEX"),
                CastMember(actorName: "Casey Kim",  characterName: "SAM")
            ],
            locationRoster: [
                Location(name: "Stage 4",   address: "100 Studio Way"),
                Location(name: "Harbor",    address: "1 Pier Rd")
            ],
            scheduleLock: nil
        )
    }

    private static func day() -> ShootDay {
        let one = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "1", cast: ["ALEX", "SAM"], realLocation: "Stage 4")
        var four = Scene(title: "EXT. HARBOR - NIGHT", sceneNumber: "4", cast: ["ALEX", "RILEY"], realLocation: "Harbor")
        four.locationAddress = "Scene's own address"
        var field = Scene(title: "EXT. FIELD - DAY", sceneNumber: "7", cast: ["RILEY"], realLocation: "Field")
        field.locationAddress = "Route 9"
        return ShootDay(date: Date(timeIntervalSince1970: 1_700_000_000), scenes: [one, four, field])
    }

    private static func filledSheet() -> CallSheetData {
        var sheet = CallSheetData()
        sheet.generalCallTime   = "07:00 AM"
        sheet.workDaySchedule   = "07:00 AM to 07:00 PM"
        sheet.quoteOfTheDay     = "Onward."
        sheet.readyToShootTime  = "08:00 AM"
        sheet.lunchTime         = "12:30 PM"
        sheet.snackTime         = "04:00 PM"
        sheet.dinnerTime        = "07:00 PM"
        sheet.wrapTime          = "08:00 PM"
        sheet.nearestHospital   = "St. Mary's, 555-0911"
        sheet.weatherTemp       = "68°F"
        sheet.weatherCondition  = "Clear"
        sheet.weatherPrecipWind = "Rain 0%, Wind 5 km/h"
        sheet.sunTimes          = "06:45 AM / 07:30 PM"
        sheet.basecampLocation  = "Lot B"
        sheet.locations         = [Location(name: "Stage 4", address: "100 Studio Way")]
        sheet.castCallEntries   = [CastCallEntry(characterName: "ALEX", actorName: "Jordan Lee", sceneNumbers: "1, 4", ecdt: "W", pickupTime: "06:30 AM", hmuWardrobeTime: "07:00 AM", onSetTime: "08:00 AM", wrapTime: "07:00 PM", locationIndex: "2")]
        sheet.crewCallEntries   = [CrewCallEntry(role: "DP", name: "Ana Cruz", callTime: "06:30 AM", phone: "555-0201")]
        sheet.notes             = "Quiet on set.\nNo drones."
        sheet.productionNotes   = ["stale"]
        sheet.castOverride      = ["ALEX"]
        sheet.crewIDOverride    = [UUID()]
        return sheet
    }

    // MARK: - Call sheet: reading

    @Test func callSheetDraftReadsEveryField() {
        var day = Self.day()
        day.callSheet = Self.filledSheet()
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.generalCallTime   == "07:00 AM")
        #expect(draft.workDaySchedule   == "07:00 AM to 07:00 PM")
        #expect(draft.quoteOfTheDay     == "Onward.")
        #expect(draft.readyToShootTime  == "08:00 AM")
        #expect(draft.lunchTime         == "12:30 PM")
        #expect(draft.snackTime         == "04:00 PM")
        #expect(draft.dinnerTime        == "07:00 PM")
        #expect(draft.wrapTime          == "08:00 PM")
        #expect(draft.nearestHospital   == "St. Mary's, 555-0911")
        #expect(draft.weatherTemp       == "68°F")
        #expect(draft.weatherCondition  == "Clear")
        #expect(draft.weatherPrecipWind == "Rain 0%, Wind 5 km/h")
        #expect(draft.sunTimes          == "06:45 AM / 07:30 PM")
        #expect(draft.basecampLocation  == "Lot B")
        #expect(draft.notes             == "Quiet on set.\nNo drones.")
        #expect(draft.castCalls.map(\.characterName) == ["ALEX"])
        #expect(draft.crewCalls.map(\.role)          == ["DP"])
    }

    @Test func callSheetDraftDefaultsLunchFromProductionInfo() {
        let draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        #expect(draft.lunchTime == "01:00 PM")
    }

    @Test func callSheetDraftAddsTheDaysSceneLocationsOnce() {
        var day = Self.day()
        day.callSheet.locations = [Location(name: "stage 4", address: "kept")]
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.locations.map(\.name) == ["stage 4", "Harbor", "Field"], "the sheet's own first, then the scenes' once each, matched by name ignoring case")
        #expect(draft.locations[0].address == "kept")
        #expect(draft.locations[1].address == "1 Pier Rd", "a roster location lends its address")
        #expect(draft.locations[2].address == "Route 9",   "a location off the roster keeps the scene's")
    }

    @Test func callSheetDraftFallsBackToTheRostersFirstLocation() {
        var day = Self.day()
        day.scenes = []
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.locations.map(\.name) == ["Stage 4"])

        let noRoster = CallSheetDraft(day: day, productionInfo: ProductionInfo())
        #expect(noRoster.locations.isEmpty)
    }

    @Test func callSheetDraftPopulatesCastFromScenesWhenEmpty() {
        let draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        #expect(draft.castCalls.map(\.characterName) == ["ALEX", "RILEY", "SAM"], "the day's cast, sorted")
        let alex = draft.castCalls[0]
        #expect(alex.actorName    == "Jordan Lee")
        #expect(alex.sceneNumbers == "1, 4")
        #expect(alex.ecdt         == "E")
        #expect(alex.onSetTime    == "", "no ready-to-shoot and no general call yet")
        #expect(alex.wrapTime     == "")
        #expect(alex.locationIndex == "1")
        #expect(draft.castCalls[1].actorName == "", "RILEY is not on the roster")
    }

    @Test func callSheetDraftFillsBlankSceneNumbersOfExistingCastCalls() {
        var day = Self.day()
        day.callSheet.castCallEntries = [
            CastCallEntry(characterName: "riley", sceneNumbers: ""),
            CastCallEntry(characterName: "ALEX",  sceneNumbers: "99")
        ]
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.castCalls.map(\.sceneNumbers) == ["4, 7", "99"])
        #expect(draft.castCalls.count == 2, "existing entries are not auto-populated with the rest of the cast")
    }

    @Test func callSheetDraftLoadsCrewFromSetupWhenEmpty() {
        var day = Self.day()
        day.callSheet.generalCallTime = "06:00 AM"
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.crewCalls.map(\.name)     == ["Ana Cruz", "Ben Silva"])
        #expect(draft.crewCalls.map(\.callTime) == ["06:00 AM", "06:00 AM"])
        #expect(draft.crewCalls[0].phone        == "555-0201")

        let noCall = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        #expect(noCall.crewCalls[0].callTime == "07:30 AM", "the placeholder call when the day has none")
    }

    @Test func callSheetDraftFillsExistingCrewCallsByRole() {
        var day = Self.day()
        day.callSheet.crewCallEntries = [CrewCallEntry(role: "dp", name: " ", callTime: "05:00 AM", phone: "")]
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.crewCalls.count == 1)
        #expect(draft.crewCalls[0].name  == "Ana Cruz")
        #expect(draft.crewCalls[0].phone == "555-0201")
        #expect(draft.crewCalls[0].callTime == "05:00 AM", "the day's own time stays")
    }

    @Test func callSheetDraftReadsLegacyProductionNotes() {
        var day = Self.day()
        day.callSheet.productionNotes = ["One", "Two"]
        let draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        #expect(draft.notes == "One\nTwo")
    }

    // MARK: - Call sheet: editing

    @Test func callSheetDraftListsRosterLocationsNotYetOnTheDay() {
        let info = Self.productionInfo()
        var draft = CallSheetDraft(day: Self.day(), productionInfo: info)
        #expect(draft.availableRosterLocations(in: info).isEmpty, "both roster locations are already on the day")
        draft.removeLocation(id: draft.locations[1].id)
        #expect(draft.availableRosterLocations(in: info).map(\.name) == ["Harbor"])
        draft.addRosterLocation(info.locationRoster[1])
        #expect(draft.availableRosterLocations(in: info).isEmpty)
    }

    @Test func callSheetDraftAddsAndRemovesLocations() {
        var draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        let before = draft.locations.count
        draft.addLocation(name: "  ", address: "nowhere")
        #expect(draft.locations.count == before, "a blank name adds nothing")
        draft.addLocation(name: " Hangar ", address: " 1 Runway ")
        #expect(draft.locations.last?.name    == "Hangar")
        #expect(draft.locations.last?.address == "1 Runway")
        draft.removeLocation(id: draft.locations.last!.id)
        #expect(draft.locations.count == before)
    }

    @Test func callSheetDraftAddsACastCallWithTheDaysDefaults() {
        var draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        draft.generalCallTime  = "07:00 AM"
        draft.readyToShootTime = "08:00 AM"
        draft.dinnerTime       = "07:00 PM"
        let id = draft.addCastCall(character: " riley ", actor: "Drew Fox", day: Self.day())
        let entry = draft.castCalls.first { $0.id == id }
        #expect(entry?.characterName == "riley")
        #expect(entry?.actorName     == "Drew Fox")
        #expect(entry?.sceneNumbers  == "4, 7", "matched to the day's scenes ignoring case")
        #expect(entry?.onSetTime     == "08:00 AM")
        #expect(entry?.wrapTime      == "07:00 PM")
        #expect(entry?.locationIndex == "1")

        draft.readyToShootTime = ""
        let blank = draft.addCastCall(day: Self.day())
        let blankEntry = draft.castCalls.first { $0.id == blank }
        #expect(blankEntry?.characterName == "")
        #expect(blankEntry?.sceneNumbers  == "")
        #expect(blankEntry?.onSetTime     == "07:00 AM", "the general call when there is no ready-to-shoot")

        draft.removeCastCall(id: id)
        #expect(!draft.castCalls.contains { $0.id == id })
    }

    @Test func callSheetDraftRefreshesSceneNumbersWhileBlank() {
        var draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        let id = draft.addCastCall(day: Self.day())
        let i  = draft.castCalls.firstIndex { $0.id == id }!
        draft.castCalls[i].characterName = "SAM"
        draft.refreshSceneNumbers(ofCastCall: id, in: Self.day())
        #expect(draft.castCalls[i].sceneNumbers == "1")
        draft.castCalls[i].characterName = "ALEX"
        draft.refreshSceneNumbers(ofCastCall: id, in: Self.day())
        #expect(draft.castCalls[i].sceneNumbers == "1", "a filled value is never replaced")
    }

    @Test func callSheetDraftAutoPopulateFillsBlanksAndAddsTheRest() {
        var day = Self.day()
        day.callSheet.castCallEntries = [CastCallEntry(characterName: "alex", actorName: "", sceneNumbers: "kept")]
        var draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        draft.populateCast(from: day, productionInfo: Self.productionInfo())
        #expect(draft.castCalls.map(\.characterName) == ["alex", "RILEY", "SAM"])
        #expect(draft.castCalls[0].actorName    == "Jordan Lee", "the blank actor is filled from the roster")
        #expect(draft.castCalls[0].sceneNumbers == "kept")
    }

    @Test func callSheetDraftLoadsCrewWithoutDuplicates() {
        var draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        #expect(draft.crewCalls.count == 2)
        draft.loadCrew(from: Self.productionInfo())
        #expect(draft.crewCalls.count == 2, "already listed by name and role")
        draft.generalCallTime = "06:15 AM"
        let id = draft.addCrewCall(role: " Grip ", name: "Max")
        let entry = draft.crewCalls.first { $0.id == id }
        #expect(entry?.role     == "Grip")
        #expect(entry?.callTime == "06:15 AM", "a new crew call takes the general call")
        draft.removeCrewCall(id: id)
        #expect(draft.crewCalls.count == 2)
    }

    // MARK: - Call sheet: writing back

    @Test func callSheetDraftWritesEveryFieldAndCarriesTheRest() {
        var day = Self.day()
        day.callSheet = Self.filledSheet()
        let original = day.callSheet
        var draft = CallSheetDraft(day: day, productionInfo: Self.productionInfo())
        draft.generalCallTime   = "06:00 AM"
        draft.workDaySchedule   = "06:00 AM to 06:00 PM"
        draft.quoteOfTheDay     = "Again."
        draft.readyToShootTime  = "07:00 AM"
        draft.lunchTime         = "11:30 AM"
        draft.snackTime         = "03:00 PM"
        draft.dinnerTime        = "06:00 PM"
        draft.wrapTime          = "07:00 PM"
        draft.nearestHospital   = "General"
        draft.weatherTemp       = "50°F"
        draft.weatherCondition  = "Fog"
        draft.weatherPrecipWind = "Rain 80%"
        draft.sunTimes          = "07:00 AM / 06:00 PM"
        draft.basecampLocation  = "Lot C"
        draft.notes             = "Line one\n\n  \nLine two"

        let saved = draft.applied(to: original)
        #expect(saved.generalCallTime   == "06:00 AM")
        #expect(saved.workDaySchedule   == "06:00 AM to 06:00 PM")
        #expect(saved.quoteOfTheDay     == "Again.")
        #expect(saved.readyToShootTime  == "07:00 AM")
        #expect(saved.lunchTime         == "11:30 AM")
        #expect(saved.snackTime         == "03:00 PM")
        #expect(saved.dinnerTime        == "06:00 PM")
        #expect(saved.wrapTime          == "07:00 PM")
        #expect(saved.nearestHospital   == "General")
        #expect(saved.weatherTemp       == "50°F")
        #expect(saved.weatherCondition  == "Fog")
        #expect(saved.weatherPrecipWind == "Rain 80%")
        #expect(saved.sunTimes          == "07:00 AM / 06:00 PM")
        #expect(saved.basecampLocation  == "Lot C")
        #expect(saved.notes             == "Line one\n\n  \nLine two")
        #expect(saved.productionNotes   == ["Line one", "Line two"], "the notes' non-blank lines")
        #expect(saved.locations.map(\.name) == ["Stage 4", "Harbor", "Field"], "the pre-filled day locations are written")
        #expect(saved.castCallEntries   == draft.castCalls)
        #expect(saved.crewCallEntries   == draft.crewCalls)
        #expect(saved.castOverride      == original.castOverride,   "not shown, carried through")
        #expect(saved.crewIDOverride    == original.crewIDOverride, "not shown, carried through")
        #expect(saved.prodManagerContact == original.prodManagerContact)
    }

    @Test func callSheetDraftUnchangedRoundTripsAnEmptySheetExceptForThePrefills() {
        var day = Self.day()
        day.scenes = []
        let draft = CallSheetDraft(day: day, productionInfo: ProductionInfo(defaultLunchTime: ""))
        let saved = draft.applied(to: CallSheetData())
        #expect(saved == CallSheetData(), "an untouched draft of an empty day writes an equal value, so Save registers nothing")
    }

    @Test func callSheetDraftDropsRowsLeftBlank() {
        var draft = CallSheetDraft(day: Self.day(), productionInfo: Self.productionInfo())
        draft.addCastCall(day: Self.day())
        draft.addCrewCall()
        draft.locations.append(Location(name: "  ", address: "somewhere"))
        let saved = draft.applied(to: CallSheetData())
        #expect(saved.castCallEntries.count == 3, "the three from the scenes; the blank one is dropped")
        #expect(saved.crewCallEntries.count == 2)
        #expect(saved.locations.count       == 3)

        var kept = draft
        kept.castCalls[3].actorName = "Only an actor"
        kept.crewCalls[2].role      = "Only a role"
        #expect(kept.applied(to: CallSheetData()).castCallEntries.count == 4, "either name keeps a cast row")
        #expect(kept.applied(to: CallSheetData()).crewCallEntries.count == 3, "a role alone keeps a crew row")
    }

    @Test func callSheetDraftKeepsBlankRowsTheSheetAlreadyHad() {
        // A blank row from an older file (the old editor wrote rows back unchanged) is not
        // the editor's to delete on an unrelated Save; only a row added here and left blank is.
        var sheet = CallSheetData()
        sheet.castCallEntries = [CastCallEntry(characterName: "", actorName: "")]
        sheet.crewCallEntries = [CrewCallEntry(role: "", name: "")]
        sheet.locations       = [Location(name: "", address: "kept")]
        var day = Self.day()
        day.callSheet = sheet
        var draft = CallSheetDraft(day: day, productionInfo: ProductionInfo())
        draft.addCastCall(day: day)
        draft.addCrewCall()
        let saved = draft.applied(to: sheet)
        #expect(saved.castCallEntries.map(\.id).contains(sheet.castCallEntries[0].id))
        #expect(saved.crewCallEntries.map(\.id).contains(sheet.crewCallEntries[0].id))
        #expect(saved.locations.map(\.id).contains(sheet.locations[0].id), "kept beside the day's pre-filled scene locations")
        #expect(saved.castCallEntries.count == draft.castCalls.count - 1, "only the row added here is dropped")
        #expect(saved.crewCallEntries.count == draft.crewCalls.count - 1)
    }

    // MARK: - Production setup: reading

    @Test func productionSetupDraftReadsEveryField() {
        let info  = Self.productionInfo()
        let draft = ProductionSetupDraft(info: info, scenes: [])
        #expect(draft.companyName      == "Tempel Films")
        #expect(draft.directorName     == "Dana Reyes")
        #expect(draft.directorPhone    == "555-0100")
        #expect(draft.producerName     == "Lee Park")
        #expect(draft.producerPhone    == "555-0101")
        #expect(draft.adName           == "Sam Ortiz")
        #expect(draft.adPhone          == "555-0102")
        #expect(draft.defaultLunchTime == "01:00 PM")
        #expect(draft.castList         == info.castList)
        #expect(draft.crew             == info.crew)
        #expect(draft.locationRoster   == info.locationRoster, "a filled roster is not touched by the breakdown")
    }

    @Test func productionSetupDraftPullsLocationsWhenTheRosterIsEmpty() {
        var info = Self.productionInfo()
        info.locationRoster = []
        var set = Scene(title: "INT. OFFICE - DAY", sceneNumber: "2")
        set.realLocation = ""
        let banner = Scene.createBanner(type: .notice, title: "Lunch", note: "", estimatedTime: "0:30", colorHex: "000000")
        let draft = ProductionSetupDraft(info: info, scenes: Self.day().scenes + [set, banner])
        #expect(draft.locationRoster.map(\.name)    == ["Stage 4", "Harbor", "Field", "OFFICE"], "real locations, then the set when there is none; banners skipped")
        #expect(draft.locationRoster.map(\.address) == ["", "Scene's own address", "Route 9", ""])
    }

    @Test func productionSetupDraftPullFromBreakdownAddsOnlyNewNames() {
        var draft = ProductionSetupDraft(info: Self.productionInfo(), scenes: [])
        draft.pullLocationsFromBreakdown(scenes: Self.day().scenes)
        #expect(draft.locationRoster.map(\.name) == ["Stage 4", "Harbor", "Field"])
        draft.pullLocationsFromBreakdown(scenes: Self.day().scenes)
        #expect(draft.locationRoster.count == 3, "a second pull adds nothing")
    }

    // MARK: - Production setup: editing

    @Test func productionSetupDraftAddsAndRemovesRosterRows() {
        var draft = ProductionSetupDraft(info: ProductionInfo(), scenes: [])
        let cast = draft.addCastMember(actor: " Drew Fox ", character: " RILEY ")
        let crew = draft.addCrewMember(name: " Max ", role: " Grip ", phone: " 555 ", isDailyDefault: true)
        let loc  = draft.addLocation(name: " Hangar ", address: " 1 Runway ")
        #expect(draft.castList.first { $0.id == cast }?.actorName == "Drew Fox")
        #expect(draft.castList.first { $0.id == cast }?.characterName == "RILEY")
        #expect(draft.crew.first { $0.id == crew }?.name == "Max")
        #expect(draft.crew.first { $0.id == crew }?.role == "Grip")
        #expect(draft.crew.first { $0.id == crew }?.phone == "555")
        #expect(draft.crew.first { $0.id == crew }?.isDailyDefault == true)
        #expect(draft.locationRoster.first { $0.id == loc }?.name == "Hangar")
        #expect(draft.locationRoster.first { $0.id == loc }?.address == "1 Runway")
        draft.removeCastMember(id: cast)
        draft.removeCrewMember(id: crew)
        draft.removeLocation(id: loc)
        #expect(draft.castList.isEmpty && draft.crew.isEmpty && draft.locationRoster.isEmpty)
    }

    @Test func productionSetupDraftEditsUnavailabilityPerCastMember() {
        var draft = ProductionSetupDraft(info: Self.productionInfo(), scenes: [])
        let alex  = draft.castList[0].id
        let later = Date(timeIntervalSince1970: 1_700_000_000)
        let early = Date(timeIntervalSince1970: 1_600_000_000)
        draft.addUnavailableRange(start: later, end: early, toCastMember: alex)
        #expect(draft.castList[0].unavailableRanges.count == 1)
        #expect(draft.castList[0].unavailableRanges[0].start == later, "the range keeps its start")
        #expect(draft.castList[0].unavailableRanges[0].end   == later, "and the end is never before it")
        #expect(draft.castList[1].unavailableRanges.isEmpty, "only that member")
        draft.addUnavailableRange(start: early, end: later, toCastMember: UUID())
        #expect(draft.castList.allSatisfy { $0.unavailableRanges.count <= 1 }, "an unknown member is ignored")
        let range = draft.castList[0].unavailableRanges[0].id
        draft.removeUnavailableRange(id: range, fromCastMember: alex)
        #expect(draft.castList[0].unavailableRanges.isEmpty)
    }

    @Test func productionSetupDraftReportsCharacterRenames() {
        let info  = Self.productionInfo()
        var draft = ProductionSetupDraft(info: info, scenes: [])
        draft.castList[0].characterName = " ALEXANDRA "
        draft.castList[1].characterName = ""
        draft.addCastMember(actor: "New", character: "NEW")
        let renames = draft.renamedCharacters(against: info)
        #expect(renames.count == 1)
        #expect(renames.first?.old == "ALEX")
        #expect(renames.first?.new == "ALEXANDRA", "trimmed; a blanked name and a new member are not renames")
        #expect(ProductionSetupDraft(info: info, scenes: []).renamedCharacters(against: info).isEmpty)
    }

    // MARK: - Production setup: writing back

    @Test func productionSetupDraftWritesEveryFieldAndCarriesTheRest() {
        var info = Self.productionInfo()
        info.scheduleLock = ScheduleLock(lockedAt: Date(timeIntervalSince1970: 1_700_000_000), workingDays: [:])
        var draft = ProductionSetupDraft(info: info, scenes: [])
        draft.companyName      = "Other Films"
        draft.directorName     = "D"
        draft.directorPhone    = "1"
        draft.producerName     = "P"
        draft.producerPhone    = "2"
        draft.adName           = "A"
        draft.adPhone          = "3"
        draft.defaultLunchTime = "12:00 PM"
        draft.castList[0].actorName = "Recast"
        draft.crew[1].isDailyDefault = true
        draft.locationRoster.removeLast()

        let saved = draft.applied(to: info)
        #expect(saved.companyName      == "Other Films")
        #expect(saved.directorName     == "D")
        #expect(saved.directorPhone    == "1")
        #expect(saved.producerName     == "P")
        #expect(saved.producerPhone    == "2")
        #expect(saved.adName           == "A")
        #expect(saved.adPhone          == "3")
        #expect(saved.defaultLunchTime == "12:00 PM")
        #expect(saved.castList[0].actorName == "Recast")
        #expect(saved.crew[1].isDailyDefault)
        #expect(saved.locationRoster.map(\.name) == ["Stage 4"])
        #expect(saved.contactNumber    == "555-0199", "not shown, carried through")
        #expect(saved.scheduleLock     == info.scheduleLock, "not shown, carried through")
    }

    @Test func productionSetupDraftUnchangedWritesAnEqualValue() {
        let info = Self.productionInfo()
        #expect(ProductionSetupDraft(info: info, scenes: Self.day().scenes).applied(to: info) == info, "so Save registers nothing")
    }

    @Test func productionSetupDraftDropsRowsLeftBlank() {
        var draft = ProductionSetupDraft(info: ProductionInfo(), scenes: [])
        draft.addCastMember()
        draft.addCastMember(character: "SOLO")
        draft.addCrewMember(role: "Role without a name")
        draft.addCrewMember(name: "Named")
        draft.addLocation(address: "Address without a name")
        draft.addLocation(name: "Named")
        let saved = draft.applied(to: ProductionInfo())
        #expect(saved.castList.map(\.characterName) == ["SOLO"], "either name keeps a cast member")
        #expect(saved.crew.map(\.name)              == ["Named"], "a crew member needs a name")
        #expect(saved.locationRoster.map(\.name)    == ["Named"], "a location needs a name")
    }

    @Test func productionSetupDraftKeepsBlankRowsTheSetupAlreadyHad() {
        var info = ProductionInfo()
        info.castList       = [CastMember(actorName: "", characterName: "")]
        info.crew           = [CrewMember(name: "", role: "Grip")]
        info.locationRoster = [Location(name: "", address: "kept")]
        var draft = ProductionSetupDraft(info: info, scenes: [])
        draft.addCastMember()
        draft.addCrewMember()
        draft.addLocation()
        let saved = draft.applied(to: info)
        #expect(saved.castList.map(\.id)       == [info.castList[0].id])
        #expect(saved.crew.map(\.id)           == [info.crew[0].id])
        #expect(saved.locationRoster.map(\.id) == [info.locationRoster[0].id])
    }
}

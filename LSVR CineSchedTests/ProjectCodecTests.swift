//
//  ProjectCodecTests.swift
//  LSVR CineSchedTests
//
//  ProjectCodec is the one place a project becomes bytes and back (#7). These tests pin
//  the file format the codec inherited from ProjectStore: pretty-printed JSON with ISO
//  dates, plus the two older shapes it must still read (dates as timestamps, and the
//  pre-title file that had only scenes and days).
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ProjectCodecTests {

    // MARK: - Fixture

    /// A project with every part of the snapshot filled in: Boneyard scenes, days with
    /// a full call sheet, a title, production info, shift mode and a created date.
    /// The date is on a whole second because the file format carries no fractions.
    static var project: ProjectData {
        var days = PDFFixture.days
        days[3] = PDFFixture.callSheetDay
        return ProjectData(
            allScenes:          [PDFFixture.makeScene(90), PDFFixture.makeScene(91, dayNight: .night)],
            shootDays:          days,
            projectTitle:       PDFFixture.title,
            isShiftModeEnabled: true,
            createdDate:        Date(timeIntervalSince1970: 1_700_000_000),
            productionInfo:     PDFFixture.productionInfo
        )
    }

    /// The oldest lineage's file: only `allScenes` and `shootDays`, a comma-joined cast
    /// string, timestamp dates and the `isBlackout` flag. Shared with the document tests.
    static let legacyJSON = """
    {
      "allScenes" : [
        { "id" : "5D9F6C88-0F84-4B7A-9A6C-4C2E0F1D2A11", "title" : "2. EXT. PLAYA. DIA",
          "duration" : 8, "estimatedTime" : 30, "dayNightType" : "DAY", "cast" : "ANA, LUIS" }
      ],
      "shootDays" : [
        { "id" : "2A2B6F4E-9E5B-4C1F-A3E4-1B2C3D4E5F60", "date" : 700000000,
          "scenes" : [], "callSheet" : {}, "isBlackout" : true }
      ]
    }
    """

    // MARK: - Current shape

    @Test func encodeThenDecodeIsIdentity() throws {
        let original = Self.project
        let data     = try ProjectCodec.encode(original)
        let decoded  = try ProjectCodec.decode(data)
        #expect(decoded == original)
    }

    @Test func encodesPrettyPrintedJSONWithISODates() throws {
        let data = try ProjectCodec.encode(Self.project)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.hasPrefix("{\n"))
        // The formatter writes the machine's zone offset, so only the shape is pinned here;
        // the round trip above proves the instant survives.
        #expect(text.range(of: #""createdDate" : "\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4}""#, options: .regularExpression) != nil)
        #expect(text.contains("\"projectTitle\" : \"The Long Way Home\""))
    }

    @Test func currentShapeFixtureDecodes() throws {
        let json = """
        {
          "projectTitle" : "Fixture",
          "createdDate" : "2026-09-16T10:00:00+0000",
          "isShiftModeEnabled" : false,
          "allScenes" : [
            { "id" : "5D9F6C88-0F84-4B7A-9A6C-4C2E0F1D2A11", "title" : "INT. KITCHEN - DAY",
              "sceneNumber" : "1", "duration" : 12, "estimatedTime" : 45,
              "dayNightType" : "DAY", "cast" : ["ALEX"] }
          ],
          "shootDays" : [
            { "id" : "2A2B6F4E-9E5B-4C1F-A3E4-1B2C3D4E5F60", "date" : "2026-11-02T12:00:00+0000",
              "scenes" : [], "callSheet" : { "generalCallTime" : "7:00 AM" },
              "dayType" : "travel", "dayNote" : "Fly LAX → ABQ", "isBlackout" : false }
          ],
          "productionInfo" : { "companyName" : "Lightsail", "directorName" : "Morgan", "crew" : [], "castList" : [] }
        }
        """
        let decoded = try ProjectCodec.decode(Data(json.utf8))
        #expect(decoded.projectTitle == "Fixture")
        #expect(decoded.allScenes.map(\.title) == ["INT. KITCHEN - DAY"])
        #expect(decoded.allScenes.first?.duration == 12)
        #expect(decoded.shootDays.count == 1)
        #expect(decoded.shootDays.first?.dayType == .travel)
        #expect(decoded.shootDays.first?.callSheet.generalCallTime == "7:00 AM")
        #expect(decoded.productionInfo?.companyName == "Lightsail")
        #expect(decoded.createdDate == Date(timeIntervalSince1970: 1_789_552_800))
    }

    /// Files from before the ISO formatter carry dates as Foundation's reference-date
    /// timestamps; the codec still reads them.
    @Test func timestampDatesDecode() throws {
        let json = """
        { "projectTitle" : "Old Dates", "createdDate" : 700000000, "allScenes" : [],
          "shootDays" : [ { "id" : "2A2B6F4E-9E5B-4C1F-A3E4-1B2C3D4E5F60", "date" : 700000000,
                            "scenes" : [], "callSheet" : {} } ] }
        """
        let decoded = try ProjectCodec.decode(Data(json.utf8))
        #expect(decoded.projectTitle == "Old Dates")
        #expect(decoded.createdDate == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(decoded.shootDays.first?.date == Date(timeIntervalSinceReferenceDate: 700_000_000))
    }

    // MARK: - Legacy shape

    /// The oldest lineage wrote only `allScenes` and `shootDays`: no title, no created
    /// date, no production info. It still opens, with the title ProjectStore always gave it.
    @Test func legacyShapeFixtureDecodes() throws {
        let decoded = try ProjectCodec.decode(Data(Self.legacyJSON.utf8))
        #expect(decoded.projectTitle == "Loaded Project")
        #expect(decoded.isShiftModeEnabled == false)
        #expect(decoded.productionInfo == nil)
        #expect(decoded.allScenes.first?.cast == ["ANA", "LUIS"])
        #expect(decoded.shootDays.first?.dayType == .unavailable)
    }

    // MARK: - Palette (#11)

    /// Every file written before #11 has no `palette` key: it decodes with none, and the
    /// strip colors resolve to the standard code until the project adopts or edits one.
    @Test func aFileWithoutAPaletteDecodesWithNone() throws {
        let decoded = try ProjectCodec.decode(Data(Self.legacyJSON.utf8))
        #expect(decoded.palette == nil)
        #expect(decoded.resolvedPalette == .standard)

        var current = Self.project
        current.palette = nil
        let data = try ProjectCodec.encode(current)
        #expect(try #require(String(data: data, encoding: .utf8)).contains("\"palette\"") == false)
        #expect(try ProjectCodec.decode(data).palette == nil)
    }

    /// The palette is a flat object of slot name to hex, so a file with one round-trips
    /// unchanged and reads the same on every device.
    @Test func aPaletteRoundTripsUnchanged() throws {
        var original = Self.project
        var palette  = ScenePalette.standard
        palette.setHex("FF00AA", for: .extNight)
        palette.setHex("123456", for: .custom)
        original.palette = palette

        let data    = try ProjectCodec.encode(original)
        let decoded = try ProjectCodec.decode(data)
        #expect(decoded == original)
        #expect(decoded.palette?.hex(for: .extNight) == "FF00AA")
        #expect(decoded.palette?.hex(for: .custom)   == "123456")
        #expect(decoded.palette?.hex(for: .intDay)   == SceneColorSlot.intDay.defaultHex)

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"palette\" : {"))
        #expect(text.contains("\"extNight\" : \"FF00AA\""))
        #expect(text.contains("\"intDay\" : \"F3F4F6\""))
    }

    /// A palette hand-edited (or written by a later build) with only some slots keeps
    /// exactly those slots: the missing ones fall back to the standard code and are not
    /// written on the next save.
    @Test func aPartialPaletteKeepsOnlyItsSlots() throws {
        let json = """
        { "projectTitle" : "Partial", "createdDate" : "2026-09-16T10:00:00+0000", "allScenes" : [],
          "shootDays" : [], "palette" : { "intNight" : "00FF00" } }
        """
        let decoded = try ProjectCodec.decode(Data(json.utf8))
        let palette = try #require(decoded.palette)
        #expect(palette.hex(for: .intNight) == "00FF00")
        #expect(palette.hex(for: .extNight) == SceneColorSlot.extNight.defaultHex)
        #expect(palette != .standard)

        let text = try #require(String(data: try ProjectCodec.encode(decoded), encoding: .utf8))
        #expect(text.contains("\"palette\" : {\n    \"intNight\" : \"00FF00\"\n  }"))
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) {
            try ProjectCodec.decode(Data("not a project".utf8))
        }
        #expect(throws: (any Error).self) {
            try ProjectCodec.decode(Data("{ \"title\" : \"no scenes\" }".utf8))
        }
    }
}

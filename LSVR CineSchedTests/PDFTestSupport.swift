//
//  PDFTestSupport.swift
//  LSVR CineSchedTests
//
//  One fixture project and a few helpers shared by every exporter test, so the strip
//  schedule, shooting schedule, month calendar, call sheet, breakdown sheets and DOOD are
//  all rendered from the same days and can be compared side by side.
//
//  Set CINESCHED_PDF_DUMP_DIR to a directory and every fixture export is also written
//  there, for the visual comparison that guards any change to the drawing code. Through
//  xcodebuild that is the *environment* variable TEST_RUNNER_CINESCHED_PDF_DUMP_DIR (not a
//  build setting), and on the Mac the test host is the sandboxed app, so add
//  ENABLE_APP_SANDBOX=NO to the build settings or nothing gets written.
//

import CoreText
import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

enum PDFFixture {

    static let title = "The Long Way Home"

    /// Whether the platform has the Mac's SF face (18pt ascent 17.40234375). iOS and
    /// visionOS ship a differently-hinted, slightly narrower SF, so any expectation about
    /// a measured line height or about where a line wraps holds only when this is true.
    nonisolated static var hasMacSystemFace: Bool {
        CTFontCreateUIFontForLanguage(.system, 18, nil).map { CTFontGetAscent($0) == 17.40234375 } ?? false
    }

    static var productionInfo: ProductionInfo {
        var info = ProductionInfo()
        info.companyName   = "Lightsail Pictures"
        info.directorName  = "Morgan Vale"
        info.directorPhone = "555-0100"
        info.producerName  = "Dana Whitfield"
        info.producerPhone = "555-0101"
        info.adName        = "Chris Okafor"
        info.adPhone       = "555-0102"
        info.crew = [
            CrewMember(name: "Priya Nair",    role: "DP",           phone: "555-0110"),
            CrewMember(name: "Luis Ortega",   role: "Gaffer",       phone: "555-0111"),
            CrewMember(name: "Mei Tanaka",    role: "Sound Mixer",  phone: "555-0112"),
            CrewMember(name: "Ben Kowalski",  role: "Key Grip",     phone: "555-0113"),
            CrewMember(name: "Aisha Bello",   role: "Script Sup.",  phone: "555-0114"),
        ]
        return info
    }

    /// A date inside November 2026, at noon so the weekday never slips across a zone.
    static func novemberDate(day: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = day; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    static func makeScene(_ n: Int, dayNight: DayNightType = .day) -> Scene {
        var scene = Scene(
            title: "\(n % 2 == 0 ? "INT" : "EXT"). UNIVERSAL STUDIOS HOLLYWOOD - BACKLOT SET \(n) - \(dayNight.rawValue)",
            sceneNumber: "\(n)",
            duration: 1 + n % 7,
            estimatedTime: 30 + (n % 4) * 15,
            dayNightType: dayNight,
            cast: ["Alex Morgan", "Sam Rivera", "Jordan Lee", "Casey Kim", "Riley Chen"],
            realLocation: "HOLLYWOOD"
        )
        scene.summary = "Scene \(n): the crew regroups on the backlot before the light goes."
        return scene
    }

    /// Five shoot days of six scenes each with a lunch banner and a calendar event,
    /// plus a travel day in front: enough rows that the schedules spill onto a second
    /// page and every row style (numbered day, typed day, event line, strip, completed
    /// strip, notice strip, banner, end-of-day bar) gets drawn.
    static var days: [ShootDay] {
        var days: [ShootDay] = [
            ShootDay(date: novemberDate(day: 1), dayType: .travel, dayNote: "Fly LAX → ABQ")
        ]
        for d in 1...5 {
            var sheet = CallSheetData()
            sheet.generalCallTime  = "6:30 AM"
            sheet.readyToShootTime = "7:30 AM"
            sheet.lunchTime        = "1:00 PM"
            var scenes: [Scene] = (1...6).map { makeScene(d * 100 + $0, dayNight: $0 % 3 == 0 ? .night : .day) }
            scenes[1].isCompleted = true
            scenes[2].customStartTime = "10:15 AM"
            scenes.insert(Scene.createBanner(type: .mealBreak, title: "Lunch", estimatedTime: "0:30"), at: 3)
            scenes.append(Scene.createCalendarEvent(title: "Producer visit", time: "3:00 PM"))
            scenes.append(Scene(title: "Company move to the ranch after wrap; vans leave from basecamp at the top of the hour", dayNightType: .custom))
            days.append(ShootDay(date: novemberDate(day: 1 + d), scenes: scenes, callSheet: sheet))
        }
        return days
    }

    /// One fully filled-in call sheet: cast calls, crew calls, a quote, weather,
    /// locations, basecamp, hospital and notes, on the fixture's third shoot day.
    static var callSheetDay: ShootDay {
        var day = days[3]
        var sheet = day.callSheet
        sheet.workDaySchedule  = "Schedule: 07:30 AM to 07:30 PM"
        sheet.snackTime        = "4:30 PM"
        sheet.dinnerTime       = "7:30 PM"
        sheet.quoteOfTheDay    = "The best way out is always through."
        sheet.weatherTemp      = "72°F / 22°C"
        sheet.weatherCondition = "Partly cloudy"
        sheet.weatherPrecipWind = "10% precip · wind 8 mph"
        sheet.sunTimes         = "Sunrise 6:24 AM · Sunset 4:51 PM"
        sheet.basecampLocation = "Lot 4, 100 Universal City Plaza"
        sheet.nearestHospital  = "Providence St. Joseph, 501 S Buena Vista St"
        sheet.locations = [
            Location(name: "HOLLYWOOD", address: "100 Universal City Plaza, Universal City, CA 91608"),
            Location(name: "RANCH",     address: "2200 Ranch Rd, Agua Dulce, CA 91390"),
        ]
        sheet.castCallEntries = [
            CastCallEntry(characterName: "Alex Morgan",  actorName: "Taylor Brooks", pickupTime: "6:00 AM", hmuWardrobeTime: "6:30 AM", onSetTime: "7:30 AM", wrapTime: "7:00 PM"),
            CastCallEntry(characterName: "Sam Rivera",   actorName: "Jamie Ellis",   pickupTime: "6:00 AM", hmuWardrobeTime: "6:30 AM", onSetTime: "7:30 AM", wrapTime: "7:00 PM"),
            CastCallEntry(characterName: "Jordan Lee",   actorName: "Robin Castillo", sceneNumbers: "301, 305", ecdt: "W", onSetTime: "9:00 AM", wrapTime: "5:00 PM", locationIndex: "2"),
        ]
        sheet.crewCallEntries = [
            CrewCallEntry(role: "DP",          name: "Priya Nair",  callTime: "6:00 AM"),
            CrewCallEntry(role: "Gaffer",      name: "",            callTime: "6:00 AM"),   // name comes from the roster
            CrewCallEntry(role: "Sound Mixer", name: "Mei Tanaka",  callTime: "6:30 AM"),
            CrewCallEntry(role: "Key Grip",    name: "Ben Kowalski", callTime: "6:00 AM"),
        ]
        sheet.notes = "Wear layers; the backlot gets cold after sunset.\nNo personal vehicles on the lot — shuttle from basecamp every 15 minutes."
        day.callSheet = sheet
        return day
    }
}

// MARK: - Helpers

/// Parses `data` through PDFKit (and, given a `name`, dumps it under CINESCHED_PDF_DUMP_DIR
/// when that is set). Fails the test, and returns an empty document, if `data` is nil
/// or not a PDF.
@MainActor
func pdfDocument(from data: Data?, dumpAs name: String? = nil) -> PDFDocument {
    #expect(data != nil)
    let data = data ?? Data()
    if let name, let dir = ProcessInfo.processInfo.environment["CINESCHED_PDF_DUMP_DIR"], !dir.isEmpty {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }
    let doc = PDFDocument(data: data)
    #expect(doc != nil)
    return doc ?? PDFDocument()
}

/// Every page's text, in order.
func pdfFullText(_ doc: PDFDocument) -> String {
    (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
}

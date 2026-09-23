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

// MARK: - The fixture with shots (#40)

extension PDFFixture {

    /// Real stored frame bytes: a `width` × `height` image of one sRGB color (the tests
    /// look for it in the rendered page) with a dark band across its top, through
    /// `StoryboardFrame.encode`, the rule every frame source uses.
    static func frameJPEG(red: CGFloat, green: CGFloat, blue: CGFloat, width: Int = 320, height: Int = 180) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: height - height / 6, width: width, height: height / 6))
        return StoryboardFrame.encode(context.makeImage()!)!
    }

    /// `days` with shot lists on the first shoot day: scene 101 has four shots, each with a
    /// frame (two pages' worth at three a page with the scene's other entries), scene 102
    /// two shots without frames; every other scene is shotless and frameless.
    static var daysWithShots: [ShootDay] {
        var days = days
        var scenes = days[1].scenes
        let red = frameJPEG(red: 0.85, green: 0.1, blue: 0.1)
        scenes[0].shots = [
            Shot(details: "Wide on the backlot as the crew regroups", durationMinutes: 20, equipment: ["Technocrane"], props: ["Clipboard"], sfx: ["Wind"], frame: red),
            Shot(details: "Push in on Alex", durationMinutes: 15, equipment: ["Dolly"], frame: red),
            Shot(details: "Sam's reaction, handheld", durationMinutes: 10, frame: frameJPEG(red: 0.1, green: 0.2, blue: 0.85, width: 180, height: 320)),
            Shot(details: "Insert: the map", durationMinutes: 5, props: ["Map"], frame: red),
        ]
        scenes[0].applyShotEstimate()
        scenes[1].shots = [
            Shot(details: "Two-shot, locked off", durationMinutes: 25, equipment: ["Sticks"]),
            Shot(details: "Overs", durationMinutes: 30, sfx: ["Rain"]),
        ]
        scenes[1].applyShotEstimate()
        days[1].scenes = scenes
        return days
    }

    /// A Boneyard scene with no shots and a frame of its own (a green one), and one with
    /// neither, out of script order so the Boneyard's sort shows.
    static var boneyardWithFrame: [Scene] {
        var framed = makeScene(900)
        framed.frame = frameJPEG(red: 0.1, green: 0.7, blue: 0.2)
        framed.props = ["Lantern"]
        return [makeScene(901, dayNight: .night), framed]
    }

    static var projectWithShots: ProjectData {
        ProjectData(
            allScenes:      boneyardWithFrame,
            shootDays:      daysWithShots,
            projectTitle:   title,
            productionInfo: productionInfo
        )
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

/// Whether any pixel of page `index` is exactly the sRGB color `hex` (a strip's fill,
/// which the exporters draw as a flat rectangle, so its interior pixels are exact). The
/// page is rasterized at 1 pt per pixel through CoreGraphics alone, so it works on every
/// platform the exporters build for. False for a page that does not exist.
func pdfPage(_ doc: PDFDocument, _ index: Int, containsColorHex hex: String) -> Bool {
    guard let page = doc.page(at: index)?.pageRef else { return false }
    let box    = page.getBoxRect(.mediaBox)
    let width  = Int(box.width.rounded()), height = Int(box.height.rounded())
    guard width > 0, height > 0,
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    else { return false }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setShouldAntialias(false)
    context.drawPDFPage(page)
    guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }

    let value = UInt32(hex, radix: 16) ?? 0
    let (r, g, b) = (UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF))
    for i in stride(from: 0, to: width * height * 4, by: 4)
    where pixels[i] == r && pixels[i + 1] == g && pixels[i + 2] == b {
        return true
    }
    return false
}

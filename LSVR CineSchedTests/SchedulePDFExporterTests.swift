//
//  SchedulePDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders the strip schedule and the shooting schedule from one fixture project and
//  inspects the PDFs through PDFKit. These two exporters draw on the shared PDFCanvas
//  (CoreGraphics + CoreText, no AppKit), so this suite runs on the Mac and on the iOS
//  and visionOS simulators alike (#4).
//
//  Set CINESCHED_PDF_DUMP_DIR to a directory and the fixture exports are also written
//  there, for the side-by-side visual comparison that guards any change to the drawing
//  code. Through xcodebuild that is the *environment* variable
//  TEST_RUNNER_CINESCHED_PDF_DUMP_DIR (not a build setting), and on the Mac the test host
//  is the sandboxed app, so add ENABLE_APP_SANDBOX=NO to the build settings or nothing
//  gets written.
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct SchedulePDFExporterTests {

    // MARK: - Fixture

    /// A date inside November 2026, at noon so the weekday never slips across a zone.
    private func novemberDate(day: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = day; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    private func makeScene(_ n: Int, dayNight: DayNightType = .day) -> Scene {
        Scene(
            title: "\(n % 2 == 0 ? "INT" : "EXT"). UNIVERSAL STUDIOS HOLLYWOOD - BACKLOT SET \(n) - \(dayNight.rawValue)",
            sceneNumber: "\(n)",
            duration: 1 + n % 7,
            estimatedTime: 30 + (n % 4) * 15,
            dayNightType: dayNight,
            cast: ["Alex Morgan", "Sam Rivera", "Jordan Lee", "Casey Kim", "Riley Chen"],
            realLocation: "HOLLYWOOD"
        )
    }

    /// Five shoot days of six scenes each with a lunch banner and a calendar event,
    /// plus a travel day in front: enough rows that both exporters spill onto a
    /// second page and every row style (numbered day, typed day, event line, strip,
    /// completed strip, notice strip, banner, end-of-day bar) gets drawn.
    private var fixtureDays: [ShootDay] {
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

    private let fixtureTitle = "The Long Way Home"

    private var fixtureProductionInfo: ProductionInfo {
        var info = ProductionInfo()
        info.companyName = "Lightsail Pictures"
        return info
    }

    // MARK: - Helpers

    private func document(from data: Data?, dumpAs name: String) -> PDFDocument {
        #expect(data != nil)
        let data = data ?? Data()
        if let dir = ProcessInfo.processInfo.environment["CINESCHED_PDF_DUMP_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        let doc = PDFDocument(data: data)
        #expect(doc != nil)
        return doc ?? PDFDocument()
    }

    private func fullText(_ doc: PDFDocument) -> String {
        (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }

    // MARK: - Strip schedule

    @Test func stripScheduleRendersFixtureProject() {
        let doc = document(
            from: StripboardPDFExporter.generatePDF(
                shootDays: fixtureDays,
                projectTitle: fixtureTitle,
                productionInfo: fixtureProductionInfo
            ),
            dumpAs: "StripSchedule.pdf"
        )
        #expect(doc.pageCount == 2)

        let firstPage = doc.page(at: 0)?.string ?? ""
        #expect(firstPage.contains(fixtureTitle))
        #expect(firstPage.contains("Strip Schedule"))
        #expect(firstPage.contains("Lightsail Pictures"))

        let text = fullText(doc)
        #expect(text.contains("Day 1"))
        #expect(text.contains("END OF DAY #5"))
        #expect(text.contains("Producer visit"))
        #expect(text.contains("Alex Morgan"))
        #expect(text.contains("Page 2"))
        // The travel day has no strips, so it is not a scheduled day and is not printed.
        #expect(!text.contains("TRAVEL"))
    }

    @Test func stripScheduleRefusesAnEmptySchedule() {
        let empty = [ShootDay(date: novemberDate(day: 3))]
        #expect(StripboardPDFExporter.generatePDF(shootDays: empty, projectTitle: "Nothing", productionInfo: ProductionInfo()) == nil)
    }

    // MARK: - Shooting schedule

    @Test func shootingScheduleRendersFixtureProject() {
        let doc = document(
            from: ShootingSchedulePDFExporter.generatePDF(
                shootDays: fixtureDays,
                projectTitle: fixtureTitle,
                productionInfo: fixtureProductionInfo
            ),
            dumpAs: "ShootingSchedule.pdf"
        )
        #expect(doc.pageCount == 3)

        let firstPage = doc.page(at: 0)?.string ?? ""
        #expect(firstPage.contains(fixtureTitle.uppercased()))
        #expect(firstPage.contains("SHOOTING SCHEDULE"))
        #expect(firstPage.contains("PAGE 1"))

        let text = fullText(doc)
        #expect(text.contains("SHOOT DAY #1"))
        #expect(text.contains("CREW CALL"))
        #expect(text.contains("SET CALL"))
        #expect(text.contains("LUNCH"))
        #expect(text.contains("END OF DAY #5"))
        #expect(text.contains("PAGE 2"))
    }
}

//
//  SchedulePDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders the strip schedule and the shooting schedule from the fixture project in
//  PDFTestSupport and inspects the PDFs through PDFKit. These two exporters draw on the
//  shared PDFCanvas (CoreGraphics + CoreText, no AppKit), so this suite runs on the Mac
//  and on the iOS and visionOS simulators alike (#4). Set CINESCHED_PDF_DUMP_DIR to keep
//  the PDFs for a visual comparison (see PDFTestSupport).
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct SchedulePDFExporterTests {

    // MARK: - Strip schedule

    @Test func stripScheduleRendersFixtureProject() {
        let doc = pdfDocument(
            from: StripboardPDFExporter.generatePDF(
                shootDays: PDFFixture.days,
                projectTitle: PDFFixture.title,
                productionInfo: PDFFixture.productionInfo,
                palette: .standard
            ),
            dumpAs: "StripSchedule.pdf"
        )
        #expect(doc.pageCount == 2)

        let firstPage = doc.page(at: 0)?.string ?? ""
        #expect(firstPage.contains(PDFFixture.title))
        #expect(firstPage.contains("Strip Schedule"))
        #expect(firstPage.contains("Lightsail Pictures"))

        let text = pdfFullText(doc)
        #expect(text.contains("Day 1"))
        #expect(text.contains("END OF DAY #5"))
        #expect(text.contains("Producer visit"))
        #expect(text.contains("Alex Morgan"))
        #expect(text.contains("Page 2"))
        // The travel day has no strips, so it is not a scheduled day and is not printed.
        #expect(!text.contains("TRAVEL"))
    }

    /// The palette is the project's (#11): a customized slot colors the strips of every
    /// exporter that draws them, and the standard color is gone from the page.
    @Test func stripSchedulesDrawTheProjectPalette() {
        var palette = ScenePalette.standard
        palette.setHex("C71585", for: .intDay)   // a color no standard slot uses
        let standardIntDay = SceneColorSlot.intDay.defaultHex

        let strip = pdfDocument(from: StripboardPDFExporter.generatePDF(
            shootDays: PDFFixture.days, projectTitle: PDFFixture.title,
            productionInfo: PDFFixture.productionInfo, palette: palette))
        #expect(pdfPage(strip, 0, containsColorHex: "C71585"))
        #expect(!pdfPage(strip, 0, containsColorHex: standardIntDay))

        let shooting = pdfDocument(from: ShootingSchedulePDFExporter.generatePDF(
            shootDays: PDFFixture.days, projectTitle: PDFFixture.title,
            productionInfo: PDFFixture.productionInfo, palette: palette))
        #expect(pdfPage(shooting, 0, containsColorHex: "C71585"))
        #expect(!pdfPage(shooting, 0, containsColorHex: standardIntDay))

        // And the standard palette still draws the standard color, so the check is real.
        let standard = pdfDocument(from: StripboardPDFExporter.generatePDF(
            shootDays: PDFFixture.days, projectTitle: PDFFixture.title,
            productionInfo: PDFFixture.productionInfo, palette: .standard))
        #expect(pdfPage(standard, 0, containsColorHex: standardIntDay))
        #expect(!pdfPage(standard, 0, containsColorHex: "C71585"))
    }

    @Test func stripScheduleRefusesAnEmptySchedule() {
        let empty = [ShootDay(date: PDFFixture.novemberDate(day: 3))]
        #expect(StripboardPDFExporter.generatePDF(shootDays: empty, projectTitle: "Nothing", productionInfo: ProductionInfo(), palette: .standard) == nil)
    }

    // MARK: - Shooting schedule

    @Test func shootingScheduleRendersFixtureProject() {
        let doc = pdfDocument(
            from: ShootingSchedulePDFExporter.generatePDF(
                shootDays: PDFFixture.days,
                projectTitle: PDFFixture.title,
                productionInfo: PDFFixture.productionInfo,
                palette: .standard
            ),
            dumpAs: "ShootingSchedule.pdf"
        )
        #expect(doc.pageCount == 3)

        let firstPage = doc.page(at: 0)?.string ?? ""
        #expect(firstPage.contains(PDFFixture.title.uppercased()))
        #expect(firstPage.contains("SHOOTING SCHEDULE"))
        #expect(firstPage.contains("PAGE 1"))

        let text = pdfFullText(doc)
        #expect(text.contains("SHOOT DAY #1"))
        #expect(text.contains("CREW CALL: 6:30 AM"))   // the header bar's milestone
        // The fixture's days carry no General Call or Ready to Shoot strips, so no such row prints.
        #expect(!text.contains("SET CALL"))
        #expect(!text.contains("GENERAL CALL"))
        #expect(text.contains("LUNCH"))
        #expect(text.contains("END OF DAY #5"))
        #expect(text.contains("PAGE 2"))
    }

    /// The Stripboard's per-day export: one synced day (its General Call and Ready to
    /// Shoot strips are zero-length auto-meals) with a zero-length notice of its own. The
    /// day keeps its production number, every strip prints the board's time
    /// (`dayTimeline`), every scene its estimate and its cast, and there is no "Pg." column.
    @Test func shootingScheduleForOneDayPrintsTheBoardsTimesCastAndEstimates() {
        var days = PDFFixture.days
        var day = days[3]   // production day 3 (days[0] is the travel day)
        day.scenes = day.scenesWithSyncedAutoMeals()
        day.scenes.insert(Scene.createBanner(type: .notice, title: "Safety meeting", estimatedTime: "0:00"), at: 4)
        days[3] = day

        let doc = pdfDocument(
            from: ShootingSchedulePDFExporter.generatePDF(
                shootDays: days,
                printingDayIDs: [day.id],
                projectTitle: PDFFixture.title,
                productionInfo: PDFFixture.productionInfo,
                palette: .standard
            ),
            dumpAs: "ShootingScheduleOneDay.pdf"
        )
        let text = pdfFullText(doc)

        #expect(text.contains("SHOOT DAY #3"))
        #expect(text.contains("END OF DAY #3"))
        #expect(!text.contains("SHOOT DAY #1"))
        #expect(!text.contains("SHOOT DAY #2"))
        #expect(!text.contains("Pg. "))

        let strips   = day.scenes.filter { !$0.isCalendarEvent }
        let timeline = dayTimeline(for: day, scenes: strips)
        for strip in strips {
            let entry = timeline[strip.id]!
            #expect(text.contains(entry.timeDisplay), "\(strip.title) should print \(entry.timeDisplay)")
            if !strip.isBanner {
                #expect(text.contains("\(strip.sceneNumber). "))
                #expect(text.contains("Est: \(entry.durStr)"))
            }
        }
        #expect(text.contains("Alex Morgan, Sam Rivera, Jordan Lee, Casey Kim, Riley Chen"))

        // The header's lunch is the call sheet's lunch strip, not the day's own Lunch banner.
        #expect(text.contains("01:00 PM"))
        #expect(text.contains("GENERAL CALL"))
        #expect(text.contains("READY TO SHOOT"))
    }

    /// The two options: off (the default) neither prints; on, a scene with a shot list
    /// says how many and every scene prints its description, a shotless one no count.
    @Test func shootingScheduleOptionsAddShotCountAndDescription() {
        let days = PDFFixture.daysWithShots   // one build: every read makes new ids
        func text(_ options: ShootingSchedulePDFOptions, dumpAs name: String) -> String {
            pdfFullText(pdfDocument(
                from: ShootingSchedulePDFExporter.generatePDF(
                    shootDays: days,
                    printingDayIDs: [days[1].id],
                    projectTitle: PDFFixture.title,
                    productionInfo: PDFFixture.productionInfo,
                    palette: .standard,
                    options: options
                ),
                dumpAs: name
            ))
        }
        let summary = "Scene 101: the crew regroups"

        let plain = text(.default, dumpAs: "ShootingScheduleOneDayPlain.pdf")
        #expect(!plain.contains("4 shots"))
        #expect(!plain.contains(summary))

        let extras = text(ShootingSchedulePDFOptions(includeShotCount: true, includeDescription: true),
                          dumpAs: "ShootingScheduleOneDayExtras.pdf")
        #expect(extras.contains("4 shots"))
        #expect(extras.contains("2 shots"))
        #expect(!extras.contains("0 shots"))
        #expect(extras.contains(summary))
        #expect(extras.contains("Scene 106:"))
        #expect(extras.contains("Alex Morgan, Sam Rivera"))
    }
}

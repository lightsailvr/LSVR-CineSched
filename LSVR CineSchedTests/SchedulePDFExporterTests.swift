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
        #expect(text.contains("CREW CALL"))
        #expect(text.contains("SET CALL"))
        #expect(text.contains("LUNCH"))
        #expect(text.contains("END OF DAY #5"))
        #expect(text.contains("PAGE 2"))
    }
}

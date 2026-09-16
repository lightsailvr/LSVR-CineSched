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
                productionInfo: PDFFixture.productionInfo
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

    @Test func stripScheduleRefusesAnEmptySchedule() {
        let empty = [ShootDay(date: PDFFixture.novemberDate(day: 3))]
        #expect(StripboardPDFExporter.generatePDF(shootDays: empty, projectTitle: "Nothing", productionInfo: ProductionInfo()) == nil)
    }

    // MARK: - Shooting schedule

    @Test func shootingScheduleRendersFixtureProject() {
        let doc = pdfDocument(
            from: ShootingSchedulePDFExporter.generatePDF(
                shootDays: PDFFixture.days,
                projectTitle: PDFFixture.title,
                productionInfo: PDFFixture.productionInfo
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

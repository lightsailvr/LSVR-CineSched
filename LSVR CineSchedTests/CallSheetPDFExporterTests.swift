//
//  CallSheetPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders the call sheet for the fixture project's fully filled-in day (cast calls,
//  crew calls, quote, weather, locations, notes) and reads it back through PDFKit.
//  CallSheetExporter draws on PDFCanvas, so this suite runs on the Mac and on the iOS
//  and visionOS simulators (#5). Set CINESCHED_PDF_DUMP_DIR to keep the PDFs for a
//  visual comparison (see PDFTestSupport).
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct CallSheetPDFExporterTests {

    private func render(_ day: ShootDay, dayNumber: Int?, dumpAs name: String) -> PDFDocument {
        pdfDocument(
            from: CallSheetExporter.generatePDF(
                shootDay: day,
                productionInfo: PDFFixture.productionInfo,
                projectTitle: PDFFixture.title,
                dayNumber: dayNumber,
                totalProductionDays: 5,
                language: .english
            ),
            dumpAs: name
        )
    }

    @Test func callSheetRendersCastCrewAndNotesOnOnePage() {
        let doc = render(PDFFixture.callSheetDay, dayNumber: 3, dumpAs: "CallSheet.pdf")
        #expect(doc.pageCount == 1)

        let text = pdfFullText(doc)
        // Banner and general call
        #expect(text.contains("CALL SHEET # 03"))
        #expect(text.contains("GENERAL CALL"))
        #expect(text.contains("6:30 AM"))
        #expect(text.contains("Quote of the day: The best way out is always through."))
        #expect(text.contains("Schedule: 07:30 AM to 07:30 PM"))
        // Contacts, milestones, weather
        #expect(text.contains("PRODUCER"))
        #expect(text.contains("Dana Whitfield - Tel: 555-0101"))
        #expect(text.contains("1ST AD"))
        #expect(text.contains("Chris Okafor - Tel: 555-0102"))
        #expect(text.contains("READY TO"))               // "READY TO SHOOT" wraps in its cell
        #expect(text.contains("4:30 PM"))                     // snack
        #expect(text.contains("Temp: 72°F / 22°C"))
        #expect(text.contains("Sunrise 6:24 AM"))
        // Basecamp and hospital
        #expect(text.contains("BASECAMP: Lot 4, 100 Universal City Plaza"))
        #expect(text.contains("NEAREST HOSPITAL: Providence St. Joseph"))
        // Scenes table: every scene of the day, with the matched location's address
        #expect(text.contains("SET / DESCRIPTION"))
        #expect(text.contains("301"))
        #expect(text.contains("306"))
        #expect(text.contains("100 Universal City Plaza, Univer"))    // truncated to the ADDRESS column
        // Cast calls: explicit scene numbers kept, missing ones derived from the day's scenes
        #expect(text.contains("Taylor Brooks"))
        #expect(text.contains("Robin Castillo"))
        #expect(text.contains("301, 305"))
        #expect(text.contains("301, 302,"))              // the derived list wraps in the SCENES column
        // Crew calls: a blank name is filled in from the production roster
        #expect(text.contains("CREW CALL TIMES"))
        #expect(text.contains("DP: Priya Nair"))
        #expect(text.contains("Gaffer: Luis Ortega"))
        // Notes
        #expect(text.contains("GENERAL NOTES"))
        #expect(text.contains("Wear layers; the backlot gets cold after sunset."))
        #expect(text.contains("shuttle from basecamp every 15 minutes."))
    }

    /// The filled-in day again, with every cell short enough to fit: no synopsis, one cast
    /// name, a short address, no company-move notice. Nothing on this sheet is
    /// ellipsis-truncated, so its dump is the one to pixel-compare across drawing changes
    /// (PDFCanvas deliberately lays truncated lines out a character differently from
    /// TextKit; see learnings.md).
    @Test func callSheetRendersACompactDay() {
        var day = PDFFixture.callSheetDay
        day.scenes = day.scenes.filter { $0.isBanner || $0.isCalendarEvent || !$0.sceneNumber.isEmpty }.map { scene in
            var scene = scene
            scene.summary = ""
            scene.cast = Array(scene.cast.prefix(1))
            return scene
        }
        day.callSheet.locations[0].address = "100 Universal City Plaza"
        let doc = render(day, dayNumber: 3, dumpAs: "CallSheet-Compact.pdf")
        #expect(doc.pageCount == 1)

        let text = pdfFullText(doc)
        #expect(text.contains("Alex Morgan 1/8 1 100 Universal City Plaza"))
        #expect(!text.contains("\u{2026}"))
    }

    @Test func callSheetFallsBackToTheRosterAndDefaultsOnABareDay() {
        var day = PDFFixture.days[1]
        day.callSheet = CallSheetData()
        let doc = render(day, dayNumber: nil, dumpAs: "CallSheet-Bare.pdf")
        #expect(doc.pageCount == 1)

        let text = pdfFullText(doc)
        #expect(text.contains("CALL SHEET # 01"))      // no production day number → 01
        #expect(text.contains("07:30 AM"))              // default general call
        #expect(!text.contains("Quote of the day"))
        #expect(text.contains("LUNCH"))                 // empty milestones still list the four labels
        #expect(text.contains("Priya Nair"))            // crew from the roster, 07:30 AM default
        #expect(text.contains("Aisha Bello"))
        #expect(text.contains("GENERAL NOTES"))
    }

    /// A day too long for one page: 27 scene rows (24 scenes, the lunch banner, the
    /// event and the company move) and 15 cast calls. The rows are fixed heights, so the
    /// split is the same on every platform: 14 scene rows fit under the header on page 1,
    /// the remaining 13 and the whole cast table go on page 2, and the crew calls and the
    /// notes on page 3. Every section used to draw everything after the first page break
    /// below the page (#32), so this checks that the content survives, not just the count.
    @Test func callSheetPaginatesALongDay() {
        var day = PDFFixture.callSheetDay
        day.scenes += (7...24).map { PDFFixture.makeScene(300 + $0) }
        day.callSheet.castCallEntries += (1...12).map {
            CastCallEntry(characterName: "Extra \($0)", actorName: "Performer \($0)", onSetTime: "8:00 AM")
        }
        let doc = render(day, dayNumber: 3, dumpAs: "CallSheet-Long.pdf")
        #expect(doc.pageCount == 3)

        let pages = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        for (index, text) in pages.enumerated() {
            #expect(!text.isEmpty, "page \(index + 1) is blank")
        }

        let firstPage = pages.first ?? ""
        #expect(firstPage.contains("301"))
        #expect(firstPage.contains("311"))     // the last row that fits above the bottom margin
        #expect(!firstPage.contains("312"))    // the next row starts page 2 instead of overflowing
        #expect(!firstPage.contains("GENERAL NOTES"))

        // Everything after the first break lands on the pages opened for it.
        let laterPages = pages.dropFirst().joined(separator: "\n")
        #expect(laterPages.contains("312"))
        #expect(laterPages.contains("324"))
        #expect(laterPages.contains("CHARACTER"))          // the cast table header
        #expect(laterPages.contains("Taylor Brooks"))
        #expect(laterPages.contains("Performer 12"))       // the last cast entry
        #expect(laterPages.contains("CREW CALL TIMES"))
        #expect(laterPages.contains("GENERAL NOTES"))
        #expect(laterPages.contains("Wear layers; the backlot gets cold after sunset."))

        // And in order: the scenes and cast on page 2, the crew and notes on page 3.
        let secondPage = pages.count > 1 ? pages[1] : ""
        let thirdPage  = pages.count > 2 ? pages[2] : ""
        #expect(secondPage.contains("324"))
        #expect(secondPage.contains("Performer 12"))
        #expect(thirdPage.contains("CREW CALL TIMES"))
        #expect(thirdPage.contains("GENERAL NOTES"))
    }
}

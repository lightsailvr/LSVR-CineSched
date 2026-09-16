//
//  MonthPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders month PDFs from synthetic ShootDays and inspects them through PDFKit —
//  the breakdown must paginate instead of dropping days, English output must not
//  leak Spanish abbreviations, and the export options must control the scene chips.
//

// PDFExporter still draws through AppKit and is gated to macOS until it moves onto
// PDFCanvas (see StripboardPDFExporter for the shape), so this suite is gated with it;
// it is meant to run on every platform once it does.
#if os(macOS)
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct MonthPDFExporterTests {

    /// A date inside November 2026 (the month all fixtures schedule into).
    private func novemberDate(day: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = day; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    private func makeScene(_ n: Int) -> Scene {
        Scene(
            title: "EXT. UNIVERSAL STUDIOS HOLLYWOOD - BACKLOT SET \(n) - DAY",
            sceneNumber: "\(n)",
            duration: 3,
            estimatedTime: 45,
            cast: ["Alex Morgan", "Sam Rivera", "Jordan Lee", "Casey Kim", "Riley Chen"],
            realLocation: "HOLLYWOOD"
        )
    }

    private func packedMonth(dayCount: Int, scenesPerDay: Int) -> [ShootDay] {
        (1...dayCount).map { d in
            var sheet = CallSheetData()
            sheet.generalCallTime = "7:00 AM"
            sheet.lunchTime = "1:00 PM"
            return ShootDay(
                date: novemberDate(day: d),
                scenes: (1...scenesPerDay).map { makeScene(d * 100 + $0) },
                callSheet: sheet
            )
        }
    }

    private func render(_ days: [ShootDay], options: MonthPDFOptions = .default) -> PDFDocument {
        let data = PDFExporter.generateMonthPDF(
            month: novemberDate(day: 1),
            shootDays: days,
            projectTitle: "Test Project",
            productionInfo: ProductionInfo(),
            options: options
        )
        #expect(data != nil)
        let doc = PDFDocument(data: data ?? Data())
        #expect(doc != nil)
        return doc ?? PDFDocument()
    }

    private func fullText(_ doc: PDFDocument) -> String {
        (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }

    /// Pages 2+ only — the grid page always shows scene number + location, so
    /// options-driven assertions must not read page 1.
    private func breakdownText(_ doc: PDFDocument) -> String {
        (1..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test func breakdownPaginatesInsteadOfDroppingDays() {
        let doc = render(packedMonth(dayCount: 20, scenesPerDay: 8))
        // Grid page + more breakdown than fits on one page.
        #expect(doc.pageCount >= 3)
        let text = fullText(doc)
        // The last day survives onto a later page (the old exporter silently dropped it).
        #expect(text.contains("November 20"))
        // Continuation pages are labelled.
        #expect(text.contains("(cont.)"))
        #expect(text.contains("Page 2"))
    }

    @Test func englishExportHasNoSpanishAbbreviations() {
        let text = fullText(render(packedMonth(dayCount: 4, scenesPerDay: 3)))
        #expect(!text.contains("Esc "))
        #expect(!text.contains("págs"))
        #expect(text.contains("Sc "))
        #expect(text.contains("pgs"))
    }

    @Test func gridCellShowsSceneNumberAndLocation() {
        let doc = render(packedMonth(dayCount: 2, scenesPerDay: 2))
        let gridText = doc.page(at: 0)?.string ?? ""
        #expect(gridText.contains("101 · HOLLYWOOD"))
    }

    @Test func optionsControlSceneChips() {
        var scene = makeScene(1)
        scene.specialEquipment = ["Drone", "Crane"]
        scene.summary = "The big finale on the backlot"
        scene.estimatedTime = 90
        scene.realLocation = "RESEDA RANCH"   // distinct from the slugline text
        let day = [ShootDay(date: novemberDate(day: 5), scenes: [scene])]

        let defaultText = breakdownText(render(day))
        #expect(defaultText.contains("Alex Morgan"))          // cast pill (default on)
        #expect(defaultText.contains("RESEDA RANCH"))         // location pill (default on)
        #expect(!defaultText.contains("Drone"))
        #expect(!defaultText.contains("big finale"))

        let custom = MonthPDFOptions(
            fields: [.summary, .specialEquipment],
            includePageCount: false,
            includeEstimatedTime: true
        )
        let customText = breakdownText(render(day, options: custom))
        #expect(customText.contains("Drone, Crane"))          // equipment pill
        #expect(customText.contains("The big finale"))        // synopsis line
        #expect(!customText.contains("Alex Morgan"))          // cast not selected
        #expect(!customText.contains("RESEDA RANCH"))         // location not selected
        // Estimated time on: the heading meta carries the formatted 90 minutes.
        #expect(customText.contains(formattedTime(90)))
    }

    @Test func longSceneLinesWrapWithoutTruncatingContent() {
        var scene = makeScene(1)
        // Too wide for a single pill row: becomes a full-width pill with wrapped
        // text, within the 3-line cap that guards against swallowing the card.
        scene.cast = (1...10).map { "Performer Number \($0)" }
        let day = [ShootDay(date: novemberDate(day: 5), scenes: [scene])]
        let text = fullText(render(day))
        // The tail of the cast list survives onto a wrapped line instead of
        // being truncated.
        #expect(text.contains("Performer Number 10"))
    }
}
#endif

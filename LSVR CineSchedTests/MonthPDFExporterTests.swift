//
//  MonthPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders month PDFs from synthetic ShootDays and inspects them through PDFKit —
//  the breakdown must paginate instead of dropping days, English output must not
//  leak Spanish abbreviations, and the export options must control the scene chips.
//  The fixture render at the end draws every cell and card style from the shared
//  PDFTestSupport project; PDFExporter draws on PDFCanvas, so the whole suite runs on
//  the Mac and on the iOS and visionOS simulators (#5).
//

import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct MonthPDFExporterTests {

    /// A date inside November 2026 (the month all fixtures schedule into).
    private func novemberDate(day: Int) -> Date { PDFFixture.novemberDate(day: day) }

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

    private func render(
        _ days: [ShootDay],
        options: MonthPDFOptions = .default,
        projectTitle: String = "Test Project",
        productionInfo: ProductionInfo = ProductionInfo(),
        dumpAs name: String? = nil
    ) -> PDFDocument {
        let data = PDFExporter.generateMonthPDF(
            month: novemberDate(day: 1),
            shootDays: days,
            projectTitle: projectTitle,
            productionInfo: productionInfo,
            options: options
        )
        return pdfDocument(from: data, dumpAs: name)
    }

    private func fullText(_ doc: PDFDocument) -> String { pdfFullText(doc) }

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

    // MARK: - Fixture render (both pages, every cell and card style)

    /// The shared fixture plus one agenda-only day: a typed day with a note (TRAVEL badge,
    /// note-only card), shoot days with night scenes, a banner and an event (DAY # badge,
    /// event chips, full scene cards) and a day holding just a calendar event (the
    /// "AGENDA / PREP DAY" card).
    private var fixtureDays: [ShootDay] {
        PDFFixture.days + [
            ShootDay(date: PDFFixture.novemberDate(day: 9),
                     scenes: [Scene.createCalendarEvent(title: "Location scout — ranch", time: "10:00 AM")])
        ]
    }

    @Test func monthCalendarRendersFixtureProject() {
        let doc = render(fixtureDays, projectTitle: PDFFixture.title, productionInfo: PDFFixture.productionInfo,
                         dumpAs: "MonthCalendar.pdf")
        #expect(doc.pageCount == 6)

        let grid = doc.page(at: 0)?.string ?? ""
        #expect(grid.contains("The Long Way Home — NOVEMBER 2026"))
        #expect(grid.contains("Month Shoot Days: 6"))   // the agenda-only day counts
        #expect(grid.contains("Director: Morgan Vale"))
        #expect(grid.contains("DAY #1"))
        #expect(grid.contains("TRAVEL"))
        #expect(grid.contains("Fly LAX → ABQ"))
        #expect(grid.contains("10:00 AM · Location s"))     // event chip, truncated to the cell
        #expect(grid.contains("101 · HOLLYWOOD"))

        let breakdown = breakdownText(doc)
        #expect(breakdown.contains("Schedule & Breakdown"))
        #expect(breakdown.contains("SHOOT DAY #1"))
        #expect(breakdown.contains("SHOOT DAY #5"))
        #expect(breakdown.contains("TRAVEL DAY"))
        #expect(breakdown.contains("AGENDA / PREP DAY"))
        #expect(breakdown.contains("Location scout"))
        #expect(breakdown.contains("Call: 6:30 AM"))
        #expect(breakdown.contains("Lunch: 1:00 PM"))
        #expect(breakdown.contains("Sc 505:"))
        #expect(breakdown.contains("Page 5"))
    }

    /// Every optional field on: the italic synopsis line and the full set of tinted pills.
    @Test func monthCalendarRendersEveryFieldWhenAsked() {
        var days = fixtureDays
        days[1].scenes[0].specialEquipment = ["Drone", "Crane"]
        days[1].scenes[0].props = ["Lantern"]
        let everything = MonthPDFOptions(fields: Set(StripboardField.allCases), includePageCount: true, includeEstimatedTime: true)
        let doc = render(days, options: everything, projectTitle: PDFFixture.title, productionInfo: PDFFixture.productionInfo,
                         dumpAs: "MonthCalendar-AllFields.pdf")
        #expect(doc.pageCount >= 6)

        let breakdown = breakdownText(doc)
        #expect(breakdown.contains("the crew regroups on the backlot"))   // synopsis, italic
        #expect(breakdown.contains("Drone, Crane"))
        #expect(breakdown.contains("Lantern"))
        #expect(breakdown.contains(formattedTime(45)))
    }

    // MARK: - Full-schedule calendar (File ▸ Export Schedule PDF)

    /// The older whole-production calendar in the same file: one landscape grid of every
    /// week, header on page 1 only. Same fixture so its dump sits beside the month export.
    @Test func scheduleCalendarRendersFixtureProject() {
        let days = fixtureDays
        let doc = pdfDocument(
            from: PDFExporter.generatePDF(
                shootDays: days,
                projectTitle: PDFFixture.title,
                allScenes: [],
                startDate: days.first!.date,
                endDate: days.last!.date
            ),
            dumpAs: "ScheduleCalendar.pdf"
        )
        #expect(doc.pageCount == 1)

        let text = fullText(doc)
        #expect(text.contains(PDFFixture.title))
        #expect(text.contains("Shoot Days: 6"))
        #expect(text.contains("Day 1"))
        #expect(text.contains("Day 5"))
        #expect(text.contains("Total: 3 1/8"))
        #expect(text.contains("Est: \(formattedTime(345))"))   // six scenes plus the 30-minute lunch
    }
}

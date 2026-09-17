//
//  DaysOutOfDaysPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders the Days Out of Days grid from a cast schedule with every status code (start,
//  work, hold, finish, start-finish, unavailable) across shoot days and a typed non-shoot
//  day, and reads it back through PDFKit. DaysOutOfDaysExporter draws on PDFCanvas, so
//  this suite runs on the Mac and on the iOS and visionOS simulators (#6). Set
//  CINESCHED_PDF_DUMP_DIR to keep the PDFs for a visual comparison (see PDFTestSupport).
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct DaysOutOfDaysPDFExporterTests {

    /// Six days: a travel day, four shoot days and a production-wide day off in the
    /// middle (a shoot-typed date with nothing scheduled).
    ///
    ///   Nov 1  travel   —
    ///   Nov 2  shoot    Alex, Sam, Jordan
    ///   Nov 3  shoot    Alex, Jordan
    ///   Nov 4  shoot    —            (day off for everyone)
    ///   Nov 5  shoot    Alex, Sam
    ///   Nov 6  shoot    Alex, Casey
    ///
    /// Alex works every shoot day (SW W W WF); Sam holds on the 3rd (SW H WF); Jordan
    /// starts and finishes on consecutive days (SW WF); Casey works once (SWF); Riley is
    /// on the roster but never scheduled, so has no row.
    private var days: [ShootDay] {
        func day(_ n: Int, _ cast: [[String]]) -> ShootDay {
            ShootDay(date: PDFFixture.novemberDate(day: n), scenes: cast.enumerated().map { i, names in
                var scene = PDFFixture.makeScene(n * 10 + i)
                scene.cast = names
                return scene
            })
        }
        return [
            ShootDay(date: PDFFixture.novemberDate(day: 1), dayType: .travel, dayNote: "Fly LAX → ABQ"),
            day(2, [["Alex Morgan", "Sam Rivera"], ["Jordan Lee"]]),
            day(3, [["Alex Morgan", "Jordan Lee"]]),
            day(4, []),
            day(5, [["Alex Morgan", "Sam Rivera"]]),
            day(6, [["Alex Morgan"], ["Casey Kim"]]),
        ]
    }

    private var productionInfo: ProductionInfo {
        var info = PDFFixture.productionInfo
        info.castList = [
            CastMember(actorName: "Taylor Brooks",  characterName: "Alex Morgan"),
            CastMember(actorName: "Jamie Ellis",    characterName: "Sam Rivera",
                       unavailableRanges: [DateRange(start: PDFFixture.novemberDate(day: 3), end: PDFFixture.novemberDate(day: 3))]),
            CastMember(actorName: "Robin Castillo", characterName: "Jordan Lee"),
            CastMember(actorName: "",               characterName: "Riley Chen"),
        ]
        return info
    }

    private func render(_ days: [ShootDay], info: ProductionInfo? = nil, includeHold: Bool, dumpAs name: String) -> PDFDocument {
        pdfDocument(
            from: DaysOutOfDaysExporter.generatePDF(
                shootDays: days,
                projectTitle: PDFFixture.title,
                productionInfo: info ?? productionInfo,
                includeHold: includeHold
            ),
            dumpAs: name
        )
    }

    // MARK: - Rows

    @Test func rowsCarryEveryStatusCodeAndSkipUnscheduledCast() {
        let (sorted, rows) = DaysOutOfDaysExporter.buildRows(shootDays: days, productionInfo: productionInfo)
        #expect(sorted.count == 6)
        #expect(rows.map(\.displayName) == ["Taylor Brooks — Alex Morgan", "Jamie Ellis — Sam Rivera", "Robin Castillo — Jordan Lee", "Casey Kim"])

        #expect(rows[0].statuses == [.none, .startWork, .work, .none, .work, .finish])
        #expect(rows[0].workDayCount == 4 && rows[0].holdDayCount == 0 && rows[0].totalSpan == 5)
        // Sam's hold on the 3rd is overridden by the actor's unavailable date; the day
        // off on the 4th stays blank because nobody works it.
        #expect(rows[1].statuses == [.none, .startWork, .unavailable, .none, .finish, .none])
        #expect(rows[1].workDayCount == 2 && rows[1].holdDayCount == 0 && rows[1].totalSpan == 4)
        #expect(rows[2].statuses == [.none, .startWork, .finish, .none, .none, .none])
        #expect(rows[3].statuses == [.none, .none, .none, .none, .none, .startFinish])
        #expect(rows[3].workDayCount == 1 && rows[3].totalSpan == 1)
    }

    @Test func holdDaysAreLeftBlankWhenTheToggleIsOff() {
        var info = productionInfo
        info.castList[1].unavailableRanges = []
        let withHold = DaysOutOfDaysExporter.buildRows(shootDays: days, productionInfo: info, includeHold: true).rows
        let without  = DaysOutOfDaysExporter.buildRows(shootDays: days, productionInfo: info, includeHold: false).rows
        #expect(withHold[1].statuses == [.none, .startWork, .hold, .none, .finish, .none])
        #expect(withHold[1].holdDayCount == 1)
        #expect(without[1].statuses == [.none, .startWork, .none, .none, .finish, .none])
        #expect(without[1].holdDayCount == 0)
    }

    // MARK: - PDF

    @Test func doodRendersTheGridWithHoldsOnOnePage() {
        var info = productionInfo
        info.castList[1].unavailableRanges = []
        let doc = render(days, info: info, includeHold: true, dumpAs: "DOOD.pdf")
        #expect(doc.pageCount == 1)

        // PDFKit reads the grid column by column: the name and summary cells of every row
        // run together, then the status codes.
        let text = pdfFullText(doc)
        #expect(text.contains("\(PDFFixture.title) — Days Out of Days"))
        #expect(text.contains("Page 1 of 1"))
        // Summary columns, with the hold column
        #expect(text.contains("TOT WRK HLD"))
        // Day headers: the month once, then a weekday initial over each day number
        // (the travel day's column is there, shaded, with no codes in it)
        #expect(text.contains("Nov\nS\n1\nM\n2"))
        // Rows: total span, work days, hold days
        #expect(text.contains("Taylor Brooks — Alex Morgan 5 4 0"))
        #expect(text.contains("Jamie Ellis — Sam Rivera 4 2 1"))
        #expect(text.contains("Robin Castillo — Jordan Lee 2 2 0"))
        #expect(text.contains("Casey Kim 1 1 0"))
        #expect(!text.contains("Riley Chen"))
        // Codes: Sam's hold sits between the start and the finish
        #expect(text.contains("H WF"))
        #expect(text.contains("SWF"))
        // Legend
        #expect(text.contains("H = Hold"))
        #expect(text.contains("HLD = Hold Days"))
    }

    @Test func doodOmitsTheHoldColumnAndLegendWhenTheToggleIsOff() {
        let doc = render(days, includeHold: false, dumpAs: "DOOD-NoHold.pdf")
        #expect(doc.pageCount == 1)

        let text = pdfFullText(doc)
        #expect(text.contains("TOT WRK"))
        #expect(!text.contains("HLD"))
        #expect(text.contains("Jamie Ellis — Sam Rivera 4 2 Robin"))   // no hold count
        #expect(!text.contains("H = Hold"))
        #expect(text.contains("X = Unavailable"))
        // Sam's unavailable date prints X between the start and the finish (with the
        // toggle off it was blank, not a hold, before the unavailable range overrode it)
        #expect(text.contains("X WF"))
    }

    @Test func doodPaginatesAcrossDaysAndRows() {
        // 30 shoot days at 22pt a column fit 21 to a page (with the hold column), and 30
        // rows at 18pt fit 25: two day chunks × two row chunks. Characters that are not
        // on the roster sort alphabetically ("Character 1", "Character 10", …), so the
        // first row page ends at "Character 4" and the second holds 5 through 9.
        let cast = (1...30).map { "Character \($0)" }
        let many: [ShootDay] = (1...30).map { n in
            var scene = PDFFixture.makeScene(n)
            scene.cast = cast
            return ShootDay(date: PDFFixture.novemberDate(day: n), scenes: [scene])
        }
        let doc = render(many, includeHold: true, dumpAs: "DOOD-Paginated.pdf")
        #expect(doc.pageCount == 4)
        let page1 = doc.page(at: 0)?.string ?? "", page2 = doc.page(at: 1)?.string ?? "", page4 = doc.page(at: 3)?.string ?? ""
        #expect(page1.contains("Page 1 of 4"))
        #expect(page4.contains("Page 4 of 4"))
        #expect(page1.contains("Character 30") && page1.contains("Character 4"))
        #expect(!page1.contains("Character 5"))
        #expect(page2.contains("Character 5") && page2.contains("Character 9"))
        #expect(!page2.contains("Character 4"))
    }

    @Test func doodReturnsNilWithoutCastOrDays() {
        #expect(DaysOutOfDaysExporter.generatePDF(shootDays: [], projectTitle: "", productionInfo: productionInfo) == nil)
        let uncast = [ShootDay(date: PDFFixture.novemberDate(day: 2), scenes: [Scene(title: "INT. ROOM - DAY")])]
        #expect(DaysOutOfDaysExporter.generatePDF(shootDays: uncast, projectTitle: "", productionInfo: ProductionInfo()) == nil)
    }
}

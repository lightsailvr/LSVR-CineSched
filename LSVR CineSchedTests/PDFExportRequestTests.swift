//
//  PDFExportRequestTests.swift
//  LSVR CineSchedTests
//
//  The export requests every platform's presentation receives (#23): one per document,
//  built from the shared fixture project, must carry exactly the exporter's bytes under
//  the file name the Mac's save panel has always proposed. Two renders of one document
//  differ only in the PDF's creation and modification dates and the trailer's time-derived
//  `/ID` (learnings, 2026-09-19 #32), so the comparison masks those and nothing else. The
//  failure rows are the exporters' own (no scenes, no cast), worded for the alert; the
//  temporary file is what the share sheet sends.
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct PDFExportRequestTests {

    // MARK: - Fixture

    /// The shared fixture days under a customized palette (a magenta no standard slot
    /// uses, as SchedulePDFExporterTests), so a request drawn with the standard one differs.
    private var project: ProjectData {
        var palette = ScenePalette.standard
        palette.setHex("C71585", for: .intDay)
        return ProjectData(
            allScenes:      [PDFFixture.makeScene(900), PDFFixture.makeScene(901, dayNight: .night)],
            shootDays:      PDFFixture.days,
            projectTitle:   PDFFixture.title,
            productionInfo: PDFFixture.productionInfo,
            palette:        palette
        )
    }

    private var range: (Date, Date) {
        (PDFFixture.novemberDate(day: 1), PDFFixture.novemberDate(day: 6))
    }

    /// `data` with the time-derived bytes masked: the Info dictionary's dates and the
    /// trailer's `/ID` pair. Everything else in a Quartz PDF is a function of the drawing.
    private func masked(_ data: Data) -> String {
        var text = String(data: data, encoding: .isoLatin1) ?? ""
        // Quartz breaks the Info dictionary's line before the date, so the key and its
        // value are separated by whitespace, not one space.
        text = text.replacingOccurrences(of: #"/(CreationDate|ModDate)\s+\(D:[^)]*\)"#, with: "/$1 (D:0)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"/ID \[\s*<[0-9A-Fa-f]+>\s*<[0-9A-Fa-f]+>\s*\]"#, with: "/ID []", options: .regularExpression)
        return text
    }

    private func expectSameBytes(_ request: PDFExportRequest, as expected: Data?, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(expected != nil, sourceLocation: sourceLocation)
        #expect(masked(request.data) == masked(expected ?? Data()), sourceLocation: sourceLocation)
        #expect(PDFDocument(data: request.data)?.pageCount == PDFDocument(data: expected ?? Data())?.pageCount, sourceLocation: sourceLocation)
    }

    // MARK: - One request per document, the exporter's bytes under the Mac's file name

    @Test func scheduleCalendarIsTheCalendarExportersOutput() throws {
        let project = project
        let (start, end) = range
        let request = try PDFExport.scheduleCalendar(project: project, startDate: start, endDate: end)
        #expect(request.kind == .scheduleCalendar)
        #expect(request.fileName == "The_Long_Way_Home_Calendar.pdf")
        expectSameBytes(request, as: PDFExporter.generatePDF(
            shootDays: project.shootDays, projectTitle: project.projectTitle, allScenes: project.allScenes, startDate: start, endDate: end))
    }

    @Test func monthCalendarIsTheMonthExportersOutputWithItsOptions() throws {
        let project = project
        var options = MonthPDFOptions.default
        options.includeEstimatedTime = true
        let request = try PDFExport.monthCalendar(project: project, month: PDFFixture.novemberDate(day: 12), options: options)
        #expect(request.kind == .monthCalendar)
        #expect(request.fileName == "Calendar_2026_11.pdf")
        expectSameBytes(request, as: PDFExporter.generateMonthPDF(
            month: PDFFixture.novemberDate(day: 12), shootDays: project.shootDays, projectTitle: project.projectTitle,
            productionInfo: project.productionInfo!, palette: project.resolvedPalette, options: options))
    }

    @Test func stripScheduleIsTheStripboardExportersOutputWithTheProjectsPalette() throws {
        let project = project
        let request = try PDFExport.stripSchedule(project: project)
        #expect(request.kind == .stripSchedule)
        #expect(request.fileName == "The_Long_Way_Home_StripSchedule.pdf")
        expectSameBytes(request, as: StripboardPDFExporter.generatePDF(
            shootDays: project.shootDays, projectTitle: project.projectTitle, productionInfo: project.productionInfo!, palette: project.resolvedPalette))
        // The bytes carry the project's palette, not the standard one.
        let standard = StripboardPDFExporter.generatePDF(
            shootDays: project.shootDays, projectTitle: project.projectTitle, productionInfo: project.productionInfo!, palette: .standard)
        #expect(masked(request.data) != masked(standard ?? Data()))
    }

    @Test func shootingScheduleIsTheWholeScheduleOrTheGivenDays() {
        let project = project
        let whole = PDFExport.shootingSchedule(project: project)
        #expect(whole.kind == .shootingSchedule)
        #expect(whole.fileName == "The_Long_Way_Home_Shooting_Schedule.pdf")
        expectSameBytes(whole, as: ShootingSchedulePDFExporter.generatePDF(
            shootDays: project.shootDays, projectTitle: project.projectTitle, productionInfo: project.productionInfo!, palette: project.resolvedPalette))

        let oneDay = PDFExport.shootingSchedule(project: project, days: [project.shootDays[2]])
        expectSameBytes(oneDay, as: ShootingSchedulePDFExporter.generatePDF(
            shootDays: [project.shootDays[2]], projectTitle: project.projectTitle, productionInfo: project.productionInfo!, palette: project.resolvedPalette))
        #expect(masked(oneDay.data) != masked(whole.data))
    }

    @Test func daysOutOfDaysIsTheDOODExportersOutputWithTheHoldToggle() throws {
        let project = project
        let request = try PDFExport.daysOutOfDays(project: project, includeHold: false)
        #expect(request.kind == .daysOutOfDays)
        #expect(request.fileName == "The_Long_Way_Home_DOoD.pdf")
        expectSameBytes(request, as: DaysOutOfDaysExporter.generatePDF(
            shootDays: project.shootDays, projectTitle: project.projectTitle, productionInfo: project.productionInfo!, includeHold: false))
    }

    @Test func breakdownsAreTheBreakdownExportersOutput() throws {
        let project = project
        let request = try PDFExport.breakdowns(project: project)
        #expect(request.kind == .breakdowns)
        #expect(request.fileName == "The_Long_Way_Home_Breakdowns.pdf")
        expectSameBytes(request, as: BreakdownExporter.generatePDF(
            shootDays: project.shootDays, allScenes: project.allScenes, projectTitle: project.projectTitle))
    }

    @Test func callSheetIsTheCallSheetExportersOutputNumberedAmongTheShootDays() throws {
        var project = project
        project.shootDays[3] = PDFFixture.callSheetDay
        let day = project.shootDays[3]
        let request = try PDFExport.callSheet(project: project, day: day)
        #expect(request.kind == .callSheet)
        #expect(request.fileName == "CallSheet_\(formattedDate(day.date).replacingOccurrences(of: " ", with: "_")).pdf")
        let numbers = productionDayNumbers(for: project.shootDays)
        expectSameBytes(request, as: CallSheetExporter.generatePDF(
            shootDay: day, productionInfo: project.productionInfo!, projectTitle: project.projectTitle,
            dayNumber: numbers[day.id], totalProductionDays: numbers.values.max() ?? 0))
        // Day 3 of the fixture's five: the number came from the project, not the day alone.
        #expect(numbers[day.id] == 3)
        #expect(pdfFullText(PDFDocument(data: request.data)!).contains("CALL SHEET # 03"))
    }

    // MARK: - File names

    @Test func projectWideNamesReplaceTheCharactersFilesRefuses() throws {
        var project = project
        project.projectTitle = "Long Way: Home/Part 2?"
        #expect(try PDFExport.stripSchedule(project: project).fileName == "Long_Way__Home_Part_2__StripSchedule.pdf")
        #expect(try PDFExport.breakdowns(project: project).fileName == "Long_Way__Home_Part_2__Breakdowns.pdf")
        #expect(try PDFExport.daysOutOfDays(project: project, includeHold: true).fileName == "Long_Way__Home_Part_2__DOoD.pdf")
        #expect(try PDFExport.scheduleCalendar(project: project, startDate: range.0, endDate: range.1).fileName == "Long_Way__Home_Part_2__Calendar.pdf")
    }

    @Test func anUntitledProjectExportsAsMovieSchedule() throws {
        var project = project
        project.projectTitle = ""
        #expect(try PDFExport.stripSchedule(project: project).fileName == "MovieSchedule_StripSchedule.pdf")
        #expect(PDFExport.shootingSchedule(project: project).fileName == "Shooting_Schedule.pdf")
    }

    // MARK: - Failures, worded for the alert

    @Test func aScheduleWithNoScenesHasNoStripScheduleOrBreakdowns() {
        let empty = ProjectData(allScenes: [], shootDays: [ShootDay(date: PDFFixture.novemberDate(day: 2))], projectTitle: "Empty")
        #expect(throws: PDFExportError(message: "Couldn't generate a strip schedule PDF — schedule at least one scene first.")) {
            try PDFExport.stripSchedule(project: empty)
        }
        #expect(throws: PDFExportError(message: "Couldn't generate scene breakdowns — add some scenes first.")) {
            try PDFExport.breakdowns(project: empty)
        }
    }

    @Test func aScheduleWithNoCastHasNoDaysOutOfDays() {
        var scene = PDFFixture.makeScene(1)
        scene.cast = []
        let noCast = ProjectData(allScenes: [], shootDays: [ShootDay(date: PDFFixture.novemberDate(day: 2), scenes: [scene])], projectTitle: "No cast")
        #expect(throws: PDFExportError(message: "Couldn't generate a Days Out of Days report — add cast to your scenes and Production Setup first.")) {
            try PDFExport.daysOutOfDays(project: noCast, includeHold: true)
        }
    }

    // MARK: - The mask

    @Test func theMaskHidesOnlyTheTimeDerivedBytes() {
        let project = project
        let a = masked(BreakdownExporter.generatePDF(shootDays: project.shootDays, allScenes: project.allScenes, projectTitle: project.projectTitle)!)
        #expect(!a.contains("CreationDate\n(D:2"))
        #expect(a.contains("/CreationDate (D:0)"))
        #expect(a.contains("/ModDate (D:0)"))
        #expect(a.contains("/ID []"))
        #expect(a.hasPrefix("%PDF"))
        #expect(a.contains("/Producer"))
    }

    // MARK: - The request itself

    @Test func requestsCompareByDocumentNotByPresentation() {
        let a = PDFExportRequest(kind: .breakdowns, fileName: "A.pdf", data: Data([1, 2, 3]))
        let b = PDFExportRequest(kind: .breakdowns, fileName: "A.pdf", data: Data([1, 2, 3]))
        #expect(a == b)
        #expect(a.id != b.id)
        #expect(a != PDFExportRequest(kind: .breakdowns, fileName: "B.pdf", data: Data([1, 2, 3])))
        #expect(a != PDFExportRequest(kind: .callSheet, fileName: "A.pdf", data: Data([1, 2, 3])))
        #expect(a != PDFExportRequest(kind: .breakdowns, fileName: "A.pdf", data: Data([1, 2])))
    }

    @Test func theSharedFileIsTheBytesUnderTheExportName() throws {
        let request = PDFExportRequest(kind: .callSheet, fileName: "CallSheet_Mon_Nov_2.pdf", data: Data("%PDF-1.4 not really".utf8))
        let url = try request.writeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.lastPathComponent == "CallSheet_Mon_Nov_2.pdf")
        #expect(try Data(contentsOf: url) == request.data)
        // A second request for the same document gets its own directory: sending one
        // must not overwrite the other.
        let again = try PDFExportRequest(kind: .callSheet, fileName: "CallSheet_Mon_Nov_2.pdf", data: Data("other".utf8)).writeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: again.deletingLastPathComponent()) }
        #expect(again != url)
        #expect(try Data(contentsOf: url) == request.data)
    }
}

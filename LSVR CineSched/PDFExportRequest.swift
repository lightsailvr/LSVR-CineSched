// PDFExportRequest.swift
// What one PDF export produces before the platform decides where it goes (#23): which
// document it is, the file name the user will see and the exporter's bytes. The Mac
// hands a request to its save panel, iPad, iPhone and Vision Pro to the preview and the
// share sheet (PDFExportPresentation), and both get exactly the same bytes for the same
// project and palette, because `PDFExport` below is the one place the exporters are
// called with the project's values, on every platform. The file names are the ones the
// Mac's save panels have always proposed, `.pdf` included.
//
// `PDFExport` is a pure function of the project (and the per-export parameters the Mac's
// call sites already took: the range pickers' dates, the DOOD's hold toggle, the month
// and its options, the day) to a request or a `PDFExportError` carrying the message the
// alert shows, so the wiring in ContentView+PDFExports.swift decides only where the
// result goes. Tested in PDFExportRequestTests.

import Foundation

// MARK: - Request

/// Nonisolated and `Sendable` (`Transferable` requires it) so the share sheet can write
/// the file off the main actor.
nonisolated struct PDFExportRequest: Identifiable, Sendable {

    /// The six documents (the month calendar counts twice: the whole-range calendar the
    /// Mac's File menu exports and the single month the calendar's own button exports).
    enum Kind: String, CaseIterable {
        case scheduleCalendar
        case monthCalendar
        case stripSchedule
        case shootingSchedule
        case daysOutOfDays
        case breakdowns
        case callSheet

        /// The document's name for the preview's title.
        @MainActor var title: String {
            switch self {
            case .scheduleCalendar: return L("Schedule Calendar")
            case .monthCalendar:    return L("Month Calendar")
            case .stripSchedule:    return L("Strip Schedule")
            case .shootingSchedule: return L("Shooting Schedule")
            case .daysOutOfDays:    return L("Days Out of Days")
            case .breakdowns:       return L("Scene Breakdowns")
            case .callSheet:        return L("Call Sheet")
            }
        }
    }

    /// One presentation per request: a second export of the same document is a new sheet.
    let id = UUID()
    let kind:     Kind
    /// The name the file is saved or shared under, with its `.pdf` extension.
    let fileName: String
    /// The exporter's output, untouched.
    let data:     Data

    init(kind: Kind, fileName: String, data: Data) {
        self.kind     = kind
        self.fileName = fileName
        self.data     = data
    }
}

extension PDFExportRequest: Equatable {
    /// Two requests for the same document with the same bytes are the same export; the
    /// presentation id is not part of it.
    static func == (lhs: PDFExportRequest, rhs: PDFExportRequest) -> Bool {
        lhs.kind == rhs.kind && lhs.fileName == rhs.fileName && lhs.data == rhs.data
    }
}

/// Why an export produced nothing, worded for the alert.
nonisolated struct PDFExportError: Error, Equatable {
    let message: String
}

// MARK: - The exports

enum PDFExport {

    /// The file-name stem every project-wide export starts from.
    static func projectStem(_ projectTitle: String) -> String {
        sanitizeFilename(projectTitle.isEmpty ? "MovieSchedule" : projectTitle)
    }

    /// A file name safe on every file system: the characters Finder and Files refuse
    /// become underscores, and so do spaces.
    static func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// File ▸ Export Schedule to PDF…: the whole production range as a month calendar,
    /// over the range pickers' dates.
    static func scheduleCalendar(project: ProjectData, startDate: Date, endDate: Date) throws(PDFExportError) -> PDFExportRequest {
        guard let data = PDFExporter.generatePDF(
            shootDays:    project.shootDays,
            projectTitle: project.projectTitle,
            allScenes:    project.allScenes,
            startDate:    startDate,
            endDate:      endDate
        ) else {
            throw PDFExportError(message: "Failed to generate schedule PDF.")
        }
        return PDFExportRequest(kind: .scheduleCalendar, fileName: "\(projectStem(project.projectTitle))_Calendar.pdf", data: data)
    }

    /// The calendar's Export Month button, after its options sheet.
    static func monthCalendar(project: ProjectData, month: Date, options: MonthPDFOptions) throws(PDFExportError) -> PDFExportRequest {
        guard let data = PDFExporter.generateMonthPDF(
            month:          month,
            shootDays:      project.shootDays,
            projectTitle:   project.projectTitle,
            productionInfo: project.productionInfo ?? ProductionInfo(),
            palette:        project.resolvedPalette,
            options:        options
        ) else {
            throw PDFExportError(message: "Failed to generate month PDF.")
        }
        return PDFExportRequest(kind: .monthCalendar, fileName: "Calendar_\(formattedDate(month, pattern: "yyyy_MM")).pdf", data: data)
    }

    /// File ▸ Export Strip Schedule to PDF….
    static func stripSchedule(project: ProjectData) throws(PDFExportError) -> PDFExportRequest {
        guard let data = StripboardPDFExporter.generatePDF(
            shootDays:      project.shootDays,
            projectTitle:   project.projectTitle,
            productionInfo: project.productionInfo ?? ProductionInfo(),
            palette:        project.resolvedPalette
        ) else {
            throw PDFExportError(message: "Couldn't generate a strip schedule PDF — schedule at least one scene first.")
        }
        return PDFExportRequest(kind: .stripSchedule, fileName: "\(projectStem(project.projectTitle))_StripSchedule.pdf", data: data)
    }

    /// The Stripboard's per-day export passes just that day; nil is the whole schedule.
    /// The stem keeps the title's punctuation, as the Mac's panel always has.
    static func shootingSchedule(project: ProjectData, days: [ShootDay]? = nil) -> PDFExportRequest {
        let data = ShootingSchedulePDFExporter.generatePDF(
            shootDays:      days ?? project.shootDays,
            projectTitle:   project.projectTitle,
            productionInfo: project.productionInfo ?? ProductionInfo(),
            palette:        project.resolvedPalette
        )
        let title = project.projectTitle.replacingOccurrences(of: " ", with: "_")
        return PDFExportRequest(kind: .shootingSchedule, fileName: title.isEmpty ? "Shooting_Schedule.pdf" : "\(title)_Shooting_Schedule.pdf", data: data)
    }

    /// File ▸ Export Days Out of Days….
    static func daysOutOfDays(project: ProjectData, includeHold: Bool) throws(PDFExportError) -> PDFExportRequest {
        guard let data = DaysOutOfDaysExporter.generatePDF(
            shootDays:      project.shootDays,
            projectTitle:   project.projectTitle,
            productionInfo: project.productionInfo ?? ProductionInfo(),
            includeHold:    includeHold
        ) else {
            throw PDFExportError(message: "Couldn't generate a Days Out of Days report — add cast to your scenes and Production Setup first.")
        }
        return PDFExportRequest(kind: .daysOutOfDays, fileName: "\(projectStem(project.projectTitle))_DOoD.pdf", data: data)
    }

    /// File ▸ Export Scene Breakdowns….
    static func breakdowns(project: ProjectData) throws(PDFExportError) -> PDFExportRequest {
        guard let data = BreakdownExporter.generatePDF(
            shootDays:    project.shootDays,
            allScenes:    project.allScenes,
            projectTitle: project.projectTitle
        ) else {
            throw PDFExportError(message: "Couldn't generate scene breakdowns — add some scenes first.")
        }
        return PDFExportRequest(kind: .breakdowns, fileName: "\(projectStem(project.projectTitle))_Breakdowns.pdf", data: data)
    }

    /// One day's call sheet, numbered among the project's shoot days.
    static func callSheet(project: ProjectData, day: ShootDay) throws(PDFExportError) -> PDFExportRequest {
        let dayNumbers = productionDayNumbers(for: project.shootDays)
        guard let data = CallSheetExporter.generatePDF(
            shootDay:            day,
            productionInfo:      project.productionInfo ?? ProductionInfo(),
            projectTitle:        project.projectTitle,
            dayNumber:           dayNumbers[day.id],
            totalProductionDays: dayNumbers.values.max() ?? 0
        ) else {
            throw PDFExportError(message: "Failed to generate call sheet PDF.")
        }
        return PDFExportRequest(kind: .callSheet, fileName: "\(sanitizeFilename("CallSheet_\(formattedDate(day.date))")).pdf", data: data)
    }
}

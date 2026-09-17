// ContentView+PDFExports.swift
// The "generate a PDF, then ask where to save it" actions behind the File menu, the
// calendar's Export Month button, and the call-sheet / shooting-schedule buttons on the
// two schedule views. Every exporter call site in the app lives here. These panels stay
// on the Mac (#8): a PDF is an export, not the document.
//
// Every exporter draws through PDFCanvas, so this builds on every platform; the save
// panel it hands the bytes to is the `FilePanels` seam, inert off the Mac until the
// share sheet of milestone 3 (#23) replaces it there.

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {

    // MARK: - PDF exports

    func showSchedulePDFSavePanel() {
        guard let pdfData = PDFExporter.generatePDF(
            shootDays: shootDays,
            projectTitle: projectTitle,
            allScenes: allScenes,
            startDate: startDate,
            endDate: endDate
        ) else {
            alertMessage = "Failed to generate schedule PDF."
            showingAlert = true
            return
        }
        showPDFSavePanel(
            data: pdfData,
            defaultName: sanitizeFilename("\(projectTitle.isEmpty ? "MovieSchedule" : projectTitle)_Calendar")
        )
    }

    func showStripboardPDFSavePanel() {
        guard let pdfData = StripboardPDFExporter.generatePDF(
            shootDays: shootDays,
            projectTitle: projectTitle,
            productionInfo: productionInfo
        ) else {
            alertMessage = "Couldn't generate a strip schedule PDF — schedule at least one scene first."
            showingAlert = true
            return
        }
        showPDFSavePanel(
            data: pdfData,
            defaultName: sanitizeFilename("\(projectTitle.isEmpty ? "MovieSchedule" : projectTitle)_StripSchedule")
        )
    }

    func showDaysOutOfDaysPDFSavePanel() {
        guard let pdfData = DaysOutOfDaysExporter.generatePDF(
            shootDays: shootDays,
            projectTitle: projectTitle,
            productionInfo: productionInfo,
            includeHold: includeHoldInDOOD
        ) else {
            alertMessage = "Couldn't generate a Days Out of Days report — add cast to your scenes and Production Setup first."
            showingAlert = true
            return
        }
        showPDFSavePanel(
            data: pdfData,
            defaultName: sanitizeFilename("\(projectTitle.isEmpty ? "MovieSchedule" : projectTitle)_DOoD")
        )
    }

    func showBreakdownPDFSavePanel() {
        guard let pdfData = BreakdownExporter.generatePDF(
            shootDays: shootDays,
            allScenes: allScenes,
            projectTitle: projectTitle
        ) else {
            alertMessage = "Couldn't generate scene breakdowns — add some scenes first."
            showingAlert = true
            return
        }
        showPDFSavePanel(
            data: pdfData,
            defaultName: sanitizeFilename("\(projectTitle.isEmpty ? "MovieSchedule" : projectTitle)_Breakdowns")
        )
    }

    func showCallSheetPDFSavePanel(for day: ShootDay) {
        let dayNumbers = productionDayNumbers(for: shootDays)
        guard let pdfData = CallSheetExporter.generatePDF(
            shootDay: day,
            productionInfo: productionInfo,
            projectTitle: projectTitle,
            dayNumber: dayNumbers[day.id],
            totalProductionDays: dayNumbers.values.max() ?? 0
        ) else {
            alertMessage = "Failed to generate call sheet PDF."
            showingAlert = true
            return
        }
        showPDFSavePanel(
            data: pdfData,
            defaultName: sanitizeFilename("CallSheet_\(formattedDate(day.date))")
        )
    }

    /// The Stripboard's per-day export passes just that day; the toolbar passes nothing
    /// and gets the whole schedule.
    func showShootingSchedulePDFSavePanel(for targetDays: [ShootDay]? = nil) {
        let daysToExport = targetDays ?? shootDays
        let pdfData = ShootingSchedulePDFExporter.generatePDF(
            shootDays: daysToExport,
            projectTitle: projectTitle,
            productionInfo: productionInfo
        )
        let baseName = projectTitle.isEmpty ? "Shooting_Schedule" : projectTitle.replacingOccurrences(of: " ", with: "_")
        FilePanels.chooseSaveLocation(
            title: L("Export Plan de Rodaje (PDF)"),
            defaultName: "\(baseName)_Shooting_Schedule.pdf",
            allowedTypes: [.pdf],
            directory: nil
        ) { url in
            do {
                try pdfData.write(to: url)
            } catch {
                alertMessage = "Error saving Shooting Schedule PDF: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    /// The calendar's Export Month button, after the options sheet has been confirmed.
    func exportMonthPDF(month: Date, options: MonthPDFOptions) {
        guard let pdfData = PDFExporter.generateMonthPDF(
            month: month,
            shootDays: shootDays,
            projectTitle: projectTitle,
            productionInfo: productionInfo,
            options: options
        ) else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy_MM"
        FilePanels.chooseSaveLocation(
            title: L("Export Month (PDF)"),
            defaultName: "Calendar_\(df.string(from: month)).pdf",
            allowedTypes: [.pdf],
            directory: nil
        ) { url in
            try? pdfData.write(to: url)
        }
    }

    private func showPDFSavePanel(data: Data, defaultName: String) {
        FilePanels.chooseSaveLocation(
            title: "Export PDF",
            prompt: "Export",
            defaultName: defaultName,
            allowedTypes: [.pdf],
            directory: defaultPanelDirectory
        ) { url in
            do {
                try data.write(to: url)
                alertMessage = "PDF exported to: \(url.lastPathComponent)"
                showingAlert = true
            } catch {
                alertMessage = "Failed to export PDF: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

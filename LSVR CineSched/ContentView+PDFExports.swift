// ContentView+PDFExports.swift
// The "generate a PDF, then hand it over" actions behind the File menu, the iPad
// toolbar's Export menu, the calendar's Export Month button, and the call-sheet /
// shooting-schedule buttons on the two schedule views and the day inspector. Every
// exporter call site in the app lives here, and every one is the same two steps: build
// the `PDFExportRequest` (PDFExportRequest.swift, the exporter's bytes under the file's
// name) and deliver it. Where it goes is the `PlatformExportPresentation` seam (#23): the
// Mac's save panel through `FilePanels` (#8: a PDF is an export, not the document), or
// the preview sheet with Share on the iPad, the iPhone and the Vision Pro
// (`pdfExportPresentation`, hung off the editor's root in `applyExportPresentation`).
//
// The `show…SavePanel` names predate the preview and are what the inspector and the
// schedule views call; they now show whichever presentation the platform has.

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {

    // MARK: - Where an export goes

    /// The preview sheet (iPad, iPhone, Vision Pro) or the Mac's save panel.
    private func deliver(_ request: PDFExportRequest, savePanel: (PDFExportRequest) -> Void) {
        if PlatformExportPresentation.previewsExports {
            exportPreview = request
        } else {
            savePanel(request)
        }
    }

    private func report(_ error: PDFExportError) {
        alertMessage = error.message
        showingAlert = true
    }

    /// The preview sheet, attached to the editor's root on every platform (only the
    /// platforms that preview ever set `exportPreview`).
    func applyExportPresentation<Content: View>(_ content: Content) -> some View {
        content.pdfExportPresentation($exportPreview)
    }

    // MARK: - Panel helpers

    /// The folder to default file panels to: beside the project, when it has been saved.
    var defaultPanelDirectory: URL? {
        document.fileURL?.deletingLastPathComponent()
    }

    // MARK: - PDF exports

    func showSchedulePDFSavePanel() {
        do {
            deliver(try PDFExport.scheduleCalendar(project: document.project, startDate: startDate, endDate: endDate), savePanel: showPDFSavePanel)
        } catch {
            report(error)
        }
    }

    func showStripboardPDFSavePanel() {
        do {
            deliver(try PDFExport.stripSchedule(project: document.project), savePanel: showPDFSavePanel)
        } catch {
            report(error)
        }
    }

    func showDaysOutOfDaysPDFSavePanel() {
        do {
            deliver(try PDFExport.daysOutOfDays(project: document.project, includeHold: includeHoldInDOOD), savePanel: showPDFSavePanel)
        } catch {
            report(error)
        }
    }

    func showBreakdownPDFSavePanel() {
        do {
            deliver(try PDFExport.breakdowns(project: document.project), savePanel: showPDFSavePanel)
        } catch {
            report(error)
        }
    }

    func showCallSheetPDFSavePanel(for day: ShootDay) {
        do {
            deliver(try PDFExport.callSheet(project: document.project, day: day), savePanel: showPDFSavePanel)
        } catch {
            report(error)
        }
    }

    /// The Stripboard's per-day export passes just that day; the Export menu passes
    /// nothing and gets the whole schedule.
    func showShootingSchedulePDFSavePanel(for targetDays: [ShootDay]? = nil) {
        let request = PDFExport.shootingSchedule(project: document.project, days: targetDays)
        deliver(request) { request in
            FilePanels.chooseSaveLocation(
                title: L("Export Plan de Rodaje (PDF)"),
                defaultName: request.fileName,
                allowedTypes: [.pdf],
                directory: nil
            ) { url in
                do {
                    try request.data.write(to: url)
                } catch {
                    alertMessage = "Error saving Shooting Schedule PDF: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    /// The calendar's Export Month button, after the options sheet has been confirmed.
    func exportMonthPDF(month: Date, options: MonthPDFOptions) {
        guard let request = try? PDFExport.monthCalendar(project: document.project, month: month, options: options) else { return }
        deliver(request) { request in
            FilePanels.chooseSaveLocation(
                title: L("Export Month (PDF)"),
                defaultName: request.fileName,
                allowedTypes: [.pdf],
                directory: nil
            ) { url in
                try? request.data.write(to: url)
            }
        }
    }

    /// The File menu exports' panel: beside the project, with a confirmation.
    private func showPDFSavePanel(_ request: PDFExportRequest) {
        FilePanels.chooseSaveLocation(
            title: "Export PDF",
            prompt: "Export",
            defaultName: request.fileName,
            allowedTypes: [.pdf],
            directory: defaultPanelDirectory
        ) { url in
            do {
                try request.data.write(to: url)
                alertMessage = "PDF exported to: \(url.lastPathComponent)"
                showingAlert = true
            } catch {
                alertMessage = "Failed to export PDF: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// PhoneExports.swift
// Every PDF export call site of the iPhone editor (#28, #26, the M4 review), the phone's
// counterpart of `ContentView+PDFExports.swift`: one `PhoneExports` value `PhoneEditor`
// wires (the project to draw, where a request goes — the preview sheet's `exportPreview` —
// and where a failure's message goes — the Export Failed alert) and hands the Production
// tab for its six documents and `PhoneDayEdits` for the Day screen's and the call sheet
// editor's Export Call Sheet PDF. Each function is the same two steps as the Mac's: build
// the `PDFExportRequest` (PDFExportRequest.swift, the exporter's bytes under the file's
// name) and deliver it. Nothing else on the phone calls `PDFExport`, and nothing here
// checks the platform: the phone always previews (`PlatformExportPresentation` decides
// for `ContentView`; this editor exists only where it previews).
//
// `deliver` takes an untyped `throws`: a closure literal's thrown type is inferred as
// `any Error`, not the exporter's typed one (learnings 2026-09-21 #28).
//
// Platform-free; the Mac compiles it and never runs it.

import Foundation

struct PhoneExports {
    /// The project as it is when the export runs.
    let project: () -> ProjectData
    /// Where a request goes: the preview sheet with Share (`PhoneEditor.exportPreview`).
    let present: (PDFExportRequest) -> Void
    /// Where a failure's message goes (`PDFExportError.message`).
    let fail:    (String) -> Void

    // MARK: - The documents

    func scheduleCalendar(startDate: Date, endDate: Date) {
        deliver { try PDFExport.scheduleCalendar(project: project(), startDate: startDate, endDate: endDate) }
    }

    func monthCalendar(month: Date, options: MonthPDFOptions) {
        deliver { try PDFExport.monthCalendar(project: project(), month: month, options: options) }
    }

    func stripSchedule() {
        deliver { try PDFExport.stripSchedule(project: project()) }
    }

    func shootingSchedule() {
        deliver { PDFExport.shootingSchedule(project: project()) }
    }

    func daysOutOfDays(includeHold: Bool) {
        deliver { try PDFExport.daysOutOfDays(project: project(), includeHold: includeHold) }
    }

    func breakdowns() {
        deliver { try PDFExport.breakdowns(project: project()) }
    }

    /// The call sheet of `day` (the Day screen's row, the call sheet editor's Export PDF).
    func callSheet(day: ShootDay) {
        deliver { try PDFExport.callSheet(project: project(), day: day) }
    }

    // MARK: - Where an export goes

    private func deliver(_ make: () throws -> PDFExportRequest) {
        do {
            present(try make())
        } catch let error as PDFExportError {
            fail(error.message)
        } catch {
            fail(error.localizedDescription)
        }
    }
}

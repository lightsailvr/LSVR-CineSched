// ProductionTab+Exports.swift
// The Production tab's Export section (#28): the six documents as rows — Schedule
// Calendar, Month Calendar (a `Menu` of the months the shoot spans, then the calendar's
// `MonthPDFOptionsSheet` on its `@AppStorage` keys), Strip Schedule, Shooting Schedule,
// Days Out of Days with the Include Hold toggle beside it, Scene Breakdowns — each a call
// into `PhoneExports` (PhoneExports.swift, the phone's one export call site, which builds
// the request and hands it to the editor's preview sheet or its alert). Nothing here
// calls `PDFExport` or an exporter.

import SwiftUI

extension ProductionTab {

    // MARK: - The section

    var exportSection: some View {
        Section {
            actionRow(L("Schedule Calendar"), systemImage: "calendar") {
                exports.scheduleCalendar(startDate: currentRange.lowerBound, endDate: currentRange.upperBound)
            }
            Menu {
                ForEach(project.productionMonths(), id: \.self) { month in
                    Button(formattedDate(month, pattern: "LLLL yyyy")) {
                        activeSheet = .monthOptions(month: month)
                    }
                }
            } label: {
                rowLabel(L("Month Calendar"), systemImage: "calendar.day.timeline.left", detail: L("Choose a month"))
            }
            .disabled(shootDays.isEmpty)
            actionRow(L("Strip Schedule"), systemImage: "rectangle.split.3x1") {
                exports.stripSchedule()
            }
            actionRow(L("Shooting Schedule"), systemImage: "doc.text") {
                exports.shootingSchedule()
            }
            actionRow(L("Days Out of Days"), systemImage: "tablecells") {
                exports.daysOutOfDays(includeHold: includeHoldInDOOD)
            }
            Toggle(L("Include Hold Days in DOoD Report"), isOn: $includeHoldInDOOD)
            actionRow(L("Scene Breakdowns"), systemImage: "list.clipboard") {
                exports.breakdowns()
            }
        } header: {
            Text(L("Export"))
        } footer: {
            Text(L("Each export opens a preview you can share, print or save to Files."))
        }
    }

    // MARK: - The month calendar

    /// The calendar's export options, then the month's export.
    func monthOptionsSheet(_ month: Date) -> some View {
        MonthPDFOptionsSheet(
            selectedFields:       monthPDFFields,
            includePageCount:     $monthPDFShowPages,
            includeEstimatedTime: $monthPDFShowTime,
            onCancel:             { activeSheet = nil },
            onExport:             {
                activeSheet = nil
                exportMonth(month)
            }
        )
    }

    private var monthPDFFields: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(monthPDFFieldsRaw) },
            set: { monthPDFFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    private func exportMonth(_ month: Date) {
        let options = MonthPDFOptions(
            fields:               StripboardFieldSettings.decode(monthPDFFieldsRaw),
            includePageCount:     monthPDFShowPages,
            includeEstimatedTime: monthPDFShowTime
        )
        exports.monthCalendar(month: month, options: options)
    }
}

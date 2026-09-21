// SendToDaySheet.swift
// A day picker for the calendar's "Send to Day…" context menu action (#19: one adaptive
// `Form`): lets a selection be moved to a day that isn't currently scrolled into view,
// instead of dragging a strip up or down a long schedule. Uses the same graphical
// month-calendar control as the native date pickers elsewhere in the app; Send is
// enabled only while the picked date is one of the schedule's days. Only the size
// around the form changes per container (`editorContainer`). The iPhone's Swap with Day
// (#25) is the same picker under its own title, subtitle and action, with the day being
// swapped unavailable as a pick; the defaults are the labels the Mac's call sites have
// always shown, which pass nothing new.

import SwiftUI

struct SendToDaySheet: View {
    let shootDays:  [ShootDay]
    let sceneCount: Int
    let title:       String
    let subtitle:    String
    let actionTitle: String
    /// A day the picker offers but the action refuses (Swap with Day's own day); nil for none.
    let unavailableDayID: UUID?
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void

    @State private var selectedDate: Date

    static let sheetSize = EditorSheetSize(width: 400, height: 560, compactDetents: [.large])

    init(shootDays: [ShootDay], sceneCount: Int,
         title: String? = nil, subtitle: String? = nil, actionTitle: String? = nil, unavailableDayID: UUID? = nil,
         onSelect: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) {
        self.shootDays        = shootDays
        self.sceneCount       = sceneCount
        self.title            = title ?? L("Send to Day")
        self.subtitle         = subtitle ?? "\(sceneCount) \(sceneCount == 1 ? L("scene") : L("scenes")) \(L("selected"))"
        self.actionTitle      = actionTitle ?? L("Send")
        self.unavailableDayID = unavailableDayID
        self.onSelect         = onSelect
        self.onCancel         = onCancel
        _selectedDate = State(initialValue: shootDays.first?.date ?? Date())
    }

    private var dateRange: ClosedRange<Date> {
        guard let first = shootDays.first?.date, let last = shootDays.last?.date else {
            let now = Date()
            return now...now
        }
        return first...last
    }

    private var matchedDay: ShootDay? {
        let cal = Calendar.current
        return shootDays.first { cal.isDate($0.date, inSameDayAs: selectedDate) }
    }

    /// The day the action may act on: the matched day, unless it is the unavailable one.
    private var targetDay: ShootDay? {
        guard let day = matchedDay, day.id != unavailableDayID else { return nil }
        return day
    }

    var body: some View {
        EditorChrome {
            EditorTitle(title: title, subtitle: subtitle)
        } content: {
            Form {
                Section {
                    DatePicker(
                        L("Day"),
                        selection: $selectedDate,
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                } footer: {
                    if let day = matchedDay, day.id == unavailableDayID {
                        Text(L("Pick a different day"))
                    } else if let day = matchedDay {
                        Text(day.scenes.isEmpty
                             ? L("No scenes currently scheduled that day")
                             : "\(day.scenes.count) \(day.scenes.count == 1 ? L("scene") : L("scenes")) \(L("already scheduled that day"))")
                    } else {
                        Text(L("Pick a day of the schedule"))
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Button(L("Cancel")) { onCancel() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(actionTitle) {
                    if let day = targetDay { onSelect(day.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetDay == nil)
            }
        }
        .editorContainer(Self.sheetSize)
    }
}

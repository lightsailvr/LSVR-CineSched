// SendToDaySheet.swift
// A day picker for the calendar's "Send to Day…" context menu action (#19: one adaptive
// `Form`): lets a selection be moved to a day that isn't currently scrolled into view,
// instead of dragging a strip up or down a long schedule. Uses the same graphical
// month-calendar control as the native date pickers elsewhere in the app; Send is
// enabled only while the picked date is one of the schedule's days. Only the size
// around the form changes per container (`editorContainer`). The picker has two modes
// (`Mode`): Send to Day for a number of scenes (the Mac's, and the default of the
// initializer the Mac's call sites have always used) and the iPhone's Swap with Day (#25),
// the same picker titled for the exchange, with the day being swapped named in the
// subtitle and unavailable as a pick.

import SwiftUI

struct SendToDaySheet: View {

    /// What the picked day is for; the title, subtitle and action follow.
    enum Mode: Hashable {
        /// Send to Day: `sceneCount` scenes land at the end of the picked day.
        case send(sceneCount: Int)
        /// Swap with Day: the picked day exchanges everything with the day `excluding`,
        /// which the picker offers but the action refuses.
        case swap(excluding: UUID)
    }

    let shootDays: [ShootDay]
    let mode:      Mode
    let onSelect:  (UUID) -> Void
    let onCancel:  () -> Void

    @State private var selectedDate: Date

    static let sheetSize = EditorSheetSize(width: 400, height: 560, compactDetents: [.large])

    /// The Mac's initializer: Send to Day for `sceneCount` scenes.
    init(shootDays: [ShootDay], sceneCount: Int, onSelect: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) {
        self.init(shootDays: shootDays, mode: .send(sceneCount: sceneCount), onSelect: onSelect, onCancel: onCancel)
    }

    init(shootDays: [ShootDay], mode: Mode, onSelect: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) {
        self.shootDays = shootDays
        self.mode      = mode
        self.onSelect  = onSelect
        self.onCancel  = onCancel
        _selectedDate  = State(initialValue: shootDays.first?.date ?? Date())
    }

    // MARK: - The mode's words

    private var title: String {
        switch mode {
        case .send: return L("Send to Day")
        case .swap: return L("Swap with Day")
        }
    }

    private var subtitle: String {
        switch mode {
        case .send(let sceneCount):
            return "\(sceneCount) \(sceneCount == 1 ? L("scene") : L("scenes")) \(L("selected"))"
        case .swap(let dayID):
            let dayNumbers = productionDayNumbers(for: shootDays)
            let name = shootDays.first { $0.id == dayID }.map { DaySummary.label(dayNumber: dayNumbers[$0.id], date: $0.date) } ?? L("this day")
            return "\(L("Exchange everything on")) \(name) \(L("with the day you pick"))"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .send: return L("Send")
        case .swap: return L("Swap")
        }
    }

    /// The day the picker offers but the action refuses (Swap with Day's own day).
    private var unavailableDayID: UUID? {
        if case .swap(let dayID) = mode { return dayID }
        return nil
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

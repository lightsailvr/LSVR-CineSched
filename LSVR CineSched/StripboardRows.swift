// StripboardRows.swift
// Decides which rows the Stripboard draws for a production's day list.
//
// Every date in the production range has a ShootDay, so a shoot with a block in
// November and another in January would otherwise render weeks of empty day sections
// between them. This file folds each run of consecutive empty days into a single
// StripboardGap row that the view can draw as one slim strip and expand on demand.
// It is a pure function over the model so the grouping rules are unit-testable
// without a view.

import Foundation

// MARK: - Gap

/// A run of consecutive days with no script scenes, shown collapsed as one row.
struct StripboardGap: Identifiable {
    /// The id of the first day in the run. Stable as long as that day stays empty.
    let id: UUID
    /// The days in the run, each paired with its index into the full `shootDays` array
    /// (the view needs the index for auto-meal sync and the editor sheet).
    let days: [(index: Int, day: ShootDay)]

    var dayCount:      Int   { days.count }
    var firstDate:     Date  { days.first!.day.date }
    var lastDate:      Date  { days.last!.day.date }
    var weekendCount:  Int   { days.filter { isWeekend($0.day.date) }.count }
    var blackoutCount: Int   { days.filter { $0.day.isBlackout }.count }
    var dayIDs:        Set<UUID> { Set(days.map { $0.day.id }) }
}

// MARK: - Row

enum StripboardRow: Identifiable {
    case day(index: Int, day: ShootDay)
    case gap(StripboardGap)

    var id: UUID {
        switch self {
        case .day(_, let day): return day.id
        case .gap(let gap):    return gap.id
        }
    }
}

// MARK: - Grouping

/// True when the day has nothing the Stripboard would draw as a strip: no scenes at
/// all, or only calendar events (which the board never shows).
func stripboardDayIsEmpty(_ day: ShootDay) -> Bool {
    !day.scenes.contains { !$0.isCalendarEvent }
}

/// Builds the Stripboard's row list.
///
/// - `showAllDays`: when true every day is a `.day` row, including empty ones, so the
///   board reads like a full calendar. When false, runs of empty days collapse into
///   `.gap` rows.
/// - `expandedDayIDs`: a gap is drawn expanded (as individual `.day` rows) when *any* of
///   its days is in this set. Keying on day ids rather than gap ids means that dropping a
///   scene into the middle of an expanded gap, which splits it in two, leaves both halves
///   expanded instead of silently collapsing the second one.
func stripboardRows(for shootDays: [ShootDay],
                    showAllDays: Bool,
                    expandedDayIDs: Set<UUID>) -> [StripboardRow] {
    if showAllDays {
        return shootDays.enumerated().map { .day(index: $0.offset, day: $0.element) }
    }

    var rows: [StripboardRow] = []
    var run:  [(index: Int, day: ShootDay)] = []

    func flushRun() {
        guard !run.isEmpty else { return }
        let gap = StripboardGap(id: run[0].day.id, days: run)
        if run.contains(where: { expandedDayIDs.contains($0.day.id) }) {
            rows.append(contentsOf: run.map { .day(index: $0.index, day: $0.day) })
        } else {
            rows.append(.gap(gap))
        }
        run = []
    }

    for (index, day) in shootDays.enumerated() {
        if stripboardDayIsEmpty(day) {
            run.append((index, day))
        } else {
            flushRun()
            rows.append(.day(index: index, day: day))
        }
    }
    flushRun()
    return rows
}

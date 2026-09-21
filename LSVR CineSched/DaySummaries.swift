// DaySummaries.swift
// The iPhone's pure summaries (#24): what the Days list header and the Day screen header
// say about one day, the week strip around a date, where Today lands and how a date
// becomes a row to scroll to. Plain values and free functions over `[ShootDay]`, so the
// views draw them and `DaySummariesTests` checks them without a view. Every function
// takes the calendar it should count days in; the views pass `.current`, the tests a
// fixed UTC one.
//
// Weeks are Sunday-first, a lineage fact (CONTEXT.md): the strip finds its Sunday from
// the Gregorian weekday component (1 = Sunday), never from the calendar's
// `firstWeekday`, so a locale that starts weeks on Monday changes nothing.

import Foundation

// MARK: - Day summary

/// One day as a header reads it: its production day number (nil for an empty or a typed
/// day, as `productionDayNumbers` says), its date, type, script scene count, total pages
/// in eighths, general call, event count, note and whether a call sheet has been filled
/// in. Banners and auto-meals are strips but not scenes, so they count in `stripCount`
/// only; calendar events count in `eventCount` only.
struct DaySummary: Equatable, Identifiable {
    let dayID:               UUID
    let date:                Date
    let productionDayNumber: Int?
    let dayType:             DayType
    /// Script scenes on the day (not banners, not events).
    let sceneCount:          Int
    /// Script scenes and banners: what the strip list draws.
    let stripCount:          Int
    /// The script scenes' page lengths, in eighths.
    let totalEighths:        Int
    /// The call sheet's general call as typed, else the time the cascade starts at
    /// (`dayStartMinutes`: the ready-to-shoot time, else 07:30 AM).
    let generalCall:         String
    let eventCount:          Int
    let note:                String
    let hasCallSheet:        Bool

    var id: UUID { dayID }

    init(day: ShootDay, dayNumbers: [UUID: Int]) {
        let scriptScenes = day.scenes.filter { !$0.isBanner && !$0.isCalendarEvent }
        dayID               = day.id
        date                = day.date
        productionDayNumber = dayNumbers[day.id]
        dayType             = day.dayType
        sceneCount          = scriptScenes.count
        stripCount          = day.scenes.filter { !$0.isCalendarEvent }.count
        totalEighths        = scriptScenes.reduce(0) { $0 + $1.duration }
        generalCall         = day.callSheet.generalCallTime.isEmpty
                                ? formatMinutesToClock(dayStartMinutes(for: day))
                                : day.callSheet.generalCallTime
        eventCount          = day.scenes.filter { $0.isCalendarEvent }.count
        note                = day.dayNote
        hasCallSheet        = day.hasCallSheetData
    }

    /// The pages as the board prints them ("1 7/8", "0").
    var pagesText: String { FractionParser.formatEighths(totalEighths) }

    /// "Day 3 · Mon Nov 2", or the date alone for a day with no production day number:
    /// how the phone names a day wherever one is named in a line (the Today control, the
    /// Send to Day and Add Scenes pickers, a search result).
    var label: String { Self.label(dayNumber: productionDayNumber, date: date) }

    static func label(dayNumber: Int?, date: Date) -> String {
        (dayNumber.map { "\(L("Day")) \($0) · " } ?? "") + formattedDate(date)
    }
}

// MARK: - Week strip

/// One cell of the week strip: a date, the shoot day on it if the production range
/// covers it, and what the cell shows (scene count, event count, day type, today).
struct WeekStripDay: Identifiable, Equatable {
    /// The start of the day in the strip's calendar.
    let date:       Date
    /// The shoot day dated `date`, nil when the range does not include it.
    let day:        ShootDay?
    /// Script scenes on the day; 0 for an absent day.
    let sceneCount: Int
    /// Calendar events on the day; 0 for an absent day.
    let eventCount: Int
    /// The day's type; nil for an absent day.
    let dayType:    DayType?
    let isToday:    Bool

    var id: Date { date }
}

/// The seven days, Sunday first, of the week containing a reference date, each paired
/// with the shoot day on it. `previousWeekDate` and `nextWeekDate` are the Sundays the
/// strip pages to.
struct WeekStrip: Equatable {
    /// The Sunday the strip starts on (the start of that day).
    let start: Date
    let days:  [WeekStripDay]
    let previousWeekDate: Date
    let nextWeekDate:     Date

    /// The start of the Sunday that begins the week containing `date`, from the Gregorian
    /// weekday component (1 = Sunday) so the calendar's `firstWeekday` plays no part.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day     = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
    }

    init(containing reference: Date, shootDays: [ShootDay], today: Date, calendar: Calendar) {
        let sunday     = Self.weekStart(containing: reference, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)

        start = sunday
        days  = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: sunday) ?? sunday
            let day  = shootDays.first { calendar.isDate($0.date, inSameDayAs: date) }
            return WeekStripDay(
                date:       date,
                day:        day,
                sceneCount: day?.scenes.filter { !$0.isBanner && !$0.isCalendarEvent }.count ?? 0,
                eventCount: day?.scenes.filter { $0.isCalendarEvent }.count ?? 0,
                dayType:    day?.dayType,
                isToday:    calendar.isDate(date, inSameDayAs: todayStart)
            )
        }
        previousWeekDate = calendar.date(byAdding: .day, value: -7, to: sunday) ?? sunday
        nextWeekDate     = calendar.date(byAdding: .day, value:  7, to: sunday) ?? sunday
    }
}

// MARK: - Today

/// The day the Today control lands on: the day dated `now` when the range has one, else
/// the first day after `now`, else the last day of the range; nil for a project with no
/// days. Works in date order whatever the array's order.
func todayTarget(in shootDays: [ShootDay], now: Date, calendar: Calendar) -> UUID? {
    guard !shootDays.isEmpty else { return nil }
    let today = calendar.startOfDay(for: now)
    if let sameDay = shootDays.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
        return sameDay.id
    }
    let sorted = shootDays.sorted { $0.date < $1.date }
    if let next = sorted.first(where: { calendar.startOfDay(for: $0.date) > today }) {
        return next.id
    }
    return sorted.last?.id
}

// MARK: - Scroll target

/// A date turned into the Days list row to scroll to: the day's id and whether that day
/// is folded into a collapsed gap right now (the list must expand the gap before the row
/// exists, as the Stripboard's `scrollToDate` does).
struct DayScrollTarget: Equatable {
    let dayID:            UUID
    let isInCollapsedGap: Bool
}

/// The row for `date`, or nil when no shoot day is dated that day. `expandedDayIDs` is
/// the list's open-gap state (`stripboardRows`' `expandedDayIDs`).
func dayScrollTarget(for date: Date, in shootDays: [ShootDay], expandedDayIDs: Set<UUID>, calendar: Calendar) -> DayScrollTarget? {
    guard let day = shootDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return nil }
    let collapsed = stripboardDayIsEmpty(day) && !expandedDayIDs.contains(day.id)
    return DayScrollTarget(dayID: day.id, isInCollapsedGap: collapsed)
}

// ProductionRange.swift
// Changing the production range: regenerate the shoot-day list for new start and end
// dates while keeping everything that was scheduled. A pure edit of `ProjectData`, so the
// Mac editor applies it through the document's `perform` funnel as one undo step (#9)
// and the tests run it directly (`ProductionRangeTests`).
//
// Two behaviours, chosen by the project's shift mode:
//   - merge (shift off): every day keeps what it had; the new range just adds empty days
//     or drops days. Script scenes on a dropped day go back to the Boneyard; call sheets,
//     calendar events, day types and notes on a dropped day stay on that date as an extra
//     day outside the range, so nothing typed is lost.
//   - shift (shift on): everything slides by the offset between the old first scheduled
//     day and the new start, so a travel day the day before Day 1 is still the day before
//     Day 1. Then the same merge rules apply on the shifted dates.
//
// `previewProductionRange` runs the same regeneration on a copy and reports what it
// would do (the day count, the scenes it would send to the Boneyard), for the iPhone's
// confirmation before Update (#28); the Mac applies without one.

import Foundation

/// What a range change would do, before it is applied.
nonisolated struct ProductionRangePreview: Equatable {
    /// Days in the new range (the extra days kept outside it for their events, call
    /// sheets and types are not counted).
    var dayCount:            Int
    /// Script scenes (not banners) that no longer fit a day and would return to the
    /// Boneyard with the rest of their day's strips.
    var displacedSceneCount: Int
    /// Whether everything slides with the start (shift mode on and the start moved), or
    /// stays on its dates (shift off, or the start unchanged): what the confirmation says
    /// happens to the call sheets, events, day types and notes.
    var shifts:              Bool
}

extension ProjectData {

    /// Regenerates `shootDays` for the range `newStart...newEnd` (whole days in
    /// `calendar`), merging or shifting the current schedule into it as described in the
    /// file header. Never drops a script scene: any that no longer fits a day is appended
    /// to `allScenes`.
    mutating func updateProductionRange(from newStart: Date, to newEnd: Date, calendar cal: Calendar = .current) {
        let normNewStart = cal.startOfDay(for: newStart)
        let normNewEnd   = cal.startOfDay(for: newEnd)

        // 1. Bucket everything by date: script scenes, calendar events, call sheets, and day
        //    types/notes. In shift mode all of it slides by the same offset, so a travel day
        //    or a table read the day before Day 1 is still the day before Day 1. Events are
        //    kept separate from script scenes only because they never go to the Boneyard
        //    (step 4). Before this bookkeeping existed, every regenerated day came back with a
        //    blank call sheet and no blackout flag.
        var calendarEventsByDate: [Date: [Scene]] = [:]
        var scriptScenesByDate: [Date: [Scene]] = [:]
        var callSheetsByDate: [Date: CallSheetData] = [:]
        var dayMetaByDate: [Date: (type: DayType, note: String)] = [:]
        // In day order, so the scenes a shorter range sends to the Boneyard arrive there in
        // schedule order rather than however a dictionary happens to iterate.
        var allExistingScriptScenes: [Scene] = []

        for day in shootDays {
            let dayNorm = cal.startOfDay(for: day.date)
            let events = day.scenes.filter { $0.isCalendarEvent }
            let scripts = day.scenes.filter { !$0.isCalendarEvent }
            if !events.isEmpty {
                calendarEventsByDate[dayNorm, default: []].append(contentsOf: events)
            }
            if !scripts.isEmpty {
                scriptScenesByDate[dayNorm, default: []].append(contentsOf: scripts)
                allExistingScriptScenes.append(contentsOf: scripts)
            }
            if day.hasCallSheetData {
                callSheetsByDate[dayNorm] = day.callSheet
            }
            if day.dayType != .shoot || !day.dayNote.isEmpty {
                dayMetaByDate[dayNorm] = (day.dayType, day.dayNote)
            }
        }

        // 2. The shift offset: from the old shooting start (the first day with script
        //    scenes, else the new start) to the new start. Zero unless shift mode is on.
        let dayOffset = shiftDayOffset(toStart: normNewStart, calendar: cal)

        // Re-key a per-date map by the shift offset. Identity when shift mode is off.
        func shifted<T>(_ map: [Date: T]) -> [Date: T] {
            guard dayOffset != 0 else { return map }
            var out: [Date: T] = [:]
            for (date, value) in map {
                if let moved = cal.date(byAdding: .day, value: dayOffset, to: date) {
                    out[cal.startOfDay(for: moved)] = value
                }
            }
            return out
        }
        let scriptsByTarget = shifted(scriptScenesByDate)
        let eventsByTarget  = shifted(calendarEventsByDate)
        let sheetsByTarget  = shifted(callSheetsByDate)
        let metaByTarget    = shifted(dayMetaByDate)

        var updatedDays: [ShootDay] = []
        var scheduledSceneIDs: Set<UUID> = []

        var current = normNewStart
        while current <= normNewEnd {
            var dayScenes: [Scene] = []

            if let sourceScenes = scriptsByTarget[current] {
                dayScenes.append(contentsOf: sourceScenes)
            }

            if let events = eventsByTarget[current] {
                dayScenes.append(contentsOf: events)
            }

            for s in dayScenes where !s.isCalendarEvent {
                scheduledSceneIDs.insert(s.id)
            }

            let meta = metaByTarget[current]
            updatedDays.append(ShootDay(date: current, scenes: dayScenes,
                                        callSheet: sheetsByTarget[current] ?? CallSheetData(),
                                        dayType: meta?.type ?? .shoot, dayNote: meta?.note ?? ""))
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // 3. Preserve calendar events, day types, notes, and call sheets that land outside the
        //    new shoot range (a travel day the week before the shoot starts, say). Script
        //    scenes outside the range go back to the Boneyard in step 4 instead.
        let outsideDates = Set(eventsByTarget.keys).union(metaByTarget.keys).union(sheetsByTarget.keys)
        for outsideDate in outsideDates where outsideDate < normNewStart || outsideDate > normNewEnd {
            if !updatedDays.contains(where: { cal.isDate($0.date, inSameDayAs: outsideDate) }) {
                let meta = metaByTarget[outsideDate]
                updatedDays.append(ShootDay(date: outsideDate,
                                            scenes: eventsByTarget[outsideDate] ?? [],
                                            callSheet: sheetsByTarget[outsideDate] ?? CallSheetData(),
                                            dayType: meta?.type ?? .shoot, dayNote: meta?.note ?? ""))
            }
        }

        // 4. ANTI-LOSS SAFETY NET: Any script scenes that didn't fit into the new schedule
        // are returned to allScenes (Boneyard) so they are NEVER permanently lost!
        var boneyardIDs = Set(allScenes.map(\.id))
        for scene in allExistingScriptScenes where !scheduledSceneIDs.contains(scene.id) && !boneyardIDs.contains(scene.id) {
            allScenes.append(scene)
            boneyardIDs.insert(scene.id)
        }

        updatedDays.sort { $0.date < $1.date }
        shootDays = updatedDays
    }

    /// How many days everything slides by in shift mode: from the old shooting start (the
    /// first day holding script scenes, else `newStart` itself) to `newStart`. Zero with
    /// shift mode off, so the merge rules apply as they are.
    private func shiftDayOffset(toStart normNewStart: Date, calendar cal: Calendar) -> Int {
        guard isShiftModeEnabled ?? false else { return 0 }
        let oldScriptStart = shootDays
            .filter { day in day.scenes.contains { !$0.isCalendarEvent } }
            .map { cal.startOfDay(for: $0.date) }
            .min() ?? normNewStart
        return cal.dateComponents([.day], from: oldScriptStart, to: normNewStart).day ?? 0
    }

    /// The regeneration's outcome for `newStart...newEnd` without applying it.
    func previewProductionRange(from newStart: Date, to newEnd: Date, calendar cal: Calendar = .current) -> ProductionRangePreview {
        var copy = self
        copy.updateProductionRange(from: newStart, to: newEnd, calendar: cal)
        let start = cal.startOfDay(for: newStart)
        let end   = cal.startOfDay(for: newEnd)
        let days  = start <= end ? (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1 : 0
        let scriptScenes = { (project: ProjectData) in project.allScenes.filter { !$0.isBanner }.count }
        return ProductionRangePreview(
            dayCount:            days,
            displacedSceneCount: max(0, scriptScenes(copy) - scriptScenes(self)),
            shifts:              shiftDayOffset(toStart: start, calendar: cal) != 0
        )
    }

    /// The first day of every month the shoot days span, first to last, for a month
    /// export's choice (#28); empty for a project without days.
    func productionMonths(calendar cal: Calendar = .current) -> [Date] {
        guard let first = shootDays.first?.date, let last = shootDays.last?.date, first <= last else { return [] }
        guard var month = cal.date(from: cal.dateComponents([.year, .month], from: first)) else { return [] }
        var months: [Date] = []
        while month <= last {
            months.append(month)
            guard let next = cal.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return months
    }
}

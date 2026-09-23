// DayEdits.swift
// The edits the iPhone makes to one day (#26), as pure mutations of `ProjectData` so
// the Day screen and the strip actions stay thin and each edit is one `perform`: the
// day type and note (what the inspector's day detail writes), the notice strips a day
// gains and loses (a banner or a calendar event added at the end, one replaced in place
// by `replaceScene`, one deleted outright, never through the Boneyard: an event has no
// place there and a banner is filtered out of its display, so the Mac's Delete Banner,
// which appends the banner to `allScenes`, left an invisible strip in the file), a
// strip's time (`applyStripTime`: the Stripboard's Set Time, with its rule that a fixed
// time on the lunch strip is the call sheet's new lunch, and the auto-meal sync in the
// same edit so the retitled strip and the time undo together), the call sheet
// (`saveCallSheet`: the day replaced by id, its auto-meals synced, the inspector's
// save), and Duplicate Scene (`duplicateScene(withID:)` over `Scene.duplicated()`, the
// copy the Mac's Stripboard makes: a fresh Boneyard scene titled "(Copy)" with the
// same number, lengths, cast, summary and breakdown tags and none of the scheduling
// state). Every function returns false (or nil) and changes nothing when its target is
// gone, so a stale sheet cannot write into the wrong day. Tested in `DayEditsTests`.

import Foundation

// MARK: - Duplicate Scene

extension Scene {
    /// The copy Duplicate Scene makes (the Stripboard's `duplicateScene`, pinned by
    /// `DayEditsTests`): a new id, the title suffixed " (Copy)", the same number, lengths,
    /// type, cast, summary and breakdown tags. The set and address, the fixed start time,
    /// the completion flag and the banner fields are not carried: the copy is a fresh,
    /// unscheduled script scene.
    func duplicated() -> Scene {
        Scene(
            title:            title + " (Copy)",
            sceneNumber:      sceneNumber,
            duration:         duration,
            estimatedTime:    estimatedTime,
            dayNightType:     dayNightType,
            cast:             cast,
            summary:          summary,
            extras:           extras,
            props:            props,
            setDressing:      setDressing,
            wardrobe:         wardrobe,
            makeupHair:       makeupHair,
            vehicles:         vehicles,
            specialEquipment: specialEquipment,
            stunts:           stunts,
            sfx:              sfx,
            vfx:              vfx,
            breakdownNotes:   breakdownNotes
        )
    }
}

// MARK: - The day's edits

extension ProjectData {

    // MARK: Day type and note

    /// Sets the day's type. False when no day has that id.
    @discardableResult
    mutating func setDayType(_ type: DayType, forDayID dayID: UUID) -> Bool {
        guard let index = dayIndex(forDayID: dayID) else { return false }
        shootDays[index].dayType = type
        return true
    }

    /// Sets the day's note, trimmed. False when no day has that id.
    @discardableResult
    mutating func setDayNote(_ note: String, forDayID dayID: UUID) -> Bool {
        guard let index = dayIndex(forDayID: dayID) else { return false }
        shootDays[index].dayNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    /// Back to a plain shoot day with no note, the day being dropped if that leaves it
    /// empty outside `productionRange` (`[ShootDay].clearDayType`, the rule the phone, the
    /// inspector and the calendar share). False when no day has that id.
    @discardableResult
    mutating func clearDayType(forDayID dayID: UUID, productionRange: ClosedRange<Date>?, calendar: Calendar = .current) -> Bool {
        shootDays.clearDayType(forDayID: dayID, productionRange: productionRange, calendar: calendar)
    }

    // MARK: Notice strips

    /// Appends a banner or a calendar event to the day (Add Banner, Add Event). A script
    /// scene is refused: scheduling one is a move (`ScheduleMoves`), never an append.
    @discardableResult
    mutating func addNoticeStrip(_ strip: Scene, toDayID dayID: UUID) -> Bool {
        guard strip.isBanner || strip.isCalendarEvent, let index = dayIndex(forDayID: dayID) else { return false }
        shootDays[index].scenes.append(strip)
        return true
    }

    /// Removes a banner or a calendar event from its day outright (Delete Banner, Delete
    /// Event): neither is Boneyard material. A script scene is refused; it returns to the
    /// Boneyard through `ScheduleMoves.returnToBoneyard`.
    @discardableResult
    mutating func deleteNoticeStrip(withID id: UUID) -> Bool {
        guard let strip = scene(withID: id), strip.isBanner || strip.isCalendarEvent else { return false }
        return removeScene(withID: id)
    }

    // MARK: Set Time

    /// The Stripboard's Set Time: `updated` (the strip with its new fixed start and
    /// estimate, `QuickTimeDraft.applied(to:)`) replaces the strip in place on `dayID`.
    /// A fixed time on the lunch strip is the call sheet's new lunch (the Mac's rule),
    /// and the day's auto-meal strips are synced in the same edit so the retitled lunch
    /// and the call sheet undo as one step. False when the strip is not on that day.
    @discardableResult
    mutating func applyStripTime(_ updated: Scene, dayID: UUID) -> Bool {
        guard let dayIndex = dayIndex(forDayID: dayID),
              let sceneIndex = shootDays[dayIndex].scenes.firstIndex(where: { $0.id == updated.id })
        else { return false }
        shootDays[dayIndex].scenes[sceneIndex] = updated
        let lowered = updated.title.lowercased()
        let isLunch = (updated.isAutoMeal && updated.mealKind == .lunch) || lowered.contains("lunch") || lowered.contains("almuerzo")
        if isLunch, !updated.customStartTime.isEmpty {
            shootDays[dayIndex].callSheet.lunchTime = updated.customStartTime
            let synced = shootDays[dayIndex].scenesWithSyncedAutoMeals()
            if synced != shootDays[dayIndex].scenes { shootDays[dayIndex].scenes = synced }
        }
        return true
    }

    // MARK: Call sheet

    /// The call sheet editor's save: `day` (the day with its edited call sheet) replaces
    /// the day with its id, and its auto-meal strips follow the new times in the same
    /// edit (the inspector's rule, learnings 2026-09-20). False when no day has that id.
    @discardableResult
    mutating func saveCallSheet(_ day: ShootDay) -> Bool {
        guard let index = dayIndex(forDayID: day.id) else { return false }
        shootDays[index] = day
        let synced = shootDays[index].scenesWithSyncedAutoMeals()
        if synced != shootDays[index].scenes { shootDays[index].scenes = synced }
        return true
    }

    // MARK: Duplicate Scene

    /// Duplicate Scene: the copy of the script scene with `id` joins the Boneyard, as on
    /// the Mac. Returns the copy's id, or nil for a notice strip or an unknown id.
    @discardableResult
    mutating func duplicateScene(withID id: UUID) -> UUID? {
        guard let original = scene(withID: id), !original.isBanner, !original.isCalendarEvent else { return nil }
        let copy = original.duplicated()
        allScenes.append(copy)
        return copy.id
    }
}

// MARK: - Days outside the range

/// The range pickers' two dates as the production range these functions take: whole days,
/// nil while the end precedes the start (a half-edited range drops nothing). The phone's,
/// the inspector's and the calendar's one way to build it.
func pickerRange(start: Date, end: Date, calendar: Calendar = .current) -> ClosedRange<Date>? {
    let first = calendar.startOfDay(for: start)
    let last  = calendar.startOfDay(for: end)
    return first <= last ? first...last : nil
}

extension [ShootDay] {

    /// Back to a plain shoot day with no note. A day outside `productionRange` (the range
    /// pickers', whole days) exists only to hold something — a type, a note, an event, a
    /// call sheet (`updateProductionRange` keeps such days past the range's edges, and the
    /// Mac's calendar creates them) — so once the type and note are cleared and nothing
    /// else is on it, the day goes entirely (`removeIfEmptyOutsideRange`). With no range
    /// known nothing is dropped. False when no day has that id. The calendar calls this
    /// on its days; `ProjectData.clearDayType` on the project's.
    @discardableResult
    mutating func clearDayType(forDayID dayID: UUID, productionRange: ClosedRange<Date>?, calendar: Calendar = .current) -> Bool {
        guard let index = firstIndex(where: { $0.id == dayID }) else { return false }
        self[index].dayType = .shoot
        self[index].dayNote = ""
        removeIfEmptyOutsideRange(dayID: dayID, productionRange: productionRange, calendar: calendar)
        return true
    }

    /// Drops the day if it lies outside `productionRange` (compared as whole days) and
    /// holds nothing: no strips, a plain shoot type, no note, no call sheet. The date is an
    /// empty tile again instead of a stray blank day. What the calendar runs on the source
    /// day after a day swap or a band move, and Clear Day Type after its reset. Nil drops
    /// nothing. True when the day went.
    @discardableResult
    mutating func removeIfEmptyOutsideRange(dayID: UUID, productionRange: ClosedRange<Date>?, calendar: Calendar = .current) -> Bool {
        guard let productionRange, let index = firstIndex(where: { $0.id == dayID }) else { return false }
        let day     = self[index]
        let start   = calendar.startOfDay(for: productionRange.lowerBound)
        let end     = calendar.startOfDay(for: productionRange.upperBound)
        let inRange = day.date >= start && day.date <= end
        guard !inRange, day.scenes.isEmpty, day.dayType.isShootable, day.dayNote.isEmpty, !day.hasCallSheetData
        else { return false }
        remove(at: index)
        return true
    }
}

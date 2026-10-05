// DayTimeline.swift
// The time cascade: the start and end time every strip of a day gets from the call
// sheet's times and the strips' estimates. The day starts at its ready-to-shoot time,
// else its general call, else 07:30 AM; each strip starts where the one before ended, a
// strip with a custom start time restarts the cascade from there, a script scene with no
// estimate takes 15 minutes, and a banner takes exactly its own estimate (a zero-length
// notice shows a single time). Calendar events are never passed in: an event's time is
// an appointment on the day, not work in the cascade, and its `customStartTime` would
// reset the math for every strip after it (see `StripboardView.dayEventChips`).
//
// This was `StripboardView.computeDayTimeline` (the fork's, see CONTEXT.md "Lineage")
// until the iPhone's Days list and Day screen needed the same numbers (#24); it moved
// here as-is so the board's times cannot drift from the phone's (`DayTimelineTests`).

import Foundation

// MARK: - Entry

/// What the cascade says about one strip: the range the strip prints, its two ends and
/// its duration, all as clock strings.
struct DayTimelineEntry: Equatable {
    /// "07:30 AM – 08:15 AM", or the start alone for a zero-duration strip.
    let timeDisplay: String
    let startStr:    String
    let endStr:      String
    /// "H:MM".
    let durStr:      String
}

// MARK: - Cascade

/// The minute of the day the cascade starts from: the ready-to-shoot time, else the
/// general call, else 07:30 AM; a time that does not parse falls back to 07:30 AM too.
func dayStartMinutes(for day: ShootDay) -> Int {
    let sheet = day.callSheet
    let start = sheet.readyToShootTime.isEmpty
        ? (sheet.generalCallTime.isEmpty ? "07:30 AM" : sheet.generalCallTime)
        : sheet.readyToShootTime
    return parseTimeToMinutes(start) ?? (7 * 60 + 30)
}

/// One strip's place in the cascade, in minutes from the day's midnight (past 1440 for a
/// strip that runs over it): what `dayTimeline` formats and what `BoardTimes.swift` reads
/// the lunch and the wrap from without formatting every strip.
struct DayCascadeSlot: Equatable {
    let sceneID:  UUID
    let startMin: Int
    let endMin:   Int
}

/// The cascade over `scenes` in minutes, in strip order: the one place its rules live.
func dayCascade(for day: ShootDay, scenes: [Scene]) -> [DayCascadeSlot] {
    var startMin = dayStartMinutes(for: day)

    var slots: [DayCascadeSlot] = []
    slots.reserveCapacity(scenes.count)
    for s in scenes {
        if !s.customStartTime.isEmpty, let customMin = parseTimeToMinutes(s.customStartTime) {
            startMin = customMin
        }
        let dur: Int
        if s.isBanner {
            dur = s.estimatedTime
        } else {
            dur = s.estimatedTime > 0 ? s.estimatedTime : 15
        }
        let endMin = startMin + dur
        slots.append(DayCascadeSlot(sceneID: s.id, startMin: startMin, endMin: endMin))
        startMin = endMin
    }
    return slots
}

/// The cascade over `scenes` (the day's strips, in order, without its calendar events),
/// keyed by scene id. A scene that is not in `scenes` has no entry.
func dayTimeline(for day: ShootDay, scenes: [Scene]) -> [UUID: DayTimelineEntry] {
    var map: [UUID: DayTimelineEntry] = [:]
    for slot in dayCascade(for: day, scenes: scenes) {
        let dur        = slot.endMin - slot.startMin
        let startClock = formatMinutesToClock(slot.startMin)
        let endClock   = formatMinutesToClock(slot.endMin)
        let durClock   = formattedTimeHM(dur)
        let fullRange  = (dur == 0) ? startClock : "\(startClock) – \(endClock)"

        map[slot.sceneID] = DayTimelineEntry(timeDisplay: fullRange, startStr: startClock, endStr: endClock, durStr: durClock)
    }
    return map
}

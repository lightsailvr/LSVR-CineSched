// BoardTimes.swift
// The call sheet's lunch and wrap as the Stripboard has them. A call sheet's Lunch and
// Wrap are overrides: typed, they are the day's times (and the auto-meal sync pins a
// strip there, AutoMealSync.swift); left blank, they are read from the board, so the
// call sheet, the Shooting Schedule and every day header follow the strips as they move
// instead of a time typed once. Until 4.10 the call sheet editor filled the production's
// default lunch (01:30 PM) into every sheet it opened, which then planted a pinned
// LUNCH strip that fought the board's own lunch.
//
// The lunch is the start of the day's lunch strip: the call sheet's auto-meal, else a
// banner titled lunch (English or the fork's Spanish), else the first Meal Break banner.
// The wrap is the end of the day's last strip. Both come from `dayCascade`, the same
// minutes the board prints, and are formatted once, never per strip, because the
// calendar reads them in every cell (#34). Pure; `BoardTimesTests`.

import Foundation

extension ShootDay {

    /// The strips the cascade runs over: everything but the calendar events.
    private var cascadeStrips: [Scene] { scenes.filter { !$0.isCalendarEvent } }

    /// The day's lunch strip, by the rule in the header; nil when the board has none.
    var boardLunchStrip: Scene? {
        let strips = cascadeStrips
        return strips.first { $0.isAutoMeal && $0.mealKind == .lunch }
            ?? strips.first { $0.isBanner && !$0.isAutoMeal && Self.isLunchTitle($0.title) }
            ?? strips.first { $0.isBanner && !$0.isAutoMeal && $0.bannerType == .mealBreak }
    }

    /// When the board's lunch starts ("01:30 AM"); nil when the board has no lunch strip.
    var boardLunchTime: String? {
        guard let lunch = boardLunchStrip else { return nil }
        let slot = dayCascade(for: self, scenes: cascadeStrips).first { $0.sceneID == lunch.id }
        return slot.map { formatMinutesToClock($0.startMin) }
    }

    /// When the board's last strip ends; nil for a day without strips.
    var boardWrapTime: String? {
        dayCascade(for: self, scenes: cascadeStrips).last.map { formatMinutesToClock($0.endMin) }
    }

    /// The lunch every reader shows: the call sheet's when typed, else the board's, else "".
    var effectiveLunchTime: String {
        let typed = callSheet.lunchTime.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? (boardLunchTime ?? "") : typed
    }

    /// The wrap every reader shows: the call sheet's when typed, else the board's, else "".
    var effectiveWrapTime: String {
        let typed = callSheet.wrapTime.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? (boardWrapTime ?? "") : typed
    }

    static func isLunchTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("almuerzo") || lowered.contains("lunch")
    }
}

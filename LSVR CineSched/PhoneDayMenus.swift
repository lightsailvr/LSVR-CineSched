// PhoneDayMenus.swift
// The two menus the iPhone builds for a day in more than one place (the M4 review), each
// one `@ViewBuilder` so the Days list and the Day screen show the same items in the same
// order: the day's menu (the Day screen's ⋯ button, the Days list header's long press —
// which also opens the Day screen, so it takes `openDay`) with the edits that add to the
// day and open its call sheet (#26) and the moves that act on the whole day (#25), and a
// calendar event's menu (an event chip in the Days list, an event row on the Day screen):
// Edit Event and Delete Event. A strip's menu is `PhoneStripActions` (PhoneStripRow.swift).
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

// MARK: - The day's menu

/// Open Day (when `openDay` is given), Edit Call Sheet…, Add Banner…, Add Event…, then
/// Add Scenes… and Swap with Day….
@ViewBuilder
func phoneDayMenuItems(dayID: UUID, moves: PhoneMoves, dayEdits: PhoneDayEdits, openDay: (() -> Void)?) -> some View {
    if let openDay {
        Button {
            openDay()
        } label: {
            Label(L("Open Day"), systemImage: "calendar")
        }
        Divider()
    }
    Button {
        dayEdits.presentCallSheet(dayID: dayID)
    } label: {
        Label(L("Edit Call Sheet…"), systemImage: "doc.plaintext")
    }
    Button {
        dayEdits.presentBannerEditor(dayID: dayID)
    } label: {
        Label(L("Add Banner…"), systemImage: "flag")
    }
    Button {
        dayEdits.presentEventEditor(dayID: dayID)
    } label: {
        Label(L("Add Event…"), systemImage: "calendar.badge.plus")
    }
    Divider()
    Button {
        moves.presentAddScenes(dayID: dayID)
    } label: {
        Label(L("Add Scenes…"), systemImage: "plus.rectangle.on.rectangle")
    }
    Button {
        moves.presentSwapDay(dayID: dayID)
    } label: {
        Label(L("Swap with Day…"), systemImage: "arrow.left.arrow.right")
    }
}

// MARK: - A calendar event's menu

/// Edit Event and Delete Event, for the event `event` on `dayID`.
@ViewBuilder
func phoneEventMenuItems(_ event: Scene, dayID: UUID, dayEdits: PhoneDayEdits) -> some View {
    Button {
        dayEdits.presentEventEditor(dayID: dayID, eventID: event.id)
    } label: {
        Label(L("Edit Event"), systemImage: "pencil")
    }
    Divider()
    Button(role: .destructive) {
        dayEdits.deleteNoticeStrip(event)
    } label: {
        Label(L("Delete Event"), systemImage: "trash")
    }
}

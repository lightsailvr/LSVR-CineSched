// ProjectCommands.swift
// How a menu item reaches the frontmost project window (#8). CineSchedApp builds the menus
// once for the whole app, but every command acts on one window's document: each
// ContentView publishes one of these through `.focusedSceneValue(\.projectCommands, …)`,
// and a menu Button reads `@FocusedValue(\.projectCommands)`, which is the value from
// whichever window is key, or nil when no project window is (the item is then disabled).
// This replaced the notification names the menus used to post and ContentView observed;
// with two projects open a notification would have reached both windows.
//
// New, Open, Open Recent, Save, Duplicate, Rename, Move To, Revert To, Close and the Edit
// menu's Undo and Redo are the document infrastructure's own items and need no slot here.
// The View menu's toggles are bindings for the same reason: they are the key window's view
// state (see WindowPreference.swift), not app preferences, so two open projects can show
// different views. Dark Mode and Theme are app-wide and stay @AppStorage in the menu.
//
// Adding a menu command touches three places: a closure slot (or binding) here, a `Button`
// or `Toggle` in CineSchedApp, and the slot's assignment in `ContentView.projectCommands`.

import SwiftUI

struct ProjectCommands {
    // File
    var importScript:          () -> Void
    var exportSchedulePDF:     () -> Void
    var exportStripboardPDF:   () -> Void
    var exportDaysOutOfDays:   () -> Void
    var exportBreakdowns:      () -> Void
    // Production
    var openProductionSetup:   () -> Void
    var scanForConflicts:      () -> Void
    var openBreakdownBrowser:  () -> Void
    var lockSchedule:          () -> Void
    var unlockSchedule:        () -> Void
    var showScheduleLockReport: () -> Void
    // View
    var showColorLegend:        () -> Void
    var showSceneColorSettings: () -> Void
    var showStripboardFields:   () -> Void
    var viewMode:               Binding<ScheduleViewMode>
    var showCastOnCards:        Binding<Bool>
    var showEstTimeOnCards:     Binding<Bool>
    var stripboardShowAllDays:  Binding<Bool>
}

extension FocusedValues {
    @Entry var projectCommands: ProjectCommands?
}

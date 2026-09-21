// PhoneEditor.swift
// The compact-width editor (#24, milestone 4 of #1): what a project document shows on an
// iPhone and in a narrow iPad window. A `TabView` with Days (`DaysTab`: the Stripboard as a
// list of day cards under the week strip, the Day screen pushed from a header), Boneyard,
// Production and a Search tab in the search role; the tab bar minimizes on scroll and
// carries the Today control as its bottom accessory. Boneyard and Search are #27's,
// Production is #28's: each is one line here that those tickets replace.
//
// This view owns what `ContentView` owns for the other layouts, so the tabs are plain
// views: the document and the edit funnel (`edit(_:_:)`, the same `perform` under an
// `EditGesture`, handed down as a `ProjectEdit` closure), the `SyncMonitor` for the Days
// tab's indicator, the `scenePalette` environment at the root (the one place the palette
// enters the tree), the `DerivedScheduleState` cache (conflicts, once per change), and the
// PDF preview presentation with the `exportPreview` request #26 and #28 will set. Replaced
// `MinimalProjectEditor` (#12–#17), which proved the document lifecycle here.
//
// Platform-free SwiftUI: the Mac compiles it and never shows it (its window is never
// compact); the two iOS-only APIs, the tab bar's minimize behaviour and its accessory,
// are behind `phoneTabBar`.

import SwiftUI

struct PhoneEditor: View {
    let document: ProjectDocument
    @Environment(\.undoManager) private var undoManager

    enum PhoneTab: Hashable {
        case days, boneyard, production, search
    }

    @State private var selectedTab: PhoneTab = .days

    // MARK: - Edit gesture state

    /// The gesture a multi-write action opens so its writes fold into one undo step
    /// (`beginEditGesture`); nil between actions. Nothing opens it in #24; the moves (#25)
    /// and editors (#26) will.
    @State private var activeGesture: EditGesture?

    // MARK: - Derived and sync state

    /// Conflict sets and the rest of what the whole project implies, computed once per
    /// change (DerivedScheduleState.swift). The Boneyard sort is #27's; script order here.
    @State private var derivedCache = DerivedScheduleStateCache()
    private var derived: DerivedScheduleState {
        derivedCache.state(for: document.project, changeCount: document.changeCount, boneyardSort: .showOrder)
    }

    /// The iCloud sync state in the document's bar and the conflict notice (#14, #15):
    /// one monitor per editor, run by the `syncMonitored` modifier at the root.
    @State private var syncMonitor = SyncMonitor()

    /// The export the preview sheet shows (#23); the call sheet export (#26) and the
    /// Production tab's exports (#28) set it.
    @State var exportPreview: PDFExportRequest? = nil

    /// The date the Days list scrolls to next: the Today control sets it here, the week
    /// strip and the month popover set it inside the tab, and the tab clears it.
    @State private var scrollToDate: Date? = nil

    private var palette: ScenePalette { document.project.resolvedPalette }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(L("Days"), systemImage: "calendar.day.timeline.left", value: .days) {
                DaysTab(
                    document:         document,
                    conflictSceneIDs: derived.conflictSceneIDs,
                    scrollToDate:     $scrollToDate,
                    edit:             projectEdit
                )
            }
            Tab(L("Boneyard"), systemImage: "tray.full", value: .boneyard) {
                PhoneTabPlaceholder(title: L("Boneyard"), symbol: "tray.full", message: L("The unscheduled scenes will live here."))
            }
            Tab(L("Production"), systemImage: "person.3", value: .production) {
                PhoneTabPlaceholder(title: L("Production"), symbol: "person.3", message: L("Production Setup, reports and exports will live here."))
            }
            Tab(value: .search, role: .search) {
                PhoneTabPlaceholder(title: L("Search"), symbol: "magnifyingglass", message: L("Search across scenes and days will live here."))
            }
        }
        // The document infrastructure wraps the editor in its own bar (Back, the title
        // menu) and mirrors both into any navigation bar inside (2026-09-20 #17), so the
        // Days tab hides its stack's bar at the root and the project's one bar is that
        // outer one: a toolbar item placed here lands in it.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SyncStateIndicator(monitor: syncMonitor)
            }
        }
        .phoneTabBar {
            TodayControl(shootDays: document.project.shootDays) { date in
                selectedTab  = .days
                scrollToDate = date
            }
        }
        // The one place the palette enters the view tree; every strip below reads it
        // from the environment rather than from the device.
        .environment(\.scenePalette, palette)
        .syncMonitored(syncMonitor, document: document)
        .pdfExportPresentation($exportPreview)
    }

    // MARK: - Edit funnel

    /// Applies one change to the project through the document's funnel, under the gesture
    /// an action may have opened. `actionName` labels Undo and Redo.
    func edit(_ actionName: String? = nil, _ change: (inout ProjectData) -> Void) {
        document.perform(actionName, coalescing: activeGesture, undoManager: undoManager, change)
    }

    /// `edit` as the closure the tabs take.
    private var projectEdit: ProjectEdit {
        { actionName, change in edit(actionName, change) }
    }

    /// Opens the gesture the following `edit`s fold into, and closes it at the end of the
    /// run-loop turn regardless, so a token never outlives its action (the `ContentView`
    /// rule). For #25's moves and #26's multi-write saves.
    func beginEditGesture() {
        let gesture = EditGesture()
        activeGesture = gesture
        DispatchQueue.main.async {
            if activeGesture == gesture { activeGesture = nil }
        }
    }
}

// MARK: - Stub tabs

/// What a tab shows until its ticket lands: the system's empty state naming what is coming.
private struct PhoneTabPlaceholder: View {
    let title:   String
    let symbol:  String
    let message: String

    var body: some View {
        // No stack of its own: the document infrastructure's bar mirrors into any inner
        // bar (see PhoneEditor's toolbar note), so a stack here would show two.
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

// MARK: - Today control

/// The tab bar accessory: one tap lands the Days list on today's shoot day (`todayTarget`:
/// today, else the next day, else the last). Expanded above the bar it names the day it
/// will land on; folded in beside the minimized bar it is the word alone.
private struct TodayControl: View {
    let shootDays: [ShootDay]
    let onToday: (Date) -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let now      = Date()
        let calendar = Calendar.current
        let targetID = todayTarget(in: shootDays, now: now, calendar: calendar)
        let target   = shootDays.first { $0.id == targetID }
        let numbers  = productionDayNumbers(for: shootDays)
        Button {
            if let target { onToday(target.date) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(L("Today"))
                    .font(.headline)
                if placement != .inline, let target {
                    Text(description(of: target, dayNumber: numbers[target.id], now: now, calendar: calendar))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if placement != .inline {
                    Image(systemName: "arrow.down.to.line")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityIdentifier("TodayControl")
    }

    /// "Day 3 · Wed Nov 4" for today's shoot day; "Next: …" or "Last: …" when today has none.
    private func description(of day: ShootDay, dayNumber: Int?, now: Date, calendar: Calendar) -> String {
        let name = dayNumber.map { "\(L("Day")) \($0) · " } ?? ""
        let date = formattedDate(day.date)
        if calendar.isDate(day.date, inSameDayAs: now) { return name + date }
        return (day.date > now ? L("Next: ") : L("Last: ")) + name + date
    }
}

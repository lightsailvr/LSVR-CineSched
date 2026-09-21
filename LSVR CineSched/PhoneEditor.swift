// PhoneEditor.swift
// The compact-width editor (#24, milestone 4 of #1): what a project document shows on an
// iPhone and in a narrow iPad window. A `TabView` with Days (`DaysTab`: the Stripboard as a
// list of day cards under the week strip, the Day screen pushed from a header), Boneyard,
// Production (`ProductionTab`, #28: the Mac's Production, View and File menu commands as
// rows) and a Search tab in the search role; the tab bar minimizes on scroll and carries
// the Today control as its bottom accessory. Boneyard and Search are #27's: each is one
// line here that that ticket replaces.
//
// This view owns what `ContentView` owns for the other layouts, so the tabs are plain
// views: the document and the edit funnel (`edit(_:_:)`, the same `perform` under an
// `EditGesture`, handed down as a `ProjectEdit` closure; `edit(_:coalescing:_:)` for a
// gesture the caller owns), the `SyncMonitor` for the Days tab's indicator, the
// `scenePalette` environment at the root (the one place the palette enters the tree), the
// `DerivedScheduleState` cache (conflicts, once per change), the PDF preview presentation
// with the `exportPreview` request the Production tab (#28) and the Day screen (#26) set,
// and the `ProjectCommands` the iPad's menu bar acts through in a narrow window (#22):
// published as the focused scene value and into `ActiveProjectCommands` while the window
// appears active, each command handing the Production tab a `ProductionCommand`.
// Replaced `MinimalProjectEditor` (#12–#17), which proved the document lifecycle here.
//
// Platform-free SwiftUI: the Mac compiles it and never shows it (its window is never
// compact); the two iOS-only APIs, the tab bar's minimize behaviour and its accessory,
// are behind `phoneTabBar`.

import SwiftUI

struct PhoneEditor: View {
    let document: ProjectDocument
    @Environment(\.undoManager) private var undoManager
    /// The menu bar's fallback channel to the active window (#22; nil on the Mac, which
    /// never shows this editor): the commands are published here while the window
    /// appears active. `editorID` is this editor's key in the holder.
    @Environment(ActiveProjectCommands.self) private var activeProject: ActiveProjectCommands?
    @Environment(\.appearsActive) private var appearsActive
    @State private var editorID = UUID()

    enum PhoneTab: Hashable {
        case days, boneyard, production, search
    }

    @State private var selectedTab: PhoneTab = .days

    // MARK: - Edit gesture state

    /// The gesture a multi-write action opens so its writes fold into one undo step
    /// (`beginEditGesture`); nil between actions. The Production tab opens it for the
    /// setup's character renames (#28); the moves (#25) and editors (#26) will too.
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

    /// The export the preview sheet shows (#23); the Production tab's exports (#28) and
    /// the call sheet export (#26) set it.
    @State var exportPreview: PDFExportRequest? = nil

    /// The date the Days list scrolls to next: the Today control sets it here, the week
    /// strip and the month popover set it inside the tab, and the tab clears it.
    @State private var scrollToDate: Date? = nil

    /// What the menu bar asked the Production tab to do (#22, #28): set here with the
    /// tab switch, consumed and cleared by the tab.
    @State private var productionCommand: ProductionCommand? = nil

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
                ProductionTab(
                    document:                 document,
                    derived:                  derived,
                    edit:                     projectEdit,
                    editCoalescing:           coalescedProjectEdit,
                    beginEditGestureIfNeeded: { if activeGesture == nil { beginEditGesture() } },
                    command:                  $productionCommand,
                    exportPreview:            $exportPreview,
                    jumpToDate:               { date in
                        selectedTab  = .days
                        scrollToDate = date
                    }
                )
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
        // The menu bar's commands (#22): the focused value, and the holder for the iPad,
        // where the focused value is nil without a hardware keyboard in use.
        .focusedSceneValue(\.projectCommands, projectCommands)
        .onChange(of: appearsActive, initial: true) { _, active in
            if active { activeProject?.publish(projectCommands, from: editorID) }
            else      { activeProject?.retire(editorID) }
        }
        .onDisappear { activeProject?.retire(editorID) }
    }

    // MARK: - Menu commands

    /// The menu commands this window answers (ProjectCommands.swift), each one a switch to
    /// the Production tab with the command for it to run. The View menu's bindings are
    /// constants: the phone has no calendar, no cast row and no all-days toggle.
    private var projectCommands: ProjectCommands {
        func production(_ command: ProductionCommand) -> () -> Void {
            {
                selectedTab       = .production
                productionCommand = command
            }
        }
        return ProjectCommands(
            importScript:           production(.importScript),
            exportSchedulePDF:      production(.exportScheduleCalendar),
            exportStripboardPDF:    production(.exportStripSchedule),
            exportDaysOutOfDays:    production(.exportDaysOutOfDays),
            exportBreakdowns:       production(.exportBreakdowns),
            openProductionSetup:    production(.openProductionSetup),
            scanForConflicts:       production(.scanForConflicts),
            openBreakdownBrowser:   production(.openBreakdownBrowser),
            lockSchedule:           production(.lockSchedule),
            unlockSchedule:         production(.unlockSchedule),
            showScheduleLockReport: production(.showScheduleLockReport),
            showColorLegend:        production(.showColorLegend),
            showSceneColorSettings: production(.showSceneColorSettings),
            showStripboardFields:   production(.showStripboardFields),
            viewMode:               .constant(.stripboard),
            showCastOnCards:        .constant(false),
            showEstTimeOnCards:     .constant(false),
            stripboardShowAllDays:  .constant(false)
        )
    }

    // MARK: - Edit funnel

    /// Applies one change to the project through the document's funnel, under the gesture
    /// an action may have opened. `actionName` labels Undo and Redo.
    func edit(_ actionName: String? = nil, _ change: (inout ProjectData) -> Void) {
        document.perform(actionName, coalescing: activeGesture, undoManager: undoManager, change)
    }

    /// `edit` under a gesture the caller owns and keeps across calls (the Production tab's
    /// title field, one per focus session; its color editor, one per slot), where the
    /// editor's own `activeGesture` would close at the end of the turn.
    func edit(_ actionName: String?, coalescing token: EditGesture, _ change: (inout ProjectData) -> Void) {
        document.perform(actionName, coalescing: token, undoManager: undoManager, change)
    }

    /// `edit` as the closure the tabs take.
    private var projectEdit: ProjectEdit {
        { actionName, change in edit(actionName, change) }
    }

    /// `edit(_:coalescing:_:)` as the closure the Production tab takes.
    private var coalescedProjectEdit: CoalescedProjectEdit {
        { token, actionName, change in edit(actionName, coalescing: token, change) }
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

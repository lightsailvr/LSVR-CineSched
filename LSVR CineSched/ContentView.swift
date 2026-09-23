// ContentView.swift
// The editor for one project document: sidebar, toolbar, calendar and stripboard views,
// laid out for the Mac window (two columns under the window toolbar, `EditorLayout.twoColumn`)
// or, in regular width on the iPad and Vision Pro (#17), as three columns with a trailing
// inspector bound to the selected scene or day (`.threeColumn`; the inspector is
// ContentView+Inspector.swift). One view, one set of state and sheets, two bodies: the
// Mac's is untouched by the iPad's, and the platform's scene in CineSchedApp chooses.
// The project itself lives in the `ProjectDocument` the window was opened with
// (#8, ADR 0004); this view reads it freely and writes it only through `edit(_:_:)` and
// the bindings built on it, all of which go through the document's `perform` funnel so
// that every change is undoable and autosaved. UI state that is not the project (the
// pending range-picker dates, selection, sheets) stays `@State` here.
// Script import lives in ContentView+ScriptImport.swift, the PDF export actions in
// ContentView+PDFExports.swift, and the drag/drop and editing flows in CalendarView.swift
// and StripboardView.swift.

import SwiftUI
import UniformTypeIdentifiers

/// What the three-column toolbar's Undo and Redo buttons show (#17); see
/// `ContentView.undoAvailability`.
struct UndoAvailability: Equatable {
    var canUndo = false
    var canRedo = false
}

// MARK: - Schedule View Mode

enum ScheduleViewMode: String, CaseIterable {
    case calendar   = "Calendar"
    case stripboard = "Stripboard"

    var localizedTitle: String {
        L(rawValue)
    }

    var systemImage: String {
        switch self {
        case .calendar:   return "calendar"
        case .stripboard: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Editor layout

/// Which window the editor is laid out for (#17). The platform's `DocumentGroup` in
/// CineSchedApp (a seam) chooses; the view itself has no platform conditionals.
enum EditorLayout {
    /// The Mac window: sidebar and detail under the window toolbar (the view switcher,
    /// Share, the search field; the stats as the title's subtitle), and the app's menus
    /// for the rest.
    case twoColumn
    /// The iPad and Vision Pro window in regular width: sidebar, the calendar or Stripboard
    /// as the content with a system toolbar, and a trailing inspector showing the selected
    /// scene's editor or the selected day's detail.
    case threeColumn
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue
    @Environment(\.colorScheme) private var colorScheme

    // MARK: Project state

    /// The window's project. Read through the accessors below; write only through `edit`.
    let document: ProjectDocument
    /// The layout this window draws (see `EditorLayout`).
    let layout: EditorLayout
    /// The window's undo manager, supplied by the document infrastructure. Every `perform`
    /// registers with it, which is also what marks the document edited and autosaves it.
    /// Read by the clipboard extension too, which puts it on the responder chain for the
    /// iPad's undo gestures (ContentView+Clipboard.swift).
    @Environment(\.undoManager) var undoManager
    /// The menu bar's fallback channel to the active window (#22, iPad; nil on the Mac,
    /// whose menus read the focused value): this editor publishes its commands there
    /// while its window appears active. `editorID` is its key in the holder.
    @Environment(ActiveProjectCommands.self) private var activeProject: ActiveProjectCommands?
    @Environment(\.appearsActive) private var appearsActive
    @State private var editorID = UUID()

    var allScenes:          [Scene]        { document.project.allScenes }
    var shootDays:          [ShootDay]     { document.project.shootDays }
    var projectTitle:       String         { document.project.projectTitle }
    var productionInfo:     ProductionInfo { document.project.productionInfo ?? ProductionInfo() }
    var isShiftModeEnabled: Bool           { document.project.isShiftModeEnabled ?? false }
    /// The strip colors every view below and every export draws with (#11).
    var palette:            ScenePalette   { document.project.resolvedPalette }

    /// The range picker's pending dates: what the user is choosing before pressing Update
    /// Calendar, so UI state rather than project state. Seeded from the shoot days' bounds,
    /// and re-seeded only when the project is replaced under the view (undo, redo, reload)
    /// *and* those bounds changed, so an unrelated Undo leaves a half-typed range alone.
    @State var startDate: Date
    @State var endDate:   Date
    /// The bounds the pickers were last seeded from.
    @State private var seededRange: ClosedRange<Date>?

    init(document: ProjectDocument, layout: EditorLayout = .twoColumn) {
        self.document = document
        self.layout   = layout
        let range   = Self.dateRange(of: document.project.shootDays)
        _startDate   = State(initialValue: range?.lowerBound ?? Date())
        _endDate     = State(initialValue: range?.upperBound ?? Date())
        _seededRange = State(initialValue: range)
    }

    private static func dateRange(of days: [ShootDay]) -> ClosedRange<Date>? {
        guard let first = days.first?.date, let last = days.last?.date, first <= last else { return nil }
        return first...last
    }

    // MARK: UI / sheet state
    @State private var newSceneNumber:   String       = ""
    @State private var newSceneTitle:    String       = ""
    @State private var newDuration:      String       = ""
    @State private var newEstimate:      String       = ""
    @State private var newDayNightType:  DayNightType = .day

    @State var showingAlert                   = false
    @State var showingImportAlert             = false

    @State var alertMessage:   String = ""
    @State var importMessage:  String = ""
    @State private var importedScenesCount = 0

    // Fountain import confirmation & summary
    @State var pendingFountainImport:   FountainImportResult? = nil
    @State var completedFountainImport: FountainImportResult? = nil
    @State var showingFountainImportConfirmation = false
    @State var showingImportSummary              = false

    // Unscheduled-scene editing
    @State private var editingUnscheduledScene:      Scene?
    @State private var editingUnscheduledSceneIndex: Int?

    // Appearance (app-wide)
    @AppStorage("CineSchedDarkMode") var isDarkMode: Bool = false
    @AppStorage("CineSchedIncludeHoldInDOOD") var includeHoldInDOOD: Bool = true
    /// Stripboard field selection, stored as a comma-joined raw-value string so it fits
    /// @AppStorage; decoded on read via `stripboardFields`.
    @AppStorage(StripboardFieldSettings.defaultsKey) private var stripboardFieldsRaw: String = StripboardFieldSettings.defaultRaw

    // View state (this window's, seeded from the last window's; see WindowPreference.swift).
    // The View menu edits these through `projectCommands`, so it acts on the key window.
    @WindowPreference("CineSchedViewMode") private var viewMode: ScheduleViewMode = .calendar
    @WindowPreference("CineSchedShowCastRow") var showCastOnCards: Bool = false
    @WindowPreference("CineSchedShowEstTimeOnCards") var showEstTimeOnCards: Bool = false
    /// Stripboard only: draw every date, or fold runs of empty days into one gap row each.
    @WindowPreference("CineSchedStripboardShowAllDays") private var stripboardShowAllDays: Bool = false
    /// Stripboard only (#42): Show Shots, every strip's shots under it. Collapsed by default.
    @WindowPreference("CineSchedShowShots") private var showShots: Bool = false
    /// The strips whose chevron was flipped against Show Shots (`ShotExpansion`). Plain
    /// state, not a window preference: they are this project's scene ids and would mean
    /// nothing to the next window. Never in the file either way.
    @State private var shotExpansionExceptions: Set<UUID> = []

    // Production Setup & Conflict states
    @State private var conflictReportResults: [ScheduleConflict] = []
    @State private var scrollToDate: Date? = nil
    @State private var searchQuery: String = ""

    // Month PDF export options: an app preference (UserDefaults) shared with the phone's
    // Production tab, so the options sheet remembers the last selection between exports.
    @AppStorage(MonthPDFOptionSettings.fieldsKey) private var monthPDFFieldsRaw: String = MonthPDFOptionSettings.defaultFieldsRaw
    @AppStorage(MonthPDFOptionSettings.pagesKey)  private var monthPDFShowPages: Bool = MonthPDFOptions.default.includePageCount
    @AppStorage(MonthPDFOptionSettings.timeKey)   private var monthPDFShowTime:  Bool = MonthPDFOptions.default.includeEstimatedTime
    /// The month the options sheet exports, seeded as it opens (`openMonthPDFOptions`).
    @State private var monthPDFMonth: Date = Date()
    // The Shot List's options (#40), app-wide like the month's and shared with the phone.
    @AppStorage(ShotListPDFOptionSettings.scopeKey)         private var shotListScopeRaw: String = ShotListPDFOptionSettings.projectRaw
    @AppStorage(ShotListPDFOptionSettings.includeFramesKey) private var shotListIncludeFrames: Bool = ShotListPDFOptions.default.includeFrames
    /// The options sheet's Export, run as the sheet finishes dismissing (`runPendingShotListExport`).
    @State private var pendingShotListExport: ShotListPDFOptions? = nil

    // MARK: - Derived state

    /// The sorted Boneyard, conflict sets, duplicate numbers and lock drift, computed from
    /// the project at most once per change (see DerivedScheduleState.swift). Read through
    /// `derived`; nothing here is stored state, so an edit costs one body pass, not two.
    @State private var derivedCache = DerivedScheduleStateCache()
    var derived: DerivedScheduleState {
        derivedCache.state(for: document.project, changeCount: document.changeCount, boneyardSort: boneyardSort)
    }

    // MARK: - Sync state

    /// The iCloud sync state beside the title and the conflict notice (#14, #15): one
    /// monitor per window, run by the `syncMonitored` modifier in `applyLifecycle`.
    @State var syncMonitor = SyncMonitor()

    // MARK: - Breakdown Browser
    @State private var breakdownBrowserScenes: [Scene] = []
    @State private var breakdownBrowserIndex: Int = 0

    // MARK: - Edit gesture state

    /// The gesture opened by a child view's `onBeforeSceneChange`, so the several binding
    /// writes one calendar or Stripboard action makes fold into one undo step. Closed by
    /// `onSceneChanged` and, regardless, at the end of the run-loop turn (see
    /// `beginEditGesture`).
    @State var activeGesture: EditGesture?
    /// Typing in the title field is one gesture per focus session: every keystroke writes
    /// the binding, and without a token each would be its own undo step.
    @State private var titleGesture = EditGesture()
    @FocusState private var titleFieldFocused: Bool
    /// Whether the undo manager can undo and redo, for the three-column toolbar's two
    /// buttons (#17). Held as state and refreshed from the manager's notifications
    /// rather than read live in the toolbar builder: a live read rendered stale (Redo
    /// stayed disabled after an undo on the iPad although the manager could redo).
    @State private var undoAvailability = UndoAvailability()
    /// The color editor's open step: a ColorPicker writes on every movement of the wheel,
    /// so the token stays while one slot is being edited and changes with the slot (see
    /// `setPaletteColor`). Cleared when the sheet closes.
    @State private var paletteGesture: (slot: SceneColorSlot, token: EditGesture)?

    // MARK: - Sheet presentation
    enum ActiveSheet: Identifiable, Hashable {
        case unscheduledEdit, productionSetup, conflictReport, scheduleLockReport, breakdownBrowser, sceneColorSettings, stripboardFields
        /// The inspector's day detail (#17) adds an event or opens one of the day's for
        /// editing (`eventID` nil to add), and opens the day's call sheet; the schedule
        /// views present their own copies of these sheets for their own cells.
        case calendarEvent(dayID: UUID, eventID: UUID?)
        case callSheet(dayID: UUID)
        /// The month calendar's month and options before its export, from the Share menu's
        /// Month Calendar… (the calendar's own Export Month button went with the toolbar
        /// redesign). The month is `monthPDFMonth`.
        case monthPDFOptions
        /// The Shot List's scope and frames before its export (#40), from File ▸ Export
        /// Shot List… and the Share menu.
        case shotListOptions
        var id: Self { self }
    }
    @State var activeSheet: ActiveSheet? = nil
    @State private var showingColorLegend = false
    /// The export the preview sheet shows on the iPad and the Vision Pro (#23); the Mac's
    /// exports go to its save panels and never set it (ContentView+PDFExports.swift).
    @State var exportPreview: PDFExportRequest? = nil

    // MARK: - Inspector selection (three-column layout)

    /// What the inspector shows (#17): the scene or day last tapped, or nothing. Written
    /// by every single tap on a strip (through `lastSelectedSceneBinding`) and on a day
    /// (`onSelectDay`), pruned with the multi-selection when its target leaves the
    /// project. Set on the Mac too, where nothing reads it.
    @State var selection: EditorSelection?
    /// Whether the inspector column is open; the toolbar toggles it. Per window, seeded
    /// from the last window like the other view state.
    @WindowPreference("CineSchedInspectorVisible") private var showInspector: Bool = true
    /// The scene editor closes itself (`isPresented = false`) after Save as well as on
    /// Cancel and Delete; in the inspector only the latter two should clear the selection.
    /// `onSave` sets this so the next close keeps the selection (see
    /// `inspectorEditorPresented`).
    @State var inspectorKeepsSelection = false
    /// The page the inspector's scene editor opens on (#42): a shot sub-row's single tap in
    /// the three-column layout selects its scene with this set. Cleared when the selection
    /// moves off that scene (`applyLifecycle`).
    @State var inspectorRoute: InspectorRoute?

    private var isPresentedUnscheduledEdit: Binding<Bool> {
        Binding(get: { activeSheet == .unscheduledEdit }, set: { if !$0 { activeSheet = nil } })
    }
    private var isPresentedProductionSetup: Binding<Bool> {
        Binding(get: { activeSheet == .productionSetup }, set: { if !$0 { activeSheet = nil } })
    }
    private var isPresentedBreakdownBrowser: Binding<Bool> {
        Binding(get: { activeSheet == .breakdownBrowser }, set: { if !$0 { activeSheet = nil } })
    }

    // Boneyard sort (see DerivedScheduleState.swift for the enum and the sorting)
    @AppStorage("CineSchedBoneyardSort") private var boneyardSort: BoneyardSort = .showOrder

    @AppStorage("CineSchedDateRangeExpanded") private var isDateRangeExpanded: Bool = true
    @AppStorage("CineSchedNewSceneExpanded")  private var isNewSceneExpanded:  Bool = true

    /// The multi-selection: the strips that drag, act and copy together (#18, #22).
    /// Written here, by the schedule views through their bindings and by a paste.
    @State var selectedSceneIDs:    Set<UUID> = []
    @State var lastSelectedSceneID: UUID?
    /// Bumped by every selection on the board (`focusEditor`, #22) to make the pasteboard
    /// responder the first responder, where the system's Copy, Cut and Paste go when no
    /// field is being edited (ContentView+Clipboard.swift).
    @State var pasteboardFocusRequest = 0

    // MARK: - Computed statistics
    var scheduledDays: [ShootDay] { shootDays.filter { !$0.scenes.isEmpty } }
    var totalScenes:   Int        { scheduledDays.reduce(0) { $0 + $1.scenes.count } }
    var completedScenesCount: Int {
        scheduledDays.reduce(0) { $0 + $1.scenes.filter { $0.isCompleted }.count }
    }
    var totalDuration: String     { formattedEighths(scheduledDays.reduce(0) { $0 + $1.totalDuration }) }
    var totalEstTime:  String     { formattedTime(scheduledDays.reduce(0) { $0 + $1.totalEstimatedTime }) }
    var unscheduledCount: Int     { allScenes.filter { !$0.isBanner }.count }

    // MARK: - Body
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("CineSchedSidebarCollapsed") private var sidebarCollapsedPreference: Bool = false
    private var isSidebarCollapsed: Bool { columnVisibility == .detailOnly }

    var body: some View {
        if layout == .twoColumn {
            twoColumnBody
        } else {
            threeColumnBody
        }
    }

    /// The Mac window, exactly as before #17: sidebar and detail, the Mac's own colors on
    /// the window, the alerts, the sheets and the lifecycle.
    private var twoColumnBody: some View {
        let base = NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            detailView
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .accentColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))
        .background(WindowAccessor(backgroundColor: currentTheme.canvasBackground(isDarkMode: isDarkMode)))

        let withAlerts    = applyAlerts(base)
        let withSheets    = applySheets(withAlerts)
        let withExport    = applyExportPresentation(withSheets)
        let withClipboard = applyClipboard(withExport)
        return applyLifecycle(withClipboard)
    }

    /// The iPad and Vision Pro window (#17): the same sidebar, the schedule as the content
    /// column under a system toolbar (view switcher, undo and redo, the View menu's
    /// per-window toggles, the Production menu's commands, the inspector toggle), and the
    /// inspector as a trailing column of the detail. No manual dark mode or window tint:
    /// the appearance follows the system there (story 77 of #1).
    private var threeColumnBody: some View {
        let base = NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
                // The sidebar is a fixed column, not a scroll view: with the keyboard up
                // it would otherwise be squeezed into the space above it.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 420)
        } detail: {
            // No navigation title here: the document's own title, its Rename menu and
            // its Back button sit over the sidebar (the document infrastructure puts
            // them there), and a second title would share the centre of this bar with
            // the view switcher and take its taps. The infrastructure mirrors its Back
            // button and title menu into this bar as well; `navigationBarBackButtonHidden`
            // does not remove the mirror and `toolbar(removing: .title)` takes the
            // principal item with it, so the mirror stays (it closes the document).
            scheduleContent
                .padding(10)
                .toolbar { threeColumnToolbar }
                // The system's inspector column on the iPad, a trailing pane on the
                // Vision Pro (PlatformInspector, a seam).
                .trailingInspector(isPresented: $showInspector) {
                    inspectorView
                }
        }
        .accentColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))

        let withAlerts    = applyAlerts(base)
        let withSheets    = applySheets(withAlerts)
        let withExport    = applyExportPresentation(withSheets)
        let withClipboard = applyClipboard(withExport)
        return applyLifecycle(withClipboard)
    }

    /// The content column's toolbar in the three-column layout. The view switcher and
    /// the Share menu are the Mac toolbar's; undo and redo are the Edit menu's, for a finger with no keyboard
    /// (the iPad's menu bar carries the same commands with the Mac's shortcuts, #22); the
    /// two menus carry what the Mac's View and Production menus do, on the same command
    /// closures (`projectCommands`).
    @ToolbarContentBuilder
    private var threeColumnToolbar: some ToolbarContent {
        // Leading, not principal: the document infrastructure wraps a principal item in
        // the document title's menu, whose interaction took the picker's taps. Each item
        // on its own, without the bar's shared glass: the segmented control draws its own
        // capsule, and inside the group's capsule it showed as a pill within a pill.
        ToolbarItem(placement: .navigation) {
            scheduleViewPicker
                .frame(minWidth: 220)
        }
        .withoutSharedToolbarBackground()
        ToolbarItem(placement: .navigation) {
            SyncStateIndicator(monitor: syncMonitor)
        }
        .withoutSharedToolbarBackground()
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                undoManager?.undo()
            } label: {
                Label(L("Undo"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!undoAvailability.canUndo)
            Button {
                undoManager?.redo()
            } label: {
                Label(L("Redo"), systemImage: "arrow.uturn.forward")
            }
            .disabled(!undoAvailability.canRedo)

            Menu {
                Toggle(L("Show Cast in Calendar"), isOn: $showCastOnCards)
                Toggle(L("Show Estimated Time Instead of Page Count"), isOn: $showEstTimeOnCards)
                Divider()
                Toggle(L("Show All Days on Stripboard"), isOn: $stripboardShowAllDays)
                Toggle(L("Show Shots on Stripboard"), isOn: showShotsBinding)
                Button(L("Stripboard Fields…")) { projectCommands.showStripboardFields() }
                Divider()
                Button(L("Color Legend…")) { projectCommands.showColorLegend() }
                Button(L("Customize Scene Colors…")) { projectCommands.showSceneColorSettings() }
            } label: {
                Label(L("View"), systemImage: "eye")
            }

            Menu {
                Button(L("Production Setup…")) { projectCommands.openProductionSetup() }
                Button(L("Scan for Conflicts…")) { projectCommands.scanForConflicts() }
                Button(L("Breakdown Browser…")) { projectCommands.openBreakdownBrowser() }
                Divider()
                Button(L("Lock Schedule")) { projectCommands.lockSchedule() }
                Button(L("Unlock Schedule")) { projectCommands.unlockSchedule() }
                    .disabled(productionInfo.scheduleLock == nil)
                Button(L("Schedule Lock Report…")) { projectCommands.showScheduleLockReport() }
            } label: {
                Label(L("Production"), systemImage: "clapperboard")
            }

            // Each export opens the preview sheet with Share here (#23).
            shareMenu

            Button {
                showInspector.toggle()
            } label: {
                Label(L("Inspector"), systemImage: "sidebar.trailing")
            }
        }
    }

    // MARK: - Toolbar pieces both layouts share

    /// Calendar or Stripboard: the one control that switches what the window schedules
    /// in, centred in the Mac's window toolbar and leading in the iPad's.
    private var scheduleViewPicker: some View {
        Picker(L("Schedule View"), selection: $viewMode) {
            ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                Label(mode.localizedTitle, systemImage: mode.systemImage)
                    .labelStyle(.titleAndIcon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(L("Switch between the calendar and the Stripboard"))
    }

    /// Every PDF the project exports, in one Share menu: the Mac's save panel or the
    /// preview sheet with Share (#23) takes it from there. The month calendar goes through
    /// its options sheet first, which picks the month among those the shoot spans.
    private var shareMenu: some View {
        Menu {
            Button(L("Schedule Calendar…"))  { projectCommands.exportSchedulePDF() }
            // One item, not a submenu of months: a submenu's own row does nothing on a
            // click, which read as broken. The sheet picks the month.
            Button(L("Month Calendar…"))     { openMonthPDFOptions() }
                .disabled(shootDays.isEmpty)
            Button(L("Strip Schedule…"))     { projectCommands.exportStripboardPDF() }
            Button(L("Shooting Schedule…"))  { showShootingSchedulePDFSavePanel() }
            Divider()
            Button(L("Days Out of Days…"))   { projectCommands.exportDaysOutOfDays() }
            Button(L("Scene Breakdowns…"))   { projectCommands.exportBreakdowns() }
            Button(L("Shot List…"))          { projectCommands.exportShotList() }
            if let day = selectedDay {
                Divider()
                Button("\(L("Call Sheet for")) \(formattedDate(day.date))…") { showCallSheetPDFSavePanel(for: day) }
            }
        } label: {
            Label(L("Share"), systemImage: "square.and.arrow.up")
        }
        .menuIndicator(.hidden)
        .help(L("Export the schedule, calendars, reports and call sheets as PDFs"))
    }

    /// Opens the month calendar's sheet on this month when the shoot spans it, else on the
    /// shoot's first month.
    private func openMonthPDFOptions() {
        let months = document.project.productionMonths()
        let now    = Calendar.current.dateComponents([.year, .month], from: Date())
        monthPDFMonth = months.first { Calendar.current.dateComponents([.year, .month], from: $0) == now }
            ?? months.first ?? Date()
        activeSheet = .monthPDFOptions
    }

    /// The month calendar's month and options, then its export (Share ▸ Month Calendar…).
    private var monthPDFOptionsSheet: some View {
        MonthPDFOptionsSheet(
            selectedFields:       Binding(
                get: { StripboardFieldSettings.decode(monthPDFFieldsRaw) },
                set: { monthPDFFieldsRaw = StripboardFieldSettings.encode($0) }
            ),
            includePageCount:     $monthPDFShowPages,
            includeEstimatedTime: $monthPDFShowTime,
            onCancel:             { activeSheet = nil },
            onExport:             {
                activeSheet = nil
                exportMonthPDF(month: monthPDFMonth, options: MonthPDFOptions(
                    fields:               StripboardFieldSettings.decode(monthPDFFieldsRaw),
                    includePageCount:     monthPDFShowPages,
                    includeEstimatedTime: monthPDFShowTime
                ))
            },
            month:                $monthPDFMonth,
            months:               document.project.productionMonths()
        )
    }

    /// The Shot List's scope and frames, then its export (File ▸ Export Shot List…,
    /// Share ▸ Shot List…).
    private var shotListOptionsSheet: some View {
        ShotListOptionsSheet(
            shootDays:     shootDays,
            scopeRaw:      $shotListScopeRaw,
            includeFrames: $shotListIncludeFrames,
            pendingExport: $pendingShotListExport,
            dismiss:       { activeSheet = nil }
        )
    }

    /// The `.sheet`'s `onDismiss`: the export the options sheet asked for, once it is gone.
    private func runPendingShotListExport() {
        ShotListOptionsSheet.runPendingExport($pendingShotListExport) { exportShotList(options: $0) }
    }

    // MARK: - Mac window toolbar

    /// The Mac window's toolbar: the view switcher centred, then the sync state, the
    /// Stripboard's display options (only where they have an effect), Share, and the
    /// search field the system puts at the trailing end (`.searchable` in `detailView`).
    /// The statistics are the title's subtitle (`scheduleSummary`), so the bar holds
    /// controls only.
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            scheduleViewPicker
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStateIndicator(monitor: syncMonitor)
        }
        .withoutSharedToolbarBackground()
        ToolbarItemGroup(placement: .primaryAction) {
            // Only the Stripboard prints per-field chips and folds empty days, so its
            // options are absent in calendar mode rather than offering settings with no
            // visible effect there.
            if viewMode == .stripboard {
                Menu {
                    Button("\(L("Stripboard Fields…")) (\(stripboardFields.wrappedValue.count))") {
                        activeSheet = .stripboardFields
                    }
                    // Off by default: a shoot with blocks months apart would otherwise be
                    // mostly empty day sections. The calendar always shows every date.
                    Toggle(L("Show All Days"), isOn: $stripboardShowAllDays)
                    // The View menu's Show Shots on Stripboard (#42), the same binding.
                    Toggle(L("Show Shots"), isOn: showShotsBinding)
                } label: {
                    Label(L("Display"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuIndicator(.hidden)
                .help(L("Choose the fields each strip shows, whether empty days are listed and whether shots are shown"))
            }
            shareMenu
        }
    }

    /// The schedule at a glance, under the window title: days, progress, time, Boneyard.
    private var scheduleSummary: String {
        // Short enough to sit beside the view switcher and the window's "Edited" in a
        // 1100-point window without truncating.
        let days = scheduledDays.count
        var parts = [
            "\(days) \(L(days == 1 ? "day" : "days"))",
            "\(completedScenesCount)/\(totalScenes) \(L("done"))",
            totalEstTime,
        ]
        if unscheduledCount > 0 {
            parts.append("\(unscheduledCount) \(L("in Boneyard"))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Modifiers

    /// One alert for both messages. Two `.alert(isPresented:)` chained on one view left
    /// the inner one (`showingAlert`: every export failure, the schedule lock, the empty
    /// Breakdown Browser) never presenting on macOS 27, only the outer import result
    /// (#36's review; learnings 2026-09-23). The import result wins if both are set.
    private var messageAlertPresented: Binding<Bool> {
        Binding(
            get: { showingAlert || showingImportAlert },
            set: { presented in
                if !presented {
                    showingAlert       = false
                    showingImportAlert = false
                }
            }
        )
    }

    private func applyAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert(showingImportAlert ? L("Import Result") : "CineSched", isPresented: messageAlertPresented) {
                Button(L("OK")) {}
            } message: {
                Text(showingImportAlert ? importMessage : alertMessage)
            }
            .confirmationDialog(
                "Import into Current Project?",
                isPresented: $showingFountainImportConfirmation,
                titleVisibility: .visible
            ) {
                Button("Import") { confirmPendingFountainImport() }
                Button("Cancel", role: .cancel) { cancelPendingFountainImport() }
            } message: {
                if let result = pendingFountainImport {
                    Text("'\(projectTitle)' already has scenes or a schedule. This will add \(result.scenes.count) new scene\(result.scenes.count == 1 ? "" : "s") to the Boneyard — nothing existing will be changed or removed.")
                }
            }
    }

    private func applySheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingColorLegend) {
                ColorLegendView()
            }
            .sheet(isPresented: $showingImportSummary) {
                if let result = completedFountainImport {
                    ImportSummaryView(result: result, onDismiss: { showingImportSummary = false })
                }
            }
            .sheet(item: $activeSheet, onDismiss: runPendingShotListExport) { sheet in
                switch sheet {
                case .unscheduledEdit:
                    unscheduledEditSheet
                case .productionSetup:
                    ProductionSetupSheet(
                        productionInfo: productionInfoBinding,
                        scenes: allScenes + shootDays.flatMap { $0.scenes },
                        isPresented: isPresentedProductionSetup,
                        onSave: {},
                        onCharacterRenamed: renameCastCharacter
                    )
                case .conflictReport:
                    ConflictReportSheet(
                        conflicts: conflictReportResults,
                        onSelectDate: { date in
                            activeSheet = nil
                            scrollToDate = date
                        },
                        onDismiss: { activeSheet = nil }
                    )
                case .scheduleLockReport:
                    ScheduleLockReportSheet(
                        changes: derived.scheduleLockChanges,
                        lockedAt: productionInfo.scheduleLock?.lockedAt,
                        onSelectDate: { date in
                            activeSheet = nil
                            scrollToDate = date
                        },
                        onDismiss: { activeSheet = nil }
                    )
                case .breakdownBrowser:
                    breakdownBrowserEditSheet
                case .sceneColorSettings:
                    SceneColorSettingsSheet(
                        palette: palette,
                        onSetColor: setPaletteColor,
                        onReset: resetPalette,
                        onDismiss: { activeSheet = nil }
                    )
                case .stripboardFields:
                    StripboardFieldsSheet(selectedFields: stripboardFields, onDismiss: { activeSheet = nil })
                case .calendarEvent(let dayID, let eventID):
                    inspectorCalendarEventSheet(dayID: dayID, eventID: eventID)
                case .callSheet(let dayID):
                    inspectorCallSheetSheet(dayID: dayID)
                case .monthPDFOptions:
                    monthPDFOptionsSheet
                case .shotListOptions:
                    shotListOptionsSheet
                }
            }
            .onChange(of: activeSheet) { _, newValue in
                if newValue != .unscheduledEdit {
                    clearUnscheduledEditingState()
                }
                if newValue != .sceneColorSettings {
                    paletteGesture = nil
                }
            }
    }

    @ViewBuilder
    private var breakdownBrowserEditSheet: some View {
        Group {
            if breakdownBrowserScenes.indices.contains(breakdownBrowserIndex) {
                SceneEditSheet(
                    scene: $breakdownBrowserScenes[breakdownBrowserIndex],
                    isPresented: isPresentedBreakdownBrowser,
                    onSave: { writeBackCurrentBreakdownScene() },
                    onDelete: { deleteCurrentBreakdownScene() },
                    canGoPrevious: breakdownBrowserIndex > 0,
                    canGoNext: breakdownBrowserIndex < breakdownBrowserScenes.count - 1,
                    onPrevious: goToPreviousBreakdownScene,
                    onNext: goToNextBreakdownScene,
                    positionLabel: "Scene \(breakdownBrowserIndex + 1) of \(breakdownBrowserScenes.count) — script order",
                    breakdownExpandedByDefault: true,
                    closeAfterDelete: false,
                    context: derived.sceneEditor
                )
            } else {
                VStack(spacing: 20) {
                    Text("No scenes to browse").font(.title2).foregroundColor(.secondary)
                    Button("Close") { activeSheet = nil }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24).frame(width: 400)
                .onAppear {
                    populateBreakdownBrowserScenes()
                }
            }
        }
        .id(breakdownBrowserScenes.isEmpty)
    }

    private func applyLifecycle<Content: View>(_ content: Content) -> some View {
        content
            // The kind and modifier keys of every press, for the selection's ⌘ and ⇧
            // where there are no flags to poll (#22, InputPress.swift). An observer, not
            // a gesture: one over the whole editor swallowed every Button on iPadOS 27.
            .recordsInputPresses()
            .focusedSceneValue(\.projectCommands, projectCommands)
            // The same commands for the iPad's menu bar, by window activity (#22).
            .onChange(of: appearsActive, initial: true) { _, active in
                if active { activeProject?.publish(projectCommands, from: editorID) }
                else      { activeProject?.retire(editorID) }
            }
            .onDisappear { activeProject?.retire(editorID) }
            // The one place the palette enters the view tree; every strip, card and sheet
            // below reads it from the environment rather than from the device.
            .environment(\.scenePalette, palette)
            // The sync monitor's whole lifecycle (start, stop, the counts, the scene
            // phase, the undo manager) is the modifier's.
            .syncMonitored(syncMonitor, document: document)
            .onAppear {
                columnVisibility = sidebarCollapsedPreference ? .detailOnly : .all
            }
            .onChange(of: columnVisibility) { _, newValue in
                sidebarCollapsedPreference = (newValue == .detailOnly)
            }
            // Every path into the project (an edit, an undo, a reload from disk) moves the
            // change count. The derived sets follow it through `derived`; only the
            // selection is real state that has to be trimmed here.
            .onChange(of: document.changeCount) { _, _ in
                pruneSelection()
                refreshUndoAvailability()
            }
            .onChange(of: document.restoreCount) { _, _ in
                seedRangePickers()
            }
            // The manager says when its stacks changed: after an edit's group closes, after
            // an undo and after a redo. The change count above fires during the undo,
            // before the redo is on the stack. Not `NSUndoManagerCheckpoint`: reading
            // `canRedo` posts one, so that handler would call itself forever.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { refreshUndoAvailability(after: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { refreshUndoAvailability(after: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { refreshUndoAvailability(after: $0) }
            .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) { _, _ in refreshUndoAvailability() }
            .onChange(of: titleFieldFocused) { _, focused in
                if !focused { titleGesture = EditGesture() }
            }
            // A shot's page in the inspector (#42) belongs to the scene it was asked for.
            .onChange(of: selection) { _, new in
                if let route = inspectorRoute, new != .scene(id: route.sceneID) { inspectorRoute = nil }
            }
    }

    /// The menu commands this window answers (see ProjectCommands.swift).
    private var projectCommands: ProjectCommands {
        ProjectCommands(
            importScript:           showScriptImportPanel,
            exportSchedulePDF:      showSchedulePDFSavePanel,
            exportStripboardPDF:    showStripboardPDFSavePanel,
            exportDaysOutOfDays:    showDaysOutOfDaysPDFSavePanel,
            exportBreakdowns:       showBreakdownPDFSavePanel,
            exportShotList:         { activeSheet = .shotListOptions },
            openProductionSetup:    { activeSheet = .productionSetup },
            scanForConflicts:       {
                conflictReportResults = ConflictScanner.scan(shootDays: shootDays, productionInfo: productionInfo)
                activeSheet = .conflictReport
            },
            openBreakdownBrowser:   openBreakdownBrowser,
            lockSchedule:           lockSchedule,
            unlockSchedule:         unlockSchedule,
            showScheduleLockReport: { activeSheet = .scheduleLockReport },
            showColorLegend:        { showingColorLegend = true },
            showSceneColorSettings: { activeSheet = .sceneColorSettings },
            showStripboardFields:   {
                // The picker is only meaningful on the Stripboard, so the menu item also
                // switches views rather than opening a sheet over a calendar it won't affect.
                viewMode = .stripboard
                activeSheet = .stripboardFields
            },
            viewMode:               $viewMode,
            showCastOnCards:        $showCastOnCards,
            showEstTimeOnCards:     $showEstTimeOnCards,
            stripboardShowAllDays:  $stripboardShowAllDays,
            showShotsOnStripboard:  showShotsBinding
        )
    }

    // MARK: - Edit funnel

    /// Applies one change to the project through the document's funnel, under the gesture
    /// a child view may have opened. `actionName` labels Undo and Redo in the Edit menu.
    func edit(_ actionName: String? = nil, _ change: (inout ProjectData) -> Void) {
        document.perform(actionName, coalescing: activeGesture, undoManager: undoManager, change)
    }

    /// `onBeforeSceneChange` for the calendar and Stripboard: opens the gesture their
    /// following binding writes fold into. Several calendar paths begin a gesture and finish
    /// through `assign`/`removeScene` without ever calling `onSceneChanged`, and a token that
    /// outlived its run-loop turn would fold the next unrelated edit into this step's undo,
    /// so the end of the turn closes it regardless.
    func beginEditGesture() {
        let gesture = EditGesture()
        activeGesture = gesture
        DispatchQueue.main.async {
            if activeGesture == gesture { activeGesture = nil }
        }
    }

    /// `onSceneChanged` for the calendar and Stripboard. The recomputation it used to do
    /// happens in `onChange(of: document.project)`, which also covers undo and reload.
    private func endEditGesture() {
        activeGesture = nil
    }

    /// The child views and editors mutate the project the way they always have, through
    /// bindings; these route every write through `edit`.
    var allScenesBinding: Binding<[Scene]> {
        Binding(get: { allScenes }, set: { new in edit { $0.allScenes = new } })
    }
    var shootDaysBinding: Binding<[ShootDay]> {
        Binding(get: { shootDays }, set: { new in edit { $0.shootDays = new } })
    }
    private var productionInfoBinding: Binding<ProductionInfo> {
        Binding(get: { productionInfo }, set: { new in edit(L("Edit Production Setup")) { $0.productionInfo = new } })
    }
    private var shiftModeBinding: Binding<Bool> {
        Binding(get: { isShiftModeEnabled }, set: { new in edit(L("Shift Schedule")) { $0.isShiftModeEnabled = new } })
    }
    private var projectTitleBinding: Binding<String> {
        Binding(get: { projectTitle }, set: { new in
            document.perform(L("Rename Project"), coalescing: titleGesture, undoManager: undoManager) { $0.projectTitle = new }
        })
    }

    // MARK: - Scene colors

    /// The color editor's write: one slot's hex into the project's palette (#11), one
    /// undo step per slot edited in a row.
    private func setPaletteColor(_ slot: SceneColorSlot, _ hex: String) {
        let token: EditGesture
        if let open = paletteGesture, open.slot == slot {
            token = open.token
        } else {
            token = EditGesture()
            paletteGesture = (slot, token)
        }
        document.perform(L("Change Scene Color"), coalescing: token, undoManager: undoManager) {
            $0.setStripColor(hex, for: slot)
        }
    }

    /// Reset All to Defaults: the standard code, written out in full so the project keeps
    /// a palette (a nil one would adopt this device's legacy overrides on the next open).
    private func resetPalette() {
        paletteGesture = nil
        edit(L("Reset Scene Colors")) { $0.palette = .standard }
    }

    private func seedRangePickers() {
        guard let range = Self.dateRange(of: shootDays), range != seededRange else { return }
        startDate   = range.lowerBound
        endDate     = range.upperBound
        seededRange = range
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Movie Title", text: projectTitleBinding)
                .font(.title2)
                .padding(.bottom, 2)
                .focused($titleFieldFocused)

            Text("\(L("Shoot Days:")) \(shootDays.filter { !$0.scenes.isEmpty }.count)")
                .font(.subheadline).foregroundColor(.gray)

            if let first = shootDays.first?.date, let last = shootDays.last?.date {
                Text("\(L("From")) \(formattedDate(first)) \(L("to")) \(formattedDate(last))")
                    .font(.subheadline).foregroundColor(.gray)
            }

            Divider().padding(.vertical, 2)

            // Date range picker — collapsible
            DisclosureGroup(isExpanded: $isDateRangeExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker(L("Start Date"), selection: $startDate, displayedComponents: .date)
                    DatePicker(L("End Date"), selection: $endDate, displayedComponents: .date)

                    Toggle(isOn: shiftModeBinding) {
                        HStack(spacing: 4) {
                            Text(L("Shift Schedule"))
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .fastTooltip(
                        LocalizationManager.shared.currentLanguage == .spanish
                            ? "Desplazar Calendario\nCuando está activado, al cambiar la Fecha de Inicio se desplazan automáticamente todas las escenas ya programadas en el calendario, conservando la distribución del plan de rodaje."
                            : "Shift Schedule\nWhen enabled, changing the Start Date automatically shifts all scheduled scenes across the calendar, preserving your shoot day plan."
                    )

                    Button(L("Update Calendar")) { updateShootDays(from: startDate, to: endDate) }
                }
                .padding(.top, 4)
            } label: {
                Text(L("Select Date Range")).font(.headline)
            }

            Divider().padding(.vertical, 2)

            // New Scene form — collapsible
            DisclosureGroup(isExpanded: $isNewSceneExpanded) {
                NewSceneInputView(
                    newSceneNumber:   $newSceneNumber,
                    newSceneTitle:    $newSceneTitle,
                    newDuration:      $newDuration,
                    newEstimate:      $newEstimate,
                    newDayNightType:  $newDayNightType,
                    allScenes:        allScenesBinding
                )
                .padding(.top, 4)
            } label: {
                Text(L("New Scene")).font(.headline)
            }

            Divider().padding(.vertical, 2)

            // Boneyard header with sort menu
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("Boneyard")).font(.headline)
                    Spacer()
                    if !selectedSceneIDs.isEmpty {
                        Button(L("Clear")) { selectedSceneIDs = []; lastSelectedSceneID = nil }
                            .buttonStyle(.plain)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                HStack {
                    if !selectedSceneIDs.isEmpty {
                        Text("· \(selectedSceneIDs.count) \(L("selected"))")
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))
                    }
                    Spacer()
                    Menu {
                        Button(L("Show Order"))    { boneyardSort = .showOrder }
                        Button(L("Default"))       { boneyardSort = .defaultOrder }
                        Button(L("Location"))      { boneyardSort = .location }
                        Button(L("INT/EXT"))       { boneyardSort = .intExt }
                        Button(L("Cast"))          { boneyardSort = .cast }
                        Button(L("Day/Night"))     { boneyardSort = .dayNight }
                    } label: {
                        HStack(spacing: 3) {
                            Text(boneyardSort.localizedTitle)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .borderlessButtonMenuStyle()
                }
            }

            if layout == .twoColumn {
                // Touch has no modifier keys; multi-select there is #18's.
                Text("⌘-click or ⇧-click to select multiple, then drag as a group")
                    .font(.caption2).foregroundColor(.secondary)
            }

            boneyardList
                .frame(maxHeight: .infinity)
        }
        .padding(10)
        // The Mac's 300 is its window minimum; the iPad column may go a little narrower.
        .frame(minWidth: layout == .twoColumn ? 300 : 280, maxHeight: .infinity)
        // The Mac's panel tint; the iPad's sidebar column keeps the system's material.
        .background(layout == .twoColumn ? currentTheme.panelBackground(isDarkMode: isDarkMode) : Color.clear)
    }

    // MARK: - Schedule Lock

    /// The snapshot and its storage are `ProjectData.lockSchedule(now:)` (ProductionEdits.swift),
    /// the phone's too.
    private func lockSchedule() {
        edit(L("Lock Schedule")) { $0.lockSchedule() }
        alertMessage = "Schedule locked. You'll be notified in the Schedule Lock Report if any actor's working days change from here."
        showingAlert = true
    }

    private func unlockSchedule() {
        guard productionInfo.scheduleLock != nil else { return }
        edit(L("Unlock Schedule")) { $0.unlockSchedule() }
    }

    // MARK: - Selection and cast helpers

    /// Re-reads `canUndo`/`canRedo` into `undoAvailability`; `notification` limits the
    /// manager notifications to this window's manager.
    private func refreshUndoAvailability(after notification: Notification? = nil) {
        if let notification, let sender = notification.object as? UndoManager, sender !== undoManager { return }
        let next = UndoAvailability(canUndo: undoManager?.canUndo ?? false, canRedo: undoManager?.canRedo ?? false)
        if next != undoAvailability { undoAvailability = next }
    }

    /// Drops selected IDs that are no longer in the project. Writes the selection only when
    /// something was dropped, so the usual edit does not invalidate the view a second time.
    private func pruneSelection() {
        if let selection, selection.pruned(in: document.project) == nil {
            self.selection = nil
        }
        guard !selectedSceneIDs.isEmpty else { return }
        let scheduledIDs = Set(shootDays.flatMap { $0.scenes.map(\.id) })
        let boneyardIDs  = Set(allScenes.map(\.id))
        let pruned = selectedSceneIDs.intersection(scheduledIDs.union(boneyardIDs))
        if pruned != selectedSceneIDs { selectedSceneIDs = pruned }
    }

    /// `lastSelectedSceneID` as the schedule views and the Boneyard write it: every
    /// single tap on a strip lands here (the plain-select branch of `selectScene` writes
    /// the id whether or not it changed), so it is also where a tap selects the scene
    /// into the inspector (#17). Clear (nil) drops a scene selection and leaves a day's.
    private var lastSelectedSceneBinding: Binding<UUID?> {
        Binding(get: { lastSelectedSceneID }, set: { id in
            lastSelectedSceneID = id
            if let id {
                selection = .scene(id: id)
                focusEditor()
            } else if case .scene = selection {
                selection = nil
            }
        })
    }

    /// The day the inspector shows, for the schedule views' selected outline. Nil in the
    /// two-column layout: the Mac has no inspector, so a day is never outlined there and
    /// the date in a cell stays the button that opens Day Detail (#17, "Mac unchanged").
    private var selectedDayID: UUID? {
        guard layout == .threeColumn, case .day(let id) = selection else { return nil }
        return id
    }

    /// What a tap on a day does in the three-column layout: select it into the inspector.
    /// Nil on the Mac for the same reason as `selectedDayID`.
    private var onSelectDay: ((ShootDay) -> Void)? {
        guard layout == .threeColumn else { return nil }
        return { day in selection = .day(id: day.id); focusEditor() }
    }

    /// That day itself, for the Export menu's call sheet item.
    private var selectedDay: ShootDay? {
        guard let id = selectedDayID, let index = document.project.dayIndex(forDayID: id) else { return nil }
        return shootDays[index]
    }

    /// The rename's rule (every cast and call sheet override, without case; blanks and a
    /// case-only change refused) is `ProjectData.renameCharacter(from:to:)`, the phone's too.
    private func renameCastCharacter(from oldName: String, to newName: String) {
        // Only Production Setup's Save renames (possibly several characters), and its own
        // write of the roster follows in the same turn; one gesture folds all of it into
        // one step.
        if activeGesture == nil { beginEditGesture() }
        edit(L("Edit Production Setup")) { $0.renameCharacter(from: oldName, to: newName) }
    }

    // MARK: - Boneyard scene navigation

    private var currentBoneyardPosition: Int? {
        guard let idx = editingUnscheduledSceneIndex else { return nil }
        return derived.sortedBoneyard.firstIndex { $0.index == idx }
    }

    private func goToPreviousUnscheduledScene() {
        guard let pos = currentBoneyardPosition, pos > 0 else { return }
        let target = derived.sortedBoneyard[pos - 1]
        editingUnscheduledSceneIndex = target.index
        editingUnscheduledScene      = target.scene
    }

    private func goToNextUnscheduledScene() {
        guard let pos = currentBoneyardPosition, pos < derived.sortedBoneyard.count - 1 else { return }
        let target = derived.sortedBoneyard[pos + 1]
        editingUnscheduledSceneIndex = target.index
        editingUnscheduledScene      = target.scene
    }

    // MARK: - Boneyard list (Movie Magic strip styling)

    /// The list itself is `BoneyardListView`, shared by both layouts; this wires its
    /// actions to the selection, the sheets and the edit funnel.
    private var boneyardList: some View {
        let state = derived
        return BoneyardListView(
            items:                   state.sortedBoneyard,
            duplicateSceneNumberIDs: state.duplicateSceneNumberIDs,
            selectedSceneIDs:        selectedSceneIDs,
            onSelect:                selectScene,
            onEdit:                  { index, scene in
                editingUnscheduledSceneIndex = index
                editingUnscheduledScene      = scene
                activeSheet = .unscheduledEdit
            },
            onDuplicate:             duplicateBoneyardScene,
            onDelete:                { index in
                edit(L("Delete Scene")) { $0.allScenes.remove(at: index) }
            },
            dragPayload:             boneyardDragPayload,
            onDropFromSchedule:      moveScenesToBoneyard
        )
        // The Boneyard and the board fade together in an inactive window (#22); the
        // Mac's two-column layout is left as it was.
        .dimsWhenInactive(layout == .threeColumn)
    }

    /// Duplicate Scene in the Boneyard: `ProjectData.duplicateScene(withID:)`, the copy the
    /// Stripboard and the phone make (`Scene.duplicated()`: a new id, " (Copy)" on the
    /// title, the breakdown carried over; the set, the times and completion start fresh).
    private func duplicateBoneyardScene(_ scene: Scene) {
        edit(L("Duplicate Scene")) { $0.duplicateScene(withID: scene.id) }
    }

    /// Strips dropped on the Boneyard from a day, on either schedule view: back to the
    /// Boneyard in board order (events stay on their day; a day or a band is ignored). A
    /// payload from the Boneyard itself moves nothing, and an edit that moves nothing
    /// registers nothing.
    private func moveScenesToBoneyard(_ items: [ScheduleDragPayload]) {
        let ids = items.flatMap(\.sceneIDs)
        guard !ids.isEmpty else { return }
        edit(L("Move to Boneyard")) { data in
            ScheduleMoves.returnToBoneyard(ids, days: &data.shootDays, boneyard: &data.allScenes)
        }
    }

    // MARK: - Boneyard selection helpers

    private func selectScene(_ id: UUID) {
        let flags = ModifierKeys.current
        if flags.contains(.command) {
            if selectedSceneIDs.contains(id) { selectedSceneIDs.remove(id) } else { selectedSceneIDs.insert(id) }
            lastSelectedSceneID = id
        } else if flags.contains(.shift), let anchor = lastSelectedSceneID,
                  let anchorIdx  = derived.sortedBoneyard.firstIndex(where: { $0.scene.id == anchor }),
                  let targetIdx  = derived.sortedBoneyard.firstIndex(where: { $0.scene.id == id }) {
            let range = anchorIdx < targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
            selectedSceneIDs.formUnion(range.map { derived.sortedBoneyard[$0].scene.id })
        } else {
            selectedSceneIDs = [id]
            lastSelectedSceneID = id
        }
        // The tapped scene is what the inspector shows (#17), whatever the modifiers.
        selection = .scene(id: id)
        focusEditor()
    }

    /// What a Boneyard row carries when it lifts (#18): the whole multi-selection when the
    /// row is part of it (every selected scene, in display order), the row alone otherwise.
    /// A single unselected row becomes the selection as it always has (a click-and-drag is
    /// a click).
    private func boneyardDragPayload(for scene: Scene) -> ScheduleDragPayload {
        let ids: [UUID]
        if selectedSceneIDs.count > 1, selectedSceneIDs.contains(scene.id) {
            ids = derived.sortedBoneyard.map(\.scene.id).filter { selectedSceneIDs.contains($0) }
        } else {
            selectedSceneIDs    = [scene.id]
            lastSelectedSceneID = scene.id
            ids = [scene.id]
        }
        return .scenes(ids, from: nil)
    }

    // MARK: - Detail / main area

    /// The Mac's detail column: the schedule under the window toolbar (`macToolbar`), the
    /// statistics as the title's subtitle and the scene search in the toolbar.
    private var detailView: some View {
        scheduleContent
            .overlay(alignment: .topTrailing) { searchResultsAnchor }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(currentTheme.canvasBackground(isDarkMode: isDarkMode))
            .windowSubtitle(scheduleSummary)
            .toolbar { macToolbar }
            .searchable(text: $searchQuery, placement: .toolbar, prompt: Text(L("Search scenes")))
            .onSubmit(of: .search) {
                if let first = scheduleSearchResults.first { selectSearchResult(first) }
            }
    }

    /// The calendar or the Stripboard, whichever `viewMode` says, wired to the funnel and
    /// the selection; shared by both layouts. The inspector hooks (`onSelectDay`,
    /// `selectedDayID`) are live in both, but only the three-column layout shows what
    /// they select.
    private var scheduleContent: some View {
        let state = derived
        return Group {
            if viewMode == .calendar {
                CompactMonthCalendarView(
                    shootDays:    shootDaysBinding,
                    assignScene:  assign,
                    allScenes:    allScenesBinding,
                    updateScene:  updateScene,
                    removeScene:  removeScene,
                    projectTitle: projectTitle,
                    productionInfo: productionInfo,
                    isSidebarCollapsed: isSidebarCollapsed,
                    showCastOnCards: showCastOnCards,
                    showEstTimeOnCards: showEstTimeOnCards,
                    startDate: startDate,
                    endDate: endDate,
                    selectedSceneIDs: $selectedSceneIDs,
                    lastSelectedSceneID: lastSelectedSceneBinding,
                    conflictDates: state.conflictDates,
                    conflictSceneIDs: state.conflictSceneIDs,
                    duplicateSceneNumberIDs: state.duplicateSceneNumberIDs,
                    scheduleLockChangedDates: state.scheduleLockChangedDates,
                    scrollToDate: $scrollToDate,
                    dragStateResetToken: document.restoreCount,
                    onBeforeSceneChange: beginEditGesture,
                    onSceneChanged: endEditGesture,
                    onCallSheetExport: { day in
                        showCallSheetPDFSavePanel(for: day)
                    },
                    onSelectDay: onSelectDay,
                    selectedDayID: selectedDayID,
                    // Seven columns beside a sidebar and an inspector: the iPad's floor is
                    // what fits a 13-inch landscape window with both open.
                    minimumCellWidth: layout == .twoColumn ? 100 : 72,
                    sceneEditorContext: state.sceneEditor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StripboardView(
                    shootDays: shootDaysBinding,
                    allScenes: allScenesBinding,
                    productionInfo: productionInfo,
                    visibleFields: stripboardFields.wrappedValue,
                    showAllDays: stripboardShowAllDays,
                    selectedSceneIDs: $selectedSceneIDs,
                    lastSelectedSceneID: lastSelectedSceneBinding,
                    conflictDates: state.conflictDates,
                    conflictSceneIDs: state.conflictSceneIDs,
                    duplicateSceneNumberIDs: state.duplicateSceneNumberIDs,
                    scrollToDate: $scrollToDate,
                    dragStateResetToken: document.restoreCount,
                    onBeforeSceneChange: beginEditGesture,
                    onSceneChanged: endEditGesture,
                    onCallSheetExport: { day in
                        showCallSheetPDFSavePanel(for: day)
                    },
                    onShootingScheduleExport: { days in
                        showShootingSchedulePDFSavePanel(for: days)
                    },
                    onSelectDay: onSelectDay,
                    selectedDayID: selectedDayID,
                    shotExpansion: shotExpansionBinding,
                    onMoveShot: moveShot,
                    onSelectShot: onSelectShot,
                    sceneEditorContext: state.sceneEditor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // An inactive window's board is dimmed (#22), so with two projects open it is
        // plain which one the keyboard and the pasteboard act on; not on the Mac, whose
        // board the spec leaves as it was.
        .dimsWhenInactive(layout == .threeColumn)
    }

    // MARK: - Shots on the Stripboard (#42)

    /// Which strips show their shots: this window's Show Shots and the chevrons' exceptions.
    private var shotExpansionBinding: Binding<ShotExpansion> {
        ShotExpansion.binding(showAll: $showShots, exceptions: $shotExpansionExceptions)
    }

    /// Show Shots, for the View menu, the toolbar's menus and `projectCommands`: every strip
    /// at once, the chevrons' exceptions dropped.
    private var showShotsBinding: Binding<Bool> {
        ShotExpansion.showAllBinding(shotExpansionBinding)
    }

    /// A shot dropped among its scene's sub-rows: one edit, one undo step, the letters
    /// following the new order and the estimate (the strip's time) unchanged.
    private func moveShot(_ shotID: UUID, inSceneID sceneID: UUID, to position: ShotDropPosition) {
        edit(L("Move Shot")) { $0.moveShot(withID: shotID, inSceneID: sceneID, to: position) }
    }

    /// What a single tap on a shot sub-row does in the three-column layout: the scene
    /// becomes the selection and the inspector opens on the shot's page. Nil on the Mac,
    /// which has no inspector (a click selects the strip; a double-click opens the sheet).
    private var onSelectShot: ((UUID, UUID) -> Void)? {
        guard layout == .threeColumn else { return nil }
        return { sceneID, shotID in
            selectedSceneIDs    = [sceneID]
            lastSelectedSceneID = sceneID
            inspectorRoute      = InspectorRoute(sceneID: sceneID, route: .shot(shotID))
            selection           = .scene(id: sceneID)
            focusEditor()
        }
    }

    // MARK: - Stripboard fields

    /// Live view of the persisted Stripboard field selection. Writes go straight back to
    /// UserDefaults through the @AppStorage string, so the sheet's toggles update the board
    /// behind them immediately.
    private var stripboardFields: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(stripboardFieldsRaw) },
            set: { stripboardFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    // MARK: - Schedule search

    fileprivate struct ScheduleSearchResult: Identifiable {
        let id = UUID()
        let scene: Scene
        let dayDate: Date?
    }

    private var scheduleSearchResults: [ScheduleSearchResult] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }

        func matches(_ scene: Scene) -> Bool {
            if scene.title.lowercased().contains(query) { return true }
            if scene.summary.lowercased().contains(query) { return true }
            if scene.cast.contains(where: { $0.lowercased().contains(query) }) { return true }
            return false
        }

        var results: [ScheduleSearchResult] = []
        for scene in allScenes where matches(scene) {
            results.append(ScheduleSearchResult(scene: scene, dayDate: nil))
        }
        for day in shootDays {
            for scene in day.scenes where matches(scene) {
                results.append(ScheduleSearchResult(scene: scene, dayDate: day.date))
            }
        }
        return Array(results.prefix(30))
    }

    private var searchPopoverIsPresented: Binding<Bool> {
        Binding<Bool>(
            get: { self.searchPopoverShouldShow },
            set: { (newValue: Bool) in if !newValue { self.searchQuery = "" } }
        )
    }

    private var searchPopoverShouldShow: Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        return !scheduleSearchResults.isEmpty
    }

    private var searchPopoverHeight: CGFloat {
        let rowHeight: CGFloat = 46
        let padding: CGFloat = 8
        let maxHeight: CGFloat = 340
        let contentHeight: CGFloat = CGFloat(scheduleSearchResults.count) * rowHeight + padding
        return min(contentHeight, maxHeight)
    }

    private func selectSearchResult(_ result: ScheduleSearchResult) {
        selectedSceneIDs = [result.scene.id]
        lastSelectedSceneID = result.scene.id
        if let date = result.dayDate { scrollToDate = date }
        searchQuery = ""
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(scheduleSearchResults) { result in
                    ScheduleSearchResultRow(result: result, onSelect: { self.selectSearchResult(result) })
                    Divider()
                }
            }
        }
        .frame(width: 320, height: searchPopoverHeight)
    }

    /// Where the results hang: an invisible strip at the top trailing corner of the
    /// schedule, under the toolbar's search field, since a popover cannot anchor to the
    /// system's field itself.
    private var searchResultsAnchor: some View {
        Color.clear
            .frame(width: 240, height: 1)
            .allowsHitTesting(false)
            .popover(isPresented: searchPopoverIsPresented, arrowEdge: .top) {
                searchResultsList
            }
    }

    func statBadge(icon: String, value: String, label: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            Text(value)
                .font(.system(.body, design: .rounded)).fontWeight(.semibold).foregroundColor(color)
            if let label = label {
                Text(L(label)).font(.caption).foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - Unscheduled scene edit sheet

    @ViewBuilder
    private var unscheduledEditSheet: some View {
        if let idx = editingUnscheduledSceneIndex, idx < allScenes.count {
            SceneEditSheet(
                scene: allScenesBinding[idx],
                isPresented: isPresentedUnscheduledEdit,
                onSave: {},
                onDelete: {
                    if let i = editingUnscheduledSceneIndex {
                        edit(L("Delete Scene")) { $0.allScenes.remove(at: i) }
                    }
                    clearUnscheduledEditingState()
                },
                canGoPrevious: (currentBoneyardPosition ?? 0) > 0,
                canGoNext: currentBoneyardPosition.map { $0 < derived.sortedBoneyard.count - 1 } ?? false,
                onPrevious: goToPreviousUnscheduledScene,
                onNext: goToNextUnscheduledScene,
                positionLabel: currentBoneyardPosition.map { "Scene \($0 + 1) of \(derived.sortedBoneyard.count)" },
                context: derived.sceneEditor
            )
        } else {
            VStack(spacing: 20) {
                Text("Error: Scene not found").font(.title2).foregroundColor(.red)
                Text("The scene may have been deleted.").font(.body).multilineTextAlignment(.center)
                Button("Close") {
                    activeSheet = nil
                    clearUnscheduledEditingState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24).frame(width: 400)
        }
    }

    private func clearUnscheduledEditingState() {
        editingUnscheduledScene      = nil
        editingUnscheduledSceneIndex = nil
    }

    // MARK: - Breakdown Browser

    @discardableResult
    private func populateBreakdownBrowserScenes() -> Bool {
        // The order (every scene once, in script order) is `BreakdownBrowser`'s, the
        // phone's too; the Mac pages through a snapshot of the scenes and writes back by id.
        breakdownBrowserScenes = BreakdownBrowser(project: document.project).scenes(in: document.project)
        if breakdownBrowserIndex >= breakdownBrowserScenes.count {
            breakdownBrowserIndex = 0
        }
        return !breakdownBrowserScenes.isEmpty
    }

    private func openBreakdownBrowser() {
        guard populateBreakdownBrowserScenes() else {
            alertMessage = "There are no scenes to browse yet — add some scenes first."
            showingAlert = true
            return
        }
        breakdownBrowserIndex = 0
        activeSheet = .breakdownBrowser
    }

    private func writeBackCurrentBreakdownScene() {
        guard breakdownBrowserScenes.indices.contains(breakdownBrowserIndex) else { return }
        let scene = breakdownBrowserScenes[breakdownBrowserIndex]
        edit(L("Edit Scene")) { data in
            if let i = data.allScenes.firstIndex(where: { $0.id == scene.id }) {
                data.allScenes[i] = scene
                return
            }
            for d in data.shootDays.indices {
                if let i = data.shootDays[d].scenes.firstIndex(where: { $0.id == scene.id }) {
                    data.shootDays[d].scenes[i] = scene
                    return
                }
            }
        }
    }

    private func deleteCurrentBreakdownScene() {
        guard breakdownBrowserScenes.indices.contains(breakdownBrowserIndex) else { return }
        let id = breakdownBrowserScenes[breakdownBrowserIndex].id
        edit(L("Delete Scene")) { data in
            if let i = data.allScenes.firstIndex(where: { $0.id == id }) {
                data.allScenes.remove(at: i)
            } else {
                for d in data.shootDays.indices {
                    if let i = data.shootDays[d].scenes.firstIndex(where: { $0.id == id }) {
                        data.shootDays[d].scenes.remove(at: i)
                        break
                    }
                }
            }
        }
        breakdownBrowserScenes.remove(at: breakdownBrowserIndex)
        if breakdownBrowserIndex >= breakdownBrowserScenes.count {
            breakdownBrowserIndex = max(0, breakdownBrowserScenes.count - 1)
        }
        if breakdownBrowserScenes.isEmpty { activeSheet = nil }
    }

    private func goToPreviousBreakdownScene() {
        guard breakdownBrowserIndex > 0 else { return }
        breakdownBrowserIndex -= 1
    }

    private func goToNextBreakdownScene() {
        guard breakdownBrowserIndex < breakdownBrowserScenes.count - 1 else { return }
        breakdownBrowserIndex += 1
    }

    // MARK: - Scene management

    /// The calendar's three scene callbacks, each one edit through the funnel.
    func assign(scene: Scene, to day: ShootDay) {
        edit(L("Schedule Scene")) { data in
            guard let idx = data.shootDays.firstIndex(where: { $0.id == day.id }) else { return }
            data.shootDays[idx].scenes.append(scene)
            data.allScenes.removeAll { $0.id == scene.id }
        }
    }

    func updateScene(_ updated: Scene, in dayId: UUID) {
        edit(L("Edit Scene")) { data in
            guard let di = data.shootDays.firstIndex(where: { $0.id == dayId }),
                  let si = data.shootDays[di].scenes.firstIndex(where: { $0.id == updated.id }) else { return }
            data.shootDays[di].scenes[si] = updated
        }
    }

    func removeScene(_ scene: Scene, from dayId: UUID) {
        edit(L("Move to Boneyard")) { data in
            guard let di = data.shootDays.firstIndex(where: { $0.id == dayId }) else { return }
            data.shootDays[di].scenes.removeAll { $0.id == scene.id }
            data.allScenes.append(scene)
        }
    }

    // MARK: - Calendar update (merge vs shift)

    /// The Update Calendar button: one edit, so the whole regeneration (and whatever the
    /// shift or the Boneyard return moved) is one undo step. The regeneration itself is
    /// `ProjectData.updateProductionRange` (ProductionRange.swift).
    private func updateShootDays(from newStart: Date, to newEnd: Date) {
        edit(L("Update Calendar")) { data in
            data.updateProductionRange(from: newStart, to: newEnd)
        }
    }
}

fileprivate struct ScheduleSearchResultRow: View {
    let result: ContentView.ScheduleSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.scene.displayTitle).font(.callout).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard let date = result.dayDate else { return "Boneyard (unscheduled)" }
        return formattedDate(date)
    }
}

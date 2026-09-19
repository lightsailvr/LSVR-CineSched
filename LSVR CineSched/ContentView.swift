// ContentView.swift
// The Mac editor for one project document: sidebar, toolbar, calendar and stripboard
// views. The project itself lives in the `ProjectDocument` the window was opened with
// (#8, ADR 0004); this view reads it freely and writes it only through `edit(_:_:)` and
// the bindings built on it, all of which go through the document's `perform` funnel so
// that every change is undoable and autosaved. UI state that is not the project (the
// pending range-picker dates, selection, sheets) stays `@State` here.
// Script import lives in ContentView+ScriptImport.swift, the PDF export actions in
// ContentView+PDFExports.swift, and the drag/drop and editing flows in CalendarView.swift
// and StripboardView.swift.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Schedule View Mode

enum ScheduleViewMode: String, CaseIterable {
    case calendar   = "Calendar"
    case stripboard = "Stripboard"

    var localizedTitle: String {
        L(rawValue)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue
    @Environment(\.colorScheme) private var colorScheme

    // MARK: Project state

    /// The window's project. Read through the accessors below; write only through `edit`.
    let document: ProjectDocument
    /// The window's undo manager, supplied by the document infrastructure. Every `perform`
    /// registers with it, which is also what marks the document edited and autosaves it.
    @Environment(\.undoManager) private var undoManager

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

    init(document: ProjectDocument) {
        self.document = document
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

    // Production Setup & Conflict states
    @State private var conflictReportResults: [ScheduleConflict] = []
    @State private var scrollToDate: Date? = nil
    @State private var searchQuery: String = ""

    // MARK: - Derived state

    /// The sorted Boneyard, conflict sets, duplicate numbers and lock drift, computed from
    /// the project at most once per change (see DerivedScheduleState.swift). Read through
    /// `derived`; nothing here is stored state, so an edit costs one body pass, not two.
    @State private var derivedCache = DerivedScheduleStateCache()
    private var derived: DerivedScheduleState {
        derivedCache.state(for: document.project, changeCount: document.changeCount, boneyardSort: boneyardSort)
    }

    // MARK: - Sync state

    /// The iCloud sync state beside the title and the conflict notice (#14, #15): one
    /// monitor per window, run by the `syncMonitored` modifier in `applyLifecycle`.
    @State private var syncMonitor = SyncMonitor()

    // MARK: - Breakdown Browser
    @State private var breakdownBrowserScenes: [Scene] = []
    @State private var breakdownBrowserIndex: Int = 0

    // MARK: - Edit gesture state

    /// The gesture opened by a child view's `onBeforeSceneChange`, so the several binding
    /// writes one calendar or Stripboard action makes fold into one undo step. Closed by
    /// `onSceneChanged` and, regardless, at the end of the run-loop turn (see
    /// `beginEditGesture`).
    @State private var activeGesture: EditGesture?
    /// Typing in the title field is one gesture per focus session: every keystroke writes
    /// the binding, and without a token each would be its own undo step.
    @State private var titleGesture = EditGesture()
    @FocusState private var titleFieldFocused: Bool
    /// The color editor's open step: a ColorPicker writes on every movement of the wheel,
    /// so the token stays while one slot is being edited and changes with the slot (see
    /// `setPaletteColor`). Cleared when the sheet closes.
    @State private var paletteGesture: (slot: SceneColorSlot, token: EditGesture)?

    // MARK: - Sheet presentation
    private enum ActiveSheet: Identifiable, Hashable {
        case unscheduledEdit, productionSetup, conflictReport, scheduleLockReport, breakdownBrowser, sceneColorSettings, stripboardFields
        var id: Self { self }
    }
    @State private var activeSheet: ActiveSheet? = nil
    @State private var showingColorLegend = false

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

    @State private var selectedSceneIDs:    Set<UUID> = []
    @State private var lastSelectedSceneID: UUID?

    // MARK: - Computed statistics
    private var scheduledDays: [ShootDay] { shootDays.filter { !$0.scenes.isEmpty } }
    private var totalScenes:   Int        { scheduledDays.reduce(0) { $0 + $1.scenes.count } }
    private var completedScenesCount: Int {
        scheduledDays.reduce(0) { $0 + $1.scenes.filter { $0.isCompleted }.count }
    }
    private var totalDuration: String     { formattedEighths(scheduledDays.reduce(0) { $0 + $1.totalDuration }) }
    private var totalEstTime:  String     { formattedTime(scheduledDays.reduce(0) { $0 + $1.totalEstimatedTime }) }

    // MARK: - Body
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("CineSchedSidebarCollapsed") private var sidebarCollapsedPreference: Bool = false
    private var isSidebarCollapsed: Bool { columnVisibility == .detailOnly }

    var body: some View {
        let base = NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            detailView
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .accentColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))
        .background(WindowAccessor(backgroundColor: currentTheme.canvasBackground(isDarkMode: isDarkMode)))

        let withAlerts = applyAlerts(base)
        let withSheets = applySheets(withAlerts)
        return applyLifecycle(withSheets)
    }

    // MARK: - Modifiers

    private func applyAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("CineSched"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showingImportAlert) {
                Alert(title: Text("Import Result"), message: Text(importMessage), dismissButton: .default(Text("OK")))
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
            .sheet(item: $activeSheet) { sheet in
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
                    closeAfterDelete: false
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
            .focusedSceneValue(\.projectCommands, projectCommands)
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
            }
            .onChange(of: document.restoreCount) { _, _ in
                seedRangePickers()
            }
            .onChange(of: titleFieldFocused) { _, focused in
                if !focused { titleGesture = EditGesture() }
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
            stripboardShowAllDays:  $stripboardShowAllDays
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
    private func beginEditGesture() {
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
    private var allScenesBinding: Binding<[Scene]> {
        Binding(get: { allScenes }, set: { new in edit { $0.allScenes = new } })
    }
    private var shootDaysBinding: Binding<[ShootDay]> {
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

            Text("⌘-click or ⇧-click to select multiple, then drag as a group")
                .font(.caption2).foregroundColor(.secondary)

            boneyardList
                .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(minWidth: 300, maxHeight: .infinity)
        .background(currentTheme.panelBackground(isDarkMode: isDarkMode))
    }

    // MARK: - Schedule Lock

    private func lockSchedule() {
        let working = ScheduleLockScanner.currentWorkingDays(shootDays: shootDays)
        var stored: [String: [Date]] = [:]
        for (character, dates) in working { stored[character] = dates.sorted() }
        edit(L("Lock Schedule")) { data in
            var info = data.productionInfo ?? ProductionInfo()
            info.scheduleLock = ScheduleLock(lockedAt: Date(), workingDays: stored)
            data.productionInfo = info
        }
        alertMessage = "Schedule locked. You'll be notified in the Schedule Lock Report if any actor's working days change from here."
        showingAlert = true
    }

    private func unlockSchedule() {
        guard productionInfo.scheduleLock != nil else { return }
        edit(L("Unlock Schedule")) { $0.productionInfo?.scheduleLock = nil }
    }

    // MARK: - Selection and cast helpers

    /// Drops selected IDs that are no longer in the project. Writes the selection only when
    /// something was dropped, so the usual edit does not invalidate the view a second time.
    private func pruneSelection() {
        guard !selectedSceneIDs.isEmpty else { return }
        let scheduledIDs = Set(shootDays.flatMap { $0.scenes.map(\.id) })
        let boneyardIDs  = Set(allScenes.map(\.id))
        let pruned = selectedSceneIDs.intersection(scheduledIDs.union(boneyardIDs))
        if pruned != selectedSceneIDs { selectedSceneIDs = pruned }
    }

    private func renameCastCharacter(from oldName: String, to newName: String) {
        let old = oldName.trimmingCharacters(in: .whitespaces)
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard !old.isEmpty, !new.isEmpty, old.caseInsensitiveCompare(new) != .orderedSame else { return }

        func renamed(_ cast: [String]) -> [String] {
            cast.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }

        // Only Production Setup's Save renames (possibly several characters), and its own
        // write of the roster follows in the same turn; one gesture folds all of it into
        // one step.
        if activeGesture == nil { beginEditGesture() }
        edit(L("Edit Production Setup")) { data in
            for i in data.allScenes.indices {
                data.allScenes[i].cast = renamed(data.allScenes[i].cast)
            }
            for d in data.shootDays.indices {
                for s in data.shootDays[d].scenes.indices {
                    data.shootDays[d].scenes[s].cast = renamed(data.shootDays[d].scenes[s].cast)
                }
                if let override = data.shootDays[d].callSheet.castOverride {
                    data.shootDays[d].callSheet.castOverride = renamed(override)
                }
            }
        }
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

    private var boneyardList: some View {
        let state = derived
        return ScrollView {
            VStack(spacing: 2) {
                ForEach(state.sortedBoneyard, id: \.scene.id) { item in
                    let isDup = state.duplicateSceneNumberIDs.contains(item.scene.id)
                    HStack(spacing: 6) {
                        if !item.scene.sceneNumber.isEmpty {
                            Text(item.scene.sceneNumber)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(item.scene.stripTextColor.opacity(0.6))
                                .lineLimit(1)
                                .frame(minWidth: 18, alignment: .leading)
                        }

                        Text(item.scene.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(item.scene.stripTextColor)
                            .lineLimit(1)

                        if isDup {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                        }

                        Spacer(minLength: 4)

                        Text(FractionParser.formatEighths(item.scene.duration))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(item.scene.stripTextColor.opacity(0.8))
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background(item.scene.stripColor(in: palette))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(selectedSceneIDs.contains(item.scene.id) ? Color.accentColor : item.scene.stripTextColor.opacity(0.2), lineWidth: selectedSceneIDs.contains(item.scene.id) ? 2 : 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .opacity(isDup ? 1 : 0)
                    )
                    .onDrag { dragPayload(for: item.scene) }
                    .fastTooltip(item.scene.tooltipText)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            editingUnscheduledSceneIndex = item.index
                            editingUnscheduledScene      = item.scene
                            activeSheet = .unscheduledEdit
                        }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            selectScene(item.scene.id)
                        }
                    )
                    .contextMenu {
                        Button(L("Edit Scene")) {
                            editingUnscheduledSceneIndex = item.index
                            editingUnscheduledScene      = item.scene
                            activeSheet = .unscheduledEdit
                        }
                        Button(L("Duplicate Scene")) {
                            edit(L("Duplicate Scene")) { $0.allScenes.append(Scene(
                                title:            item.scene.title + " (Copy)",
                                sceneNumber:      item.scene.sceneNumber,
                                duration:         item.scene.duration,
                                estimatedTime:    item.scene.estimatedTime,
                                dayNightType:     item.scene.dayNightType,
                                cast:             item.scene.cast,
                                summary:          item.scene.summary,
                                extras:           item.scene.extras,
                                props:            item.scene.props,
                                setDressing:      item.scene.setDressing,
                                wardrobe:         item.scene.wardrobe,
                                makeupHair:       item.scene.makeupHair,
                                vehicles:         item.scene.vehicles,
                                specialEquipment: item.scene.specialEquipment,
                                stunts:           item.scene.stunts,
                                sfx:              item.scene.sfx,
                                vfx:              item.scene.vfx,
                                breakdownNotes:   item.scene.breakdownNotes
                            )) }
                        }
                        Divider()
                        Button(L("Delete Scene"), role: .destructive) {
                            edit(L("Delete Scene")) { $0.allScenes.remove(at: item.index) }
                        }
                    }
                }
            }
            .padding(4)
        }
        .tooltipContainer()
        .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { item, _ in
                if let idString = item as? String {
                    DispatchQueue.main.async { moveScenesToBoneyard(idString) }
                }
            }
            return true
        }
    }

    private func moveScenesToBoneyard(_ payload: String) {
        let ids = payload.components(separatedBy: ",").compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return }
        edit(L("Move to Boneyard")) { data in
            for id in ids {
                guard let d = data.shootDays.firstIndex(where: { day in day.scenes.contains { $0.id == id } }),
                      let scene = data.shootDays[d].scenes.first(where: { $0.id == id }) else { continue }
                data.shootDays[d].scenes.removeAll { $0.id == id }
                data.allScenes.append(scene)
            }
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
    }

    private func dragPayload(for scene: Scene) -> NSItemProvider {
        let ids: [UUID]
        if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
            ids = derived.sortedBoneyard.map(\.scene).filter { selectedSceneIDs.contains($0.id) }.map(\.id)
        } else {
            selectedSceneIDs   = [scene.id]
            lastSelectedSceneID = scene.id
            ids = [scene.id]
        }
        let payload = ids.map(\.uuidString).joined(separator: ",")
        return NSItemProvider(object: payload as NSString)
    }

    // MARK: - Detail / main area

    private var detailView: some View {
        let state = derived
        return VStack {
            toolbarRow
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
                    lastSelectedSceneID: $lastSelectedSceneID,
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
                    onExportMonthPDF: { month, options in
                        exportMonthPDF(month: month, options: options)
                    }
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
                    lastSelectedSceneID: $lastSelectedSceneID,
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
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(currentTheme.canvasBackground(isDarkMode: isDarkMode))
    }

    // MARK: - Toolbar row

    /// Live view of the persisted Stripboard field selection. Writes go straight back to
    /// UserDefaults through the @AppStorage string, so the sheet's toggles update the board
    /// behind them immediately.
    private var stripboardFields: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(stripboardFieldsRaw) },
            set: { stripboardFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    private var toolbarRow: some View {
        HStack {
            Text(projectTitle.isEmpty ? "Untitled Movie" : projectTitle)
                .font(.headline).fontWeight(.bold)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 220)

            // The iCloud sync state (nothing for a local file) and the conflict notice.
            SyncStateIndicator(monitor: syncMonitor)

            Divider().frame(height: 20)

            HStack(spacing: 15) {
                statBadge(icon: "calendar", value: "\(scheduledDays.count)", label: "days",   color: .blue)
                statBadge(icon: "checkmark.circle", value: "\(completedScenesCount)/\(totalScenes)", label: "completed", color: .green)
                statBadge(icon: "clock",    value: totalEstTime,              label: nil,      color: .purple)
                let unscheduledCount = allScenes.filter { !$0.isBanner }.count
                if unscheduledCount > 0 {
                    statBadge(icon: "tray.full", value: "\(unscheduledCount)", label: "unscheduled", color: .orange)
                }
            }

            Spacer()

            // Custom View Mode Switcher pill styled with currentTheme.activeTabColor
            HStack(spacing: 2) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                    Button {
                        viewMode = mode
                    } label: {
                        Text(mode.localizedTitle)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .foregroundColor(viewMode == mode ? .white : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewMode == mode
                                        ? currentTheme.activeTabColor(isDarkMode: isDarkMode)
                                        : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(8)

            // Only the Stripboard prints per-field chips, so the picker is hidden in
            // calendar mode rather than offering a setting with no visible effect there.
            if viewMode == .stripboard {
                Button {
                    activeSheet = .stripboardFields
                } label: {
                    Label("\(L("Fields")) (\(stripboardFields.wrappedValue.count))", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption).fontWeight(.semibold)
                }
                .controlSize(.small)
                .help(L("Choose which scene fields (Real Location, Special Equipment, Cast...) each strip shows"))

                // Off by default: a shoot with blocks months apart would otherwise be mostly
                // empty day sections. The calendar always shows every date regardless.
                Toggle(L("All days"), isOn: $stripboardShowAllDays)
                    .checkboxToggleStyle()
                    .font(.caption).fontWeight(.semibold)
                    .controlSize(.small)
                    .help(L("Show every date in the range instead of folding empty days into gap rows"))
            }

            scheduleSearchField
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(currentTheme.panelBackground(isDarkMode: isDarkMode))
        )
        .padding(.bottom, 6)
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

    private var scheduleSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search title, cast, summary…", text: $searchQuery)
                .textFieldStyle(.plain)
                .frame(width: 200)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        .popover(isPresented: searchPopoverIsPresented, arrowEdge: .bottom) {
            searchResultsList
        }
    }

    private func statBadge(icon: String, value: String, label: String?, color: Color) -> some View {
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
                positionLabel: currentBoneyardPosition.map { "Scene \($0 + 1) of \(derived.sortedBoneyard.count)" }
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
        var seen = Set<UUID>()
        var combined: [Scene] = []
        for s in allScenes where !seen.contains(s.id) { seen.insert(s.id); combined.append(s) }
        for day in shootDays {
            for s in day.scenes where !seen.contains(s.id) { seen.insert(s.id); combined.append(s) }
        }
        breakdownBrowserScenes = combined.sorted {
            let a = $0.scriptOrderKey
            let b = $1.scriptOrderKey
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1 < b.1
        }
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

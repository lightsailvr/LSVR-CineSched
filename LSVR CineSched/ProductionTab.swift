// ProductionTab.swift
// The iPhone's Production tab (#28): every Mac menu command that is not about one strip
// or one day, as rows of a grouped list. Production (Setup, Scan for Conflicts, Lock or
// Unlock, the Schedule Lock Report, the Breakdown Browser), Appearance (the Color Legend,
// Customize Scene Colors, the Stripboard fields), Project (the title, the production
// range with Shift Schedule and Update Calendar: `ProductionTab+Range.swift`), Export (the
// six documents, each into the preview sheet with Share through `PhoneExports`:
// `ProductionTab+Exports.swift`) and Import (a script into this project's Boneyard, with
// the summary before anything is written: `ProductionTab+Import.swift`), the
// `ContentView+*` pattern. Nothing here is new behaviour: every row presents an adaptive
// editor, report or setting that already exists and wires it to the editor's `edit`
// funnel (or the pure `ProductionEdits`) exactly as `ContentView` does for the Mac's
// menus, so the same undo steps come out (one per Save, one per color slot, one per
// typing burst in the title, one for a whole range change).
//
// The menu bar of a narrow iPad window reaches these rows too (#22): `PhoneEditor`
// publishes `ProjectCommands` whose closures hand a `ProductionCommand` to this tab
// through the `command` binding and switch to it; the tab runs the command on the next
// change (or on appear, when the tab had not been shown yet) and clears it, so the state
// behind the sheets stays here.
//
// Platform-free SwiftUI: `fileImporter`, `confirmationDialog` and the sheets exist on
// every platform; the Mac compiles it and never shows it.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Commands from the menu bar

/// What the menu bar can ask the Production tab to do (#22): the Mac's Production, View
/// and File menu items this tab answers, by name.
enum ProductionCommand: Hashable {
    case openProductionSetup, scanForConflicts, openBreakdownBrowser
    case lockSchedule, unlockSchedule, showScheduleLockReport
    case showColorLegend, showSceneColorSettings, showStripboardFields
    case importScript
    case exportScheduleCalendar, exportStripSchedule, exportDaysOutOfDays, exportBreakdowns
    case exportShotList
}

// MARK: - The tab

struct ProductionTab: View {
    let document: ProjectDocument
    /// Conflict sets and lock drift, computed once per change by the editor.
    let derived: DerivedScheduleState
    let edit: ProjectEdit
    let editCoalescing: CoalescedProjectEdit
    /// Opens the editor's gesture if none is open, so the setup's character renames and
    /// its own write are one undo step.
    let beginEditGestureIfNeeded: () -> Void
    /// The menu bar's request, consumed here.
    @Binding var command: ProductionCommand?
    /// The phone's export call site (`PhoneExports.swift`): each document into the
    /// editor's preview sheet, a failure into its alert.
    let exports: PhoneExports
    /// Switches to the Days list and scrolls it to a date (a report row's jump).
    let jumpToDate: (Date) -> Void

    @Environment(\.scenePalette) private var palette

    // MARK: Sheet state

    enum ActiveSheet: Identifiable, Hashable {
        case productionSetup, conflictReport, scheduleLockReport, breakdownBrowser
        case colorLegend, sceneColorSettings, stripboardFields
        case monthOptions(month: Date)
        case shotListOptions
        case importSummary
        var id: Self { self }
    }
    @State var activeSheet: ActiveSheet?
    @State private var conflictReportResults: [ScheduleConflict] = []
    /// The breakdown browser's current scene, by id; the list itself is rebuilt from the
    /// project on every body (`BreakdownBrowser`).
    @State private var browserSceneID: UUID?
    /// The color editor's open step (the `ContentView` rule): one token per slot edited
    /// in a row, cleared when the sheet closes.
    @State private var paletteGesture: (slot: SceneColorSlot, token: EditGesture)?

    // MARK: Project settings state

    /// Typing in the title is one gesture per focus session.
    @State var titleGesture = EditGesture()
    @FocusState var titleFocused: Bool
    /// The range pickers' pending dates, the editor's state (`PhoneEditor` seeds them from
    /// the shoot days' bounds and re-seeds them on `restoreCount`; the Day screen's Clear
    /// Day Type reads the same range to know which days lie outside it).
    @Binding var startDate: Date
    @Binding var endDate:   Date
    /// The bounds the pickers were last seeded from.
    @Binding var seededRange: ClosedRange<Date>?
    @State var pendingRangePreview: ProductionRangePreview?
    @State var showingRangeConfirmation = false

    // MARK: Import and alerts

    @State var showingImportPicker = false
    @State var pendingImport: FountainImportResult?
    @State var alertMessage: String?
    /// The Shot List options sheet's Export, run once the sheet has gone
    /// (`runPendingShotListExport`), so the preview or the failure alert is not
    /// presented over a sheet that is still dismissing.
    @State var pendingShotListExport: ShotListPDFOptions?

    // App-wide preferences the exports and the fields picker read (the Mac's keys).
    @AppStorage("CineSchedIncludeHoldInDOOD") var includeHoldInDOOD: Bool = true
    @AppStorage(StripboardFieldSettings.defaultsKey) private var stripboardFieldsRaw: String = StripboardFieldSettings.defaultRaw
    @AppStorage(MonthPDFOptionSettings.fieldsKey) var monthPDFFieldsRaw: String = MonthPDFOptionSettings.defaultFieldsRaw
    @AppStorage(MonthPDFOptionSettings.pagesKey)  var monthPDFShowPages: Bool = MonthPDFOptions.default.includePageCount
    @AppStorage(MonthPDFOptionSettings.timeKey)   var monthPDFShowTime:  Bool = MonthPDFOptions.default.includeEstimatedTime
    @AppStorage(ShotListPDFOptionSettings.scopeKey)         var shotListScopeRaw: String = ShotListPDFOptionSettings.projectRaw
    @AppStorage(ShotListPDFOptionSettings.includeFramesKey) var shotListIncludeFrames: Bool = ShotListPDFOptions.default.includeFrames

    var project:        ProjectData    { document.project }
    var shootDays:      [ShootDay]     { project.shootDays }
    var productionInfo: ProductionInfo { project.productionInfo ?? ProductionInfo() }
    private var sceneCount: Int        { project.allScenes.count + shootDays.reduce(0) { $0 + $1.scenes.count } }

    /// The shoot days' bounds, what the range pickers are seeded from (`ContentView`'s rule).
    static func dateRange(of days: [ShootDay]) -> ClosedRange<Date>? {
        guard let first = days.first?.date, let last = days.last?.date, first <= last else { return nil }
        return first...last
    }

    // MARK: - Body

    var body: some View {
        // No stack of its own: nothing here pushes, and the document infrastructure's
        // bar would mirror into an inner one (PhoneEditor's note).
        // The range confirmation and the import picker hang off the list from their
        // extensions (`ContentView`'s `applyX` pattern).
        applyImportPicker(applyRangeConfirmation(List {
            productionSection
            appearanceSection
            projectSection
            exportSection
            importSection
        }))
        .insetGroupedListStyle()
        .sheet(item: $activeSheet, onDismiss: runPendingShotListExport) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue != .sceneColorSettings { paletteGesture = nil }
            if newValue != .breakdownBrowser   { browserSceneID = nil }
            if newValue != .importSummary      { pendingImport  = nil }
        }
        .onChange(of: command) { _, newValue in run(newValue) }
        .onAppear { run(command) }
        .onChange(of: titleFocused) { _, focused in
            if !focused { titleGesture = EditGesture() }
        }
        .alert(L("CineSched"), isPresented: alertPresented) {
            Button(L("OK")) { alertMessage = nil }
        } message: {
            if let alertMessage { Text(alertMessage) }
        }
    }

    // MARK: - Sections

    private var productionSection: some View {
        Section {
            actionRow(L("Production Setup"), systemImage: "person.3", detail: setupDetail) {
                activeSheet = .productionSetup
            }
            actionRow(L("Scan for Conflicts"), systemImage: "exclamationmark.triangle", detail: conflictDetail, detailColor: derived.conflictSceneIDs.isEmpty ? nil : .red) {
                scanForConflicts()
            }
            if let lock = productionInfo.scheduleLock {
                actionRow(L("Unlock Schedule"), systemImage: "lock.open", detail: "\(L("Locked")) \(formattedDate(lock.lockedAt))") {
                    unlockSchedule()
                }
            } else {
                actionRow(L("Lock Schedule"), systemImage: "lock") {
                    lockSchedule()
                }
            }
            actionRow(L("Schedule Lock Report"), systemImage: "lock.doc", detail: lockReportDetail, detailColor: derived.scheduleLockChanges.isEmpty ? nil : .orange) {
                activeSheet = .scheduleLockReport
            }
            actionRow(L("Breakdown Browser"), systemImage: "list.bullet.rectangle", detail: sceneCount == 0 ? L("No scenes") : "\(sceneCount) \(L("scenes"))") {
                openBreakdownBrowser()
            }
        } header: {
            Text(L("Production"))
        }
    }

    private var appearanceSection: some View {
        Section {
            actionRow(L("Color Legend"), systemImage: "paintpalette") {
                activeSheet = .colorLegend
            }
            actionRow(L("Customize Scene Colors"), systemImage: "eyedropper") {
                activeSheet = .sceneColorSettings
            }
            actionRow(L("Stripboard Fields"), systemImage: "line.3.horizontal.decrease.circle", detail: "\(stripboardFields.wrappedValue.count)") {
                activeSheet = .stripboardFields
            }
        } header: {
            Text(L("Appearance"))
        } footer: {
            Text(L("Scene colors belong to the project and follow it to every device; the fields are this device's preference for the Stripboard."))
        }
    }

    // MARK: - Rows

    /// A row that opens a sheet or runs a command: the icon in the accent color, the
    /// title, and an optional detail at the trailing edge.
    func actionRow(_ title: String, systemImage: String, detail: String? = nil, detailColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, systemImage: systemImage, detail: detail, detailColor: detailColor)
        }
        .accessibilityIdentifier("ProductionRow.\(title)")
    }

    func rowLabel(_ title: String, systemImage: String, detail: String? = nil, detailColor: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            // `Color.primary`, not the hierarchical `.primary`, which inside a tinted
            // button resolves to the tint and drew the whole row blue.
            Text(title)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(detailColor ?? Color.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private var setupDetail: String? {
        let cast = productionInfo.castList.count
        return cast == 0 ? nil : (cast == 1 ? L("1 cast member") : String(format: L("%d cast members"), cast))
    }

    private var conflictDetail: String {
        let count = derived.conflictSceneIDs.count
        return count == 0 ? L("None") : (count == 1 ? L("1 scene") : String(format: L("%d scenes"), count))
    }

    private var lockReportDetail: String? {
        guard productionInfo.scheduleLock != nil else { return L("Not locked") }
        let count = derived.scheduleLockChanges.count
        return count == 0 ? L("No changes") : (count == 1 ? L("1 change") : String(format: L("%d changes"), count))
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .productionSetup:
            ProductionSetupSheet(
                productionInfo:     productionInfoBinding,
                scenes:             project.allScenes + shootDays.flatMap { $0.scenes },
                isPresented:        sheetPresented(.productionSetup),
                onSave:             {},
                onCharacterRenamed: renameCastCharacter
            )
        case .conflictReport:
            ConflictReportSheet(
                conflicts:    conflictReportResults,
                onSelectDate: { date in activeSheet = nil; jumpToDate(date) },
                onDismiss:    { activeSheet = nil }
            )
        case .scheduleLockReport:
            ScheduleLockReportSheet(
                changes:      derived.scheduleLockChanges,
                lockedAt:     productionInfo.scheduleLock?.lockedAt,
                onSelectDate: { date in activeSheet = nil; jumpToDate(date) },
                onDismiss:    { activeSheet = nil }
            )
        case .breakdownBrowser:
            breakdownBrowserSheet
        case .colorLegend:
            ColorLegendView()
        case .sceneColorSettings:
            SceneColorSettingsSheet(
                palette:    palette,
                onSetColor: setPaletteColor,
                onReset:    resetPalette,
                onDismiss:  { activeSheet = nil }
            )
        case .stripboardFields:
            StripboardFieldsSheet(selectedFields: stripboardFields, onDismiss: { activeSheet = nil })
        case .monthOptions(let month):
            monthOptionsSheet(month)
        case .shotListOptions:
            shotListOptionsSheet
        case .importSummary:
            importSummarySheet
        }
    }

    func sheetPresented(_ sheet: ActiveSheet) -> Binding<Bool> {
        Binding(get: { activeSheet == sheet }, set: { if !$0 { activeSheet = nil } })
    }

    // MARK: - Breakdown Browser

    /// The scene editor over the project's scenes in script order (`BreakdownBrowser`),
    /// bound to the current scene by id: Previous and Next save and step, Save closes,
    /// Delete removes the scene outright and steps (the Mac's browser).
    @ViewBuilder
    private var breakdownBrowserSheet: some View {
        let browser = BreakdownBrowser(project: project)
        if let id = browserSceneID, let scene = project.scene(withID: id), let position = browser.position(of: id) {
            SceneEditSheet(
                scene:         browserSceneBinding(id: id, fallback: scene),
                isPresented:   sheetPresented(.breakdownBrowser),
                onSave:        {},
                onDelete:      { deleteBrowserScene(id, browser: browser) },
                canGoPrevious: browser.id(before: id) != nil,
                canGoNext:     browser.id(after: id) != nil,
                onPrevious:    { browserSceneID = browser.id(before: id) },
                onNext:        { browserSceneID = browser.id(after: id) },
                positionLabel: String(format: L("Scene %d of %d — script order"), position + 1, browser.count),
                breakdownExpandedByDefault: true,
                closeAfterDelete: false,
                knownLocations: project.knownLocations,
                breakdownSuggestions: project.breakdownSuggestions
            )
            .id(id)
        } else {
            EditorChrome {
                EditorTitle(title: L("Breakdown Browser"))
            } content: {
                ContentUnavailableView(
                    L("No Scenes to Browse"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(L("Import a script or add scenes first."))
                )
            } footer: {
                HStack {
                    Spacer()
                    Button(L("Close")) { activeSheet = nil }
                        .buttonStyle(.bordered)
                }
            }
            .editorContainer(EditorSheetSize(width: 400, height: 320, compactDetents: [.medium]))
        }
    }

    private func openBreakdownBrowser() {
        browserSceneID = BreakdownBrowser(project: project).first
        activeSheet    = .breakdownBrowser
    }

    /// The current scene wherever it is; the editor's Save is one assignment, so one
    /// `edit` and one undo step.
    private func browserSceneBinding(id: UUID, fallback: Scene) -> Binding<Scene> {
        Binding(
            get: { project.scene(withID: id) ?? fallback },
            set: { new in edit(L("Edit Scene")) { $0.replaceScene(new) } }
        )
    }

    private func deleteBrowserScene(_ id: UUID, browser: BreakdownBrowser) {
        let next = browser.successor(of: id)
        edit(L("Delete Scene")) { $0.removeScene(withID: id) }
        browserSceneID = next
        if next == nil { activeSheet = nil }
    }

    // MARK: - Production Setup

    private var productionInfoBinding: Binding<ProductionInfo> {
        Binding(get: { productionInfo }, set: { new in edit(L("Edit Production Setup")) { $0.productionInfo = new } })
    }

    /// The character name join (CONTEXT.md): a renamed character reaches every scene's
    /// cast and every call sheet's cast override (`ProjectData.renameCharacter`), in the
    /// gesture the setup's own write then joins, so the rename and the roster are one undo
    /// step (the Mac's rule).
    private func renameCastCharacter(from oldName: String, to newName: String) {
        beginEditGestureIfNeeded()
        edit(L("Edit Production Setup")) { $0.renameCharacter(from: oldName, to: newName) }
    }

    // MARK: - Conflicts and the schedule lock

    private func scanForConflicts() {
        conflictReportResults = ConflictScanner.scan(shootDays: shootDays, productionInfo: productionInfo)
        activeSheet = .conflictReport
    }

    private func lockSchedule() {
        edit(L("Lock Schedule")) { $0.lockSchedule() }
        alertMessage = L("Schedule locked. You'll be notified in the Schedule Lock Report if any actor's working days change from here.")
    }

    private func unlockSchedule() {
        guard productionInfo.scheduleLock != nil else { return }
        edit(L("Unlock Schedule")) { $0.unlockSchedule() }
    }

    // MARK: - Appearance

    /// The Stripboard field selection as the picker's binding, straight through the
    /// app preference (`ContentView.stripboardFields`).
    private var stripboardFields: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(stripboardFieldsRaw) },
            set: { stripboardFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    private var monthPDFFields: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(monthPDFFieldsRaw) },
            set: { monthPDFFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    /// One slot's hex into the project's palette (#11), one undo step per slot edited in
    /// a row: a `ColorPicker` writes on every movement of the wheel.
    private func setPaletteColor(_ slot: SceneColorSlot, _ hex: String) {
        let token: EditGesture
        if let open = paletteGesture, open.slot == slot {
            token = open.token
        } else {
            token = EditGesture()
            paletteGesture = (slot, token)
        }
        editCoalescing(token, L("Change Scene Color")) { $0.setStripColor(hex, for: slot) }
    }

    /// The standard code, written out in full so the project keeps a palette.
    private func resetPalette() {
        paletteGesture = nil
        edit(L("Reset Scene Colors")) { $0.palette = .standard }
    }

    // MARK: - Alerts

    private var alertPresented: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    // MARK: - Commands from the menu bar

    /// Runs and clears a command the editor handed down (#22).
    private func run(_ command: ProductionCommand?) {
        guard let command else { return }
        self.command = nil
        switch command {
        case .openProductionSetup:    activeSheet = .productionSetup
        case .scanForConflicts:       scanForConflicts()
        case .openBreakdownBrowser:   openBreakdownBrowser()
        case .lockSchedule:           lockSchedule()
        case .unlockSchedule:         unlockSchedule()
        case .showScheduleLockReport: activeSheet = .scheduleLockReport
        case .showColorLegend:        activeSheet = .colorLegend
        case .showSceneColorSettings: activeSheet = .sceneColorSettings
        case .showStripboardFields:   activeSheet = .stripboardFields
        case .importScript:           showingImportPicker = true
        case .exportScheduleCalendar: exports.scheduleCalendar(startDate: currentRange.lowerBound, endDate: currentRange.upperBound)
        case .exportStripSchedule:    exports.stripSchedule()
        case .exportDaysOutOfDays:    exports.daysOutOfDays(includeHold: includeHoldInDOOD)
        case .exportBreakdowns:       exports.breakdowns()
        case .exportShotList:         activeSheet = .shotListOptions
        }
    }
}

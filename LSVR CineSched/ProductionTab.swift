// ProductionTab.swift
// The iPhone's Production tab (#28): every Mac menu command that is not about one strip
// or one day, as rows of a grouped list. Production (Setup, Scan for Conflicts, Lock or
// Unlock, the Schedule Lock Report, the Breakdown Browser), Appearance (the Color Legend,
// Customize Scene Colors, the Stripboard fields), Project (the title, the production
// range with Shift Schedule and Update Calendar), Export (the six documents, each into
// the preview sheet with Share) and Import (a script into this project's Boneyard, with
// the summary before anything is written). Nothing here is new behaviour: every row
// presents an adaptive editor, report or setting that already exists and wires it to the
// editor's `edit` funnel exactly as `ContentView` does for the Mac's menus, so the same
// undo steps come out (one per Save, one per color slot, one per typing burst in the
// title, one for a whole range change).
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
}

/// `edit` under a gesture the caller owns, for the writes that must fold across several
/// calls: every keystroke of the title, every movement of a color slot's wheel.
typealias CoalescedProjectEdit = (_ token: EditGesture, _ actionName: String?, _ change: (inout ProjectData) -> Void) -> Void

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
    /// The export the editor's preview sheet shows (#23).
    @Binding var exportPreview: PDFExportRequest?
    /// Switches to the Days list and scrolls it to a date (a report row's jump).
    let jumpToDate: (Date) -> Void

    @Environment(\.scenePalette) private var palette

    // MARK: Sheet state

    enum ActiveSheet: Identifiable, Hashable {
        case productionSetup, conflictReport, scheduleLockReport, breakdownBrowser
        case colorLegend, sceneColorSettings, stripboardFields
        case monthOptions(month: Date)
        case importSummary
        var id: Self { self }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var conflictReportResults: [ScheduleConflict] = []
    /// The breakdown browser's current scene, by id; the list itself is rebuilt from the
    /// project on every body (`BreakdownBrowser`).
    @State private var browserSceneID: UUID?
    /// The color editor's open step (the `ContentView` rule): one token per slot edited
    /// in a row, cleared when the sheet closes.
    @State private var paletteGesture: (slot: SceneColorSlot, token: EditGesture)?

    // MARK: Project settings state

    /// Typing in the title is one gesture per focus session.
    @State private var titleGesture = EditGesture()
    @FocusState private var titleFocused: Bool
    /// The range pickers' pending dates, seeded from the shoot days' bounds and re-seeded
    /// only when the project is replaced under the view and those bounds changed.
    @State private var startDate: Date
    @State private var endDate:   Date
    @State private var seededRange: ClosedRange<Date>?
    @State private var pendingRangePreview: ProductionRangePreview?
    @State private var showingRangeConfirmation = false

    // MARK: Import and alerts

    @State private var showingImportPicker = false
    @State private var pendingImport: FountainImportResult?
    @State private var alertMessage: String?

    // App-wide preferences the exports and the fields picker read (the Mac's keys).
    @AppStorage("CineSchedIncludeHoldInDOOD") private var includeHoldInDOOD: Bool = true
    @AppStorage(StripboardFieldSettings.defaultsKey) private var stripboardFieldsRaw: String = StripboardFieldSettings.defaultRaw
    @AppStorage(MonthPDFOptionSettings.fieldsKey) private var monthPDFFieldsRaw: String = MonthPDFOptionSettings.defaultFieldsRaw
    @AppStorage(MonthPDFOptionSettings.pagesKey)  private var monthPDFShowPages: Bool = MonthPDFOptions.default.includePageCount
    @AppStorage(MonthPDFOptionSettings.timeKey)   private var monthPDFShowTime:  Bool = MonthPDFOptions.default.includeEstimatedTime

    init(
        document: ProjectDocument,
        derived: DerivedScheduleState,
        edit: @escaping ProjectEdit,
        editCoalescing: @escaping CoalescedProjectEdit,
        beginEditGestureIfNeeded: @escaping () -> Void,
        command: Binding<ProductionCommand?>,
        exportPreview: Binding<PDFExportRequest?>,
        jumpToDate: @escaping (Date) -> Void
    ) {
        self.document                 = document
        self.derived                  = derived
        self.edit                     = edit
        self.editCoalescing           = editCoalescing
        self.beginEditGestureIfNeeded = beginEditGestureIfNeeded
        self.jumpToDate               = jumpToDate
        _command       = command
        _exportPreview = exportPreview
        let range      = Self.dateRange(of: document.project.shootDays)
        _startDate     = State(initialValue: range?.lowerBound ?? Date())
        _endDate       = State(initialValue: range?.upperBound ?? Date())
        _seededRange   = State(initialValue: range)
    }

    private var project:        ProjectData    { document.project }
    private var shootDays:      [ShootDay]     { project.shootDays }
    private var productionInfo: ProductionInfo { project.productionInfo ?? ProductionInfo() }
    private var sceneCount:     Int            { project.allScenes.count + shootDays.reduce(0) { $0 + $1.scenes.count } }

    private static func dateRange(of days: [ShootDay]) -> ClosedRange<Date>? {
        guard let first = days.first?.date, let last = days.last?.date, first <= last else { return nil }
        return first...last
    }

    // MARK: - Body

    var body: some View {
        // No stack of its own: nothing here pushes, and the document infrastructure's
        // bar would mirror into an inner one (PhoneEditor's note).
        List {
            productionSection
            appearanceSection
            projectSection
            exportSection
            importSection
        }
        .insetGroupedListStyle()
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue != .sceneColorSettings { paletteGesture = nil }
            if newValue != .breakdownBrowser   { browserSceneID = nil }
            if newValue != .importSummary      { pendingImport  = nil }
        }
        .onChange(of: command) { _, newValue in run(newValue) }
        .onAppear { run(command) }
        .onChange(of: document.restoreCount) { _, _ in seedRangePickers() }
        .onChange(of: titleFocused) { _, focused in
            if !focused { titleGesture = EditGesture() }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: ScriptImport.contentTypes,
            allowsMultipleSelection: false,
            onCompletion: importPickerFinished
        )
        .confirmationDialog(
            L("Update the production range?"),
            isPresented: $showingRangeConfirmation,
            titleVisibility: .visible,
            presenting: pendingRangePreview
        ) { _ in
            Button(L("Update Calendar")) { applyRangeUpdate() }
            Button(L("Cancel"), role: .cancel) { pendingRangePreview = nil }
        } message: { preview in
            Text(rangeConfirmationMessage(preview))
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

    private var projectSection: some View {
        Section {
            TextField(L("Movie Title"), text: projectTitleBinding)
                .font(.headline)
                .focused($titleFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("ProjectTitleField")
            DatePicker(L("Start Date"), selection: $startDate, displayedComponents: .date)
            DatePicker(L("End Date"), selection: $endDate, displayedComponents: .date)
            Toggle(L("Shift Schedule"), isOn: shiftModeBinding)
            Button {
                requestRangeUpdate()
            } label: {
                HStack {
                    Label(L("Update Calendar"), systemImage: "calendar.badge.clock")
                    Spacer()
                    Text(rangeDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!rangeIsApplicable)
            .accessibilityIdentifier("UpdateCalendar")
        } header: {
            Text(L("Project"))
        } footer: {
            Text(L("Shift Schedule: when the start date moves, every scene, event, call sheet, day type and note slides with it. Off, everything stays on its date and days outside the new range return their scenes to the Boneyard."))
        }
    }

    private var exportSection: some View {
        Section {
            actionRow(L("Schedule Calendar"), systemImage: "calendar") {
                export { try PDFExport.scheduleCalendar(project: project, startDate: currentRange.lowerBound, endDate: currentRange.upperBound) }
            }
            Menu {
                ForEach(project.productionMonths(), id: \.self) { month in
                    Button(formattedDate(month, pattern: "LLLL yyyy")) {
                        activeSheet = .monthOptions(month: month)
                    }
                }
            } label: {
                rowLabel(L("Month Calendar"), systemImage: "calendar.day.timeline.left", detail: L("Choose a month"))
            }
            .disabled(shootDays.isEmpty)
            actionRow(L("Strip Schedule"), systemImage: "rectangle.split.3x1") {
                export { try PDFExport.stripSchedule(project: project) }
            }
            actionRow(L("Shooting Schedule"), systemImage: "doc.text") {
                export { PDFExport.shootingSchedule(project: project) }
            }
            actionRow(L("Days Out of Days"), systemImage: "tablecells") {
                export { try PDFExport.daysOutOfDays(project: project, includeHold: includeHoldInDOOD) }
            }
            Toggle(L("Include Hold Days in DOoD Report"), isOn: $includeHoldInDOOD)
            actionRow(L("Scene Breakdowns"), systemImage: "list.clipboard") {
                export { try PDFExport.breakdowns(project: project) }
            }
        } header: {
            Text(L("Export"))
        } footer: {
            Text(L("Each export opens a preview you can share, print or save to Files."))
        }
    }

    private var importSection: some View {
        Section {
            actionRow(L("Import Script…"), systemImage: "square.and.arrow.down", detail: L("Fountain, Final Draft, Highland")) {
                showingImportPicker = true
            }
        } header: {
            Text(L("Import"))
        } footer: {
            Text(L("The script's scenes are added to this project's Boneyard after you review the summary."))
        }
    }

    // MARK: - Rows

    /// A row that opens a sheet or runs a command: the icon in the accent color, the
    /// title, and an optional detail at the trailing edge.
    private func actionRow(_ title: String, systemImage: String, detail: String? = nil, detailColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, systemImage: systemImage, detail: detail, detailColor: detailColor)
        }
        .accessibilityIdentifier("ProductionRow.\(title)")
    }

    private func rowLabel(_ title: String, systemImage: String, detail: String? = nil, detailColor: Color? = nil) -> some View {
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
            MonthPDFOptionsSheet(
                selectedFields:       monthPDFFields,
                includePageCount:     $monthPDFShowPages,
                includeEstimatedTime: $monthPDFShowTime,
                onCancel:             { activeSheet = nil },
                onExport:             {
                    activeSheet = nil
                    exportMonth(month)
                }
            )
        case .importSummary:
            if let result = pendingImport {
                ImportSummaryView(
                    result:       result,
                    onDismiss:    { activeSheet = nil },
                    onConfirm:    { commitImport(result) },
                    confirmation: .existingProject
                )
            }
        }
    }

    private func sheetPresented(_ sheet: ActiveSheet) -> Binding<Bool> {
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
                knownLocations: knownLocations
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

    /// The location roster plus every real location in use, for the editor's suggestions.
    private var knownLocations: [String] {
        var set = Set<String>()
        for day in shootDays {
            for scene in day.scenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        }
        for scene in project.allScenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        for location in productionInfo.locationRoster where !location.name.isEmpty { set.insert(location.name) }
        return Array(set).sorted()
    }

    // MARK: - Production Setup

    private var productionInfoBinding: Binding<ProductionInfo> {
        Binding(get: { productionInfo }, set: { new in edit(L("Edit Production Setup")) { $0.productionInfo = new } })
    }

    /// The character name join (CONTEXT.md): a renamed character reaches every scene's
    /// cast and every call sheet's cast override, in the gesture the setup's own write
    /// then joins, so the rename and the roster are one undo step (the Mac's rule).
    private func renameCastCharacter(from oldName: String, to newName: String) {
        let old = oldName.trimmingCharacters(in: .whitespaces)
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard !old.isEmpty, !new.isEmpty, old.caseInsensitiveCompare(new) != .orderedSame else { return }

        func renamed(_ cast: [String]) -> [String] {
            cast.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }

        beginEditGestureIfNeeded()
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

    // MARK: - Conflicts and the schedule lock

    private func scanForConflicts() {
        conflictReportResults = ConflictScanner.scan(shootDays: shootDays, productionInfo: productionInfo)
        activeSheet = .conflictReport
    }

    private func lockSchedule() {
        let working = ScheduleLockScanner.currentWorkingDays(shootDays: shootDays)
        var stored: [String: [Date]] = [:]
        for (character, dates) in working { stored[character] = dates.sorted() }
        edit(L("Lock Schedule")) { data in
            var info = data.productionInfo ?? ProductionInfo()
            info.scheduleLock = ScheduleLock(lockedAt: Date(), workingDays: stored)
            data.productionInfo = info
        }
        alertMessage = L("Schedule locked. You'll be notified in the Schedule Lock Report if any actor's working days change from here.")
    }

    private func unlockSchedule() {
        guard productionInfo.scheduleLock != nil else { return }
        edit(L("Unlock Schedule")) { $0.productionInfo?.scheduleLock = nil }
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

    // MARK: - Project settings

    private var projectTitleBinding: Binding<String> {
        Binding(
            get: { project.projectTitle },
            set: { new in editCoalescing(titleGesture, L("Rename Project")) { $0.projectTitle = new } }
        )
    }

    private var shiftModeBinding: Binding<Bool> {
        Binding(
            get: { project.isShiftModeEnabled ?? false },
            set: { new in edit(L("Shift Schedule")) { $0.isShiftModeEnabled = new } }
        )
    }

    /// The project's range as it is (the exports draw it), today twice for a project
    /// without days.
    private var currentRange: ClosedRange<Date> {
        Self.dateRange(of: shootDays) ?? Date()...Date()
    }

    private var rangeIsApplicable: Bool {
        guard startDate <= endDate else { return false }
        let cal = Calendar.current
        guard let current = Self.dateRange(of: shootDays) else { return true }
        return !(cal.isDate(startDate, inSameDayAs: current.lowerBound) && cal.isDate(endDate, inSameDayAs: current.upperBound))
    }

    /// "Nov 2 – Nov 6 · 5 days", or what is wrong with the pending range.
    private var rangeDetail: String {
        guard startDate <= endDate else { return L("End before start") }
        let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1
        return days == 1 ? L("1 day") : String(format: L("%d days"), days)
    }

    private func seedRangePickers() {
        guard let range = Self.dateRange(of: shootDays), range != seededRange else { return }
        startDate   = range.lowerBound
        endDate     = range.upperBound
        seededRange = range
    }

    /// Update Calendar: a range that would send scenes back to the Boneyard is confirmed
    /// first (there is no visible Undo on a phone); any other applies at once.
    private func requestRangeUpdate() {
        guard rangeIsApplicable else { return }
        let preview = project.previewProductionRange(from: startDate, to: endDate)
        if preview.displacedSceneCount > 0 {
            pendingRangePreview      = preview
            showingRangeConfirmation = true
        } else {
            applyRangeUpdate()
        }
    }

    /// One edit, so the whole regeneration is one undo step (`ProductionRange.swift`).
    private func applyRangeUpdate() {
        pendingRangePreview = nil
        let newStart = startDate
        let newEnd   = endDate
        edit(L("Update Calendar")) { $0.updateProductionRange(from: newStart, to: newEnd) }
        seededRange = Self.dateRange(of: shootDays)
    }

    private func rangeConfirmationMessage(_ preview: ProductionRangePreview) -> String {
        let scenes = preview.displacedSceneCount == 1
            ? L("1 scene on a day outside the new range will return to the Boneyard.")
            : String(format: L("%d scenes on days outside the new range will return to the Boneyard."), preview.displacedSceneCount)
        return scenes + " " + L("Call sheets, calendar events, day types and notes stay on their dates.")
    }

    // MARK: - Exports

    /// Builds the request and hands it to the preview sheet; a failure is the alert's
    /// message (`PDFExportError`). Never an exporter call from here. (Untyped `throws`:
    /// a closure literal's thrown type is inferred as `any Error`, not the typed one.)
    private func export(_ make: () throws -> PDFExportRequest) {
        do {
            exportPreview = try make()
        } catch let error as PDFExportError {
            alertMessage = error.message
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportMonth(_ month: Date) {
        let options = MonthPDFOptions(
            fields:               StripboardFieldSettings.decode(monthPDFFieldsRaw),
            includePageCount:     monthPDFShowPages,
            includeEstimatedTime: monthPDFShowTime
        )
        export { try PDFExport.monthCalendar(project: project, month: month, options: options) }
    }

    // MARK: - Import

    /// The picker returned: parse the script (any format, `ScriptImport`) and show the
    /// summary; nothing is written until Add to Boneyard.
    private func importPickerFinished(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try ScriptImport.parse(at: url)
                activeSheet   = .importSummary
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    /// Add to Boneyard: the one write, and the summary closes.
    private func commitImport(_ result: FountainImportResult) {
        edit(L("Import Script")) { $0.allScenes.append(contentsOf: result.scenes) }
        activeSheet = nil
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
        case .exportScheduleCalendar: export { try PDFExport.scheduleCalendar(project: project, startDate: currentRange.lowerBound, endDate: currentRange.upperBound) }
        case .exportStripSchedule:    export { try PDFExport.stripSchedule(project: project) }
        case .exportDaysOutOfDays:    export { try PDFExport.daysOutOfDays(project: project, includeHold: includeHoldInDOOD) }
        case .exportBreakdowns:       export { try PDFExport.breakdowns(project: project) }
        }
    }
}

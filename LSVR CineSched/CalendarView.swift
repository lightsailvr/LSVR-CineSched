// CalendarView.swift
// Calendar grid with drag-and-drop scene scheduling

import SwiftUI
import UniformTypeIdentifiers

// MARK: - DropIndicatorView & Delegates

// MARK: - Day type submenu (shared by the day cell and empty cell context menus)

/// A submenu listing every `DayType`. With a `current` value it is a `Picker`, which a
/// context menu renders as a titled submenu with a checkmark on the current type. The
/// "every Saturday" variant passes `nil` because those days may disagree, and a Picker
/// with no matching tag logs a warning, so that case is a plain `Menu` of buttons.
@ViewBuilder
func dayTypePicker(_ title: String, current: DayType?, onSelect: @escaping (DayType) -> Void) -> some View {
    if let current {
        Picker(title, selection: Binding(get: { current }, set: { onSelect($0) })) {
            ForEach(DayType.allCases, id: \.self) { type in
                Label(type.localizedName, systemImage: type.icon).tag(type)
            }
        }
    } else {
        Menu(title) {
            ForEach(DayType.allCases, id: \.self) { type in
                Button { onSelect(type) } label: {
                    Label(type.localizedName, systemImage: type.icon)
                }
            }
        }
    }
}

struct DropIndicatorView: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(height: 2)
            .padding(.vertical, 1)
    }
}

struct CombinedDayDropDelegate: DropDelegate {
    let dayId: UUID
    let scenes: [Scene]
    @Binding var dropTargetDayId: UUID?
    @Binding var dropTargetPosition: Int?
    @Binding var dayDropTargetId: UUID?
    @Binding var draggingDayId: UUID?
    let onSceneDrop: (UUID) -> Void
    let onDayDrop: (UUID) -> Void
    /// A day-type band being dragged (calendar only). Optional so the Stripboard, which has
    /// no band, keeps its existing call sites. Moves just the type and note, not the day.
    var draggingDayTypeId: Binding<UUID?>? = nil
    var onDayTypeDrop: ((UUID) -> Void)? = nil

    func performDrop(info: DropInfo) -> Bool {
        if let typeBinding = draggingDayTypeId, let sourceId = typeBinding.wrappedValue {
            if sourceId != dayId { onDayTypeDrop?(sourceId) }
            typeBinding.wrappedValue = nil
            dayDropTargetId = nil
            return true
        }
        if let dayIdStr = draggingDayId, dayIdStr != dayId {
            onDayDrop(dayIdStr)
            draggingDayId = nil
            dayDropTargetId = nil
            return true
        }
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else { return false }
        // Drag payloads are built with NSItemProvider(object: … as NSString), so load them back
        // as NSString; loadItem(forTypeIdentifier:) is deprecated as of the 27.0 SDKs.
        item.loadObject(ofClass: NSString.self) { loaded, _ in
            if let idStr = loaded as? String {
                let firstIdStr = idStr.split(separator: ",").first.map(String.init) ?? idStr
                if let uuid = UUID(uuidString: firstIdStr) {
                    DispatchQueue.main.async {
                        onSceneDrop(uuid)
                    }
                }
            }
        }
        dropTargetDayId = nil
        dropTargetPosition = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        let typeDragId = draggingDayTypeId?.wrappedValue
        if (draggingDayId != nil && draggingDayId != dayId) || (typeDragId != nil && typeDragId != dayId) {
            dayDropTargetId = dayId
        } else {
            dropTargetDayId = dayId
            dropTargetPosition = scenes.count
        }
    }

    func dropExited(info: DropInfo) {
        if dayDropTargetId == dayId { dayDropTargetId = nil }
        if dropTargetDayId == dayId { dropTargetDayId = nil }
    }
}

struct SceneDropDelegate: DropDelegate {
    let dayId: UUID
    let position: Int
    @Binding var dropTargetDayId: UUID?
    @Binding var dropTargetPosition: Int?
    let onDrop: (UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else { return false }
        // Drag payloads are built with NSItemProvider(object: … as NSString), so load them back
        // as NSString; loadItem(forTypeIdentifier:) is deprecated as of the 27.0 SDKs.
        item.loadObject(ofClass: NSString.self) { loaded, _ in
            if let idStr = loaded as? String {
                let firstIdStr = idStr.split(separator: ",").first.map(String.init) ?? idStr
                if let uuid = UUID(uuidString: firstIdStr) {
                    DispatchQueue.main.async {
                        onDrop(uuid)
                    }
                }
            }
        }
        dropTargetDayId = nil
        dropTargetPosition = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        dropTargetDayId = dayId
        dropTargetPosition = position
    }

    func dropExited(info: DropInfo) {
        if dropTargetDayId == dayId && dropTargetPosition == position {
            dropTargetDayId = nil
            dropTargetPosition = nil
        }
    }
}

// MARK: - Standalone DayCellView

struct DayCellView: View {
    let day: ShootDay
    let dayIndex: Int
    let dayNumber: Int?
    let isSidebarCollapsed: Bool
    let showCastOnCards: Bool
    let showEstTimeOnCards: Bool
    let isInShootRange: Bool
    let selectedSceneIDs: Set<UUID>
    let conflictSceneIDs: Set<UUID>
    let duplicateSceneNumberIDs: Set<UUID>

    @Binding var draggingDayId: UUID?
    @Binding var dropTargetDayId: UUID?
    @Binding var dropTargetPosition: Int?
    @Binding var dayDropTargetId: UUID?
    @Binding var addingEventForDayId: UUID?
    @Binding var callSheetDay: ShootDay?
    @Binding var interactingSceneId: UUID?
    @Binding var draggedSceneId: UUID?
    @Binding var draggingDayTypeId: UUID?

    let onOpenDayDetail: () -> Void
    let onEditScene: (Int, Scene) -> Void
    let onRemoveScene: (Scene) -> Void
    let onDuplicateScene: (Scene) -> Void
    let onToggleCompletedScene: (Scene) -> Void
    let onSelectScene: (Scene) -> Void
    let onSendToDay: (Scene) -> Void
    let onHandleSceneDrop: (UUID, Int) -> Void
    let onHandleDayRearrange: (UUID) -> Void
    /// The day-type band from `sourceDayId` was dropped on this cell.
    let onHandleDayTypeMove: (UUID) -> Void
    let onSetDayType: (ShootDay, DayType) -> Void
    let onSetDayTypeForWeekday: (ShootDay, DayType) -> Void
    let onClearDayType: (ShootDay) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue

    private var visibleScenes: [Scene] {
        day.scenes.filter { !$0.isBanner || $0.isCalendarEvent }
    }

    private var isShootDay: Bool {
        day.dayType.isShootable && (dayNumber != nil || isInShootRange || !day.scenes.filter { !$0.isCalendarEvent }.isEmpty)
    }

    private var dayTypeColor: Color { Color(hex: day.dayType.colorHex) }

    private var isTarget: Bool {
        dayDropTargetId == day.id || dropTargetDayId == day.id
    }

    private var borderColor: Color {
        if dayDropTargetId == day.id { return .green }
        if dropTargetDayId == day.id { return .red }
        if !day.dayType.isShootable { return dayTypeColor.opacity(0.5) }
        if isShootDay { return currentTheme.shootDayBorderColor(isDarkMode: colorScheme == .dark) }
        return .primary.opacity(0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            dayTypeBand
            sceneList
            Spacer()
            footer
        }
        .padding(8)
        .frame(minHeight: 120, alignment: .topLeading)
        .background(
            ZStack {
                if isShootDay {
                    currentTheme.shootDayRangeHighlight(isDarkMode: colorScheme == .dark)
                } else {
                    Color.controlBackground
                }
                if isWeekend(day.date) { Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03) }
                if !day.dayType.isShootable { dayTypeColor.opacity(colorScheme == .dark ? 0.22 : 0.1) }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isTarget ? 2 : 1)
        )
        .opacity(draggingDayId == day.id ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenDayDetail()
        }
        .onDrop(of: [UTType.text.identifier], delegate: CombinedDayDropDelegate(
            dayId: day.id,
            scenes: visibleScenes,
            dropTargetDayId: $dropTargetDayId,
            dropTargetPosition: $dropTargetPosition,
            dayDropTargetId: $dayDropTargetId,
            draggingDayId: $draggingDayId,
            onSceneDrop: { sceneId in onHandleSceneDrop(sceneId, visibleScenes.count) },
            onDayDrop: { sourceDayId in onHandleDayRearrange(sourceDayId) },
            draggingDayTypeId: $draggingDayTypeId,
            onDayTypeDrop: { sourceDayId in onHandleDayTypeMove(sourceDayId) }
        ))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(draggingDayId == day.id ? .blue : .secondary)
                    .padding(2)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggingDayId = day.id
                        return NSItemProvider(object: "day:\(day.id.uuidString)" as NSString)
                    }
                    .help("Drag to swap this day's scenes, call sheet, day type, and note with another date")

                Button {
                    onOpenDayDetail()
                } label: {
                    HStack(spacing: 3) {
                        let cal = Calendar.current
                        let dayOfMonth = cal.component(.day, from: day.date)
                        let weekdayStr = localizedShortWeekday(day.date)

                        Text("\(dayOfMonth)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(day.dayType.isShootable ? .primary : dayTypeColor)

                        Text(weekdayStr)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if day.hasCallSheetData {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 2)

                if let dayNumber, isShootDay {
                    Text("\(L("Day")) \(dayNumber)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(currentTheme.primaryAccent(isDarkMode: colorScheme == .dark))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(currentTheme.primaryAccent(isDarkMode: colorScheme == .dark).opacity(0.18))
                        .cornerRadius(3.5)
                }

                Button {
                    addingEventForDayId = day.id
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Add Calendar Event"))
            }

            if !day.callSheet.lunchTime.isEmpty || !day.callSheet.snackTime.isEmpty || !day.callSheet.dinnerTime.isEmpty {
                HStack(spacing: 4) {
                    Spacer()
                    if !day.callSheet.lunchTime.isEmpty {
                        Text("🍽️ \(day.callSheet.lunchTime)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !day.callSheet.snackTime.isEmpty {
                        Text("☕ \(day.callSheet.snackTime)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !day.callSheet.dinnerTime.isEmpty {
                        Text("🎬 \(day.callSheet.dinnerTime)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .contextMenu {
            Button(LocalizationManager.shared.currentLanguage == .spanish ? "Ver Detalle del Día" : "View Day Details") { onOpenDayDetail() }
            Button(L("Add Calendar Event")) { addingEventForDayId = day.id }
            Divider()
            // A Picker inside a context menu renders as a submenu with a checkmark on the
            // current value, which is exactly the "what is this day?" affordance we want.
            dayTypePicker(L("Set Day Type"), current: day.dayType) { onSetDayType(day, $0) }
            dayTypePicker("\(L("Set Every")) \(localizedFullWeekday(day.date))", current: nil) { onSetDayTypeForWeekday(day, $0) }
            if !day.dayType.isShootable || !day.dayNote.isEmpty {
                Button(L("Clear Day Type")) { onClearDayType(day) }
            }
        }
    }

    /// Full-width label for non-shoot days (travel, holiday, …), then the free-text day note.
    /// Shoot days show only the note, so a plain reminder doesn't force a type change.
    @ViewBuilder
    private var dayTypeBand: some View {
        if !day.dayType.isShootable {
            HStack(spacing: 4) {
                Image(systemName: day.dayType.icon)
                    .font(.system(size: 8, weight: .bold))
                Text(day.dayType.localizedName.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(dayTypeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(dayTypeColor.opacity(0.18))
            .cornerRadius(3.5)
            .contentShape(Rectangle())
            // The band is what people grab when they want to "move the scout day". It moves
            // only the type and note; the header handle is the gesture for the whole day.
            .onDrag {
                draggingDayTypeId = day.id
                return NSItemProvider(object: "daytype:\(day.id.uuidString)" as NSString)
            }
            .help(L("Drag to move this day type to another date"))
        }
        if !day.dayNote.isEmpty {
            Text(day.dayNote)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func localizedShortWeekday(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = LocalizationManager.shared.currentLanguage == .spanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateFormat = "EEE"
        return df.string(from: date).capitalized
    }

    private func localizedFullWeekday(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = LocalizationManager.shared.currentLanguage == .spanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateFormat = "EEEE"
        return df.string(from: date).capitalized
    }

    private var sceneList: some View {
        VStack(spacing: 2) {
            ForEach(Array(visibleScenes.enumerated()), id: \.element.id) { sceneIndex, scene in
                VStack(spacing: 0) {
                    if dropTargetDayId == day.id && dropTargetPosition == sceneIndex {
                        DropIndicatorView()
                    }
                    SceneCardView(
                        scene: scene,
                        dayId: day.id,
                        dayIndex: dayIndex,
                        sceneIndex: sceneIndex,
                        interactingSceneId: $interactingSceneId,
                        isSelected: selectedSceneIDs.contains(scene.id),
                        selectionCount: selectedSceneIDs.count,
                        showCast: isSidebarCollapsed || showCastOnCards,
                        showEstTimeOnCards: showEstTimeOnCards,
                        hasConflict: conflictSceneIDs.contains(scene.id),
                        hasDuplicateSceneNumber: duplicateSceneNumberIDs.contains(scene.id),
                        isOnNonShootDay: !day.dayType.isShootable,
                        onEdit:      { onEditScene(sceneIndex, scene) },
                        onRemove:    { onRemoveScene(scene) },
                        onDuplicate: { onDuplicateScene(scene) },
                        onToggleCompleted: { onToggleCompletedScene(scene) },
                        onDragStart: { draggedSceneId = scene.id },
                        onDragEnd:   { draggedSceneId = nil },
                        onSelect:    { onSelectScene(scene) },
                        onSendToDay: { onSendToDay(scene) },
                        dragPayload: { scene.id.uuidString }
                    )
                }
                .onDrop(of: [UTType.text.identifier], delegate: SceneDropDelegate(
                    dayId: day.id,
                    position: sceneIndex,
                    dropTargetDayId: $dropTargetDayId,
                    dropTargetPosition: $dropTargetPosition,
                    onDrop: { sceneId in onHandleSceneDrop(sceneId, sceneIndex) }
                ))
            }

            if dropTargetDayId == day.id && dropTargetPosition == visibleScenes.count {
                DropIndicatorView()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !visibleScenes.isEmpty {
            let scriptScenes = visibleScenes.filter { !$0.isBanner }
            let totalDur = scriptScenes.reduce(0) { $0 + $1.duration }
            let totalEst = scriptScenes.reduce(0) { $0 + $1.estimatedTime }
            if totalDur > 0 || totalEst > 0 {
                Text("\(L("Total:")) \(formattedEighths(totalDur)) · \(formattedTime(totalEst))")
                    .font(.caption2).fontWeight(.medium).foregroundColor(.secondary)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage == .spanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date).capitalized
    }
}

// MARK: - CompactMonthCalendarView

enum CalendarViewMode: String, CaseIterable {
    case monthGrid
    case shootDaysOnly
}

struct CompactMonthCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var shootDays: [ShootDay]
    let assignScene:  (Scene, ShootDay) -> Void
    @Binding var allScenes: [Scene]
    let updateScene:  (Scene, UUID) -> Void
    let removeScene:  (Scene, UUID) -> Void
    let projectTitle: String
    let productionInfo: ProductionInfo
    let isSidebarCollapsed: Bool
    let showCastOnCards: Bool
    let showEstTimeOnCards: Bool
    let startDate: Date
    let endDate: Date
    @Binding var selectedSceneIDs:    Set<UUID>
    @Binding var lastSelectedSceneID: UUID?
    let conflictDates: Set<Date>
    let conflictSceneIDs: Set<UUID>
    let duplicateSceneNumberIDs: Set<UUID>
    let scheduleLockChangedDates: Set<Date>
    @Binding var scrollToDate: Date?
    let dragStateResetToken: Int
    let onBeforeSceneChange: () -> Void
    let onSceneChanged: () -> Void
    let onCallSheetExport: (ShootDay) -> Void
    /// Month PDF export, handed the displayed month and the confirmed options; the
    /// exporter call and the save panel live with the other exports in ContentView.
    let onExportMonthPDF: (Date, MonthPDFOptions) -> Void

    // View Mode Switcher
    @AppStorage("CineSchedCalendarViewMode") private var calendarViewMode: CalendarViewMode = .monthGrid

    // Day Detail Inspector Sheet state
    @State private var inspectingDay: ShootDay? = nil

    // Editing state
    @State private var editingScene:      Scene?
    @State private var editingDayId:      UUID?
    @State private var editingDayIndex:   Int?
    @State private var editingSceneIndex: Int?
    @State private var showingEditSheet = false

    // Call sheet state
    @State private var callSheetDay: ShootDay? = nil

    // Send to Day state
    @State private var showingSendToDaySheet = false
    @State private var sendToDaySceneIDs: [UUID] = []

    // Day rearrange drag/drop state
    @State private var draggingDayId:       UUID? = nil
    @State private var draggingDayTypeId:   UUID? = nil
    @State private var dayDropTargetId:     UUID? = nil

    // Drag/drop state
    @State private var dropTargetDayId:    UUID?
    @State private var dropTargetPosition: Int?
    @State private var draggedSceneId:     UUID?
    @State private var interactingSceneId: UUID?

    // Add Calendar Event sheet state
    @State private var addingEventForDayId: UUID? = nil
    @State private var editingEventScene: Scene? = nil
    @State private var editingEventDayId: UUID? = nil

    // Month navigation state
    @State private var displayedMonth: Date = Date()

    // Month PDF export options — an app preference (UserDefaults), like the Stripboard
    // fields, so the dialog remembers the last selection between exports.
    @State private var showingExportOptions = false
    @AppStorage(MonthPDFOptionSettings.fieldsKey) private var monthPDFFieldsRaw: String = MonthPDFOptionSettings.defaultFieldsRaw
    @AppStorage(MonthPDFOptionSettings.pagesKey)  private var monthPDFShowPages: Bool = MonthPDFOptions.default.includePageCount
    @AppStorage(MonthPDFOptionSettings.timeKey)   private var monthPDFShowTime:  Bool = MonthPDFOptions.default.includeEstimatedTime

    private var monthPDFFieldsBinding: Binding<Set<StripboardField>> {
        Binding(
            get: { StripboardFieldSettings.decode(monthPDFFieldsRaw) },
            set: { monthPDFFieldsRaw = StripboardFieldSettings.encode($0) }
        )
    }

    private var isSpanish: Bool {
        LocalizationManager.shared.currentLanguage == .spanish
    }

    private var startOfDisplayedMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
        return cal.date(from: comps) ?? displayedMonth
    }

    private var daysInDisplayedMonth: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: startOfDisplayedMonth) else { return [] }
        return range.compactMap { day -> Date? in
            cal.date(byAdding: .day, value: day - 1, to: startOfDisplayedMonth)
        }
    }

    private var monthLeadingOffsetCount: Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: startOfDisplayedMonth) // 1=Sun, 2=Mon...
        return weekday - 1 // Sunday=0
    }

    private var monthYearTitle: String {
        let df = DateFormatter()
        df.locale = isSpanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: displayedMonth).capitalized
    }

    private var weekdaySymbols: [String] {
        if isSpanish {
            return ["DOMINGO", "LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO"]
        } else {
            return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        }
    }

    private var monthNavigationRow: some View {
        HStack(spacing: 12) {
            // View Mode Switcher
            Picker("", selection: $calendarViewMode) {
                Text(isSpanish ? "📅 Mes Completo" : "📅 Full Month").tag(CalendarViewMode.monthGrid)
                Text(isSpanish ? "🎬 Horario Completo" : "🎬 Full Schedule").tag(CalendarViewMode.shootDaysOnly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Divider().frame(height: 20)

            if calendarViewMode == .monthGrid {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.bordered)
                .help(L("Previous Month"))

                Text(monthYearTitle)
                    .font(.system(size: 15, weight: .bold))
                    .frame(minWidth: 150, alignment: .center)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.bordered)
                .help(L("Next Month"))

                Button(L("Go to Shoot")) {
                    if let firstShoot = shootDays.first(where: { !$0.scenes.isEmpty }) ?? shootDays.first {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonth = firstShoot.date
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button(L("Today")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = Date()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text("\(onlyActualShootDays.count) \(isSpanish ? "Días en Plan de Rodaje" : "Days in Schedule")")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingExportOptions = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc.fill")
                    Text(L("Export Month (PDF)"))
                }
            }
            .buttonStyle(.bordered)
            .help(L("Export Month (PDF)"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var onlyActualShootDays: [(offset: Int, element: ShootDay)] {
        Array(shootDays.enumerated()).filter { _, day in
            let start = Calendar.current.startOfDay(for: startDate)
            let end = Calendar.current.startOfDay(for: endDate)
            let dayDate = Calendar.current.startOfDay(for: day.date)
            return dayDate >= start && dayDate <= end
        }
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.08))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            monthNavigationRow

            weekdayHeaderRow

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    let columns = Array(repeating: GridItem(.flexible(minimum: 100), spacing: 8), count: 7)
                    LazyVGrid(columns: columns, spacing: 8) {
                        if calendarViewMode == .monthGrid {
                            ForEach(0..<monthLeadingOffsetCount, id: \.self) { _ in
                                Color.clear
                                    .frame(minHeight: 120)
                            }
                            ForEach(daysInDisplayedMonth, id: \.self) { date in
                                if let dayIndex = shootDays.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                                    dayCell(day: shootDays[dayIndex], dayIndex: dayIndex)
                                        .id(shootDays[dayIndex].id)
                                } else {
                                    emptyDayCell(for: date)
                                        .id(date)
                                }
                            }
                        } else {
                            // Shoot Days Only mode
                            let shootDaysList = onlyActualShootDays
                            let leadingShootOffset: Int = {
                                guard let first = shootDaysList.first?.element else { return 0 }
                                let weekday = Calendar.current.component(.weekday, from: first.date)
                                return weekday - 1 // Sunday=0
                            }()
                            ForEach(0..<leadingShootOffset, id: \.self) { _ in
                                Color.clear
                                    .frame(minHeight: 120)
                            }
                            ForEach(shootDaysList, id: \.element.id) { dayIndex, day in
                                dayCell(day: day, dayIndex: dayIndex)
                                    .id(day.id)
                            }
                        }
                    }
                    .id("\(isSidebarCollapsed)-\(showCastOnCards)")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 60)
                }
                .onChange(of: scrollToDate) { _, newValue in
                    guard let date = newValue else { return }
                    displayedMonth = date
                    if let target = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                        withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                    }
                    scrollToDate = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tooltipContainer()
        .onChange(of: dragStateResetToken) { _, _ in
            // Undo/redo restores allScenes/shootDays but has no way to reach into this
            // view's own local drag-target state — this clears it explicitly so a day
            // cell's drop-target border can't get stuck highlighted after an undo.
            dropTargetDayId = nil
            dropTargetPosition = nil
            draggedSceneId = nil
            dayDropTargetId = nil
            draggingDayId = nil
            draggingDayTypeId = nil
        }
        .onAppear {
            if let firstShoot = shootDays.first(where: { !$0.scenes.isEmpty }) ?? shootDays.first {
                displayedMonth = firstShoot.date
            }
        }
        .sheet(item: $inspectingDay) { day in
            DayDetailSheet(
                day: day,
                dayNumber: dayNumbers[day.id],
                productionInfo: productionInfo,
                isPresented: Binding(
                    get: { inspectingDay != nil },
                    set: { if !$0 { inspectingDay = nil } }
                ),
                onEditScene: { scene in
                    if let dIdx = shootDays.firstIndex(where: { $0.id == day.id }),
                       let sIdx = shootDays[dIdx].scenes.firstIndex(where: { $0.id == scene.id }) {
                        inspectingDay = nil
                        editScene(dayIndex: dIdx, sceneIndex: sIdx, scene: scene, dayId: day.id)
                    }
                },
                onRemoveScene: { scene in
                    removeFromDay(scene, dayId: day.id)
                    if let updated = shootDays.first(where: { $0.id == day.id }) {
                        inspectingDay = updated
                    } else {
                        inspectingDay = nil
                    }
                },
                onAddCalendarEvent: {
                    inspectingDay = nil
                    addingEventForDayId = day.id
                },
                onSetDayType: { type in
                    setDayType(day, to: type)
                    // `day` is a copy; hand the sheet the fresh value so the badge updates.
                    if let updated = shootDays.first(where: { $0.id == day.id }) { inspectingDay = updated }
                },
                onSetDayNote: { note in
                    setDayNote(day.id, to: note)
                    if inspectingDay != nil, let updated = shootDays.first(where: { $0.id == day.id }) {
                        inspectingDay = updated
                    }
                },
                onClearDayType: {
                    clearDayType(day)
                    // Clearing can delete an out-of-range day outright; close the sheet then.
                    inspectingDay = shootDays.first(where: { $0.id == day.id })
                },
                onOpenCallSheet: {
                    inspectingDay = nil
                    callSheetDay = day
                },
                onExportCallSheetPDF: {
                    inspectingDay = nil
                    onCallSheetExport(day)
                }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            editSheetContent()
        }
        .sheet(item: $callSheetDay) { day in
            callSheetEditorContent(for: day)
        }
        .sheet(isPresented: $showingSendToDaySheet) {
            SendToDaySheet(
                shootDays:  shootDays,
                sceneCount: sendToDaySceneIDs.count,
                onSelect: { targetDayId in
                    sendScenes(sendToDaySceneIDs, toDay: targetDayId)
                    showingSendToDaySheet = false
                },
                onCancel: { showingSendToDaySheet = false }
            )
        }
        .sheet(isPresented: Binding(
            get: { addingEventForDayId != nil },
            set: { if !$0 { addingEventForDayId = nil } }
        )) {
            CalendarEventInputSheet(isPresented: Binding(
                get: { addingEventForDayId != nil },
                set: { if !$0 { addingEventForDayId = nil } }
            ), onSave: { newEvent in
                if let targetId = addingEventForDayId,
                   let idx = shootDays.firstIndex(where: { $0.id == targetId }) {
                    shootDays[idx].scenes.append(newEvent)
                    onSceneChanged()
                }
            })
        }
        .sheet(item: $editingEventScene) { ev in
            CalendarEventInputSheet(
                isPresented: Binding(
                    get: { editingEventScene != nil },
                    set: { if !$0 { editingEventScene = nil; editingEventDayId = nil } }
                ),
                initialEvent: ev,
                onSave: { updatedEvent in
                    if let dId = editingEventDayId ?? shootDays.first(where: { $0.scenes.contains(where: { $0.id == ev.id }) })?.id,
                       let dayIdx = shootDays.firstIndex(where: { $0.id == dId }),
                       let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == ev.id }) {
                        shootDays[dayIdx].scenes[sceneIdx] = updatedEvent
                        onSceneChanged()
                    }
                    editingEventScene = nil
                    editingEventDayId = nil
                }
            )
        }
        .sheet(isPresented: $showingExportOptions) {
            MonthPDFOptionsSheet(
                selectedFields: monthPDFFieldsBinding,
                includePageCount: $monthPDFShowPages,
                includeEstimatedTime: $monthPDFShowTime,
                onCancel: { showingExportOptions = false },
                onExport: {
                    showingExportOptions = false
                    exportMonthPDF()
                }
            )
        }
        .onChange(of: showingEditSheet) { _, isShowing in
            if !isShowing { clearEditingState() }
        }
    }

    @ViewBuilder
    private func emptyDayCell(for date: Date) -> some View {
        let cal = Calendar.current
        let dayDigit = cal.component(.day, from: date)
        let isShootRange = date >= cal.startOfDay(for: startDate) && date <= cal.startOfDay(for: endDate)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(dayDigit)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isShootRange ? currentTheme.primaryAccent(isDarkMode: colorScheme == .dark) : .secondary)
                Spacer()
                Button {
                    createAndAddEvent(for: date)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Add Calendar Event"))
            }
            Spacer()
        }
        .padding(8)
        .frame(minHeight: 120, alignment: .topLeading)
        .background(
            isShootRange
                ? currentTheme.shootDayRangeHighlight(isDarkMode: colorScheme == .dark)
                : Color.controlBackground.opacity(0.5)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isShootRange
                        ? currentTheme.shootDayBorderColor(isDarkMode: colorScheme == .dark)
                        : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            createAndAddEvent(for: date)
        }
        .onDrop(of: [UTType.text.identifier], delegate: CombinedDayDropDelegate(
            dayId: UUID(),
            scenes: [],
            dropTargetDayId: $dropTargetDayId,
            dropTargetPosition: $dropTargetPosition,
            dayDropTargetId: $dayDropTargetId,
            draggingDayId: $draggingDayId,
            onSceneDrop: { sceneId in
                onBeforeSceneChange()
                var targetDay: ShootDay
                if let existing = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    targetDay = existing
                } else {
                    targetDay = ShootDay(date: date)
                    shootDays.append(targetDay)
                    shootDays.sort { $0.date < $1.date }
                }
                handleSceneDrop(sceneId: sceneId, targetDayId: targetDay.id, targetPosition: targetDay.scenes.count)
            },
            onDayDrop: { sourceDayId in handleDayRearrange(sourceDayId: sourceDayId, toDate: date) },
            draggingDayTypeId: $draggingDayTypeId,
            onDayTypeDrop: { sourceDayId in moveDayType(from: sourceDayId, toDate: date) }
        ))
        .contextMenu {
            Button(L("Add Calendar Event")) {
                createAndAddEvent(for: date)
            }
            Button(L("Mark as Shoot Day")) {
                onBeforeSceneChange()
                let newDay = ShootDay(date: date)
                shootDays.append(newDay)
                shootDays.sort { $0.date < $1.date }
                onSceneChanged()
            }
            Divider()
            dayTypePicker(L("Set Day Type"), current: nil) { type in
                onBeforeSceneChange()
                let newDay = ShootDay(date: date, dayType: type)
                shootDays.append(newDay)
                shootDays.sort { $0.date < $1.date }
                onSceneChanged()
            }
        }
    }

    private func createAndAddEvent(for date: Date) {
        if let existing = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            addingEventForDayId = existing.id
        } else {
            onBeforeSceneChange()
            let newDay = ShootDay(date: date)
            shootDays.append(newDay)
            shootDays.sort { $0.date < $1.date }
            onSceneChanged()
            addingEventForDayId = newDay.id
        }
    }

    // MARK: - Day type

    private func setDayType(_ day: ShootDay, to type: DayType) {
        guard let idx = shootDays.firstIndex(where: { $0.id == day.id }),
              shootDays[idx].dayType != type else { return }
        onBeforeSceneChange()
        shootDays[idx].dayType = type
        onSceneChanged()
    }

    /// Applies `type` to every day sharing `day`'s weekday, e.g. "every Sunday is a Day Off".
    /// Successor to the old "Mark Weekday Unavailable" toggle.
    private func setDayTypeForWeekday(_ day: ShootDay, to type: DayType) {
        let targetWeekday = Calendar.current.component(.weekday, from: day.date)
        onBeforeSceneChange()
        for idx in 0..<shootDays.count
        where Calendar.current.component(.weekday, from: shootDays[idx].date) == targetWeekday {
            shootDays[idx].dayType = type
        }
        onSceneChanged()
    }

    private func setDayNote(_ dayId: UUID, to note: String) {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = shootDays.firstIndex(where: { $0.id == dayId }),
              shootDays[idx].dayNote != clean else { return }
        onBeforeSceneChange()
        shootDays[idx].dayNote = clean
        onSceneChanged()
    }

    private func exportMonthPDF() {
        let options = MonthPDFOptions(
            fields: StripboardFieldSettings.decode(monthPDFFieldsRaw),
            includePageCount: monthPDFShowPages,
            includeEstimatedTime: monthPDFShowTime
        )
        onExportMonthPDF(displayedMonth, options)
    }

    // MARK: - Day Cell Component

    private var dayNumbers: [UUID: Int] { productionDayNumbers(for: shootDays) }

    @ViewBuilder
    private func dayCell(day: ShootDay, dayIndex: Int) -> some View {
        let cal = Calendar.current
        let inRange = day.date >= cal.startOfDay(for: startDate) && day.date <= cal.startOfDay(for: endDate)

        DayCellView(
            day: day,
            dayIndex: dayIndex,
            dayNumber: dayNumbers[day.id],
            isSidebarCollapsed: isSidebarCollapsed,
            showCastOnCards: showCastOnCards,
            showEstTimeOnCards: showEstTimeOnCards,
            isInShootRange: inRange,
            selectedSceneIDs: selectedSceneIDs,
            conflictSceneIDs: conflictSceneIDs,
            duplicateSceneNumberIDs: duplicateSceneNumberIDs,
            draggingDayId: $draggingDayId,
            dropTargetDayId: $dropTargetDayId,
            dropTargetPosition: $dropTargetPosition,
            dayDropTargetId: $dayDropTargetId,
            addingEventForDayId: $addingEventForDayId,
            callSheetDay: $callSheetDay,
            interactingSceneId: $interactingSceneId,
            draggedSceneId: $draggedSceneId,
            draggingDayTypeId: $draggingDayTypeId,
            onOpenDayDetail: { inspectingDay = day },
            onEditScene: { sceneIndex, scene in editScene(dayIndex: dayIndex, sceneIndex: sceneIndex, scene: scene, dayId: day.id) },
            onRemoveScene: { scene in removeFromDay(scene, dayId: day.id) },
            onDuplicateScene: { scene in duplicateScene(scene) },
            onToggleCompletedScene: { scene in toggleSceneCompleted(scene) },
            onSelectScene: { scene in selectScene(scene, dayId: day.id) },
            onSendToDay: { scene in beginSendToDay(scene) },
            onHandleSceneDrop: { sceneId, pos in handleSceneDrop(sceneId: sceneId, targetDayId: day.id, targetPosition: pos) },
            onHandleDayRearrange: { sourceDayId in handleDayRearrange(sourceDayId: sourceDayId, targetDayId: day.id) },
            onHandleDayTypeMove: { sourceDayId in moveDayType(from: sourceDayId, toDayId: day.id) },
            onSetDayType: { targetDay, type in setDayType(targetDay, to: type) },
            onSetDayTypeForWeekday: { targetDay, type in setDayTypeForWeekday(targetDay, to: type) },
            onClearDayType: { targetDay in clearDayType(targetDay) }
        )
    }

    // MARK: - Actions & Handlers

    private func editScene(dayIndex: Int, sceneIndex: Int, scene: Scene, dayId: UUID) {
        if scene.isCalendarEvent {
            editingEventScene = scene
            editingEventDayId = dayId
            return
        }
        var tempScene = scene
        tempScene.autoExtractSceneNumberIfNeeded()
        editingScene      = tempScene
        editingDayId      = dayId
        editingDayIndex   = dayIndex
        editingSceneIndex = sceneIndex
        showingEditSheet  = true
    }

    private func saveCurrentSceneEdit() {
        guard let editingDayId, let editingDayIndex, let editingSceneIndex,
              editingDayIndex < shootDays.count,
              editingSceneIndex < shootDays[editingDayIndex].scenes.count else { return }
        onBeforeSceneChange()
        // SceneEditSheet already wrote every edited field directly into shootDays via its
        // own live Binding by the time this fires — this call exists purely to trigger
        // updateScene's markDirty() side effect (not exposed directly to this file), so it
        // must use the scene as it now stands, not the `editingScene` snapshot captured
        // back when the sheet was first opened. Passing that stale snapshot was the actual
        // bug: it silently reverted every field — including a changed scene type — right
        // back to whatever it was before the user opened the editor, immediately after
        // SceneEditSheet had just correctly saved the real change.
        let currentScene = shootDays[editingDayIndex].scenes[editingSceneIndex]
        updateScene(currentScene, editingDayId)
    }

    private func clearEditingState() {
        editingScene      = nil
        editingDayId      = nil
        editingDayIndex   = nil
        editingSceneIndex = nil
    }

    private func removeFromDay(_ scene: Scene, dayId: UUID) {
        onBeforeSceneChange()
        removeScene(scene, dayId)
    }

    private func duplicateScene(_ scene: Scene) {
        guard let dayId = shootDays.first(where: { $0.scenes.contains(where: { $0.id == scene.id }) })?.id else { return }
        var dup = scene
        dup.id = UUID()
        onBeforeSceneChange()
        assignScene(dup, shootDays.first(where: { $0.id == dayId })!)
    }

    private func toggleSceneCompleted(_ scene: Scene) {
        let newValue = !scene.isCompleted
        let idsToToggle: Set<UUID> = (selectedSceneIDs.contains(scene.id) && selectedSceneIDs.count > 1)
            ? selectedSceneIDs
            : [scene.id]
        onBeforeSceneChange()
        for id in idsToToggle {
            guard let dayIdx = shootDays.firstIndex(where: { $0.scenes.contains(where: { $0.id == id }) }),
                  let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == id }) else { continue }
            shootDays[dayIdx].scenes[sceneIdx].isCompleted = newValue
        }
        onSceneChanged()
    }

    private func selectScene(_ scene: Scene, dayId: UUID) {
        let flags = ModifierKeys.current
        if flags.contains(.command) {
            if selectedSceneIDs.contains(scene.id) {
                selectedSceneIDs.remove(scene.id)
            } else {
                selectedSceneIDs.insert(scene.id)
            }
            lastSelectedSceneID = scene.id
        } else if flags.contains(.shift), let lastID = lastSelectedSceneID {
            let dayScenes = shootDays.first(where: { $0.id == dayId })?.scenes ?? []
            if let lastIdx = dayScenes.firstIndex(where: { $0.id == lastID }),
               let currentIdx = dayScenes.firstIndex(where: { $0.id == scene.id }) {
                let start = min(lastIdx, currentIdx)
                let end = max(lastIdx, currentIdx)
                for idx in start...end {
                    selectedSceneIDs.insert(dayScenes[idx].id)
                }
            } else {
                selectedSceneIDs = [scene.id]
                lastSelectedSceneID = scene.id
            }
        } else {
            selectedSceneIDs = [scene.id]
            lastSelectedSceneID = scene.id
        }
    }

    private func beginSendToDay(_ scene: Scene) {
        if selectedSceneIDs.contains(scene.id) && selectedSceneIDs.count > 1 {
            sendToDaySceneIDs = Array(selectedSceneIDs)
        } else {
            sendToDaySceneIDs = [scene.id]
        }
        showingSendToDaySheet = true
    }

    private func sendScenes(_ ids: [UUID], toDay targetDayId: UUID) {
        onBeforeSceneChange()
        guard let targetDay = shootDays.first(where: { $0.id == targetDayId }) else { return }
        var scenesToMove: [Scene] = []
        for dIdx in 0..<shootDays.count {
            let matches = shootDays[dIdx].scenes.filter { ids.contains($0.id) }
            scenesToMove.append(contentsOf: matches)
            shootDays[dIdx].scenes.removeAll { ids.contains($0.id) }
        }
        for s in scenesToMove {
            assignScene(s, targetDay)
        }
    }

    private func handleSceneDrop(sceneId: UUID, targetDayId: UUID, targetPosition: Int) {
        onBeforeSceneChange()
        guard let targetDayIndex = shootDays.firstIndex(where: { $0.id == targetDayId }) else { return }

        let idsToMove: [UUID] = selectedSceneIDs.contains(sceneId) && selectedSceneIDs.count > 1
            ? Array(selectedSceneIDs)
            : [sceneId]

        if let sourceDayIndex = shootDays.firstIndex(where: { $0.scenes.contains(where: { $0.id == sceneId }) }) {
            // Dragged from another shoot day or reordering
            var scenesToMove: [Scene] = []
            if sourceDayIndex == targetDayIndex {
                let dayScenes = shootDays[sourceDayIndex].scenes
                let movingSet = Set(idsToMove)
                scenesToMove = dayScenes.filter { movingSet.contains($0.id) }
                var remaining = dayScenes.filter { !movingSet.contains($0.id) }
                let clampedPos = min(targetPosition, remaining.count)
                remaining.insert(contentsOf: scenesToMove, at: clampedPos)
                shootDays[sourceDayIndex].scenes = remaining
            } else {
                for dIdx in 0..<shootDays.count {
                    let matches = shootDays[dIdx].scenes.filter { idsToMove.contains($0.id) }
                    scenesToMove.append(contentsOf: matches)
                    shootDays[dIdx].scenes.removeAll { idsToMove.contains($0.id) }
                }
                let clampedPos = min(targetPosition, shootDays[targetDayIndex].scenes.count)
                shootDays[targetDayIndex].scenes.insert(contentsOf: scenesToMove, at: clampedPos)
            }
            onSceneChanged()
        } else {
            // Dragged from BONEYARD (allScenes)!
            let scenesFromBoneyard = allScenes.filter { idsToMove.contains($0.id) }
            if !scenesFromBoneyard.isEmpty {
                allScenes.removeAll { idsToMove.contains($0.id) }
                let clampedPos = min(targetPosition, shootDays[targetDayIndex].scenes.count)
                shootDays[targetDayIndex].scenes.insert(contentsOf: scenesFromBoneyard, at: clampedPos)
                onSceneChanged()
            }
        }
    }

    private func handleDayRearrange(sourceDayId: UUID, targetDayId: UUID) {
        guard let srcIdx = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let dstIdx = shootDays.firstIndex(where: { $0.id == targetDayId }),
              srcIdx != dstIdx else { return }
        onBeforeSceneChange()
        swapDayContents(srcIdx, dstIdx)
        pruneIfEmptyOutsideRange(dayId: sourceDayId)
        onSceneChanged()
    }

    /// A day handle dropped on a date that has no `ShootDay` yet (outside the production
    /// range). Create the day, then swap into it, so a travel day can be dragged anywhere.
    private func handleDayRearrange(sourceDayId: UUID, toDate date: Date) {
        guard shootDays.contains(where: { $0.id == sourceDayId }) else { return }
        onBeforeSceneChange()
        let newDay = ShootDay(date: date)
        shootDays.append(newDay)
        shootDays.sort { $0.date < $1.date }
        if let s = shootDays.firstIndex(where: { $0.id == sourceDayId }),
           let d = shootDays.firstIndex(where: { $0.id == newDay.id }) {
            swapDayContents(s, d)
        }
        pruneIfEmptyOutsideRange(dayId: sourceDayId)
        onSceneChanged()
    }

    /// The day-type band was dragged from one day onto another: swap only type and note,
    /// leaving each day's scenes and call sheet where they are.
    private func moveDayType(from sourceDayId: UUID, toDayId targetDayId: UUID) {
        guard let s = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let d = shootDays.firstIndex(where: { $0.id == targetDayId }), s != d else { return }
        onBeforeSceneChange()
        swapDayTypeAndNote(s, d)
        pruneIfEmptyOutsideRange(dayId: sourceDayId)
        onSceneChanged()
    }

    /// Band dropped on a date with no `ShootDay` yet (outside the range): create it first.
    private func moveDayType(from sourceDayId: UUID, toDate date: Date) {
        guard shootDays.contains(where: { $0.id == sourceDayId }) else { return }
        onBeforeSceneChange()
        let newDay = ShootDay(date: date)
        shootDays.append(newDay)
        shootDays.sort { $0.date < $1.date }
        if let s = shootDays.firstIndex(where: { $0.id == sourceDayId }),
           let d = shootDays.firstIndex(where: { $0.id == newDay.id }) {
            swapDayTypeAndNote(s, d)
        }
        pruneIfEmptyOutsideRange(dayId: sourceDayId)
        onSceneChanged()
    }

    private func swapDayTypeAndNote(_ a: Int, _ b: Int) {
        let type = shootDays[a].dayType
        let note = shootDays[a].dayNote
        shootDays[a].dayType = shootDays[b].dayType
        shootDays[a].dayNote = shootDays[b].dayNote
        shootDays[b].dayType = type
        shootDays[b].dayNote = note
    }

    /// Swaps everything that makes a day *that* day: scenes (including calendar events), call
    /// sheet, day type, and note. Dragging a travel day onto a Tuesday makes Tuesday the
    /// travel day. No undo snapshot or dirty flag here; callers bracket it.
    private func swapDayContents(_ a: Int, _ b: Int) {
        let scenes    = shootDays[a].scenes
        let callSheet = shootDays[a].callSheet
        let type      = shootDays[a].dayType
        let note      = shootDays[a].dayNote
        shootDays[a].scenes    = shootDays[b].scenes
        shootDays[a].callSheet = shootDays[b].callSheet
        shootDays[a].dayType   = shootDays[b].dayType
        shootDays[a].dayNote   = shootDays[b].dayNote
        shootDays[b].scenes    = scenes
        shootDays[b].callSheet = callSheet
        shootDays[b].dayType   = type
        shootDays[b].dayNote   = note
    }

    /// Days outside the production range only exist to hold something (an event, a type, a
    /// note, a call sheet). Once that is gone the entry goes too, so the date becomes an
    /// empty tile again instead of a stray blank day cell.
    private func pruneIfEmptyOutsideRange(dayId: UUID) {
        guard let idx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        let day = shootDays[idx]
        let cal = Calendar.current
        let inRange = day.date >= cal.startOfDay(for: startDate) && day.date <= cal.startOfDay(for: endDate)
        if !inRange, day.scenes.isEmpty, day.dayType.isShootable, day.dayNote.isEmpty, !day.hasCallSheetData {
            shootDays.remove(at: idx)
        }
    }

    /// Resets a day to a plain shoot day and drops its note. A day that only existed to hold
    /// the type (outside the production range with nothing else on it) is removed entirely.
    private func clearDayType(_ day: ShootDay) {
        guard let idx = shootDays.firstIndex(where: { $0.id == day.id }) else { return }
        onBeforeSceneChange()
        shootDays[idx].dayType = .shoot
        shootDays[idx].dayNote = ""
        pruneIfEmptyOutsideRange(dayId: day.id)
        onSceneChanged()
    }

    // MARK: - Sheets

    @ViewBuilder
    private func editSheetContent() -> some View {
        if let editingDayIndex, let editingSceneIndex,
           editingDayIndex < shootDays.count,
           editingSceneIndex < shootDays[editingDayIndex].scenes.count {
            SceneEditSheet(
                scene: $shootDays[editingDayIndex].scenes[editingSceneIndex],
                isPresented: $showingEditSheet,
                onSave: { saveCurrentSceneEdit() },
                onDelete: {
                    if let dId = editingDayId, let editingScene {
                        removeFromDay(editingScene, dayId: dId)
                    }
                    showingEditSheet = false
                },
                canGoPrevious: editingSceneIndex > 0,
                canGoNext: editingSceneIndex < shootDays[editingDayIndex].scenes.count - 1,
                onPrevious: {
                    if editingSceneIndex > 0 {
                        editScene(dayIndex: editingDayIndex, sceneIndex: editingSceneIndex - 1, scene: shootDays[editingDayIndex].scenes[editingSceneIndex - 1], dayId: shootDays[editingDayIndex].id)
                    }
                },
                onNext: {
                    if editingSceneIndex < shootDays[editingDayIndex].scenes.count - 1 {
                        editScene(dayIndex: editingDayIndex, sceneIndex: editingSceneIndex + 1, scene: shootDays[editingDayIndex].scenes[editingSceneIndex + 1], dayId: shootDays[editingDayIndex].id)
                    }
                },
                positionLabel: "Day \(editingDayIndex + 1), Scene \(editingSceneIndex + 1)"
            )
        }
    }

    @ViewBuilder
    private func callSheetEditorContent(for day: ShootDay) -> some View {
        if let idx = shootDays.firstIndex(where: { $0.id == day.id }) {
            CallSheetEditor(
                shootDay: $shootDays[idx],
                productionInfo: productionInfo,
                isPresented: Binding(
                    get: { callSheetDay != nil },
                    set: { if !$0 { callSheetDay = nil } }
                ),
                onSave: {
                    onSceneChanged()
                },
                onExportPDF: { exportedDay in
                    callSheetDay = nil
                    onCallSheetExport(exportedDay)
                },
                dayNumber: dayNumbers[day.id],
                totalProductionDays: shootDays.count
            )
        }
    }
}

// MARK: - SceneCardView (Compact single-line horizontal strip for Calendar View)

struct SceneCardView: View {
    let scene: Scene
    let dayId: UUID
    let dayIndex: Int
    let sceneIndex: Int
    @Binding var interactingSceneId: UUID?
    let isSelected:     Bool
    let selectionCount: Int
    let showCast:       Bool
    let showEstTimeOnCards: Bool
    let hasConflict:    Bool
    let hasDuplicateSceneNumber: Bool
    /// The day is travel, holiday, unavailable, etc. A scene here is almost certainly a
    /// mistake, so it gets the same red flag as a cast conflict.
    let isOnNonShootDay: Bool
    let onEdit:      () -> Void
    let onRemove:    () -> Void
    let onDuplicate: () -> Void
    let onToggleCompleted: () -> Void
    let onDragStart: () -> Void
    let onDragEnd:   () -> Void
    let onSelect:    () -> Void
    let onSendToDay: () -> Void
    let dragPayload: () -> String

    private var isDragging: Bool { interactingSceneId == scene.id }
    private var isFlagged: Bool { hasConflict || isOnNonShootDay }
    private var displayColor: Color {
        if scene.isCalendarEvent {
            return Color(hex: scene.bannerColorHex.isEmpty ? "6366F1" : scene.bannerColorHex)
        }
        return isFlagged ? .red : scene.stripColor
    }

    var body: some View {
        Group {
            if scene.isCalendarEvent {
                HStack(spacing: 4) {
                    let clockStr = scene.customStartTime.isEmpty ? scene.summary : scene.customStartTime
                    if !clockStr.isEmpty {
                        Text(clockStr)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(displayColor)
                        Text("·")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(displayColor.opacity(0.6))
                    }
                    Text(scene.bannerTitle.isEmpty ? scene.title : scene.bannerTitle)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(displayColor.opacity(0.15))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(displayColor.opacity(0.4), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        let numStr = scene.sceneNumber.isEmpty ? "" : "\(scene.sceneNumber). "
                        Text("\(numStr)\(scene.title)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(scene.stripTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if isFlagged {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.red)
                        }
                        if showEstTimeOnCards {
                            if scene.estimatedTime > 0 {
                                Text(formattedTime(scene.estimatedTime))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(scene.stripTextColor.opacity(0.8))
                            }
                        } else if scene.duration > 0 {
                            Text(formattedEighths(scene.duration))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(scene.stripTextColor.opacity(0.8))
                        }
                    }

                    // Second row: cast, shown when showCast is on (sidebar collapsed, or
                    // the "Show Cast in Calendar" toggle) — showCast already existed as a
                    // parameter here but nothing in this body ever rendered it.
                    if showCast, !scene.cast.isEmpty {
                        Text(scene.cast.joined(separator: ", "))
                            .font(.system(size: 8))
                            .foregroundColor(scene.stripTextColor.opacity(0.75))
                            .italic()
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(displayColor)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
                )
            }
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onEdit() })
        .contextMenu {
            if scene.isCalendarEvent {
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Editar Evento" : "Edit Event") { onEdit() }
                Divider()
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Eliminar Evento" : "Delete Event") { onRemove() }
            } else {
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Editar Escena" : "Edit Scene") { onEdit() }
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Duplicar Escena" : "Duplicate Scene") { onDuplicate() }
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Mover a Día..." : "Move to Day...") { onSendToDay() }
                Divider()
                Button((isSelected && selectionCount > 1)
                       ? "Mark \(selectionCount) Scenes as \(scene.isCompleted ? "Incomplete" : "Completed")"
                       : (scene.isCompleted ? "Mark as Incomplete" : "Mark as Completed")) { onToggleCompleted() }
                Divider()
                Button(LocalizationManager.shared.currentLanguage == .spanish ? "Quitar del Día" : "Remove from Day") { onRemove() }
            }
        }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: dragPayload() as NSString)
        }
        .fastTooltip(scene.tooltipText)
    }
}

// CalendarView.swift
// Calendar grid with drag-and-drop scene scheduling.
//
// Drag and drop (#18): every drag carries a `ScheduleDragPayload` (ScheduleDrag.swift), and
// each cell (and each empty date tile) is one `dropDestination` that switches on the
// payload's kind. Each strip is `draggable` with the scenes it moves (widened to the
// multi-selection), and a thin drop zone between strips gives the exact insertion point,
// with a `DropIndicatorView` where it will land. The day handle and the day-type band are
// their own draggables. Every drop is one edit gesture.
//
// Not the 27 SDK's `reorderContainer`/`reorderable`: those own the lift of an item, and
// combined with the drag container the app also needs (to carry a strip out to the Boneyard
// and to carry the day handle and band, which are not strips) the lift crashed at
// `DragContainerStorage.payload(for:)` on 27.0, because a reorderable strip is not a
// registered item of that heterogeneous drag container. The Boneyard is plain `.draggable`
// too: a `dragContainer` of the payload type claims every draggable of that type in the
// window and crashed the strips' lift the same way (BoneyardListView, learnings 2026-09-20 #18).

import SwiftUI

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

// MARK: - Selecting into the inspector

/// A single tap that exists only where there is an inspector to select into (#17): the
/// iPad editor passes the action, the Mac passes nil and its cells and day headers keep
/// exactly the gestures they had. Applied outside a double-tap gesture the single tap
/// fires on the first tap and the double tap on the second, which is the intended pair:
/// select, then open the full editor. Shared by the calendar's day cell and the
/// Stripboard's day header.
struct SelectOnTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(count: 1, perform: action)
        } else {
            content
        }
    }
}

// MARK: - Drop plumbing shared with the Stripboard

/// The blue line the drop indicator draws where a strip will land.
struct DropIndicatorView: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(height: 2)
            .padding(.vertical, 1)
    }
}

/// Follows a plain `draggable`'s session in a binding: the day handle's and the band's
/// day, which the cells read to colour a hover green (a day is coming) rather than red
/// (scenes are) and the source cell reads to fade. Set when the session starts and
/// cleared when it ends however it ends; the `onDrag` closure this replaces could only set
/// it, so a day drag dropped nowhere left the id behind for the next drop to misread.
struct DragSessionTracking: ViewModifier {
    @Binding var draggingID: UUID?
    let id: UUID

    func body(content: Content) -> some View {
        content.onDragSessionUpdated { session in
            switch session.phase {
            case .initial, .active:
                draggingID = id
            case .ended, .dataTransferCompleted:
                if draggingID == id { draggingID = nil }
            default:
                break
            }
        }
    }
}

/// The hover state of a calendar cell or a Stripboard day section during a drop session:
/// `dayDropTargetId` (green) while a day or a band is in flight, `dropTargetDayId` (red)
/// for scenes, either cleared when the session leaves or ends. The views also clear both
/// on `dragStateResetToken` so an undo mid-hover cannot leave a border stuck.
struct DropTargetTracking: ViewModifier {
    let dayID: UUID
    /// Whether the drag in flight is a whole day or a band rather than scenes.
    let isDayDrag: Bool
    @Binding var dropTargetDayId: UUID?
    @Binding var dayDropTargetId: UUID?

    func body(content: Content) -> some View {
        content.onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                if isDayDrag { dayDropTargetId = dayID } else { dropTargetDayId = dayID }
            case .exiting, .ended, .dataTransferCompleted:
                if dayDropTargetId == dayID { dayDropTargetId = nil }
                if dropTargetDayId == dayID { dropTargetDayId = nil }
            @unknown default:
                break
            }
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
    @Binding var draggingDayTypeId: UUID?

    let onOpenDayDetail: () -> Void
    let onEditScene: (Int, Scene) -> Void
    let onRemoveScene: (Scene) -> Void
    let onDuplicateScene: (Scene) -> Void
    let onToggleCompletedScene: (Scene) -> Void
    let onSelectScene: (Scene) -> Void
    let onSendToDay: (Scene) -> Void
    /// The payload a strip on this day carries when it is lifted, widened by the editor to
    /// the whole multi-selection when the strip is part of it.
    let dragPayload: (Scene) -> ScheduleDragPayload
    /// Payloads dropped on this cell (scenes at the given place, a day, a band, an event).
    /// The calendar switches on each payload's kind.
    let onDrop: ([ScheduleDragPayload], SceneDropDestination.Position) -> Void
    let onSetDayType: (ShootDay, DayType) -> Void
    let onSetDayTypeForWeekday: (ShootDay, DayType) -> Void
    let onClearDayType: (ShootDay) -> Void
    /// The iPad's inspector (#17): a single tap on the cell or its date selects the day
    /// into it, and the selected day's cell is outlined in the accent color. Nil and
    /// false on the Mac, which has no inspector.
    var onSelectDay: (() -> Void)? = nil
    var isInspected: Bool = false

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
        if isInspected { return .accentColor }
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
                .stroke(borderColor, lineWidth: isTarget || isInspected ? 2 : 1)
        )
        .opacity(draggingDayId == day.id ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenDayDetail()
        }
        .modifier(SelectOnTap(action: onSelectDay))
        // The whole cell: a day handle, a band, or scenes dropped on the header/footer
        // rather than on a strip's drop zone, which land at the end of the day.
        .dropDestination(for: ScheduleDragPayload.self) { items, _ in
            onDrop(items, .end)
        }
        .modifier(DropTargetTracking(
            dayID: day.id,
            isDayDrag: draggingDayId != nil || draggingDayTypeId != nil,
            dropTargetDayId: $dropTargetDayId,
            dayDropTargetId: $dayDropTargetId
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
                    .draggable(ScheduleDragPayload(.day(id: day.id)))
                    .modifier(DragSessionTracking(draggingID: $draggingDayId, id: day.id))
                    .help("Drag to swap this day's scenes, call sheet, day type, and note with another date")

                if let onSelectDay {
                    // With an inspector the date is the day's "select" target, a tap on
                    // a label rather than a Button: a long press on a Button fires the
                    // button and never reaches the header's context menu, and the date
                    // is what a finger lands on. The sheet stays on double tap and in
                    // the menu.
                    dateLabel
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onSelectDay)
                } else {
                    Button {
                        onOpenDayDetail()
                    } label: {
                        dateLabel
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 2)

                if let dayNumber, isShootDay {
                    Text("\(L("Day")) \(dayNumber)")
                        .font(.system(size: 9.5, weight: .bold))
                        // In a narrow cell the weekday beside it gives way first and the
                        // badge shrinks, rather than wrapping one letter per line.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
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

    /// The day of the month, its weekday and the call-sheet dot.
    private var dateLabel: some View {
        HStack(spacing: 3) {
            let cal = Calendar.current
            let dayOfMonth = cal.component(.day, from: day.date)
            let weekdayStr = localizedShortWeekday(day.date)

            Text("\(dayOfMonth)")
                .font(.system(size: 13, weight: .bold))
                // Two digits stay on one line in the iPad's narrower cells.
                .fixedSize()
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
            .draggable(ScheduleDragPayload(.dayType(dayID: day.id)))
            .modifier(DragSessionTracking(draggingID: $draggingDayTypeId, id: day.id))
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
        formattedDate(date, pattern: "EEE")
    }

    private func localizedFullWeekday(_ date: Date) -> String {
        formattedDate(date, pattern: "EEEE")
    }

    /// The day's strips, each `draggable` and each preceded by a thin drop zone that lands a
    /// scene before it (the last strip's footer zone lands at the end). The indicator marks
    /// the zone the drag is over.
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
                        onSelect:    { onSelectScene(scene) },
                        onSendToDay: { onSendToDay(scene) },
                        dragPayload: { dragPayload(scene) }
                    )
                }
                // Landing this strip before `scene`. `.before` names the scene, so an
                // insert is by id and never an index that a concurrent move invalidated.
                .dropDestination(for: ScheduleDragPayload.self) { items, _ in
                    onDrop(items, .before(scene.id))
                    return true
                } isTargeted: { targeted in
                    if targeted {
                        dropTargetDayId = day.id
                        dropTargetPosition = sceneIndex
                    } else if dropTargetDayId == day.id && dropTargetPosition == sceneIndex {
                        dropTargetPosition = nil
                    }
                }
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
    /// The iPad's inspector (#17): a single tap on a day cell or its date hands the day
    /// here, and the day whose id this is gets the selected outline. The Mac passes
    /// neither; its cells keep the double-tap sheet only.
    var onSelectDay: ((ShootDay) -> Void)? = nil
    var selectedDayID: UUID? = nil
    /// The narrowest a day column may go. The Mac's 100 is what its window minimum has
    /// always been; the iPad's three columns leave the calendar less than seven of those
    /// in landscape, so its editor passes a smaller floor rather than clipping the grid.
    var minimumCellWidth: CGFloat = 100

    // View Mode Switcher: this window's, seeded from the last (see WindowPreference.swift)
    @WindowPreference("CineSchedCalendarViewMode") private var calendarViewMode: CalendarViewMode = .monthGrid

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

    // Day rearrange drag/drop state: the day whose handle or band is in flight (the
    // source cell fades; hovers turn green) and the cell it hovers.
    @State private var draggingDayId:       UUID? = nil
    @State private var draggingDayTypeId:   UUID? = nil
    @State private var dayDropTargetId:     UUID? = nil

    // Scene drag/drop state: the cell scenes hover (red) and the strip zone the drag is
    // over (its indicator).
    @State private var dropTargetDayId:    UUID?
    @State private var dropTargetPosition: Int?

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
        formattedDate(displayedMonth, pattern: "LLLL yyyy")
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
        // Beside the iPad's sidebar and inspector the row is narrower than its labels;
        // they truncate rather than break mid-word into two-line buttons.
        .lineLimit(1)
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
                    let columns = Array(repeating: GridItem(.flexible(minimum: minimumCellWidth), spacing: 8), count: 7)
                    // Computed once per redraw, not once per cell: with a few hundred days
                    // the per-cell versions were a measurable share of every drop (#34).
                    let numbers     = dayNumbers
                    let indexByDate = dayIndexByDate
                    LazyVGrid(columns: columns, spacing: 8) {
                        if calendarViewMode == .monthGrid {
                            ForEach(0..<monthLeadingOffsetCount, id: \.self) { _ in
                                Color.clear
                                    .frame(minHeight: 120)
                            }
                            ForEach(daysInDisplayedMonth, id: \.self) { date in
                                if let dayIndex = indexByDate[Calendar.current.startOfDay(for: date)] {
                                    dayCell(day: shootDays[dayIndex], dayIndex: dayIndex, dayNumber: numbers[shootDays[dayIndex].id])
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
                                dayCell(day: day, dayIndex: dayIndex, dayNumber: numbers[day.id])
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
                mode:       .send(sceneCount: sendToDaySceneIDs.count),
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
        .dropDestination(for: ScheduleDragPayload.self) { items, _ in
            handleDrop(items, onDate: date)
        }
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
        editDays { days in
            for idx in days.indices
            where Calendar.current.component(.weekday, from: days[idx].date) == targetWeekday {
                days[idx].dayType = type
            }
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

    /// Each day's index in `shootDays` by its calendar day, so the month grid finds the
    /// day for a date with one lookup instead of a scan.
    private var dayIndexByDate: [Date: Int] {
        let cal = Calendar.current
        var result: [Date: Int] = [:]
        for (index, day) in shootDays.enumerated() where result[cal.startOfDay(for: day.date)] == nil {
            result[cal.startOfDay(for: day.date)] = index
        }
        return result
    }

    @ViewBuilder
    private func dayCell(day: ShootDay, dayIndex: Int, dayNumber: Int?) -> some View {
        let cal = Calendar.current
        let inRange = day.date >= cal.startOfDay(for: startDate) && day.date <= cal.startOfDay(for: endDate)

        DayCellView(
            day: day,
            dayIndex: dayIndex,
            dayNumber: dayNumber,
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
            draggingDayTypeId: $draggingDayTypeId,
            onOpenDayDetail: { inspectingDay = day },
            onEditScene: { sceneIndex, scene in editScene(dayIndex: dayIndex, sceneIndex: sceneIndex, scene: scene, dayId: day.id) },
            onRemoveScene: { scene in removeFromDay(scene, dayId: day.id) },
            onDuplicateScene: { scene in duplicateScene(scene) },
            onToggleCompletedScene: { scene in toggleSceneCompleted(scene) },
            onSelectScene: { scene in selectScene(scene, dayId: day.id) },
            onSendToDay: { scene in beginSendToDay(scene) },
            dragPayload: sceneDragPayload,
            onDrop: { items, position in handleDrop(items, onDayID: day.id, position: position) },
            onSetDayType: { targetDay, type in setDayType(targetDay, to: type) },
            onSetDayTypeForWeekday: { targetDay, type in setDayTypeForWeekday(targetDay, to: type) },
            onClearDayType: { targetDay in clearDayType(targetDay) },
            onSelectDay: onSelectDay.map { select in { select(day) } },
            isInspected: selectedDayID == day.id
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
        // own live Binding by the time this fires — this call exists purely to run
        // updateScene's write-back (today a no-op edit through the funnel), so it must use
        // the scene as it now stands, not the `editingScene` snapshot captured back when the
        // sheet was first opened. Passing that stale snapshot was the actual bug: it
        // silently reverted every field — including a changed scene type — right back to
        // whatever it was before the user opened the editor, immediately after
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
        editDays { days in
            for id in idsToToggle {
                guard let dayIdx = days.firstIndex(where: { $0.scenes.contains(where: { $0.id == id }) }),
                      let sceneIdx = days[dayIdx].scenes.firstIndex(where: { $0.id == id }) else { continue }
                days[dayIdx].scenes[sceneIdx].isCompleted = newValue
            }
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

    /// Every action that touches more than one day edits a local copy of `shootDays` here and
    /// writes it back once. Each write to the binding is one trip through the document's edit
    /// funnel (a whole-project copy and, for the first write of a gesture, a compare and an
    /// undo registration), so a loop that wrote per day cost as many trips as there were days
    /// in the range (#34).
    private func editDays(_ change: (inout [ShootDay]) -> Void) {
        var days = shootDays
        change(&days)
        shootDays = days
    }

    private func sendScenes(_ ids: [UUID], toDay targetDayId: UUID) {
        guard let targetDay = shootDays.first(where: { $0.id == targetDayId }) else { return }
        onBeforeSceneChange()
        var scenesToMove: [Scene] = []
        editDays { days in
            for dIdx in days.indices {
                let matches = days[dIdx].scenes.filter { ids.contains($0.id) }
                scenesToMove.append(contentsOf: matches)
                days[dIdx].scenes.removeAll { ids.contains($0.id) }
            }
        }
        for s in scenesToMove {
            assignScene(s, targetDay)
        }
    }

    // MARK: - Drag and drop (#18)

    /// What a strip carries when it is lifted (#18): the whole multi-selection when the
    /// strip is part of it (a multi-select drag moves every selected strip, in board order),
    /// the strip alone otherwise, with the day it left.
    private func sceneDragPayload(for scene: Scene) -> ScheduleDragPayload {
        let ids: [UUID]
        if selectedSceneIDs.count > 1, selectedSceneIDs.contains(scene.id) {
            ids = shootDays.flatMap { $0.scenes.filter { selectedSceneIDs.contains($0.id) }.map(\.id) }
        } else {
            ids = [scene.id]
        }
        let originDayID = shootDays.first { $0.scenes.contains { $0.id == scene.id } }?.id
        return .scenes(ids, from: originDayID)
    }

    /// Payloads dropped on a day cell: scenes and events go to `position` in the day, a
    /// handle swaps the two days, a band moves its type and note. One drop is one gesture.
    private func handleDrop(_ items: [ScheduleDragPayload], onDayID dayID: UUID, position: SceneDropDestination.Position) {
        for item in items {
            switch item.kind {
            case .scenes(let ids, _):
                moveScenes(ids, to: SceneDropDestination(dayID: dayID, position: position))
            case .calendarEvent(let id, _):
                moveScenes([id], to: SceneDropDestination(dayID: dayID, position: position))
            case .day(let sourceDayID):
                handleDayRearrange(sourceDayId: sourceDayID, targetDayId: dayID)
            case .dayType(let sourceDayID):
                moveDayType(from: sourceDayID, toDayId: dayID)
            case .sceneCopies:
                // The pasteboard's kind (#22); nothing drags one. A paste is the editor's.
                break
            }
        }
    }

    /// Payloads dropped on a date that has no `ShootDay` yet (outside the production
    /// range): the day is created first, in the same gesture, so a scene, an event, a
    /// travel day or its band can be dragged anywhere.
    private func handleDrop(_ items: [ScheduleDragPayload], onDate date: Date) {
        for item in items {
            switch item.kind {
            case .scenes, .calendarEvent:
                onBeforeSceneChange()
                var targetDay: ShootDay
                if let existing = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    targetDay = existing
                } else {
                    targetDay = ShootDay(date: date)
                    shootDays.append(targetDay)
                    shootDays.sort { $0.date < $1.date }
                }
                moveScenes(item.sceneIDs, to: SceneDropDestination(dayID: targetDay.id))
            case .day(let sourceDayID):
                handleDayRearrange(sourceDayId: sourceDayID, toDate: date)
            case .dayType(let sourceDayID):
                moveDayType(from: sourceDayID, toDate: date)
            case .sceneCopies:
                break
            }
        }
    }

    /// Moves scenes (from the Boneyard, this day or any other) to `destination` as one
    /// edit each for the Boneyard and the days, in one gesture. The payload already carries
    /// the whole multi-selection in board order (`sceneDragPayload`, the Boneyard's
    /// `boneyardDragPayload`); widening again here from the selection `Set` lost that order.
    private func moveScenes(_ ids: [UUID], to destination: SceneDropDestination) {
        onBeforeSceneChange()
        var days     = shootDays
        var boneyard = allScenes
        guard ScheduleMoves.moveScenes(ids, to: destination, days: &days, boneyard: &boneyard) else {
            onSceneChanged()
            return
        }
        if boneyard != allScenes { allScenes = boneyard }
        if days != shootDays     { shootDays = days }
        onSceneChanged()
    }

    private func handleDayRearrange(sourceDayId: UUID, targetDayId: UUID) {
        guard let srcIdx = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let dstIdx = shootDays.firstIndex(where: { $0.id == targetDayId }),
              srcIdx != dstIdx else { return }
        onBeforeSceneChange()
        editDays { days in
            ScheduleMoves.swapDays(sourceDayId, targetDayId, in: &days)
            days.removeIfEmptyOutsideRange(dayID: sourceDayId, productionRange: productionRange)
        }
        onSceneChanged()
    }

    /// A day handle dropped on a date that has no `ShootDay` yet (outside the production
    /// range). Create the day, then swap into it, so a travel day can be dragged anywhere.
    private func handleDayRearrange(sourceDayId: UUID, toDate date: Date) {
        guard shootDays.contains(where: { $0.id == sourceDayId }) else { return }
        onBeforeSceneChange()
        editDays { days in
            let newDay = ShootDay(date: date)
            days.append(newDay)
            days.sort { $0.date < $1.date }
            ScheduleMoves.swapDays(sourceDayId, newDay.id, in: &days)
            days.removeIfEmptyOutsideRange(dayID: sourceDayId, productionRange: productionRange)
        }
        onSceneChanged()
    }

    /// The day-type band was dragged from one day onto another: swap only type and note,
    /// leaving each day's scenes and call sheet where they are.
    private func moveDayType(from sourceDayId: UUID, toDayId targetDayId: UUID) {
        guard let s = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let d = shootDays.firstIndex(where: { $0.id == targetDayId }), s != d else { return }
        onBeforeSceneChange()
        editDays { days in
            swapDayTypeAndNote(&days, s, d)
            days.removeIfEmptyOutsideRange(dayID: sourceDayId, productionRange: productionRange)
        }
        onSceneChanged()
    }

    /// Band dropped on a date with no `ShootDay` yet (outside the range): create it first.
    private func moveDayType(from sourceDayId: UUID, toDate date: Date) {
        guard shootDays.contains(where: { $0.id == sourceDayId }) else { return }
        onBeforeSceneChange()
        editDays { days in
            let newDay = ShootDay(date: date)
            days.append(newDay)
            days.sort { $0.date < $1.date }
            if let s = days.firstIndex(where: { $0.id == sourceDayId }),
               let d = days.firstIndex(where: { $0.id == newDay.id }) {
                swapDayTypeAndNote(&days, s, d)
            }
            days.removeIfEmptyOutsideRange(dayID: sourceDayId, productionRange: productionRange)
        }
        onSceneChanged()
    }

    private func swapDayTypeAndNote(_ days: inout [ShootDay], _ a: Int, _ b: Int) {
        let type = days[a].dayType
        let note = days[a].dayNote
        days[a].dayType = days[b].dayType
        days[a].dayNote = days[b].dayNote
        days[b].dayType = type
        days[b].dayNote = note
    }

    /// The range pickers' range as whole days, for `removeIfEmptyOutsideRange` and Clear
    /// Day Type (DayEdits.swift): a day outside it only exists to hold something, and goes
    /// once that is gone. Nil while the end precedes the start (a half-edited range drops
    /// nothing, the phone's rule).
    private var productionRange: ClosedRange<Date>? {
        pickerRange(start: startDate, end: endDate)
    }

    /// Resets a day to a plain shoot day and drops its note. A day that only existed to hold
    /// the type (outside the production range with nothing else on it) is removed entirely.
    private func clearDayType(_ day: ShootDay) {
        guard shootDays.contains(where: { $0.id == day.id }) else { return }
        onBeforeSceneChange()
        let range = productionRange
        editDays { days in
            days.clearDayType(forDayID: day.id, productionRange: range)
        }
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
    let onSelect:    () -> Void
    let onSendToDay: () -> Void
    let dragPayload: () -> ScheduleDragPayload

    @Environment(\.scenePalette) private var palette

    private var isFlagged: Bool { hasConflict || isOnNonShootDay }
    private var displayColor: Color {
        if scene.isCalendarEvent {
            return Color(hex: scene.bannerColorHex.isEmpty ? "6366F1" : scene.bannerColorHex)
        }
        return isFlagged ? .red : scene.stripColor(in: palette)
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
        // The taps above are simultaneous gestures so neither the single nor the double tap
        // claims the long press that starts the drag (the gesture-priority fix in the
        // README); `draggable` owns that press.
        .draggable(dragPayload())
        .fastTooltip(scene.tooltipText)
    }
}

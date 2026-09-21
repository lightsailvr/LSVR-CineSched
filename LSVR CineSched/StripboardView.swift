// StripboardView.swift
// A Movie Magic Scheduling-style stripboard: a vertically-scrolling list of
// full-width day sections, each a thin rule, a plain date header, another
// rule, then that day's scenes as dense color-coded strips — closer to a
// printed one-line/strip schedule than a UI card grid. An alternate to
// CompactMonthCalendarView's square calendar grid — same underlying
// shootDays/allScenes data, same drag-and-drop payload (`ScheduleDragPayload`,
// #18), so the existing Boneyard sidebar (and its own drag-in/drag-out
// handling) works with this view for free. Each strip is `draggable` with the
// scenes it moves, a thin drop zone before each strip gives the exact insertion
// point, each day section is the drop destination for every kind, and the day
// handle and the event chips are their own draggables; the drop plumbing
// (`DropTargetTracking`, `DragSessionTracking`, `DropIndicatorView`) is shared
// with the calendar, which the same header note explains is not on the reorder
// container (it crashed at lift beside the heterogeneous drag container).

import SwiftUI

struct StripboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue
    @Binding var shootDays: [ShootDay]
    @Binding var allScenes: [Scene]
    let productionInfo: ProductionInfo
    /// Which scene fields each strip prints beside the heading (see StripboardFieldSettings).
    let visibleFields: Set<StripboardField>
    /// When true every date in the range is drawn; when false runs of empty days fold into
    /// a single gap row (see StripboardRows.swift). Toggled from the toolbar and View menu.
    let showAllDays: Bool
    @Binding var selectedSceneIDs: Set<UUID>
    @Binding var lastSelectedSceneID: UUID?
    let conflictDates: Set<Date>
    let conflictSceneIDs: Set<UUID>
    let duplicateSceneNumberIDs: Set<UUID>
    @Binding var scrollToDate: Date?
    let dragStateResetToken: Int
    /// Opens the edit gesture the following binding writes fold into, so an action that
    /// writes more than once (a drop that touches `shootDays` and `allScenes`, a call sheet
    /// Save followed by the auto-meal sync) is one undo step by construction rather than
    /// by the window's run-loop grouping (#9). Same contract as the calendar's.
    let onBeforeSceneChange: () -> Void
    let onSceneChanged: () -> Void
    let onCallSheetExport: (ShootDay) -> Void
    let onShootingScheduleExport: ([ShootDay]) -> Void
    /// The iPad's inspector (#17): a single tap on a day header hands the day here, and
    /// the day whose id this is gets the selected outline. The Mac passes neither.
    var onSelectDay: ((ShootDay) -> Void)? = nil
    var selectedDayID: UUID? = nil

    // Editing state — mirrors CompactMonthCalendarView's
    @State private var editingDayId:      UUID?
    @State private var editingDayIndex:   Int?
    @State private var editingSceneIndex: Int?
    @State private var showingEditSheet = false
    @State private var callSheetDay: ShootDay? = nil
    @State private var addingBannerForDayId: UUID? = nil
    @State private var editingEventScene: Scene? = nil
    @State private var editingEventDayId: UUID? = nil

    // Scene drag/drop state — own copy, independent of the calendar's: the day scenes
    // hover (red), the strip zone the drag is over (its indicator), and the strip being
    // lifted (it scales while it goes).
    @State private var dropTargetDayId:    UUID?
    @State private var dropTargetPosition: Int?
    @State private var interactingSceneId: UUID?

    // Day rearrange drag/drop state
    @State private var draggingDayId:   UUID? = nil
    @State private var dayDropTargetId: UUID? = nil

    // Quick Time Edit state
    @State private var quickEditingScene: Scene? = nil
    @State private var quickEditingDayId: UUID? = nil

    /// Ids of empty days whose gap the user has opened. Keyed by day, not by gap, so a
    /// gap that splits when a scene lands in its middle keeps both halves open.
    @State private var expandedGapDayIDs: Set<UUID> = []

    private var rows: [StripboardRow] {
        stripboardRows(for: shootDays, showAllDays: showAllDays, expandedDayIDs: expandedGapDayIDs)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        switch row {
                        case .day(let dayIndex, let day):
                            daySection(day: day, dayIndex: dayIndex)
                                .id(day.id)
                                .onAppear {
                                    syncAutoBannersAndMeals(for: dayIndex)
                                }
                        case .gap(let gap):
                            gapRow(gap)
                                .id(gap.id)
                        }
                    }
                }
                .padding(10)
            }
            .onChange(of: scrollToDate) { _, newValue in
                guard let date = newValue else { return }
                scrollToDate = nil
                guard let target = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { return }
                if !showAllDays, stripboardDayIsEmpty(target), !expandedGapDayIDs.contains(target.id) {
                    // The date is folded into a collapsed gap, so there is no row to scroll
                    // to yet. Open the gap first and scroll once the day rows exist.
                    expandedGapDayIDs.insert(target.id)
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                    }
                } else {
                    withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tooltipContainer()
        // A lifted strip sets `interactingSceneId` (it scales while it goes); clear it when
        // the drag ends however it ends, since the strip usually stays on screen (a reorder,
        // a same-day drop) and would otherwise keep the lifted look.
        .onDragSessionUpdated { session in
            switch session.phase {
            case .ended, .dataTransferCompleted: interactingSceneId = nil
            default: break
            }
        }
        .onChange(of: dragStateResetToken) { _ in
            // Same fix as CompactMonthCalendarView: undo/redo restores allScenes/shootDays
            // but can't reach into this view's own local drag-target state, so a day
            // cell's drop-target border could otherwise stay stuck highlighted after undo.
            dropTargetDayId = nil
            dropTargetPosition = nil
            dayDropTargetId = nil
            draggingDayId = nil
            interactingSceneId = nil
        }
        .sheet(isPresented: $showingEditSheet) { editSheetContent() }
        .sheet(item: $callSheetDay) { day in callSheetEditorContent(for: day) }
        .sheet(item: $editingEventScene) { ev in
            CalendarEventInputSheet(
                isPresented: Binding(
                    get: { editingEventScene != nil },
                    set: { if !$0 { editingEventScene = nil; editingEventDayId = nil } }
                ),
                initialEvent: ev,
                onSave: { updated in
                    if let dId = editingEventDayId,
                       let dayIdx = shootDays.firstIndex(where: { $0.id == dId }),
                       let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == ev.id }) {
                        shootDays[dayIdx].scenes[sceneIdx] = updated
                        onSceneChanged()
                    }
                    editingEventScene = nil
                    editingEventDayId = nil
                }
            )
        }
        .sheet(item: $quickEditingScene) { scn in
            QuickTimeEditSheet(
                scene: scn,
                onSave: { updated in
                    if let dId = quickEditingDayId,
                       let dayIdx = shootDays.firstIndex(where: { $0.id == dId }),
                       let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == updated.id }) {
                        onBeforeSceneChange()
                        shootDays[dayIdx].scenes[sceneIdx] = updated
                        if (updated.isAutoMeal && updated.mealKind == .lunch) || updated.title.lowercased().contains("almuerzo") || updated.title.lowercased().contains("lunch") {
                            if !updated.customStartTime.isEmpty {
                                shootDays[dayIdx].callSheet.lunchTime = updated.customStartTime
                            }
                        }
                        onSceneChanged()
                    }
                    quickEditingScene = nil
                    quickEditingDayId = nil
                },
                onCancel: {
                    quickEditingScene = nil
                    quickEditingDayId = nil
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { addingBannerForDayId != nil },
            set: { if !$0 { addingBannerForDayId = nil } }
        )) {
            BannerInputSheet(isPresented: Binding(
                get: { addingBannerForDayId != nil },
                set: { if !$0 { addingBannerForDayId = nil } }
            ), onSave: { newBanner in
                if let targetId = addingBannerForDayId,
                   let idx = shootDays.firstIndex(where: { $0.id == targetId }) {
                    shootDays[idx].scenes.append(newBanner)
                    onSceneChanged()
                }
            })
        }
        .onChange(of: showingEditSheet) { isShowing in
            if !isShowing { clearEditingState() }
        }
    }

    /// Brings the day's auto-meal strips in line with its call sheet (`AutoMealSync`), one
    /// write through the binding when anything changed.
    private func syncAutoBannersAndMeals(for dayIndex: Int) {
        guard dayIndex < shootDays.count else { return }
        let updatedScenes = shootDays[dayIndex].scenesWithSyncedAutoMeals()
        if updatedScenes != shootDays[dayIndex].scenes {
            shootDays[dayIndex].scenes = updatedScenes
        }
    }

    // MARK: - Day section

    private var dayNumbers: [UUID: Int] { productionDayNumbers(for: shootDays) }

    // MARK: - Calendar event chips

    /// The day's calendar events as chips above the strips, mirroring the calendar cell.
    /// Deliberately not part of the strip list or `dayTimeline` (DayTimeline.swift): an event is an
    /// appointment on the day, not work in the day's cascade, and its `customStartTime`
    /// would otherwise reset the call-time math for every strip after it.
    @ViewBuilder
    private func dayEventChips(day: ShootDay) -> some View {
        let events = day.scenes.filter { $0.isCalendarEvent }
        if !events.isEmpty {
            HStack(spacing: 6) {
                ForEach(events) { event in
                    let color = Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex)
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 9, weight: .bold))
                        if !event.customStartTime.isEmpty {
                            Text(event.customStartTime)
                                .font(.system(size: 10, weight: .bold))
                            Text("·").opacity(0.6)
                        }
                        Text(event.bannerTitle.isEmpty ? event.title : event.bannerTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.4), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editingEventScene = event
                        editingEventDayId = day.id
                    }
                    .contextMenu {
                        Button(L("Edit Event")) {
                            editingEventScene = event
                            editingEventDayId = day.id
                        }
                        Divider()
                        Button(L("Delete Event"), role: .destructive) {
                            deleteCalendarEvent(event, dayId: day.id)
                        }
                    }
                    .draggable(ScheduleDragPayload(.calendarEvent(id: event.id, dayID: day.id)))
                    .help(event.tooltipText)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// Events never go to the Boneyard; deleting one just drops it.
    private func deleteCalendarEvent(_ event: Scene, dayId: UUID) {
        guard let di = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        shootDays[di].scenes.removeAll { $0.id == event.id }
        onSceneChanged()
    }

    /// The day's strips, each `draggable` and each preceded by a thin drop zone that lands a
    /// scene before it (the footer zone lands at the end); the indicator marks the zone the
    /// drag is over. An empty day keeps a little height so it stays a target.
    @ViewBuilder
    private func daySceneList(day: ShootDay, dayIndex: Int) -> some View {
        let visibleScenes = day.scenes.filter { !$0.isCalendarEvent }
        let timeline = dayTimeline(for: day, scenes: visibleScenes)

        VStack(spacing: 1) {
            ForEach(Array(visibleScenes.enumerated()), id: \.element.id) { sceneIndex, scene in
                VStack(spacing: 0) {
                    if dropTargetDayId == day.id && dropTargetPosition == sceneIndex {
                        DropIndicatorView()
                    }
                    if scene.isBanner {
                        BannerStripRow(
                            scene: scene,
                            timeDisplay: timeline[scene.id]?.timeDisplay ?? (scene.customStartTime.isEmpty ? "" : scene.customStartTime),
                            interactingSceneId: $interactingSceneId,
                            isSelected: selectedSceneIDs.contains(scene.id),
                            onQuickTimeEdit: {
                                quickEditingScene = scene
                                quickEditingDayId = day.id
                            },
                            onRemove: { removeFromDay(scene, dayId: day.id) },
                            dragPayload: { sceneDragPayload(for: scene) }
                        )
                    } else {
                        SceneStripRow(
                            scene: scene,
                            timeDisplay: timeline[scene.id]?.timeDisplay ?? (scene.customStartTime.isEmpty ? "" : scene.customStartTime),
                            visibleFields: visibleFields,
                            interactingSceneId: $interactingSceneId,
                            isSelected: selectedSceneIDs.contains(scene.id),
                            selectionCount: selectedSceneIDs.count,
                            hasConflict: conflictSceneIDs.contains(scene.id),
                            hasDuplicateSceneNumber: duplicateSceneNumberIDs.contains(scene.id),
                            onQuickTimeEdit: {
                                quickEditingScene = scene
                                quickEditingDayId = day.id
                            },
                            onEdit:      { editScene(dayIndex: dayIndex, sceneIndex: sceneIndex, dayId: day.id) },
                            onRemove:    { removeFromDay(scene, dayId: day.id) },
                            onDuplicate: { duplicateScene(scene) },
                            onToggleCompleted: { toggleSceneCompleted(scene, dayId: day.id) },
                            onSelect:    { selectScene(scene, dayId: day.id) },
                            dragPayload: { sceneDragPayload(for: scene) }
                        )
                    }
                }
                .dropDestination(for: ScheduleDragPayload.self) { items, _ in
                    handleDrop(items, onDayID: day.id, position: .before(scene.id))
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
            if visibleScenes.isEmpty {
                Color.clear.frame(height: 12)
            }
        }
        .padding(.horizontal, 4)
        .background(Color.gray.opacity(colorScheme == .dark ? 0.22 : 0.12))
    }

    @ViewBuilder
    private func daySection(day: ShootDay, dayIndex: Int) -> some View {
        let isSelectedTarget = dayDropTargetId == day.id || dropTargetDayId == day.id
        let isInspected = selectedDayID == day.id
        VStack(alignment: .leading, spacing: 0) {
            dayHeader(day: day)
                .background(Color.gray.opacity(colorScheme == .dark ? 0.22 : 0.12))
                .modifier(SelectOnTap(action: onSelectDay.map { select in { select(day) } }))

            Divider().opacity(0.4)

            dayEventChips(day: day)

            daySceneList(day: day, dayIndex: dayIndex)

            EndOfDayStrip(day: day, dayNumber: dayNumbers[day.id] ?? (dayIndex + 1))
        }
        .background(
            ZStack {
                currentTheme.panelBackground(isDarkMode: colorScheme == .dark)
                if isWeekend(day.date) {
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                }
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    dayDropTargetId == day.id ? Color.green :
                    dropTargetDayId == day.id ? Color.red :
                    isInspected ? Color.accentColor : Color.primary.opacity(0.2),
                    lineWidth: isSelectedTarget ? 2.5 : isInspected ? 2 : 1
                )
        )
        // The whole section: a day handle, an event chip, or scenes dropped on the header,
        // the chip row or the end-of-day strip, which land at the end of the day.
        .dropDestination(for: ScheduleDragPayload.self) { items, _ in
            handleDrop(items, onDayID: day.id, position: .end)
        }
        .modifier(DropTargetTracking(
            dayID: day.id,
            isDayDrag: draggingDayId != nil,
            dropTargetDayId: $dropTargetDayId,
            dayDropTargetId: $dayDropTargetId
        ))
    }

    // MARK: - Gap row

    /// One slim strip standing in for a run of empty days. Clicking it swaps the strip for
    /// the individual day sections so they can take scene and day drops like any other day.
    @ViewBuilder
    private func gapRow(_ gap: StripboardGap) -> some View {
        let range = gap.dayCount == 1
            ? formattedDate(gap.firstDate)
            : "\(formattedDate(gap.firstDate)) – \(formattedDate(gap.lastDate))"
        let count = gap.dayCount == 1 ? L("1 empty day") : "\(gap.dayCount) \(L("empty days"))"
        let details = gapDetails(gap)

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedGapDayIDs.formUnion(gap.dayIDs)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(count)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("·").foregroundColor(.secondary)
                Text(range)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !details.isEmpty {
                    Text("(\(details.joined(separator: " · ")))")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
                Text(L("Show"))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(Color.primary.opacity(0.18))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Show these empty days so scenes can be dropped on them"))
    }

    /// Secondary counts for a gap row, e.g. ["4 weekend", "2 unavailable"]. Kept out of the
    /// `@ViewBuilder` body because result builders reject local `var` mutation.
    private func gapDetails(_ gap: StripboardGap) -> [String] {
        var details: [String] = []
        if gap.weekendCount > 0 { details.append("\(gap.weekendCount) \(L("weekend"))") }
        return details
    }

    /// Removes every day of the contiguous empty run around `dayId` from the expanded set,
    /// so the run folds back into a single gap row on the next render.
    private func collapseGap(containing dayId: UUID) {
        guard let idx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        var lo = idx
        while lo > 0, stripboardDayIsEmpty(shootDays[lo - 1]) { lo -= 1 }
        var hi = idx
        while hi < shootDays.count - 1, stripboardDayIsEmpty(shootDays[hi + 1]) { hi += 1 }
        for d in shootDays[lo...hi] { expandedGapDayIDs.remove(d.id) }
    }

    // MARK: - Day header

    @ViewBuilder
    private func dayHeader(day: ShootDay) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .draggable(ScheduleDragPayload(.day(id: day.id)))
                .modifier(DragSessionTracking(draggingID: $draggingDayId, id: day.id))
                .help("Drag to swap this day's scenes, call sheet, day type, and note with another date")

            HStack(spacing: 6) {
                Text(formattedDate(day.date))
                    .font(.headline)
                if day.hasCallSheetData {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                }
                if conflictDates.contains(Calendar.current.startOfDay(for: day.date)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundColor(.red)
                }
                if let dayNumber = dayNumbers[day.id] {
                    Text("\(L("Day")) \(dayNumber)")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                }
                if !day.dayType.isShootable {
                    Label(day.dayType.localizedName, systemImage: day.dayType.icon)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color(hex: day.dayType.colorHex))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: day.dayType.colorHex).opacity(0.18))
                        .cornerRadius(4)
                }
                if !day.dayNote.isEmpty {
                    Text(day.dayNote)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    if !day.callSheet.lunchTime.isEmpty {
                        Text("🍽️ \(day.callSheet.lunchTime)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !day.callSheet.snackTime.isEmpty {
                        Text("☕ \(day.callSheet.snackTime)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !day.callSheet.dinnerTime.isEmpty {
                        Text("🍕 \(day.callSheet.dinnerTime)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !day.callSheet.wrapTime.isEmpty {
                        Text("🎬 \(day.callSheet.wrapTime)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                let stripCount = day.scenes.filter { !$0.isCalendarEvent }.count
                if stripCount > 0 {
                    Text("\(stripCount) \(L("scn")) · \(formattedEighths(day.totalDuration)) \(L("pgs"))")
                        .font(.caption).foregroundColor(.secondary)
                }
                if !showAllDays, expandedGapDayIDs.contains(day.id) {
                    // This day is only visible because its gap was opened; offer the way back.
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { collapseGap(containing: day.id) }
                    } label: {
                        Label(L("Hide empty days"), systemImage: "chevron.up")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Fold this run of empty days back into one row"))
                }

                // Action Icons on Day Header: CallSheet, Add Banner, Export PDF
                HStack(spacing: 8) {
                    Button {
                        callSheetDay = day
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Edit Call Sheet"))

                    Button {
                        addingBannerForDayId = day.id
                    } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Add Notice / Banner Strip"))

                    Button {
                        onShootingScheduleExport([day])
                    } label: {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Export Plan de Rodaje (PDF)"))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Call sheet editor (mirrors CompactMonthCalendarView)

    @ViewBuilder
    private func callSheetEditorContent(for day: ShootDay) -> some View {
        if let idx = shootDays.firstIndex(where: { $0.id == day.id }) {
            CallSheetEditor(
                // The editor writes the day, then `onSave` syncs the auto-meal strips from
                // the new times: two writes, one gesture, opened by the first.
                shootDay: Binding(
                    get: { shootDays[idx] },
                    set: { new in onBeforeSceneChange(); shootDays[idx] = new }
                ),
                productionInfo: productionInfo,
                isPresented: Binding(
                    get: { callSheetDay != nil },
                    set: { if !$0 { callSheetDay = nil } }
                ),
                onSave: {
                    callSheetDay = nil
                    syncAutoBannersAndMeals(for: idx)
                    onSceneChanged()
                },
                onExportPDF: { exportDay in
                    onCallSheetExport(exportDay)
                },
                dayNumber: dayNumbers[day.id],
                totalProductionDays: dayNumbers.values.max() ?? 0
            )
        }
    }

    // MARK: - Edit sheet (mirrors CompactMonthCalendarView)

    @ViewBuilder
    private func editSheetContent() -> some View {
        if let dayIndex   = editingDayIndex,
           let sceneIndex = editingSceneIndex,
           dayIndex   < shootDays.count,
           sceneIndex < shootDays[dayIndex].scenes.count {

            SceneEditSheet(
                scene: $shootDays[dayIndex].scenes[sceneIndex],
                isPresented: $showingEditSheet,
                onSave: {
                    onSceneChanged()
                },
                onDelete: {
                    if let id = editingDayId {
                        removeFromDay(shootDays[dayIndex].scenes[sceneIndex], dayId: id)
                    }
                    clearEditingState()
                },
                canGoPrevious: sceneIndex > 0,
                canGoNext: sceneIndex < shootDays[dayIndex].scenes.count - 1,
                onPrevious: { editingSceneIndex = sceneIndex - 1 },
                onNext: { editingSceneIndex = sceneIndex + 1 },
                positionLabel: "Scene \(sceneIndex + 1) of \(shootDays[dayIndex].scenes.count)",
                knownLocations: allProjectLocations
            )
        } else {
            VStack(spacing: 20) {
                Text("Error: Scene not found")
                    .font(.title2).foregroundColor(.red)
                Text("The scene may have been moved or deleted.")
                    .font(.body).multilineTextAlignment(.center)
                Button("Close") {
                    showingEditSheet = false
                    clearEditingState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24).frame(width: 400)
        }
    }

    private func editScene(dayIndex: Int, sceneIndex: Int, dayId: UUID) {
        editingDayIndex   = dayIndex
        editingSceneIndex = sceneIndex
        editingDayId      = dayId
        showingEditSheet  = true
    }

    private func clearEditingState() {
        editingDayId      = nil
        editingDayIndex   = nil
        editingSceneIndex = nil
    }

    private var allProjectLocations: [String] {
        var set = Set<String>()
        for d in shootDays {
            for s in d.scenes where !s.realLocation.isEmpty {
                set.insert(s.realLocation)
            }
        }
        for s in allScenes where !s.realLocation.isEmpty {
            set.insert(s.realLocation)
        }
        for loc in productionInfo.locationRoster where !loc.name.isEmpty {
            set.insert(loc.name)
        }
        return Array(set).sorted()
    }

    // MARK: - Scene drag & drop handling (mirrors CompactMonthCalendarView)

    /// An action that touches several scenes or days edits local copies of `shootDays` and
    /// `allScenes` here and writes each back once (only if it changed). Every write to a
    /// binding is one trip through the document's edit funnel, so a multi-scene drop that
    /// wrote per scene cost two trips per scene (#34). Same shape as the calendar's `editDays`.
    private func editSchedule(_ change: (inout [ShootDay], inout [Scene]) -> Void) {
        onBeforeSceneChange()
        var days   = shootDays
        var scenes = allScenes
        change(&days, &scenes)
        if days != shootDays   { shootDays = days }
        if scenes != allScenes { allScenes = scenes }
    }

    /// What a strip carries when it is lifted (#18): the whole multi-selection when the
    /// strip is part of it (in board order), the strip alone otherwise, with the day it
    /// left. Same shape as the calendar's.
    private func sceneDragPayload(for scene: Scene) -> ScheduleDragPayload {
        interactingSceneId = scene.id
        let ids: [UUID]
        if selectedSceneIDs.count > 1, selectedSceneIDs.contains(scene.id) {
            ids = shootDays.flatMap { $0.scenes.filter { selectedSceneIDs.contains($0.id) }.map(\.id) }
        } else {
            ids = [scene.id]
        }
        let originDayID = shootDays.first { $0.scenes.contains { $0.id == scene.id } }?.id
        return .scenes(ids, from: originDayID)
    }

    /// Payloads dropped on a day section: scenes and events go to `position` in the day
    /// (an event to its end, where its chip row draws from), a handle swaps the two days,
    /// a band from the calendar moves its type and note. One drop is one gesture.
    private func handleDrop(_ items: [ScheduleDragPayload], onDayID dayID: UUID, position: SceneDropDestination.Position) {
        for item in items {
            switch item.kind {
            case .scenes(let ids, _):
                moveScenes(ids, to: SceneDropDestination(dayID: dayID, position: position))
            case .calendarEvent(let id, _):
                moveScenes([id], to: SceneDropDestination(dayID: dayID, position: .end))
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

    /// Moves scenes (from the Boneyard, this day or any other) to `destination`, one
    /// gesture. The payload already carries the whole multi-selection in board order
    /// (as on the calendar); widening again here from the selection `Set` lost that order.
    private func moveScenes(_ ids: [UUID], to destination: SceneDropDestination) {
        editSchedule { days, boneyard in
            ScheduleMoves.moveScenes(ids, to: destination, days: &days, boneyard: &boneyard)
        }
        onSceneChanged()
    }

    /// Removes the clicked scene from its day back into the Boneyard — or, if it's
    /// part of a multi-scene selection, every selected scene currently scheduled
    /// anywhere on the board, mirroring the calendar's grouped removal.
    private func removeFromDay(_ scene: Scene, dayId: UUID) {
        editSchedule { days, boneyard in
            if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
                for dayIdx in days.indices {
                    let matching = days[dayIdx].scenes.filter { selectedSceneIDs.contains($0.id) }
                    for s in matching {
                        removeScene(s, from: &days, boneyard: &boneyard, dayId: days[dayIdx].id)
                    }
                }
            } else {
                removeScene(scene, from: &days, boneyard: &boneyard, dayId: dayId)
            }
        }
        onSceneChanged()
    }

    private func removeScene(_ scene: Scene, from days: inout [ShootDay], boneyard: inout [Scene], dayId: UUID) {
        if let di = days.firstIndex(where: { $0.id == dayId }) {
            days[di].scenes.removeAll { $0.id == scene.id }
            // Calendar events are never Boneyard material; a grouped removal that sweeps
            // one up (multi-select spanning a chip) just deletes it.
            if !scene.isCalendarEvent { boneyard.append(scene) }
        }
    }

    private func toggleSceneCompleted(_ scene: Scene, dayId: UUID) {
        let newValue = !scene.isCompleted
        let idsToToggle: Set<UUID> = (selectedSceneIDs.contains(scene.id) && selectedSceneIDs.count > 1)
            ? selectedSceneIDs
            : [scene.id]
        editSchedule { days, _ in
            for id in idsToToggle {
                guard let di = days.firstIndex(where: { $0.scenes.contains(where: { $0.id == id }) }),
                      let si = days[di].scenes.firstIndex(where: { $0.id == id }) else { continue }
                days[di].scenes[si].isCompleted = newValue
            }
        }
        onSceneChanged()
    }

    /// The copy is `Scene.duplicated()` (DayEdits.swift, pinned by `DayEditsTests`), the
    /// same fields this built inline before the phone needed it too (#26).
    private func duplicateScene(_ scene: Scene) {
        allScenes.append(scene.duplicated())
        onSceneChanged()
    }

    // MARK: - Day rearrange (mirrors CompactMonthCalendarView.handleDayRearrange)

    /// Swaps scenes and call sheet between two days, preserving both dates —
    /// the calendar dates themselves never change, only the content moves.
    private func handleDayRearrange(sourceDayId: UUID, targetDayId: UUID) {
        guard sourceDayId != targetDayId,
              let sourceIdx = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let targetIdx = shootDays.firstIndex(where: { $0.id == targetDayId })
        else { return }

        // Swap everything that makes the day *that* day (mirrors CompactMonthCalendarView).
        editSchedule { days, _ in
            let sourceScenes    = days[sourceIdx].scenes
            let sourceCallSheet = days[sourceIdx].callSheet
            let sourceType      = days[sourceIdx].dayType
            let sourceNote      = days[sourceIdx].dayNote
            let targetScenes    = days[targetIdx].scenes
            let targetCallSheet = days[targetIdx].callSheet
            let targetType      = days[targetIdx].dayType
            let targetNote      = days[targetIdx].dayNote

            days[sourceIdx].scenes    = targetScenes
            days[sourceIdx].callSheet = targetCallSheet
            days[sourceIdx].dayType   = targetType
            days[sourceIdx].dayNote   = targetNote
            days[targetIdx].scenes    = sourceScenes
            days[targetIdx].callSheet = sourceCallSheet
            days[targetIdx].dayType   = sourceType
            days[targetIdx].dayNote   = sourceNote
        }

        draggingDayId   = nil
        dayDropTargetId = nil
        onSceneChanged()
    }

    /// A day-type band dragged from the calendar and dropped on a Stripboard day: swap only
    /// type and note, as the calendar does (`CompactMonthCalendarView.moveDayType`).
    private func moveDayType(from sourceDayId: UUID, toDayId targetDayId: UUID) {
        guard sourceDayId != targetDayId,
              let s = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let d = shootDays.firstIndex(where: { $0.id == targetDayId }) else { return }
        editSchedule { days, _ in
            let type = days[s].dayType
            let note = days[s].dayNote
            days[s].dayType = days[d].dayType
            days[s].dayNote = days[d].dayNote
            days[d].dayType = type
            days[d].dayNote = note
        }
        onSceneChanged()
    }

    // MARK: - Selection

    private func selectScene(_ scene: Scene, dayId: UUID) {
        let flags = ModifierKeys.current
        if flags.contains(.command) {
            if selectedSceneIDs.contains(scene.id) { selectedSceneIDs.remove(scene.id) } else { selectedSceneIDs.insert(scene.id) }
            lastSelectedSceneID = scene.id
        } else if flags.contains(.shift),
                  let anchor = lastSelectedSceneID,
                  let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }),
                  let anchorIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == scene.id }) {
            let range = anchorIdx < targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
            selectedSceneIDs.formUnion(range.map { shootDays[dayIdx].scenes[$0].id })
        } else {
            selectedSceneIDs = [scene.id]
            lastSelectedSceneID = scene.id
        }
    }
}

// MARK: - EndOfDayStrip

/// Movie Magic's black "end of day" marker — closes out every production
/// day's card with its number, full date, and running page/time totals, all
/// read live off the ShootDay so it updates the moment scenes move, get
/// edited, or the day itself gets rearranged.
struct EndOfDayStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = LocalizationManager.shared
    let day: ShootDay
    let dayNumber: Int

    private var backgroundColor: Color {
        Color.gray.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }

    private var textColor: Color {
        Color.primary.opacity(0.8)
    }

    private var wrapPart: String {
        let wrap = day.callSheet.wrapTime.trimmingCharacters(in: .whitespaces)
        return wrap.isEmpty ? "" : " -- \(L("Wrap:")) \(wrap)"
    }

    var body: some View {
        Text("-- \(L("END OF DAY #"))\(dayNumber) \(formattedFullDate(day.date)) -- \(L("Total Pages:")) \(formattedEighths(day.totalDuration)) -- \(L("Est. Time:")) \(formattedTimeHM(day.totalEstimatedTime))\(wrapPart) --")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .background(backgroundColor)
    }
}

// MARK: - SceneStripRow

struct SceneStripRow: View {
    let scene: Scene
    let timeDisplay: String
    let visibleFields: Set<StripboardField>
    @Binding var interactingSceneId: UUID?
    let isSelected:     Bool
    let selectionCount: Int
    let hasConflict:    Bool
    let hasDuplicateSceneNumber: Bool
    let onQuickTimeEdit: () -> Void
    let onEdit:      () -> Void
    let onRemove:    () -> Void
    let onDuplicate: () -> Void
    let onToggleCompleted: () -> Void
    let onSelect:    () -> Void
    let dragPayload: () -> ScheduleDragPayload

    @Environment(\.scenePalette) private var palette

    private var isDragging: Bool { interactingSceneId == scene.id }
    private var isMultiSelected: Bool { isSelected && selectionCount > 1 }

    private struct FieldChip: Identifiable {
        let field: StripboardField
        let value: String
        var id: StripboardField { field }
    }

    /// The enabled fields this scene actually has a value for, in StripboardField order.
    /// Blank fields are dropped here so an empty Real Location never leaves a dangling icon.
    private var fieldChips: [FieldChip] {
        StripboardField.allCases.compactMap { field in
            guard visibleFields.contains(field) else { return nil }
            let value = field.displayValue(for: scene)
            return value.isEmpty ? nil : FieldChip(field: field, value: value)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if !timeDisplay.isEmpty {
                Button {
                    onQuickTimeEdit()
                } label: {
                    Text(timeDisplay)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(scene.stripTextColor.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 142, height: 20, alignment: .center)
                        .background(Color.black.opacity(0.18))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Clic para ajustar horario o duración / Click to edit time")
            }

            HStack(spacing: 8) {
                if !scene.sceneNumber.isEmpty {
                    Text(scene.sceneNumber)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(scene.stripTextColor.opacity(0.6))
                        .lineLimit(1)
                        .frame(minWidth: 22, alignment: .leading)
                }

                Text(scene.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(scene.stripTextColor)
                    .lineLimit(1)

                if hasConflict || hasDuplicateSceneNumber {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundColor(.red)
                }

                // One small chip per enabled field, in the muted style the Cast list has
                // always used. Every chip is single-line; when the window is narrow the
                // chips truncate before the heading does, so the slugline stays readable.
                ForEach(fieldChips) { chip in
                    HStack(spacing: 3) {
                        Image(systemName: chip.field.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(chip.value)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(scene.stripTextColor.opacity(0.6))
                    .help(chip.field.label)
                }

                Spacer(minLength: 4)

                if scene.estimatedTime > 0 {
                    Text("(\(formattedTimeHM(scene.estimatedTime)))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(scene.stripTextColor.opacity(0.75))
                }

                Text(FractionParser.formatEighths(scene.duration))
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(scene.stripTextColor.opacity(0.8))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                interactingSceneId = nil
                onEdit()
            })
            .simultaneousGesture(TapGesture(count: 1).onEnded {
                interactingSceneId = nil
                onSelect()
            })
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.stripColor(in: palette))
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.accentColor : scene.stripTextColor.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
        )
        .overlay(
            Rectangle()
                .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .opacity(hasDuplicateSceneNumber ? 1 : 0)
        )
        .scaleEffect(isDragging ? 1.01 : 1.0)
        .opacity(isDragging ? 0.85 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .fastTooltip(scene.tooltipText)
        // `draggable` owns the long press; the taps above are simultaneous gestures, as on
        // the Mac, so neither the single nor the double tap claims it.
        .draggable(dragPayload())
        .contextMenu {
            Button("Set Time...") { interactingSceneId = nil; onQuickTimeEdit() }
            Divider()
            Button(L("Edit Scene")) { interactingSceneId = nil; onEdit() }
            Button(isMultiSelected ? "\(L("Remove")) \(selectionCount) \(L("scenes"))" : L("Remove from Day")) {
                interactingSceneId = nil; onRemove()
            }
            Divider()
            Button(isMultiSelected
                   ? "Mark \(selectionCount) Scenes as \(scene.isCompleted ? "Incomplete" : "Completed")"
                   : (scene.isCompleted ? "Mark as Incomplete" : "Mark as Completed")) {
                interactingSceneId = nil; onToggleCompleted()
            }
            Divider()
            Button(L("Duplicate Scene")) { interactingSceneId = nil; onDuplicate() }
        }
    }
}

// MARK: - BannerStripRow

struct BannerStripRow: View {
    let scene: Scene
    let timeDisplay: String
    @Binding var interactingSceneId: UUID?
    let isSelected: Bool
    let onQuickTimeEdit: () -> Void
    let onRemove: () -> Void
    let dragPayload: () -> ScheduleDragPayload

    private var isDragging: Bool { interactingSceneId == scene.id }
    /// The fill and the label are `BannerAppearance.swift`'s (the rules this row had
    /// inline, moved out so the iPhone's strip draws the same; pinned by
    /// `BannerAppearanceTests`).
    private var bannerColor: Color { Color(hex: scene.bannerFillHex) }
    private var bannerDisplayTitle: String { scene.bannerDisplayLabel }

    var body: some View {
        HStack(spacing: 8) {
            if !timeDisplay.isEmpty {
                Button {
                    onQuickTimeEdit()
                } label: {
                    Text(timeDisplay)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 142, height: 20, alignment: .center)
                        .background(Color.black.opacity(0.32))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Clic para ajustar horario o duración / Click to edit time")
            }

            if !scene.isAutoMeal {
                Image(systemName: scene.bannerType?.defaultIcon ?? "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(bannerDisplayTitle)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 4)

            if scene.estimatedTime > 0 {
                Text(formattedTime(scene.estimatedTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Eliminar Tira / Delete Banner")
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
        )
        .draggable(dragPayload())
        .contextMenu {
            Button(L("Set Time...")) { interactingSceneId = nil; onQuickTimeEdit() }
            Divider()
            Button(L("Delete Banner"), role: .destructive) {
                onRemove()
            }
        }
    }
}

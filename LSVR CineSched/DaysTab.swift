// DaysTab.swift
// The iPhone's Days list (#24): the Stripboard as a scrolling list of day cards, with the
// week strip pinned above it for orientation and the Day screen as a navigation
// destination. The rows come from `stripboardRows(for:showAllDays: false, expandedDayIDs:)`,
// the Mac board's row function, so gap folding, event-only days and typed days behave
// exactly as they do there: a gap row stands for a run of empty days and expands on a
// tap; a day is a card whose header (production day number, date, type, scene count,
// pages, general call) opens its Day screen, with the day's event chips and its strips,
// each timed by the cascade (`DayTimeline`). Long-pressing a strip previews the scene and
// offers the strip menu; the swipe actions and menu items are built in
// `PhoneStripActions` (PhoneStripRow.swift), the moves among them (#25).
//
// The moves (#25): a long-press drag on a strip reorders it within its day through the
// strips `ForEach`'s `.onMove` (`PhoneMoves.reorder`, one edit); the `List` gives the drag
// handles and the edge auto-scroll. A strip cannot be dragged into another day's card,
// because a `List` on iOS 27 does not deliver a cross-section drop — a row's or a
// section's `.dropDestination` is never targeted and `onInsert` never fires for a drag
// that started in another section (learnings 2026-09-21 #25) — and a `List` is what the
// swipe actions need. Cross-day moves are Send to Day instead (the strip's swipe and
// menu, `PhoneStripActions`), which lands the scene on any day picked. The day header's
// long press is the day's menu (Open Day, Add Scenes…, Swap with Day…). No `dragContainer`
// or `reorderContainer`: see ScheduleDrag.swift and learnings 2026-09-20.
//
// Scrolling to a date (the week strip, the month popover, the Today control through the
// `scrollToDate` binding the editor owns) goes through `dayScrollTarget`: a date folded
// into a collapsed gap opens the gap first and scrolls on the next run-loop turn, when
// the row exists, as the Stripboard's `scrollToDate` does. The week strip follows the
// earliest day card on screen, so it always names the week being read.
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

struct DaysTab: View {
    let document: ProjectDocument
    /// Strips whose cast is unavailable that day (`DerivedScheduleState.conflictSceneIDs`).
    let conflictSceneIDs: Set<UUID>
    /// A date to scroll to, set by the editor's Today control and by this tab's own week
    /// strip and month popover; cleared here once acted on.
    @Binding var scrollToDate: Date?
    let edit: ProjectEdit
    /// The moves and their pickers (#25), wired by the editor.
    let moves: PhoneMoves
    @Environment(\.scenePalette) private var palette
    /// Compact vertically (an iPhone in landscape): the week strip is one row.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The Day screens pushed, by day id.
    @State private var path: [UUID] = []
    /// Ids of empty days whose gap the user has opened. Keyed by day, not by gap, so a
    /// gap that splits when a scene lands in its middle keeps both halves open (the
    /// Stripboard's rule).
    @State private var expandedGapDayIDs: Set<UUID> = []
    /// The week the strip shows: seeded from Today's target, paged by the chevrons, and
    /// following the earliest day card on screen as the list scrolls.
    @State private var weekReference: Date = Date()
    @State private var didSeedWeek = false
    /// The dates of the day headers currently on screen (kept by their appear and
    /// disappear), whose earliest picks the week strip's week.
    @State private var visibleDayDates: Set<Date> = []
    @State private var showingMonthPicker = false
    @State private var monthPickerDate: Date = Date()

    private var shootDays: [ShootDay] { document.project.shootDays }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            // The strip sits above the list, not as a safe-area inset over it: a row that
            // scrolled under an inset still counts as visible to the scroll view, which
            // put the strip on the wrong week.
            VStack(spacing: 0) {
                weekStripView
                ScrollViewReader { proxy in
                    daysList
                        .onChange(of: scrollToDate) { _, date in
                            scroll(to: date, with: proxy, deferred: false)
                        }
                        .onAppear {
                            seedWeekIfNeeded()
                            // A request made before this tab existed (Today from another tab).
                            scroll(to: scrollToDate, with: proxy, deferred: true)
                        }
                }
            }
            .editorNavigationBarHidden()
            .navigationDestination(for: UUID.self) { dayID in
                DayScreen(dayID: dayID, document: document, conflictSceneIDs: conflictSceneIDs, edit: edit, moves: moves)
            }
        }
    }

    // MARK: - The list

    private var daysList: some View {
        let rows       = stripboardRows(for: shootDays, showAllDays: false, expandedDayIDs: expandedGapDayIDs)
        let dayNumbers = productionDayNumbers(for: shootDays)
        return List {
            if rows.isEmpty {
                ContentUnavailableView(
                    L("No Shoot Days"),
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(L("Set the production range on the Mac or iPad to add days."))
                )
                .listRowBackground(Color.clear)
            }
            ForEach(rows) { row in
                switch row {
                case .day(_, let day):
                    daySection(day, dayNumbers: dayNumbers)
                case .gap(let gap):
                    gapSection(gap)
                }
            }
        }
        .insetGroupedListStyle()
    }

    // MARK: - Day section

    private func daySection(_ day: ShootDay, dayNumbers: [UUID: Int]) -> some View {
        let summary  = DaySummary(day: day, dayNumbers: dayNumbers)
        let strips   = day.scenes.filter { !$0.isCalendarEvent }
        let events   = day.scenes.filter { $0.isCalendarEvent }
        let timeline = dayTimeline(for: day, scenes: strips)
        let actions  = PhoneStripActions(day: day, edit: edit, moves: moves, openDay: { path.append(day.id) })
        let displayed = strips.map(\.id)

        return Section {
            dayHeader(day, summary: summary)
            if !events.isEmpty {
                eventChips(events)
            }
            ForEach(strips) { scene in
                PhoneStripRow(scene: scene, timeText: timeline[scene.id]?.timeDisplay ?? "", hasConflict: conflictSceneIDs.contains(scene.id))
                    .stripListRow(color: PhoneStripRow.rowColor(for: scene, palette: palette))
                    .stripInteractions(actions, scene: scene)
                    .draggable(ScheduleDragPayload.scenes([scene.id], from: day.id))
            }
            .onMove { source, destination in
                moves.reorder(displayed, fromOffsets: source, toOffset: destination, in: day.id)
            }
            if stripboardDayIsEmpty(day) {
                // This day is only on screen because its gap was opened; offer the way back.
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { collapseGap(containing: day.id) }
                } label: {
                    Label(L("Hide empty days"), systemImage: "chevron.up")
                        .font(.footnote.weight(.semibold))
                }
            } else if strips.isEmpty {
                Text(L("No scenes scheduled"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The card's first row: what the day is, and the way into its Day screen; a long
    /// press is the day's menu.
    private func dayHeader(_ day: ShootDay, summary: DaySummary) -> some View {
        let typeColor = Color(hex: day.dayType.colorHex)
        return NavigationLink(value: day.id) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let number = summary.productionDayNumber {
                        Text("\(L("Day")) \(number)")
                            .font(.headline)
                        Text(formattedDate(day.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(formattedDate(day.date))
                            .font(.headline)
                    }
                    if !day.dayType.isShootable {
                        Label(day.dayType.localizedName, systemImage: day.dayType.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(typeColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(typeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if summary.hasCallSheet {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel(L("Has a call sheet"))
                    }
                }
                Text(headerDetail(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !summary.note.isEmpty {
                    Text(summary.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .id(day.id)
        .listRowBackground(day.dayType.isShootable ? nil : typeColor.opacity(0.10))
        .contextMenu { dayMenuItems(day) }
        // `onScrollVisibilityChange` never fires for a List row on 27.0; appear and
        // disappear do, one buffered cell late, which is close enough for the week.
        .onAppear    { visibleDayDates.insert(day.date); followVisibleDays() }
        .onDisappear { visibleDayDates.remove(day.date); followVisibleDays() }
    }

    /// The day header's long-press menu: the Day screen and the moves that act on the
    /// whole day (#25). #26 adds its day edits here.
    @ViewBuilder
    private func dayMenuItems(_ day: ShootDay) -> some View {
        Button {
            path.append(day.id)
        } label: {
            Label(L("Open Day"), systemImage: "calendar")
        }
        Button {
            moves.presentAddScenes(dayID: day.id)
        } label: {
            Label(L("Add Scenes…"), systemImage: "plus.rectangle.on.rectangle")
        }
        Button {
            moves.presentSwapDay(dayID: day.id)
        } label: {
            Label(L("Swap with Day…"), systemImage: "arrow.left.arrow.right")
        }
    }

    /// "6 scn · 4 2/8 pgs · Call 6:30 AM · 1 event", dropping what the day has none of.
    private func headerDetail(_ summary: DaySummary) -> String {
        var parts: [String] = []
        if summary.sceneCount > 0 {
            parts.append("\(summary.sceneCount) \(L("scn")) · \(summary.pagesText) \(L("pgs"))")
            parts.append("\(L("Call")) \(summary.generalCall)")
        } else if summary.stripCount > 0 {
            parts.append("\(L("Call")) \(summary.generalCall)")
        }
        if summary.eventCount > 0 {
            parts.append(summary.eventCount == 1 ? L("1 event") : String(format: L("%d events"), summary.eventCount))
        }
        if parts.isEmpty { return L("No scenes") }
        return parts.joined(separator: " · ")
    }

    private func eventChips(_ events: [Scene]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(events) { event in
                    PhoneEventChip(event: event)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    // MARK: - Gap section

    /// One slim card standing in for a run of empty days; a tap swaps it for the day cards.
    private func gapSection(_ gap: StripboardGap) -> some View {
        let range = gap.dayCount == 1
            ? formattedDate(gap.firstDate)
            : "\(formattedDate(gap.firstDate)) – \(formattedDate(gap.lastDate))"
        let count   = gap.dayCount == 1 ? L("1 empty day") : "\(gap.dayCount) \(L("empty days"))"
        let details = gap.weekendCount > 0 ? " · \(gap.weekendCount) \(L("weekend"))" : ""

        return Section {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expandedGapDayIDs.formUnion(gap.dayIDs) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count)
                            .font(.subheadline.weight(.semibold))
                        Text(range + details)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                    Text(L("Show"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .id(gap.id)
        }
    }

    /// Removes every day of the contiguous empty run around `dayID` from the expanded set,
    /// so the run folds back into one gap row (the Stripboard's `collapseGap`).
    private func collapseGap(containing dayID: UUID) {
        guard let index = shootDays.firstIndex(where: { $0.id == dayID }) else { return }
        var low = index
        while low > 0, stripboardDayIsEmpty(shootDays[low - 1]) { low -= 1 }
        var high = index
        while high < shootDays.count - 1, stripboardDayIsEmpty(shootDays[high + 1]) { high += 1 }
        for day in shootDays[low...high] { expandedGapDayIDs.remove(day.id) }
    }

    // MARK: - Week strip

    /// The month title with the week chevrons over the seven day cells; on one row when
    /// the window is short (an iPhone in landscape), so the list keeps its height.
    private var weekStripView: some View {
        let strip = WeekStrip(containing: weekReference, shootDays: shootDays, today: Date(), calendar: .current)
        return Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 8) {
                    weekPager(strip)
                    weekCells(strip)
                }
            } else {
                VStack(spacing: 8) {
                    weekPager(strip)
                    weekCells(strip)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func weekPager(_ strip: WeekStrip) -> some View {
        HStack {
            Button {
                weekReference = strip.previousWeekDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel(L("Previous week"))
            Spacer(minLength: 0)
            Button {
                monthPickerDate    = weekReference
                showingMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    // The week's Wednesday names the month a week that straddles two belongs to.
                    Text(formattedDate(strip.days[3].date, pattern: "MMMM yyyy"))
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("WeekStripMonth")
            .popover(isPresented: $showingMonthPicker, arrowEdge: .top) {
                monthPopover
            }
            Spacer(minLength: 0)
            Button {
                weekReference = strip.nextWeekDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel(L("Next week"))
        }
        .buttonStyle(.plain)
    }

    private func weekCells(_ strip: WeekStrip) -> some View {
        HStack(spacing: 4) {
            ForEach(strip.days) { cell in
                weekCell(cell)
            }
        }
    }

    /// One day of the week: weekday letter, day number and the scene count (a dot for an
    /// event-only day), tinted by the day type, ringed when today, dimmed and inert when
    /// the production range does not cover it.
    private func weekCell(_ cell: WeekStripDay) -> some View {
        let inRange  = cell.day != nil
        let typeTint = cell.dayType.flatMap { $0.isShootable ? nil : Color(hex: $0.colorHex) }
        let fill     = typeTint?.opacity(0.22) ?? (inRange ? Color.primary.opacity(0.06) : Color.clear)
        return Button {
            scrollToDate = cell.date
        } label: {
            VStack(spacing: 2) {
                Text(formattedDate(cell.date, pattern: "EEEEE"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formattedDate(cell.date, pattern: "d"))
                    .font(.body.weight(cell.isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(cell.isToday ? Color.accentColor : .primary)
                Text(cell.sceneCount > 0 ? "\(cell.sceneCount)" : (cell.eventCount > 0 ? "•" : " "))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(cell.sceneCount > 0 ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cell.isToday ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .opacity(inRange ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inRange)
        .accessibilityLabel(Text(formattedDate(cell.date)))
        .accessibilityValue(Text(cell.sceneCount == 1 ? L("1 scene") : String(format: L("%d scenes"), cell.sceneCount)))
    }

    /// The month popover: a graphical picker over the production range; picking a date
    /// scrolls the list to it.
    private var monthPopover: some View {
        let dates = shootDays.map(\.date)
        let range = dates.min().flatMap { first in dates.max().map { first...$0 } }
        return Group {
            if let range {
                DatePicker(L("Go to date"), selection: $monthPickerDate, in: range, displayedComponents: .date)
            } else {
                DatePicker(L("Go to date"), selection: $monthPickerDate, displayedComponents: .date)
            }
        }
        .datePickerStyle(.graphical)
        .labelsHidden()
        .onChange(of: monthPickerDate) { _, date in
            showingMonthPicker = false
            scrollToDate       = date
        }
        .padding(8)
        .frame(minWidth: 320)
        // Stay a popover on the iPhone too; the default adaptation there is a full sheet.
        .presentationCompactAdaptation(.popover)
    }

    private func seedWeekIfNeeded() {
        guard !didSeedWeek else { return }
        didSeedWeek = true
        let targetID = todayTarget(in: shootDays, now: Date(), calendar: .current)
        if let date = shootDays.first(where: { $0.id == targetID })?.date ?? shootDays.first?.date {
            weekReference = date
        }
    }

    /// Points the week strip at the week of the earliest day card on screen.
    private func followVisibleDays() {
        guard let earliest = visibleDayDates.min() else { return }
        let calendar = Calendar.current
        if WeekStrip.weekStart(containing: earliest, calendar: calendar) != WeekStrip.weekStart(containing: weekReference, calendar: calendar) {
            weekReference = earliest
        }
    }

    // MARK: - Scrolling

    /// Scrolls the list to the day dated `date`, opening its gap first when it is folded;
    /// `deferred` waits a turn for the list to lay out (the appear path). Pops any Day
    /// screen so the list is what the user sees land.
    private func scroll(to date: Date?, with proxy: ScrollViewProxy, deferred: Bool) {
        guard let date else { return }
        scrollToDate = nil
        guard let target = dayScrollTarget(for: date, in: shootDays, expandedDayIDs: expandedGapDayIDs, calendar: .current) else { return }
        path = []
        if target.isInCollapsedGap {
            // No row to scroll to yet: open the gap and scroll once the day rows exist.
            expandedGapDayIDs.insert(target.dayID)
        }
        if target.isInCollapsedGap || deferred {
            DispatchQueue.main.async {
                withAnimation { proxy.scrollTo(target.dayID, anchor: .top) }
            }
        } else {
            withAnimation { proxy.scrollTo(target.dayID, anchor: .top) }
        }
    }
}

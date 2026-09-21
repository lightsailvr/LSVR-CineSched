// DayScreen.swift
// The iPhone's Day screen (#24): everything about one shoot day, pushed from the Days
// list as a navigation destination (not a sheet). Bound to the day by id and read from
// the document on every body, so it follows an edit, an undo or a sync under it, and
// shows an empty state if a range change removes the day. The header (`DaySummary`, with
// the day's menu), the day type and note, the call sheet card, the calendar events and
// the strips with the time cascade, each its own `Section` with a `MARK`. The strips are
// the same `PhoneStripRow` the list draws, with the same `PhoneStripActions` (no Open Day
// here; this is the day), and the moves (#25): Reorder puts the list in edit mode so the
// strips show drag handles (`onMove`, one edit per drop through `PhoneMoves.reorder`; a
// long press alone is the strip's menu), and an Add Scenes… row opens the Boneyard
// checklist.
//
// The edits (#26), each one undo step through `PhoneDayEdits`: the day type is a menu
// picker and the note a field written live under one gesture per focus session (the
// title field's rule, #28), with Clear Day Type when either is set; the call sheet card
// opens the call sheet editor (its Save syncs the auto-meal strips in the same edit) and
// an Export row makes the PDF; an event row opens the event input, swipes to Delete, and
// Add Event… appends one; a strip's tap opens its editor (`PhoneStripActions.open`), and
// Add Banner… sits beside Add Scenes…. The day's menu carries the same adds and the call
// sheet, so nothing here needs scrolling to find.
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

struct DayScreen: View {
    let dayID: UUID
    let document: ProjectDocument
    let conflictSceneIDs: Set<UUID>
    /// `edit` under a gesture the screen keeps across calls: the note's typing burst;
    /// every other write goes through `moves` or `dayEdits`.
    let editCoalescing: CoalescedProjectEdit
    let moves: PhoneMoves
    let dayEdits: PhoneDayEdits
    /// The Stripboard Fields setting, decoded once by the Days tab.
    let visibleFields: Set<StripboardField>
    @Environment(\.scenePalette) private var palette

    /// Edit mode on the strips, with their drag handles (Reorder / Done in the section header).
    @State private var isReordering = false
    /// The gesture the note's keystrokes fold into; a new one per focus session.
    @State private var noteGesture = EditGesture()
    @FocusState private var noteFocused: Bool

    private var day: ShootDay? { document.project.shootDays.first { $0.id == dayID } }

    var body: some View {
        if let day {
            content(for: day)
        } else {
            ContentUnavailableView(
                L("Day Removed"),
                systemImage: "calendar.badge.exclamationmark",
                description: Text(L("This date is no longer in the production range."))
            )
        }
    }

    private func content(for day: ShootDay) -> some View {
        let shootDays  = document.project.shootDays
        let dayNumbers = productionDayNumbers(for: shootDays)
        let summary    = DaySummary(day: day, dayNumbers: dayNumbers)
        let strips     = day.scenes.filter { !$0.isCalendarEvent }
        let events     = day.scenes.filter { $0.isCalendarEvent }
        let timeline   = dayTimeline(for: day, scenes: strips)
        let index      = shootDays.firstIndex { $0.id == dayID } ?? 0
        let actions    = PhoneStripActions(day: day, moves: moves, dayEdits: dayEdits, openDay: nil,
                                           hasPreviousDay: index > 0, hasNextDay: index < shootDays.count - 1)

        return List {
            headerSection(summary)
            dayTypeSection(day)
            callSheetSection(day)
            eventsSection(events)
            stripsSection(strips, timeline: timeline, actions: actions)
        }
        .insetGroupedListStyle()
        .listReordering(isReordering)
        .navigationTitle(summary.productionDayNumber.map { "\(L("Day")) \($0)" } ?? formattedDate(day.date))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: noteFocused) { _, focused in
            // The next focus session is its own undo step; the trimmed note is committed
            // as the session ends, under the gesture that typed it.
            if !focused {
                let note    = self.day?.dayNote ?? ""
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != note {
                    editCoalescing(noteGesture, L("Edit Day Note")) { $0.setDayNote(trimmed, forDayID: dayID) }
                }
                noteGesture = EditGesture()
            }
        }
    }

    // MARK: - Header

    /// The day as the list's header reads it, at full size: the date, the day number or
    /// the type, the counts, and the day's menu (the moves that act on the whole day).
    private func headerSection(_ summary: DaySummary) -> some View {
        let typeColor = Color(hex: summary.dayType.colorHex)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedFullDate(summary.date))
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    dayMenu
                }
                HStack(spacing: 8) {
                    if let number = summary.productionDayNumber {
                        Text("\(L("Day")) \(number)")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    if !summary.dayType.isShootable {
                        Label(summary.dayType.localizedName, systemImage: summary.dayType.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(typeColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(typeColor.opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 14) {
                    stat(icon: "film",       text: summary.sceneCount == 1 ? L("1 scene") : String(format: L("%d scenes"), summary.sceneCount))
                    stat(icon: "doc.text",   text: "\(summary.pagesText) \(L("pgs"))")
                    if summary.eventCount > 0 {
                        stat(icon: "calendar.badge.clock", text: summary.eventCount == 1 ? L("1 event") : String(format: L("%d events"), summary.eventCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(summary.dayType.isShootable ? nil : typeColor.opacity(0.10))
    }

    private func stat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .lineLimit(1)
    }

    /// The day's menu: the edits that add to the day and open its call sheet (#26), and
    /// the moves that act on the whole day (#25).
    private var dayMenu: some View {
        Menu {
            Button {
                dayEdits.presentCallSheet(dayID: dayID)
            } label: {
                Label(L("Edit Call Sheet…"), systemImage: "doc.plaintext")
            }
            Button {
                dayEdits.presentBannerEditor(dayID: dayID)
            } label: {
                Label(L("Add Banner…"), systemImage: "flag")
            }
            Button {
                dayEdits.presentEventEditor(dayID: dayID)
            } label: {
                Label(L("Add Event…"), systemImage: "calendar.badge.plus")
            }
            Divider()
            Button {
                moves.presentAddScenes(dayID: dayID)
            } label: {
                Label(L("Add Scenes…"), systemImage: "plus.rectangle.on.rectangle")
            }
            Button {
                moves.presentSwapDay(dayID: dayID)
            } label: {
                Label(L("Swap with Day…"), systemImage: "arrow.left.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Day actions"))
        .accessibilityIdentifier("DayMenu")
    }

    // MARK: - Day type and note (#26)

    /// The type as a menu picker (one edit per pick), the note as a field written live
    /// under the focus session's gesture, and Clear Day Type when either is set.
    private func dayTypeSection(_ day: ShootDay) -> some View {
        Section {
            Picker(selection: Binding(get: { day.dayType }, set: { dayEdits.setDayType($0, dayID: dayID) })) {
                ForEach(DayType.allCases, id: \.self) { type in
                    Label(type.localizedName, systemImage: type.icon).tag(type)
                }
            } label: {
                Text(L("Day Type"))
            }
            .pickerStyle(.menu)
            .tint(day.dayType.isShootable ? Color.primary : Color(hex: day.dayType.colorHex))
            .accessibilityIdentifier("DayTypePicker")

            TextField(L("Day Note"), text: noteBinding(day), prompt: Text(L("Day note (travel details, hold reason, …)")), axis: .vertical)
                .lineLimit(1...4)
                .focused($noteFocused)
                .accessibilityIdentifier("DayNoteField")

            if !day.dayType.isShootable || !day.dayNote.isEmpty {
                Button {
                    noteFocused = false
                    dayEdits.clearDayType(dayID: dayID)
                } label: {
                    Label(L("Clear Day Type"), systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("ClearDayType")
            }
        }
    }

    /// Every keystroke into the note, under the session's gesture, so the list's card
    /// follows as it is typed and one undo takes the burst back.
    private func noteBinding(_ day: ShootDay) -> Binding<String> {
        Binding(
            get: { self.day?.dayNote ?? day.dayNote },
            set: { new in
                editCoalescing(noteGesture, L("Edit Day Note")) { data in
                    guard let index = data.dayIndex(forDayID: dayID) else { return }
                    data.shootDays[index].dayNote = new
                }
            }
        )
    }

    // MARK: - Call sheet card (#26: opens the call sheet editor)

    /// The card is one tap target into the call sheet editor; the row under it makes the PDF.
    private func callSheetSection(_ day: ShootDay) -> some View {
        let sheet = day.callSheet
        let empty = !day.hasCallSheetData && sheet.readyToShootTime.isEmpty && sheet.wrapTime.isEmpty
        return Section {
            Button {
                dayEdits.presentCallSheet(dayID: dayID)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        if empty {
                            Text(L("No call sheet yet"))
                                .foregroundStyle(Color.secondary)
                            Text(L("Tap to set the calls, meals, wrap and basecamp."))
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        } else {
                            callTime(L("General Call"),   sheet.generalCallTime,  icon: "megaphone.fill",       color: .blue)
                            if !sheet.readyToShootTime.isEmpty {
                                callTime(L("Ready to Shoot"), sheet.readyToShootTime, icon: "film.fill",        color: .green)
                            }
                            callTime(L("Lunch"),          sheet.lunchTime,        icon: "fork.knife",           color: .orange)
                            if !sheet.snackTime.isEmpty {
                                callTime(L("Snack"),      sheet.snackTime,        icon: "cup.and.saucer.fill",  color: .brown)
                            }
                            if !sheet.dinnerTime.isEmpty {
                                callTime(L("Dinner"),     sheet.dinnerTime,       icon: "fork.knife.circle",    color: .orange)
                            }
                            callTime(L("Wrap"),           sheet.wrapTime,         icon: "flag.checkered",       color: .red)
                            if !sheet.basecampLocation.isEmpty {
                                HStack(alignment: .top) {
                                    Label {
                                        Text(L("Basecamp")).foregroundStyle(Color.primary)
                                    } icon: {
                                        Image(systemName: "mappin.circle.fill").foregroundStyle(Color.purple)
                                    }
                                    Spacer()
                                    Text(sheet.basecampLocation)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(Color.primary)
                                }
                            }
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("CallSheetCard")

            Button {
                dayEdits.exportCallSheet(day)
            } label: {
                Label(L("Export Call Sheet PDF"), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("ExportCallSheet")
        } header: {
            Label(L("Call Sheet"), systemImage: "doc.text")
        }
    }

    private func callTime(_ label: String, _ time: String, icon: String, color: Color) -> some View {
        HStack {
            Label {
                Text(label).foregroundStyle(Color.primary)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            Spacer()
            Text(time.isEmpty ? "—" : time)
                .font(.body.weight(time.isEmpty ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(time.isEmpty ? Color.secondary : Color.primary)
        }
    }

    // MARK: - Calendar events (#26: add, edit, delete)

    private func eventsSection(_ events: [Scene]) -> some View {
        Section {
            ForEach(events) { event in
                let color = Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex)
                Button {
                    dayEdits.presentEventEditor(dayID: dayID, eventID: event.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(event.bannerTitle.isEmpty ? event.title : event.bannerTitle)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if !event.customStartTime.isEmpty {
                            Text(event.customStartTime)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        dayEdits.deleteNoticeStrip(event)
                    } label: {
                        Label(L("Delete"), systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        dayEdits.presentEventEditor(dayID: dayID, eventID: event.id)
                    } label: {
                        Label(L("Edit Event"), systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        dayEdits.deleteNoticeStrip(event)
                    } label: {
                        Label(L("Delete Event"), systemImage: "trash")
                    }
                }
            }
            Button {
                dayEdits.presentEventEditor(dayID: dayID)
            } label: {
                Label(L("Add Event…"), systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("AddEventRow")
        } header: {
            Label(L("Calendar Events"), systemImage: "calendar.badge.clock")
        }
    }

    // MARK: - Strips (#25: reorder with handles, Add Scenes; #26: the editors, Add Banner)

    private func stripsSection(_ strips: [Scene], timeline: [UUID: DayTimelineEntry], actions: PhoneStripActions) -> some View {
        let displayed = strips.map(\.id)
        return Section {
            if strips.isEmpty {
                Text(L("No scenes scheduled"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(strips) { scene in
                PhoneStripRow(scene: scene, timeText: timeline[scene.id]?.timeDisplay ?? "", hasConflict: conflictSceneIDs.contains(scene.id), visibleFields: visibleFields)
                    .stripListRow(color: PhoneStripRow.rowColor(for: scene, palette: palette))
                    .stripInteractions(actions, scene: scene)
            }
            .onMove { source, destination in
                moves.reorder(displayed, fromOffsets: source, toOffset: destination, in: dayID)
            }
            Button {
                moves.presentAddScenes(dayID: dayID)
            } label: {
                Label(L("Add Scenes…"), systemImage: "plus.rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("AddScenesRow")
            Button {
                dayEdits.presentBannerEditor(dayID: dayID)
            } label: {
                Label(L("Add Banner…"), systemImage: "flag")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("AddBannerRow")
        } header: {
            HStack {
                Label(L("Strips"), systemImage: "rectangle.stack")
                Spacer()
                if strips.count > 1 {
                    Button(isReordering ? L("Done") : L("Reorder")) {
                        withAnimation { isReordering.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("ReorderStrips")
                }
            }
        }
    }
}

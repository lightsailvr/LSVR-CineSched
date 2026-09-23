// ContentView+Inspector.swift
// The trailing inspector of the three-column layout (#17): what a single tap selects,
// edited beside the board. A selected scene shows the scene editor (`SceneEditSheet`,
// the same adaptive form the sheets show, #19); a selected day shows the day detail
// (`DayDetailSheet`: statistics, day type and note, the day's actions, call sheet
// milestones, events, scenes); nothing selected shows the project's statistics, the
// Mac toolbar row's badges. Every write is an `edit` through the document's funnel, so
// an inspector edit undoes like any other. The selection itself is `EditorSelection`
// (a pure value), addressed by id so the inspector follows a scene when a drag moves it.
//
// The editors read `editorPresentation == .inspector` to skip the sheet sizing and the
// scene editor's auto-focus.

import SwiftUI

extension ContentView {

    // MARK: - The column

    @ViewBuilder
    var inspectorView: some View {
        Group {
            switch selection {
            case .scene(let id):
                sceneInspector(id: id)
                    // A new id is a new editor: its fields repopulate and its own state
                    // (the expanded breakdown, the focused field) starts over.
                    .id(id)
            case .day(let id):
                dayInspector(id: id)
                    // Likewise; and the old day detail's disappearance commits its note.
                    .id(id)
            case nil:
                emptyInspector
            }
        }
        .environment(\.editorPresentation, .inspector)
    }

    /// Nothing selected: the project's statistics and how to select something.
    private var emptyInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Project"))
                .font(.title2).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 10) {
                statBadge(icon: "calendar",         value: "\(scheduledDays.count)",                        label: "days",        color: .blue)
                statBadge(icon: "checkmark.circle", value: "\(completedScenesCount)/\(totalScenes)",         label: "completed",   color: .green)
                statBadge(icon: "clock",            value: totalEstTime,                                    label: nil,           color: .purple)
                statBadge(icon: "doc.text",         value: totalDuration,                                   label: "pages",       color: .teal)
                statBadge(icon: "tray.full",        value: "\(unscheduledCount)",                           label: "unscheduled", color: .orange)
            }
            Divider()
            Text(L("Tap a strip to edit the scene here, or a day to see its detail. Double-tap a strip for the full editor."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Scene

    @ViewBuilder
    private func sceneInspector(id: UUID) -> some View {
        if let scene = document.project.scene(withID: id) {
            SceneEditSheet(
                scene:       inspectedSceneBinding(id: id, fallback: scene),
                isPresented: inspectorEditorPresented,
                onSave:      { inspectorKeepsSelection = true },
                onDelete:    { deleteInspectedScene(id: id) },
                knownLocations: document.project.knownLocations,
                breakdownSuggestions: document.project.breakdownSuggestions
            )
        }
    }

    /// The selected scene by id, wherever it is. The setter opens the edit gesture on its
    /// first write, so the editor's Save (one assignment per field through this binding)
    /// is one undo step and one change count by construction, not by the window's
    /// run-loop grouping; the gesture closes itself at the end of the turn.
    private func inspectedSceneBinding(id: UUID, fallback: Scene) -> Binding<Scene> {
        Binding(
            get: { document.project.scene(withID: id) ?? fallback },
            set: { new in
                if activeGesture == nil { beginEditGesture() }
                edit(L("Edit Scene")) { data in
                    switch data.locate(sceneID: id) {
                    case .boneyard(let index):                     data.allScenes[index] = new
                    case .scheduled(let dayIndex, let sceneIndex): data.shootDays[dayIndex].scenes[sceneIndex] = new
                    case nil:                                      break
                    }
                }
            }
        )
    }

    /// The editor's `isPresented`: it sets this false after Save, Cancel and Delete alike.
    /// Save has just set `inspectorKeepsSelection`, so that close keeps the scene in the
    /// inspector; the other two clear the selection. (The editor's Previous and Next,
    /// which save without closing, are not offered here, so the flag cannot go stale.)
    private var inspectorEditorPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { shown in
                guard !shown else { return }
                if inspectorKeepsSelection {
                    inspectorKeepsSelection = false
                } else {
                    selection = nil
                }
            }
        )
    }

    /// Delete Scene from the inspector, what the Mac's sheets do with the same button: a
    /// Boneyard scene is deleted, a scheduled one goes back to the Boneyard (the calendar's
    /// and the Stripboard's editors call `removeFromDay`; only the breakdown browser
    /// deletes a scheduled scene outright).
    private func deleteInspectedScene(id: UUID) {
        switch document.project.locate(sceneID: id) {
        case .boneyard:
            edit(L("Delete Scene")) { data in
                if case .boneyard(let index) = data.locate(sceneID: id) { data.allScenes.remove(at: index) }
            }
        case .scheduled(let dayIndex, _):
            let dayID = shootDays[dayIndex].id
            if let scene = document.project.scene(withID: id) { removeScene(scene, from: dayID) }
        case nil:
            break
        }
    }

    // MARK: - Day

    @ViewBuilder
    private func dayInspector(id: UUID) -> some View {
        if let index = document.project.dayIndex(forDayID: id) {
            let day = shootDays[index]
            DayDetailSheet(
                day:            day,
                dayNumber:      productionDayNumbers(for: shootDays)[day.id],
                productionInfo: productionInfo,
                isPresented:    inspectorEditorPresented,
                onEditScene: { scene in
                    if scene.isCalendarEvent {
                        activeSheet = .calendarEvent(dayID: id, eventID: scene.id)
                    } else {
                        selection = .scene(id: scene.id)
                    }
                },
                onRemoveScene:      { scene in removeFromInspectedDay(scene, dayID: id) },
                onAddCalendarEvent: { activeSheet = .calendarEvent(dayID: id, eventID: nil) },
                onSetDayType:       { type in setDayType(type, dayID: id) },
                onSetDayNote:       { note in setDayNote(note, dayID: id) },
                onClearDayType:     { clearDayType(dayID: id) },
                onOpenCallSheet:    { activeSheet = .callSheet(dayID: id) },
                onExportCallSheetPDF: { showCallSheetPDFSavePanel(for: day) }
            )
        }
    }

    // MARK: Day edits

    private func setDayType(_ type: DayType, dayID: UUID) {
        edit(L("Set Day Type")) { data in
            guard let index = data.dayIndex(forDayID: dayID) else { return }
            data.shootDays[index].dayType = type
        }
    }

    private func setDayNote(_ note: String, dayID: UUID) {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(L("Edit Day Note")) { data in
            guard let index = data.dayIndex(forDayID: dayID) else { return }
            data.shootDays[index].dayNote = clean
        }
    }

    /// Back to a plain shoot day with no note. A day outside the production range that
    /// held nothing but the type goes entirely (`clearDayType(forDayID:productionRange:)`,
    /// the calendar's and the phone's rule); the range is the pickers', which is what the
    /// calendar reads too, nil while the end precedes the start.
    private func clearDayType(dayID: UUID) {
        let range = pickerRange(start: startDate, end: endDate)
        edit(L("Clear Day Type")) { $0.clearDayType(forDayID: dayID, productionRange: range) }
    }

    /// The day detail's trash: a scene goes back to the Boneyard, a calendar event is
    /// deleted (events are never Boneyard material).
    private func removeFromInspectedDay(_ scene: Scene, dayID: UUID) {
        edit(scene.isCalendarEvent ? L("Delete Event") : L("Move to Boneyard")) { data in
            guard let index = data.dayIndex(forDayID: dayID) else { return }
            data.shootDays[index].scenes.removeAll { $0.id == scene.id }
            if !scene.isCalendarEvent { data.allScenes.append(scene) }
        }
    }

    // MARK: - The day's sheets

    /// Add Calendar Event (`eventID` nil) or edit one of the day's events, from the day
    /// detail; the editor's Save writes through the funnel.
    @ViewBuilder
    func inspectorCalendarEventSheet(dayID: UUID, eventID: UUID?) -> some View {
        let existing = eventID.flatMap { id in
            shootDays.first { $0.id == dayID }?.scenes.first { $0.id == id }
        }
        CalendarEventInputSheet(
            isPresented: Binding(get: { activeSheet != nil }, set: { if !$0 { activeSheet = nil } }),
            initialEvent: existing,
            onSave: { event in
                edit(existing == nil ? L("Add Calendar Event") : L("Edit Calendar Event")) { data in
                    guard let index = data.dayIndex(forDayID: dayID) else { return }
                    if let eventID, let position = data.shootDays[index].scenes.firstIndex(where: { $0.id == eventID }) {
                        data.shootDays[index].scenes[position] = event
                    } else {
                        data.shootDays[index].scenes.append(event)
                    }
                }
                activeSheet = nil
            }
        )
    }

    /// Edit Call Sheet from the day detail. The editor writes the day through the binding
    /// and its Save follows in the same turn, one gesture. The auto-meal strips follow the
    /// new times inside that same edit (`AutoMealSync`): the Stripboard may be showing the
    /// day already, and its own sync runs only when a section appears or its own editor
    /// saves, so without this a visible section kept the old lunch strip until scrolled off.
    @ViewBuilder
    func inspectorCallSheetSheet(dayID: UUID) -> some View {
        if let index = document.project.dayIndex(forDayID: dayID) {
            let numbers = productionDayNumbers(for: shootDays)
            let day     = shootDays[index]
            CallSheetEditor(
                shootDay: Binding(
                    get: { document.project.dayIndex(forDayID: dayID).map { shootDays[$0] } ?? day },
                    set: { new in
                        if activeGesture == nil { beginEditGesture() }
                        edit(L("Edit Call Sheet")) { data in
                            guard let i = data.dayIndex(forDayID: dayID) else { return }
                            data.shootDays[i] = new
                            data.shootDays[i].scenes = data.shootDays[i].scenesWithSyncedAutoMeals()
                        }
                    }
                ),
                productionInfo: productionInfo,
                isPresented: Binding(get: { activeSheet != nil }, set: { if !$0 { activeSheet = nil } }),
                onSave: { activeSheet = nil },
                onExportPDF: { day in
                    activeSheet = nil
                    showCallSheetPDFSavePanel(for: day)
                },
                dayNumber: numbers[dayID],
                totalProductionDays: numbers.values.max() ?? 0
            )
        }
    }
}

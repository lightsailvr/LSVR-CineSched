// PhoneDayEdits.swift
// The edits the iPhone makes to a day and its strips (#26), wired once by `PhoneEditor`
// and handed to the Days list, the Day screen and the strip actions as one
// `PhoneDayEdits` value, the way the moves are (`PhoneMoves`, #25): the day type and
// note, a banner or calendar event added, edited or deleted, a strip's time, the call
// sheet, a scene's fields and Duplicate Scene. Each is one `edit` over the pure
// `DayEdits` functions, so every edit is one undo step; the editors that write several
// times in one turn (the scene editor's Save then Duplicate, the call sheet editor's
// save then Export) open the editor's gesture first (`beginGesture`) so they fold.
//
// The editors themselves are the adaptive forms every platform has (`SceneEditSheet`,
// `BannerInputSheet`, `CalendarEventInputSheet`, `QuickTimeEditSheet`,
// `CallSheetEditor`), presented as sheets over the editor, not over the row or the Day
// screen that asked: a list asks through `presentSceneEditor`, `presentBannerEditor`,
// `presentEventEditor`, `presentSetTime` or `presentCallSheet`, `PhoneEditor` holds the
// request in `@State` and `phoneEditSheets` presents it, so a sheet survives a swipe
// action's row leaving the screen. Every editor is bound by id and reads the document on
// each body, so a scene edited, moved or undone under an open sheet is the current one.
// `PhoneSceneEditor` is the one scene editor of the phone (the M4 review folded #27's
// separate copy into it): a strip's tap opens it over its day (Previous and Next step
// the day's script scenes, live), a Boneyard row or a search result opens it with no day
// and the rows the tab shows as `siblingIDs` (Previous and Next step those; its Delete
// then deletes, as the Mac's Boneyard editor does), and Duplicate Scene is in its footer
// from every tab. A subject that left the project under an open sheet (an undo, a sync)
// shows `PhoneEditorUnavailable`, sized by the editor container like every other sheet.
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

// MARK: - The sheets

/// An editor one of the lists asked for, presented as a sheet over the editor.
struct PhoneEditSheet: Identifiable {
    enum Kind {
        /// The scene editor for a scene. `dayID` is the day whose script scenes Previous
        /// and Next step over (read live); nil for a Boneyard scene, when `siblingIDs` is
        /// the list the tab showed (the filtered Boneyard, a search's results), stepped
        /// as it was at the tap.
        case scene(sceneID: UUID, dayID: UUID?, siblingIDs: [UUID])
        /// The banner input: edit the banner with `bannerID`, or add one to the day.
        case banner(dayID: UUID, bannerID: UUID?)
        /// The calendar event input: edit the event with `eventID`, or add one to the day.
        case event(dayID: UUID, eventID: UUID?)
        /// Set Time for a strip on a day.
        case setTime(sceneID: UUID, dayID: UUID)
        /// The call sheet editor for a day.
        case callSheet(dayID: UUID)
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - The edits

struct PhoneDayEdits {
    /// The editor's funnel: `edit(name) { data in … }`, one `perform`.
    let edit: ProjectEdit
    /// Opens the editor's gesture if none is open, so the writes of one turn fold.
    let beginGesture: () -> Void
    /// Presents an editor over the editor (`PhoneEditor.editSheet`).
    let present: (PhoneEditSheet) -> Void
    /// The production range as the Production tab's pickers hold it, for Clear Day Type:
    /// a typed day outside it that is emptied goes (the inspector's rule); nil drops nothing.
    let productionRange: () -> ClosedRange<Date>?
    /// The call sheet editor's Export PDF: the request into the preview sheet.
    let exportCallSheet: (ShootDay) -> Void

    // MARK: Presenting the editors

    /// The scene editor over `sceneID`: on a day (Previous and Next over its script
    /// scenes), or off one with the tab's `siblingIDs` to step through.
    func presentSceneEditor(sceneID: UUID, dayID: UUID?, siblingIDs: [UUID] = []) {
        present(PhoneEditSheet(kind: .scene(sceneID: sceneID, dayID: dayID, siblingIDs: siblingIDs)))
    }

    func presentBannerEditor(dayID: UUID, bannerID: UUID? = nil) {
        present(PhoneEditSheet(kind: .banner(dayID: dayID, bannerID: bannerID)))
    }

    func presentEventEditor(dayID: UUID, eventID: UUID? = nil) {
        present(PhoneEditSheet(kind: .event(dayID: dayID, eventID: eventID)))
    }

    func presentSetTime(sceneID: UUID, dayID: UUID) {
        present(PhoneEditSheet(kind: .setTime(sceneID: sceneID, dayID: dayID)))
    }

    func presentCallSheet(dayID: UUID) {
        present(PhoneEditSheet(kind: .callSheet(dayID: dayID)))
    }

    /// The editor a tap on a strip opens: the scene editor for a script scene, the banner
    /// input for a custom banner, Set Time for an auto-meal (its call sheet owns the rest).
    func presentEditor(for scene: Scene, dayID: UUID) {
        if scene.isAutoMeal {
            presentSetTime(sceneID: scene.id, dayID: dayID)
        } else if scene.isBanner {
            presentBannerEditor(dayID: dayID, bannerID: scene.id)
        } else {
            presentSceneEditor(sceneID: scene.id, dayID: dayID)
        }
    }

    // MARK: Day type and note

    func setDayType(_ type: DayType, dayID: UUID) {
        edit(L("Set Day Type")) { $0.setDayType(type, forDayID: dayID) }
    }

    /// Clear Day Type: a plain shoot day with no note; an emptied day outside the
    /// production range is dropped with it, as the inspector's and the calendar's do.
    func clearDayType(dayID: UUID) {
        let range = productionRange()
        edit(L("Clear Day Type")) { $0.clearDayType(forDayID: dayID, productionRange: range) }
    }

    // MARK: Scenes

    /// The scene editor's write: the whole scene back by id, under the gesture so a
    /// Duplicate in the same turn folds in.
    func saveScene(_ scene: Scene) {
        beginGesture()
        edit(L("Edit Scene")) { $0.replaceScene(scene) }
    }

    /// Delete Scene on a Boneyard scene: gone (the Mac's Boneyard editor). A scheduled
    /// scene's Delete is `PhoneMoves.returnToBoneyard`, what the Mac's Stripboard sheet does.
    func deleteUnscheduledScene(id: UUID) {
        edit(L("Delete Scene")) { data in
            guard case .boneyard = data.locate(sceneID: id) else { return }
            data.removeScene(withID: id)
        }
    }

    func duplicateScene(id: UUID) {
        edit(L("Duplicate Scene")) { $0.duplicateScene(withID: id) }
    }

    // MARK: Notice strips

    /// Add or Save Changes from the banner or the event input: a strip the day already
    /// holds is replaced in place, a new one is appended.
    func saveNoticeStrip(_ strip: Scene, dayID: UUID, isNew: Bool) {
        let name = switch (strip.isCalendarEvent, isNew) {
        case (true,  true):  L("Add Calendar Event")
        case (true,  false): L("Edit Calendar Event")
        case (false, true):  L("Add Banner")
        case (false, false): L("Edit Banner")
        }
        edit(name) { data in
            if data.scene(withID: strip.id) != nil {
                data.replaceScene(strip)
            } else {
                data.addNoticeStrip(strip, toDayID: dayID)
            }
        }
    }

    func deleteNoticeStrip(_ strip: Scene) {
        edit(strip.isCalendarEvent ? L("Delete Event") : L("Delete Banner")) { $0.deleteNoticeStrip(withID: strip.id) }
    }

    // MARK: Set Time and the call sheet

    func applyStripTime(_ updated: Scene, dayID: UUID) {
        edit(L("Set Time")) { $0.applyStripTime(updated, dayID: dayID) }
    }

    /// The call sheet editor's write, under the gesture so Export PDF's save and the
    /// preview that follows are one step.
    func saveCallSheet(_ day: ShootDay) {
        beginGesture()
        edit(L("Edit Call Sheet")) { $0.saveCallSheet(day) }
    }
}

// MARK: - Presenting the editors

extension View {
    /// Presents the editor a list asked for (`PhoneEditor.editSheet`) and applies its
    /// Save through `dayEdits` (or `moves`, for a scheduled scene's Delete).
    func phoneEditSheets(_ sheet: Binding<PhoneEditSheet?>, document: ProjectDocument,
                         dayEdits: PhoneDayEdits, moves: PhoneMoves) -> some View {
        self.sheet(item: sheet) { request in
            PhoneEditSheetContent(request: request, document: document, dayEdits: dayEdits, moves: moves) {
                sheet.wrappedValue = nil
            }
        }
    }
}

/// The sheet's body for one request: the editor for its kind, bound by id.
private struct PhoneEditSheetContent: View {
    let request:  PhoneEditSheet
    let document: ProjectDocument
    let dayEdits: PhoneDayEdits
    let moves:    PhoneMoves
    let dismiss:  () -> Void

    private var project: ProjectData { document.project }

    /// The editors' `isPresented`: they set it false after Save, Cancel and Delete alike.
    private var presented: Binding<Bool> {
        Binding(get: { true }, set: { if !$0 { dismiss() } })
    }

    var body: some View {
        switch request.kind {
        case .scene(let sceneID, let dayID, let siblingIDs):
            PhoneSceneEditor(document: document, dayID: dayID, siblingIDs: siblingIDs, dayEdits: dayEdits, moves: moves, sceneID: sceneID, dismiss: dismiss)

        case .banner(let dayID, let bannerID):
            let existing = bannerID.flatMap { project.scene(withID: $0) }
            BannerInputSheet(isPresented: presented, initialBanner: existing) { banner in
                dayEdits.saveNoticeStrip(banner, dayID: dayID, isNew: existing == nil)
            }

        case .event(let dayID, let eventID):
            let existing = eventID.flatMap { project.scene(withID: $0) }
            CalendarEventInputSheet(isPresented: presented, initialEvent: existing) { event in
                dayEdits.saveNoticeStrip(event, dayID: dayID, isNew: existing == nil)
            }

        case .setTime(let sceneID, let dayID):
            if let scene = project.scene(withID: sceneID) {
                QuickTimeEditSheet(
                    scene:    scene,
                    onSave:   { updated in
                        dayEdits.applyStripTime(updated, dayID: dayID)
                        dismiss()
                    },
                    onCancel: dismiss
                )
            } else {
                PhoneEditorUnavailable(title: L("Set Time"), message: L("Strip Removed"), dismiss: dismiss)
            }

        case .callSheet(let dayID):
            if let index = project.dayIndex(forDayID: dayID) {
                let numbers = productionDayNumbers(for: project.shootDays)
                let day     = project.shootDays[index]
                CallSheetEditor(
                    shootDay: Binding(
                        get: { project.dayIndex(forDayID: dayID).map { project.shootDays[$0] } ?? day },
                        set: { new in dayEdits.saveCallSheet(new) }
                    ),
                    productionInfo: project.productionInfo ?? ProductionInfo(),
                    isPresented:    presented,
                    onSave:         dismiss,
                    onExportPDF:    { saved in
                        dismiss()
                        dayEdits.exportCallSheet(saved)
                    },
                    dayNumber:           numbers[dayID],
                    totalProductionDays: numbers.values.max() ?? 0
                )
            } else {
                PhoneEditorUnavailable(title: L("Call Sheet"), message: L("Day Removed"), dismiss: dismiss)
            }
        }
    }
}

// MARK: - A subject that left the project

/// What a sheet shows when its subject left the project under it (an undo, a sync): the
/// editor's chrome around an unavailable view, sized by the editor container like every
/// other sheet (never a `presentationDetents` of its own, which would size outside the
/// seam).
struct PhoneEditorUnavailable: View {
    let title:   String
    let message: String
    let dismiss: () -> Void

    static let sheetSize = EditorSheetSize(width: 400, height: 320, compactDetents: [.medium])

    var body: some View {
        EditorChrome {
            EditorTitle(title: title)
        } content: {
            ContentUnavailableView(message, systemImage: "xmark.circle", description: Text(L("It is no longer in the project.")))
        } footer: {
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .editorContainer(Self.sheetSize)
    }
}

// MARK: - The scene editor, by id

/// The phone's one scene editor: `SceneEditSheet` over the scene with `sceneID`, wherever
/// it is. Previous and Next step along the day's script scenes when the editor was opened
/// from a day (read live, so a reorder under the sheet is followed), else along the
/// `siblingIDs` the tab supplied (a new id is a new editor, as in the inspector). Save
/// writes the scene back by id; Delete returns a scheduled scene to the Boneyard (the
/// Mac's Stripboard sheet) and deletes a Boneyard one (the Mac's Boneyard editor);
/// Duplicate puts a copy in the Boneyard, in the gesture the Save before it opened.
struct PhoneSceneEditor: View {
    let document:   ProjectDocument
    let dayID:      UUID?
    let siblingIDs: [UUID]
    let dayEdits:   PhoneDayEdits
    let moves:      PhoneMoves
    @State var sceneID: UUID
    let dismiss:    () -> Void

    private var project: ProjectData { document.project }

    var body: some View {
        if let scene = project.scene(withID: sceneID) {
            let siblings = currentSiblingIDs
            let position = siblings.firstIndex(of: sceneID)
            let steps    = siblings.count > 1 && position != nil
            SceneEditSheet(
                scene:          sceneBinding(id: sceneID, fallback: scene),
                isPresented:    Binding(get: { true }, set: { if !$0 { dismiss() } }),
                onSave:         {},
                onDelete:       { delete(scene) },
                canGoPrevious:  position.map { $0 > 0 } ?? false,
                canGoNext:      position.map { $0 < siblings.count - 1 } ?? false,
                onPrevious:     steps ? { if let p = position, p > 0 { sceneID = siblings[p - 1] } } : nil,
                onNext:         steps ? { if let p = position, p < siblings.count - 1 { sceneID = siblings[p + 1] } } : nil,
                positionLabel:  steps ? position.map { String(format: L("Scene %d of %d"), $0 + 1, siblings.count) } : nil,
                knownLocations: project.knownLocations,
                onDuplicate:    { dayEdits.duplicateScene(id: sceneID) },
                breakdownSuggestions: project.breakdownSuggestions
            )
            .id(sceneID)
        } else {
            PhoneEditorUnavailable(title: L("Edit Scene"), message: L("Scene Removed"), dismiss: dismiss)
        }
    }

    /// What Previous and Next step over: the day's script scenes in order, read live, when
    /// the editor is over a day; otherwise the tab's list as it was at the tap.
    private var currentSiblingIDs: [UUID] {
        guard let dayID else { return siblingIDs }
        guard let day = project.shootDays.first(where: { $0.id == dayID }) else { return [] }
        return day.scenes.filter { !$0.isBanner && !$0.isCalendarEvent }.map(\.id)
    }

    private func sceneBinding(id: UUID, fallback: Scene) -> Binding<Scene> {
        Binding(
            get: { project.scene(withID: id) ?? fallback },
            set: { new in dayEdits.saveScene(new) }
        )
    }

    private func delete(_ scene: Scene) {
        switch project.locate(sceneID: scene.id) {
        case .boneyard:  dayEdits.deleteUnscheduledScene(id: scene.id)
        case .scheduled: moves.returnToBoneyard([scene.id])
        case nil:        break
        }
    }
}

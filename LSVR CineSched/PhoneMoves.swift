// PhoneMoves.swift
// The moves the iPhone makes to the schedule (#25), wired once by `PhoneEditor` and handed
// to the Days list, the Day screen and (with #27) the Boneyard tab as one `PhoneMoves`
// value: a reorder within a day (`reorder`), Send to Day (`sendToDay`), Move to Next Day
// and Move to Previous Day (`moveToAdjacentDay`: the one-gesture slip to tomorrow the
// spec's story 34 asks for, since a sectioned `List` never carries a drag across days,
// learnings 2026-09-21), Add Scenes (`addScenes`), Swap with Day (`swapDays`) and the
// swipe back to the Boneyard (`returnToBoneyard`). Each is one `edit` over the pure
// `ScheduleMoves` functions, so a
// move is one undo step — the shake or the three-finger swipe reverses exactly it — and
// each brings the auto-meal strips of the days it touched in line with their call sheets
// inside that same edit, as the inspector's call sheet save does (learnings 2026-09-20,
// the M3 review), so a day the Stripboard never opened does not show a stale lunch after
// a scene lands on it.
//
// The pickers those moves need are sheets over the editor, not over the list that asked
// for them: Send to Day and Swap with Day are `SendToDaySheet` (the day picker every
// platform has, titled for the job), Add Scenes is `AddScenesSheet`. A list asks for one
// through `presentSendToDay(sceneIDs:)`, `presentSwapDay(dayID:)` or
// `presentAddScenes(dayID:)`; `PhoneEditor` holds the request in `@State` and
// `phoneMoveSheets` presents it, so a sheet survives the row that asked for it leaving the
// screen (a swipe action's row, a Day screen popped by the drop). #27's Boneyard tab calls
// `presentSendToDay` for a Boneyard scene: the same sheet, the same move.
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

// MARK: - The pickers

/// A picker one of the moves needs, presented as a sheet over the editor.
struct PhoneMoveSheet: Identifiable {
    enum Kind {
        /// Send to Day for these scenes (from a day, or from the Boneyard with #27).
        case sendToDay(sceneIDs: [UUID])
        /// Swap with Day for this day.
        case swapDay(dayID: UUID)
        /// Add Scenes from the Boneyard to this day.
        case addScenes(dayID: UUID)
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - The moves

struct PhoneMoves {
    /// The editor's funnel: `edit(name) { data in … }`, one `perform`.
    let edit: ProjectEdit
    /// Presents a picker over the editor (`PhoneEditor.moveSheet`).
    let present: (PhoneMoveSheet) -> Void

    // MARK: Pickers

    func presentSendToDay(sceneIDs: [UUID]) {
        guard !sceneIDs.isEmpty else { return }
        present(PhoneMoveSheet(kind: .sendToDay(sceneIDs: sceneIDs)))
    }

    func presentSwapDay(dayID: UUID) {
        present(PhoneMoveSheet(kind: .swapDay(dayID: dayID)))
    }

    func presentAddScenes(dayID: UUID) {
        present(PhoneMoveSheet(kind: .addScenes(dayID: dayID)))
    }

    // MARK: Edits, one each

    /// Send to Day: the scenes with `ids` to the end of `dayID`.
    func sendToDay(_ ids: [UUID], to dayID: UUID) {
        edit(L("Send to Day")) { data in
            let touched = data.daysHolding(ids) + [dayID]
            guard ScheduleMoves.moveScenes(ids, to: SceneDropDestination(dayID: dayID), days: &data.shootDays, boneyard: &data.allScenes) else { return }
            data.syncAutoMeals(of: touched)
        }
    }

    /// Move to Next Day / Move to Previous Day: the scenes with `ids`, on `dayID`, to the
    /// end of the adjacent day of the schedule (`ScheduleMoves.adjacentDayID`: the next
    /// entry of `shootDays`, empty or typed days included, which is what "tomorrow" means
    /// to a scheduler reading the board). Nothing happens at the first or last day.
    func moveToAdjacentDay(_ ids: [UUID], from dayID: UUID, _ direction: DayDirection) {
        edit(direction == .next ? L("Move to Next Day") : L("Move to Previous Day")) { data in
            guard let target = ScheduleMoves.adjacentDayID(of: dayID, direction, in: data.shootDays) else { return }
            guard ScheduleMoves.moveScenes(ids, to: SceneDropDestination(dayID: target), days: &data.shootDays, boneyard: &data.allScenes) else { return }
            data.syncAutoMeals(of: [dayID, target])
        }
    }

    /// A reorder in one day's list, as `onMove` reports it over the strips it shows.
    func reorder(_ displayed: [UUID], fromOffsets source: IndexSet, toOffset destination: Int, in dayID: UUID) {
        edit(L("Reorder Scenes")) { data in
            guard ScheduleMoves.reorderStrips(displayed, fromOffsets: source, toOffset: destination, in: dayID, days: &data.shootDays) else { return }
            data.syncAutoMeals(of: [dayID])
        }
    }

    /// Add Scenes: the checked Boneyard scenes, in the Boneyard's display order, to the
    /// end of `dayID`.
    func addScenes(_ selected: Set<UUID>, inDisplayOrder displayOrder: [UUID], to dayID: UUID) {
        edit(selected.count == 1 ? L("Add Scene") : L("Add Scenes")) { data in
            guard ScheduleMoves.addScenes(selected, inDisplayOrder: displayOrder, to: dayID, days: &data.shootDays, boneyard: &data.allScenes) else { return }
            data.syncAutoMeals(of: [dayID])
        }
    }

    /// Swap with Day: everything the two days hold, exchanged.
    func swapDays(_ first: UUID, with second: UUID) {
        edit(L("Swap Days")) { data in
            ScheduleMoves.swapDays(first, second, in: &data.shootDays)
        }
    }

    /// The swipe back to the Boneyard (script scenes only; the pure move ignores events).
    func returnToBoneyard(_ ids: [UUID]) {
        edit(L("Return to Boneyard")) { data in
            let touched = data.daysHolding(ids)
            guard ScheduleMoves.returnToBoneyard(ids, days: &data.shootDays, boneyard: &data.allScenes) else { return }
            data.syncAutoMeals(of: touched)
        }
    }
}

// MARK: - Auto-meals of the days a move touched

private extension ProjectData {
    /// The ids of the days holding any of `ids`, before a move takes them away.
    func daysHolding(_ ids: [UUID]) -> [UUID] {
        let wanted = Set(ids)
        return shootDays.filter { day in day.scenes.contains { wanted.contains($0.id) } }.map(\.id)
    }

    /// Brings the auto-meal strips of `dayIDs` in line with their call sheets; a day whose
    /// strips already match is left as it is.
    mutating func syncAutoMeals(of dayIDs: [UUID]) {
        for dayID in Set(dayIDs) {
            guard let i = shootDays.firstIndex(where: { $0.id == dayID }) else { continue }
            let synced = shootDays[i].scenesWithSyncedAutoMeals()
            if synced != shootDays[i].scenes { shootDays[i].scenes = synced }
        }
    }
}

// MARK: - Presenting the pickers

extension View {
    /// Presents the picker a move asked for (`PhoneEditor.moveSheet`) and applies the
    /// pick through `moves`. `boneyard` is the Boneyard in its display order (the
    /// derived state's sorted Boneyard), what Add Scenes lists and the order it adds in.
    func phoneMoveSheets(_ sheet: Binding<PhoneMoveSheet?>, document: ProjectDocument,
                         boneyard: [Scene], moves: PhoneMoves) -> some View {
        self.sheet(item: sheet) { request in
            PhoneMoveSheetContent(request: request, document: document, boneyard: boneyard, moves: moves) {
                sheet.wrappedValue = nil
            }
        }
    }
}

/// The sheet's body for one request: the day picker titled for Send to Day or Swap with
/// Day, or the Add Scenes list.
private struct PhoneMoveSheetContent: View {
    let request:  PhoneMoveSheet
    let document: ProjectDocument
    let boneyard: [Scene]
    let moves:    PhoneMoves
    let dismiss:  () -> Void

    private var shootDays: [ShootDay] { document.project.shootDays }

    var body: some View {
        switch request.kind {
        case .sendToDay(let sceneIDs):
            SendToDaySheet(
                shootDays:  shootDays,
                sceneCount: sceneIDs.count,
                onSelect: { dayID in
                    moves.sendToDay(sceneIDs, to: dayID)
                    dismiss()
                },
                onCancel: dismiss
            )
        case .swapDay(let dayID):
            let dayNumbers = productionDayNumbers(for: shootDays)
            let name = shootDays.first { $0.id == dayID }.map { DaySummary.label(dayNumber: dayNumbers[$0.id], date: $0.date) } ?? L("this day")
            SendToDaySheet(
                shootDays:        shootDays,
                sceneCount:       0,
                title:            L("Swap with Day"),
                subtitle:         "\(L("Exchange everything on")) \(name) \(L("with the day you pick"))",
                actionTitle:      L("Swap"),
                unavailableDayID: dayID,
                onSelect: { other in
                    moves.swapDays(dayID, with: other)
                    dismiss()
                },
                onCancel: dismiss
            )
        case .addScenes(let dayID):
            let dayNumbers = productionDayNumbers(for: shootDays)
            let day        = shootDays.first { $0.id == dayID }
            AddScenesSheet(
                dayName: day.map { DaySummary.label(dayNumber: dayNumbers[$0.id], date: $0.date) } ?? "",
                boneyard: boneyard,
                onAdd: { selected in
                    moves.addScenes(selected, inDisplayOrder: boneyard.map(\.id), to: dayID)
                    dismiss()
                },
                onCancel: dismiss
            )
        }
    }
}

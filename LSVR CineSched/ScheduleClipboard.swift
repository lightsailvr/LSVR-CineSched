// ScheduleClipboard.swift
// Copy, cut and paste of scenes (#22), the pure part. The editor's Copy puts the selected
// scenes on the pasteboard as one `ScheduleDragPayload` of kind `.sceneCopies`: the
// scenes by value, in board order, because a paste may land in another project (a second
// window on the Mac or the iPad), where this project's ids mean nothing. A paste inserts
// them as new scenes with new ids, everything else as copied, so pasting twice gives two
// scenes and a paste into the same project never duplicates an id. Cut is Copy plus
// `remove`, one edit through the funnel, so it undoes as one step.
//
// Where a paste lands follows the editor's selection (`EditorSelection`): after the
// selected strip, at the end of the selected day, or into the Boneyard when nothing (or a
// Boneyard scene) is selected. The Boneyard takes script scenes only: a banner or a
// calendar event pasted with nothing selected is dropped, as the Boneyard has never held
// one. Auto-meal strips are never copied; the Stripboard writes them from the call sheet
// and a pasted one would be a stray it cannot account for.
//
// The editor wires these to the system's Copy, Cut and Paste in
// ContentView+Clipboard.swift, through the first responder in
// PlatformPasteboardResponder.swift, which moves the payload's pasteboard bytes (below).

import Foundation

// MARK: - The pasteboard's bytes

extension ScheduleDragPayload {
    /// What Copy puts on the pasteboard: the same JSON the drag's transfer
    /// representation carries (`CodableRepresentation`'s default coders), under the same
    /// type, so a drop and a paste read one shape.
    nonisolated func pasteboardData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    nonisolated init(pasteboardData: Data) throws {
        self = try JSONDecoder().decode(ScheduleDragPayload.self, from: pasteboardData)
    }
}

// MARK: - Where a paste lands

nonisolated enum PasteDestination: Hashable, Sendable {
    /// Appended to the Boneyard (script scenes only).
    case boneyard
    /// On a day, before one of its strips or at its end.
    case day(SceneDropDestination)
}

// MARK: - The clipboard's moves

enum ScheduleClipboard {

    /// The scenes Copy carries for `ids`, in board order (the Boneyard first, then the
    /// days), without auto-meal strips; ids the project does not have are ignored.
    static func scenes(copying ids: Set<UUID>, in project: ProjectData) -> [Scene] {
        guard !ids.isEmpty else { return [] }
        var copies = project.allScenes.filter { ids.contains($0.id) && !$0.isAutoMeal }
        for day in project.shootDays {
            copies.append(contentsOf: day.scenes.filter { ids.contains($0.id) && !$0.isAutoMeal })
        }
        return copies
    }

    /// The pasteboard payload for `ids`, nil when nothing copiable is among them (Copy
    /// then puts nothing on the pasteboard, and Cut removes nothing).
    static func payload(copying ids: Set<UUID>, in project: ProjectData) -> ScheduleDragPayload? {
        let copies = scenes(copying: ids, in: project)
        guard !copies.isEmpty else { return nil }
        return ScheduleDragPayload(.sceneCopies(copies))
    }

    /// Where a paste lands for the editor's selection: right after a selected strip (before
    /// the next strip of its day, or at the day's end), at the end of a selected day, the
    /// Boneyard for a selected Boneyard scene, for nothing, or for a selection whose
    /// target is gone.
    static func destination(for selection: EditorSelection?, in project: ProjectData) -> PasteDestination {
        switch selection {
        case .day(let id):
            guard project.dayIndex(forDayID: id) != nil else { return .boneyard }
            return .day(SceneDropDestination(dayID: id))
        case .scene(let id):
            guard case .scheduled(let dayIndex, let sceneIndex) = project.locate(sceneID: id) else { return .boneyard }
            let day  = project.shootDays[dayIndex]
            let next = day.scenes.indices.contains(sceneIndex + 1) ? day.scenes[sceneIndex + 1].id : nil
            return .day(SceneDropDestination(dayID: day.id, position: next.map { .before($0) } ?? .end))
        case nil:
            return .boneyard
        }
    }

    /// Inserts `scenes` at `destination` as new scenes (new ids, everything else as
    /// copied) and returns the new ids in insertion order, so the editor can select
    /// them. Nothing is inserted, and nothing returned, for a day the project does not
    /// have; the Boneyard takes script scenes only.
    @discardableResult
    static func paste(_ scenes: [Scene], at destination: PasteDestination, into project: inout ProjectData) -> [UUID] {
        var copies = scenes
        for index in copies.indices { copies[index].id = UUID() }

        switch destination {
        case .boneyard:
            copies.removeAll { $0.isBanner || $0.isCalendarEvent }
            project.allScenes.append(contentsOf: copies)
        case .day(let target):
            guard let dayIndex = project.dayIndex(forDayID: target.dayID) else { return [] }
            var insertAt = project.shootDays[dayIndex].scenes.count
            if case .before(let anchor) = target.position,
               let anchorIndex = project.shootDays[dayIndex].scenes.firstIndex(where: { $0.id == anchor }) {
                insertAt = anchorIndex
            }
            project.shootDays[dayIndex].scenes.insert(contentsOf: copies, at: insertAt)
        }
        return copies.map(\.id)
    }

    /// Cut's removal: takes the scenes with `ids` out of the Boneyard and the days.
    /// Returns false, changing nothing, when none of them is in the project.
    @discardableResult
    static func remove(_ ids: Set<UUID>, from project: inout ProjectData) -> Bool {
        guard !ids.isEmpty else { return false }
        var removed = false
        let boneyardCount = project.allScenes.count
        project.allScenes.removeAll { ids.contains($0.id) }
        removed = project.allScenes.count != boneyardCount
        for dayIndex in project.shootDays.indices {
            let count = project.shootDays[dayIndex].scenes.count
            project.shootDays[dayIndex].scenes.removeAll { ids.contains($0.id) }
            if project.shootDays[dayIndex].scenes.count != count { removed = true }
        }
        return removed
    }
}

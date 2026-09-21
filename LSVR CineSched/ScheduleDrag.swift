// ScheduleDrag.swift
// What a drag on the schedule carries and what its drop does (#18). Every drag in the
// app, on the Mac and by touch on the iPad, is one `ScheduleDragPayload`: the scenes being
// moved (one or many, with the day they left or nil for the Boneyard), a whole day from its
// handle, a day-type band, or a calendar-event chip. It is a `Transferable` on its own
// exported type, so the system's drag containers, reorder containers and drop
// destinations carry it typed, and a drop switches on the kind instead of parsing a
// string. Before #18 the payload was one of three `NSString` encodings ("day:", "daytype:"
// or comma-joined scene ids) read back through `NSItemProvider` in two drop delegates.
//
// The same payload is what Copy and Cut put on the pasteboard (#22), as its one kind that
// carries scenes by value rather than by id: a paste may land in another project, where
// the ids mean nothing, so the copies travel whole and are inserted with fresh ids
// (ScheduleClipboard.swift). A drag never carries that kind today.
//
// The drop side is here too, as pure functions over `[ShootDay]` and the Boneyard, so the
// calendar and the Stripboard apply the same move and a test can pin it: `moveScenes`
// places scenes before a strip or at the end of a day whether they come from the Boneyard,
// the same day or another day (a reorder is the difference the system reports, applied
// through the same function); `returnToBoneyard` is the drop on the Boneyard. The views
// wrap each in one edit gesture so a drag undoes as one step. The iPhone's moves (#25)
// are three more over the same arrays: `reorderStrips` turns a list's `onMove` offsets
// into one `moveScenes`, `addScenes` lands the checked Boneyard scenes in display order,
// and `swapDays` exchanges everything two days hold (the day handle's swap, as a pure
// function the phone's Swap with Day calls; the Mac's two private copies are untouched).
//
// The payload is never persisted: it lives for the length of one drag, so its shape is
// free to change (no `CodingKeys` promise, unlike the project file).

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Content type

extension UTType {
    /// `com.lsvr.cinesched.drag-payload`, the type the drag pasteboard carries the payload
    /// as. Declared in Config/Info.plist beside the project type (ADR 0005) so the system
    /// resolves it; conforms to `public.data` because it is an in-app blob, not a file.
    nonisolated static let cineschedDragPayload = UTType(exportedAs: "com.lsvr.cinesched.drag-payload", conformingTo: .data)
}

// MARK: - Payload

/// One drag's contents. `Identifiable` because the drag containers address their items by
/// id: for scenes the dragged (first) scene's, for a day or a band the day's, for an event
/// the event's.
nonisolated struct ScheduleDragPayload: Codable, Hashable, Identifiable, Sendable {

    enum Kind: Codable, Hashable, Sendable {
        /// Script scenes (calendar events among them on the calendar, where they are strips),
        /// in board order. `originDayID` is the day the drag started on, nil for the Boneyard;
        /// a drop does not depend on it (it looks the scenes up), but the Boneyard uses it to
        /// ignore a drag that started on itself.
        case scenes(ids: [UUID], originDayID: UUID?)
        /// The whole day (scenes, call sheet, type, note) from its three-line handle: swaps
        /// with the day it lands on.
        case day(id: UUID)
        /// The day-type band: moves only the type and the note to the day it lands on.
        case dayType(dayID: UUID)
        /// A calendar-event chip on the Stripboard: moves the event to the day it lands on.
        case calendarEvent(id: UUID, dayID: UUID)
        /// Scenes by value, from Copy or Cut (#22): what a paste inserts, as new scenes
        /// with new ids, wherever it lands. Nothing on the board is addressed by it.
        case sceneCopies([Scene])
    }

    var kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    /// The scenes payload for one or several scenes; `ids` must not be empty.
    static func scenes(_ ids: [UUID], from originDayID: UUID?) -> ScheduleDragPayload {
        ScheduleDragPayload(.scenes(ids: ids, originDayID: originDayID))
    }

    var id: UUID {
        switch kind {
        case .scenes(let ids, _):       return ids.first ?? UUID()
        case .day(let id):              return id
        case .dayType(let dayID):       return dayID
        case .calendarEvent(let id, _): return id
        case .sceneCopies(let scenes):  return scenes.first?.id ?? UUID()
        }
    }

    /// The scene ids a drop moves, whatever the kind called them: the scenes of a scenes
    /// payload, the event of an event payload, nothing for a day, a band or copies (a
    /// copy's scenes are not on this board; they are inserted, not moved).
    var sceneIDs: [UUID] {
        switch kind {
        case .scenes(let ids, _):       return ids
        case .calendarEvent(let id, _): return [id]
        case .day, .dayType, .sceneCopies: return []
        }
    }

    /// The scenes a paste inserts: the copies of a copies payload, nothing otherwise.
    var copiedScenes: [Scene] {
        if case .sceneCopies(let scenes) = kind { return scenes }
        return []
    }
}

// `nonisolated`: the system encodes and decodes the payload off the main actor, and an
// extension does not inherit the struct's `nonisolated` (learnings.md, 2026-09-19 #15).
nonisolated extension ScheduleDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cineschedDragPayload)
    }
}

// MARK: - Where a scene drop lands

/// A day and a place in its strip list: before one of its scenes, or after the last.
nonisolated struct SceneDropDestination: Hashable, Sendable {
    enum Position: Hashable, Sendable {
        case before(UUID)
        case end
    }

    var dayID: UUID
    var position: Position

    init(dayID: UUID, position: Position = .end) {
        self.dayID    = dayID
        self.position = position
    }
}

// MARK: - The moves a drop makes

enum ScheduleMoves {

    /// Moves the scenes with `ids`, from the Boneyard or from any day, to `destination`.
    /// Boneyard scenes keep the order `ids` gives them (the Boneyard's display order);
    /// scheduled scenes go in board order. Dropping before a scene that is itself moving
    /// lands before the next strip of that day that is not, or at the end. Returns false,
    /// changing nothing, when no scene has those ids or no day has that id.
    @discardableResult
    static func moveScenes(_ ids: [UUID], to destination: SceneDropDestination,
                           days: inout [ShootDay], boneyard: inout [Scene]) -> Bool {
        guard let targetIndex = days.firstIndex(where: { $0.id == destination.dayID }) else { return false }
        let moving = Set(ids)

        // Resolve the anchor before anything moves, so an anchor that is moving still
        // names the strip after it.
        var anchorID: UUID? = nil
        if case .before(let before) = destination.position {
            anchorID = before
            if moving.contains(before),
               let position = days[targetIndex].scenes.firstIndex(where: { $0.id == before }) {
                anchorID = days[targetIndex].scenes[position...].first { !moving.contains($0.id) }?.id
            }
        }

        var scenes = ids.compactMap { id in boneyard.first { $0.id == id } }
        boneyard.removeAll { moving.contains($0.id) }
        for dayIndex in days.indices {
            scenes.append(contentsOf: days[dayIndex].scenes.filter { moving.contains($0.id) })
            days[dayIndex].scenes.removeAll { moving.contains($0.id) }
        }
        guard !scenes.isEmpty else { return false }

        let insertAt = anchorID.flatMap { anchor in days[targetIndex].scenes.firstIndex { $0.id == anchor } }
            ?? days[targetIndex].scenes.count
        days[targetIndex].scenes.insert(contentsOf: scenes, at: insertAt)
        return true
    }

    /// Returns the scheduled scenes with `ids` to the Boneyard, in board order. Calendar
    /// events are not Boneyard material and stay on their day; Boneyard ids are already
    /// there. Returns false, changing nothing, when nothing moved.
    @discardableResult
    static func returnToBoneyard(_ ids: [UUID], days: inout [ShootDay], boneyard: inout [Scene]) -> Bool {
        let moving = Set(ids)
        var returned: [Scene] = []
        for dayIndex in days.indices {
            let matches = days[dayIndex].scenes.filter { moving.contains($0.id) && !$0.isCalendarEvent }
            guard !matches.isEmpty else { continue }
            returned.append(contentsOf: matches)
            let returnedIDs = Set(matches.map(\.id))
            days[dayIndex].scenes.removeAll { returnedIDs.contains($0.id) }
        }
        guard !returned.isEmpty else { return false }
        boneyard.append(contentsOf: returned)
        return true
    }

    // MARK: The iPhone's moves (#25)

    /// A list's reorder as one move: `displayed` is the strip ids the list shows for the
    /// day (its scenes without the calendar events, in order), `source` and `destination`
    /// are what `onMove` reports (the offsets lifted, and the offset of the strip they land
    /// before, `displayed.count` for the end). Becomes a `moveScenes` before that strip,
    /// so a strip the list does not show keeps its place. Returns false, changing nothing,
    /// when the day is unknown, the offsets name nothing, or the order would not change.
    @discardableResult
    static func reorderStrips(_ displayed: [UUID], fromOffsets source: IndexSet, toOffset destination: Int,
                              in dayID: UUID, days: inout [ShootDay]) -> Bool {
        let moving = source.compactMap { displayed.indices.contains($0) ? displayed[$0] : nil }
        guard !moving.isEmpty, let dayIndex = days.firstIndex(where: { $0.id == dayID }) else { return false }

        let anchor: SceneDropDestination.Position = displayed.indices.contains(destination)
            ? .before(displayed[destination])
            : .end
        var reordered = days
        var noBoneyard: [Scene] = []
        guard moveScenes(moving, to: SceneDropDestination(dayID: dayID, position: anchor), days: &reordered, boneyard: &noBoneyard)
        else { return false }
        // Judge "changed" by the order the list shows: a drop back onto a strip's own
        // place can still hop it over a hidden event, which is no move to the user.
        let shown = Set(displayed)
        guard reordered[dayIndex].scenes.map(\.id).filter(shown.contains) != displayed else { return false }
        days = reordered
        return true
    }

    /// Add Scenes: the checked Boneyard scenes land at the end of the day in the order the
    /// Boneyard shows them (`displayOrder`, the sorted Boneyard's ids), not the order they
    /// were checked in. An id outside `displayOrder` (a scheduled scene, a stale check) is
    /// ignored. Returns false, changing nothing, when nothing lands.
    @discardableResult
    static func addScenes(_ selected: Set<UUID>, inDisplayOrder displayOrder: [UUID], to dayID: UUID,
                          days: inout [ShootDay], boneyard: inout [Scene]) -> Bool {
        let ordered = displayOrder.filter { selected.contains($0) }
        guard !ordered.isEmpty else { return false }
        return moveScenes(ordered, to: SceneDropDestination(dayID: dayID), days: &days, boneyard: &boneyard)
    }

    /// Swap with day: exchanges everything the two days hold — scenes (the calendar events
    /// among them), the call sheet, the day type and the day note — while each day keeps
    /// its date and its id, the "nothing is anchored to a date" invariant the Mac's day
    /// handle applies (`StripboardView.handleDayRearrange`, `CalendarView.swapDayContents`,
    /// which remain their own copies). Returns false, changing nothing, for the same day
    /// twice or an unknown id.
    @discardableResult
    static func swapDays(_ first: UUID, _ second: UUID, in days: inout [ShootDay]) -> Bool {
        guard first != second,
              let a = days.firstIndex(where: { $0.id == first }),
              let b = days.firstIndex(where: { $0.id == second })
        else { return false }
        let scenes    = days[a].scenes
        let callSheet = days[a].callSheet
        let dayType   = days[a].dayType
        let dayNote   = days[a].dayNote
        days[a].scenes    = days[b].scenes
        days[a].callSheet = days[b].callSheet
        days[a].dayType   = days[b].dayType
        days[a].dayNote   = days[b].dayNote
        days[b].scenes    = scenes
        days[b].callSheet = callSheet
        days[b].dayType   = dayType
        days[b].dayNote   = dayNote
        return true
    }
}

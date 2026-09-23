// ShotEdits.swift
// A scene's shot list (#37), the pure part: the counterpart of DayEdits.swift for shots.
//
// A shot's letter is its position (A…Z, then AA, AB, … like spreadsheet columns) and its
// displayed number is the scene's number followed by that letter with no separator (12A;
// 12AA for a shot in scene 12A), so nothing is stored and a reorder never renumbers.
//
// Every change to a scene's shots goes through the edits below, which exist twice: as
// `mutating` methods on `Scene` (what the scene editor's draft runs, #39, since it holds a
// `Scene` value and not a project) and as `ProjectData` methods addressed by scene id and
// shot id (the board, the phone and any `edit` closure), which find the scene wherever it
// is — the Boneyard or any day — through `locate(sceneID:)` and call the `Scene` ones. Each
// returns false (or nil) and changes nothing when its scene or shot is gone, and each ends
// with two rules:
//
// - **The estimate rule.** While the scene has at least one shot, its `estimatedTime` is
//   written as the sum of the shots' `durationMinutes`. The estimate is written, not
//   derived, so the time cascade, the day totals, the strip's time and every exporter keep
//   reading `estimatedTime` and learn nothing about shots. A scene whose last shot is
//   removed keeps the last sum, editable again; a scene with no shots is never touched.
// - **The frame rule.** A scene with no shots can carry a storyboard frame of its own; the
//   first shot added takes it (unless that shot brings its own) and the scene's is cleared,
//   so a scene with shots never carries a frame and a board is never shown twice.
//
// The breakdown's Props, Special Equipment and SFX read the union of the scene's items and
// every shot's (`allProps`, `allSpecialEquipment` — fed by a shot's `equipment` — and
// `allSFX`), computed on read: the scene editor keeps editing the scene-level lists.

import Foundation

// MARK: - Letters and numbers

extension Shot {
    /// The letter for position `index`: 0 → A, 25 → Z, 26 → AA, 27 → AB, 701 → ZZ,
    /// 702 → AAA (bijective base 26). Empty for a negative index.
    nonisolated static func letter(forIndex index: Int) -> String {
        guard index >= 0 else { return "" }
        var scalars: [Character] = []
        var n = index + 1
        while n > 0 {
            let remainder = (n - 1) % 26
            scalars.append(Character(UnicodeScalar(UInt8(65 + remainder))))
            n = (n - 1) / 26
        }
        return String(scalars.reversed())
    }
}

extension Scene {
    /// The number shots are lettered after: the scene number field, else a number leading
    /// the title (scenes saved before the field existed), else nothing — never the "1"
    /// `extractedSceneNumber` falls back to, which would letter an unnumbered scene 1A.
    var shotNumberPrefix: String {
        Self.shotNumberPrefix(sceneNumber: sceneNumber, title: title)
    }

    /// The same over the two fields, for the scene editor's draft, which holds them as typed.
    static func shotNumberPrefix(sceneNumber: String, title: String) -> String {
        let field = sceneNumber.trimmingCharacters(in: .whitespaces)
        if !field.isEmpty { return field }
        let title = title.trimmingCharacters(in: .whitespaces)
        guard let match = leadingNumber.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let found = Range(match.range, in: title) else { return "" }
        return String(title[found]).replacingOccurrences(of: "#", with: "")
    }

    /// "12", "#12A" leading a title. Built once: the prefix is read per strip on a redraw.
    private static let leadingNumber = try! NSRegularExpression(pattern: #"^#?\d+[A-Za-z]?"#)

    /// The one way a shot number is made: the prefix followed by the letter at `index`.
    static func shotNumber(prefix: String, index: Int) -> String {
        prefix + Shot.letter(forIndex: index)
    }

    /// Every shot's displayed number, in order, for one prefix lookup per list: what a
    /// list of shot rows reads (the editor's Shots section, the Stripboard's sub-rows, the
    /// phone's rows) rather than a number worked out per row.
    var shotNumbers: [String] {
        Self.shotNumbers(prefix: shotNumberPrefix, count: shots.count)
    }

    static func shotNumbers(prefix: String, count: Int) -> [String] {
        (0..<max(0, count)).map { shotNumber(prefix: prefix, index: $0) }
    }

    /// The displayed number of the shot at `index`: "12A", "12AA" in scene 12A.
    func shotNumber(at index: Int) -> String {
        Self.shotNumber(prefix: shotNumberPrefix, index: index)
    }

    /// The displayed number of the shot with `id`; nil when the scene has no such shot.
    func shotNumber(forShotID id: UUID) -> String? {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return nil }
        return shotNumber(at: index)
    }
}

// MARK: - Where a dropped shot lands

/// Where a shot moved by a drop lands within its scene: before another shot, or at the
/// end. The shot counterpart of `SceneDropDestination.Position`; a shot never leaves its
/// scene, so no scene is named.
nonisolated enum ShotDropPosition: Hashable, Sendable {
    case before(UUID)
    case end
}

// MARK: - The rules

extension Scene {
    /// The sum the estimate rule writes; nil for a scene with no shots.
    var shotEstimate: Int? {
        shots.isEmpty ? nil : shots.reduce(0) { $0 + $1.durationMinutes }
    }

    /// The estimate rule: the sum of the durations into `estimatedTime` while there are
    /// shots; nothing when there are none. Every edit below ends with it; call it after
    /// writing `shots` any other way.
    mutating func applyShotEstimate() {
        if let sum = shotEstimate { estimatedTime = sum }
    }

    /// Every shot under a new id, everything else kept: what a duplicated or pasted scene
    /// does so no two scenes share a shot id.
    mutating func refreshShotIDs() {
        for index in shots.indices { shots[index].id = UUID() }
    }
}

// MARK: - The edits on a scene

extension Scene {

    /// Adds `shot` at the end, or right after the shot with id `previousID`. The first shot
    /// of a scene takes the scene's frame (the frame rule). False, changing nothing, for a
    /// notice strip, an anchor the scene does not have, or a shot id it already has.
    @discardableResult
    mutating func addShot(_ shot: Shot, after previousID: UUID? = nil) -> Bool {
        guard !isBanner, !isCalendarEvent, !shots.contains(where: { $0.id == shot.id }) else { return false }
        var insertAt = shots.endIndex
        if let previousID {
            guard let anchor = shots.firstIndex(where: { $0.id == previousID }) else { return false }
            insertAt = anchor + 1
        }
        var added = shot
        if shots.isEmpty {
            if added.frame == nil { added.frame = frame }
            frame = nil
        }
        shots.insert(added, at: insertAt)
        applyShotEstimate()
        return true
    }

    /// Replaces the shot with `shot.id` in place. False when the scene has no such shot.
    @discardableResult
    mutating func updateShot(_ shot: Shot) -> Bool {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }) else { return false }
        shots[index] = shot
        applyShotEstimate()
        return true
    }

    /// Removes the shot with `id`. The last one leaves its sum as the estimate.
    @discardableResult
    mutating func removeShot(withID id: UUID) -> Bool {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return false }
        shots.remove(at: index)
        applyShotEstimate()
        return true
    }

    /// A list's `onMove`: the shots at `source` to `destination`, an offset into the list
    /// before the move (the count for the end), keeping their order. False for an empty or
    /// out-of-range source, an out-of-range destination, or a move that changes nothing.
    @discardableResult
    mutating func moveShots(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        guard let first = source.first, first >= 0,
              let last = source.last, last < shots.count,
              destination >= 0, destination <= shots.count
        else { return false }
        let moving    = source.map { shots[$0] }
        var remaining = shots.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt  = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: insertAt)
        guard remaining.map(\.id) != shots.map(\.id) else { return false }
        shots = remaining
        applyShotEstimate()
        return true
    }

    /// A drop: the shot with `id` before another shot of the scene, or at the end. False
    /// for a shot or anchor the scene does not have, or a drop that changes nothing.
    @discardableResult
    mutating func moveShot(withID id: UUID, to position: ShotDropPosition) -> Bool {
        guard let from = shots.firstIndex(where: { $0.id == id }) else { return false }
        let destination: Int
        switch position {
        case .end:
            destination = shots.count
        case .before(let anchorID):
            guard let anchor = shots.firstIndex(where: { $0.id == anchorID }) else { return false }
            destination = anchor
        }
        return moveShots(fromOffsets: IndexSet(integer: from), toOffset: destination)
    }

    /// A copy of the shot with `id` (new id; the same description, duration, lists and
    /// frame) right after it. Returns the copy's id; nil when the scene has no such shot.
    @discardableResult
    mutating func duplicateShot(withID id: UUID) -> UUID? {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = shots[index]
        copy.id = UUID()
        shots.insert(copy, at: index + 1)
        applyShotEstimate()
        return copy.id
    }
}

// MARK: - The edits on a project

extension ProjectData {

    /// `Scene.addShot(_:after:)` on the scene with `sceneID`, wherever it is.
    @discardableResult
    mutating func addShot(_ shot: Shot, toSceneID sceneID: UUID, after previousID: UUID? = nil) -> Bool {
        editScene(sceneID) { $0.addShot(shot, after: previousID) }
    }

    /// `Scene.updateShot(_:)` on the scene with `sceneID`.
    @discardableResult
    mutating func updateShot(_ shot: Shot, inSceneID sceneID: UUID) -> Bool {
        editScene(sceneID) { $0.updateShot(shot) }
    }

    /// `Scene.removeShot(withID:)` on the scene with `sceneID`.
    @discardableResult
    mutating func removeShot(withID id: UUID, fromSceneID sceneID: UUID) -> Bool {
        editScene(sceneID) { $0.removeShot(withID: id) }
    }

    /// `Scene.moveShots(fromOffsets:toOffset:)` on the scene with `sceneID`.
    @discardableResult
    mutating func moveShots(inSceneID sceneID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        editScene(sceneID) { $0.moveShots(fromOffsets: source, toOffset: destination) }
    }

    /// `Scene.moveShot(withID:to:)` on the scene with `sceneID`.
    @discardableResult
    mutating func moveShot(withID id: UUID, inSceneID sceneID: UUID, to position: ShotDropPosition) -> Bool {
        editScene(sceneID) { $0.moveShot(withID: id, to: position) }
    }

    /// `Scene.duplicateShot(withID:)` on the scene with `sceneID`; the copy's id.
    @discardableResult
    mutating func duplicateShot(withID id: UUID, inSceneID sceneID: UUID) -> UUID? {
        var copyID: UUID?
        editScene(sceneID) { scene in
            copyID = scene.duplicateShot(withID: id)
            return copyID != nil
        }
        return copyID
    }

    /// Runs `change` on the scene with `id`, wherever it is, and writes it back by id
    /// (`replaceScene`) only when the change succeeded, so a refused edit leaves the
    /// project untouched. False when no scene has that id.
    @discardableResult
    private mutating func editScene(_ id: UUID, _ change: (inout Scene) -> Bool) -> Bool {
        guard var scene = scene(withID: id), change(&scene) else { return false }
        return replaceScene(scene)
    }
}

// MARK: - The breakdown unions

extension Scene {
    /// Props for the breakdown: the scene's, then each shot's, in first-seen order.
    var allProps: [String] {
        Scene.breakdownUnion(props, shots.map(\.props))
    }

    /// Special Equipment for the breakdown: the scene's, then each shot's equipment.
    var allSpecialEquipment: [String] {
        Scene.breakdownUnion(specialEquipment, shots.map(\.equipment))
    }

    /// SFX for the breakdown: the scene's, then each shot's.
    var allSFX: [String] {
        Scene.breakdownUnion(sfx, shots.map(\.sfx))
    }

    /// The scene's items then every shot's, each trimmed, blanks dropped, and an item whose
    /// case-insensitive spelling came earlier dropped (the first spelling is kept).
    nonisolated static func breakdownUnion(_ sceneItems: [String], _ shotItems: [[String]]) -> [String] {
        var seen:   Set<String> = []
        var result: [String]    = []
        for item in sceneItems + shotItems.joined() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

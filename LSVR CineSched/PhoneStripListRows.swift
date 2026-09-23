// PhoneStripListRows.swift
// A day's strips as the iPhone's Days list and Day screen show them once shots can expand
// (#43), pure (`PhoneStripListRowsTests`). An expanded script scene's strip is followed by
// one row per shot (its number after the scene's, "12A", computed once per strip — the
// prefix can fall back to a pattern match on the slugline — never per row), or, while it
// has none, one row offering Add Shot…, the Stripboard's "No shots" line (#42). A banner,
// an auto-meal or a calendar event never expands; which strips are expanded is the
// editor's `ShotExpansion`, the Mac's rule.
//
// The extra rows sit in the same `ForEach` as the strips, because a `List` cannot nest
// rows under a row, so its `onMove` offsets count them. `stripMove` maps those offsets
// back onto the strips alone before they reach `PhoneMoves.reorder`: the sub-rows are
// `moveDisabled`, so only strips are ever lifted, and a drop point is "after however many
// strips precede it" (between a strip and its own shots lands after that strip). So a
// reorder moves strips, the shots travelling inside their scene, and never a shot: shots
// reorder only in the scene editor (story 48 of #36).

import Foundation

// MARK: - A row

/// One row of a day's strip list: a strip, one of an expanded scene's shots, or the line
/// an expanded shotless scene shows.
struct PhoneStripListRow: Identifiable {
    enum Kind {
        case strip
        case shot(Shot, number: String)
        case noShots
    }

    /// Stable across redraws: a strip and its "no shots" line by the scene, a shot by its own id.
    enum ID: Hashable {
        case strip(UUID)
        case shot(UUID)
        case noShots(UUID)
    }

    /// The strip's scene, or the scene a shot row belongs to.
    let scene: Scene
    let kind:  Kind

    var id: ID {
        switch kind {
        case .strip:             return .strip(scene.id)
        case .shot(let shot, _): return .shot(shot.id)
        case .noShots:           return .noShots(scene.id)
        }
    }

    var isStrip: Bool {
        if case .strip = kind { return true }
        return false
    }

    var shot: Shot? {
        if case .shot(let shot, _) = kind { return shot }
        return nil
    }

    var shotNumber: String? {
        if case .shot(_, let number) = kind { return number }
        return nil
    }
}

// MARK: - The rows and the moves

enum PhoneStripListRows {
    /// Whether a strip can show shots (and so carries the chevron): a script scene. A
    /// banner, an auto-meal and a calendar event have no shot list.
    static func showsShots(_ scene: Scene) -> Bool {
        !scene.isBanner && !scene.isCalendarEvent
    }

    /// `strips` in order, each expanded script scene followed by its shots, or by its
    /// "no shots" line when it has none.
    static func rows(for strips: [Scene], expansion: ShotExpansion) -> [PhoneStripListRow] {
        var rows: [PhoneStripListRow] = []
        rows.reserveCapacity(strips.count)
        for scene in strips {
            rows.append(PhoneStripListRow(scene: scene, kind: .strip))
            guard showsShots(scene), expansion.isExpanded(scene.id) else { continue }
            if scene.shots.isEmpty {
                rows.append(PhoneStripListRow(scene: scene, kind: .noShots))
            } else {
                let prefix = scene.shotNumberPrefix
                for (index, shot) in scene.shots.enumerated() {
                    rows.append(PhoneStripListRow(scene: scene, kind: .shot(shot, number: prefix + Shot.letter(forIndex: index))))
                }
            }
        }
        return rows
    }

    /// A move over the strips alone.
    struct StripMove: Equatable {
        let source:      IndexSet
        let destination: Int
    }

    /// The list's `onMove` offsets over `rows` as offsets over the strips alone: each
    /// moved strip by its place among the strips, the destination as the number of strips
    /// before it. Nil when the move carries no strip.
    static func stripMove(fromOffsets source: IndexSet, toOffset destination: Int, in rows: [PhoneStripListRow]) -> StripMove? {
        var stripIndex: [Int: Int] = [:]
        var count = 0
        for (index, row) in rows.enumerated() where row.isStrip {
            stripIndex[index] = count
            count += 1
        }
        let moving = IndexSet(source.compactMap { stripIndex[$0] })
        guard !moving.isEmpty else { return nil }
        let before = rows.prefix(max(0, min(destination, rows.count))).filter(\.isStrip).count
        return StripMove(source: moving, destination: before)
    }
}

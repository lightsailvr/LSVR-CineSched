// DerivedScheduleState.swift
// What the Mac editor shows that is computed from the whole project rather than stored in
// it: the Boneyard in its chosen sort, the conflict sets, the duplicate scene numbers and
// the schedule-lock drift. Pure functions of a `ProjectData`, so a test can check them
// without a view.
//
// `DerivedScheduleStateCache` is how `ContentView` reads them: at most one computation per
// change to the document, keyed on `ProjectDocument.changeCount` and the sort. Before #34
// the editor kept these in `@State` and recomputed them in `onChange(of: document.project)`,
// which compared two whole projects on every body pass and then wrote five state values,
// so every drop and every undo paid for a second full pass over the calendar.

import Foundation

// MARK: - Boneyard sort

enum BoneyardSort: String, CaseIterable {
    case showOrder    = "Show Order"
    case defaultOrder = "Default"
    case location     = "Location"
    case intExt       = "INT/EXT"
    case cast         = "Cast"
    case dayNight     = "Day/Night"

    var localizedTitle: String { L(rawValue) }
}

// MARK: - Derived state

struct DerivedScheduleState {
    /// The Boneyard's script scenes (banners excluded) in `boneyardSort` order, each with
    /// its index in `allScenes`, which is what the editors and delete actions address.
    var sortedBoneyard: [(index: Int, scene: Scene)]
    var conflictDates:            Set<Date>
    var conflictSceneIDs:         Set<UUID>
    var duplicateSceneNumberIDs:  Set<UUID>
    var scheduleLockChanges:      [ScheduleLockChange]
    var scheduleLockChangedDates: Set<Date>

    init(project: ProjectData, boneyardSort: BoneyardSort) {
        let info      = project.productionInfo ?? ProductionInfo()
        let conflicts = ConflictScanner.scan(shootDays: project.shootDays, productionInfo: info)
        sortedBoneyard           = Self.sortedBoneyard(of: project.allScenes, by: boneyardSort)
        conflictDates            = ConflictScanner.conflictDates(conflicts)
        conflictSceneIDs         = ConflictScanner.conflictSceneIDs(conflicts)
        duplicateSceneNumberIDs  = ConflictScanner.duplicateSceneNumberIDs(allScenes: project.allScenes, shootDays: project.shootDays)
        scheduleLockChanges      = ScheduleLockScanner.changes(shootDays: project.shootDays, productionInfo: info)
        scheduleLockChangedDates = ScheduleLockScanner.changedDates(scheduleLockChanges)
    }

    static func sortedBoneyard(of allScenes: [Scene], by sort: BoneyardSort) -> [(index: Int, scene: Scene)] {
        let indexed = allScenes.enumerated()
            .filter { !$0.element.isBanner }
            .map { (index: $0.offset, scene: $0.element) }
        switch sort {
        case .showOrder:
            return indexed.sorted {
                let a = $0.scene.scriptOrderKey
                let b = $1.scene.scriptOrderKey
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1 < b.1
            }
        case .defaultOrder:
            return indexed
        case .location:
            return indexed.sorted { locationSortKey($0.scene.title) < locationSortKey($1.scene.title) }
        case .intExt:
            return indexed.sorted {
                let a = intExtSortKey($0.scene.title)
                let b = intExtSortKey($1.scene.title)
                if a != b { return a < b }
                return locationSortKey($0.scene.title) < locationSortKey($1.scene.title)
            }
        case .cast:
            return indexed.sorted {
                let a = $0.scene.cast.sorted().first ?? "ZZZ"
                let b = $1.scene.cast.sorted().first ?? "ZZZ"
                return a < b
            }
        case .dayNight:
            return indexed.sorted {
                if $0.scene.dayNightType != $1.scene.dayNightType {
                    return $0.scene.dayNightType.sortOrder < $1.scene.dayNightType.sortOrder
                }
                return locationSortKey($0.scene.title) < locationSortKey($1.scene.title)
            }
        }
    }

    // MARK: Sort keys

    private static func stripSceneNumber(_ title: String) -> String {
        let pattern = #"^\d+[A-Za-z]?\.\s*"#
        if let range = title.range(of: pattern, options: .regularExpression) {
            return String(title[range.upperBound...])
        }
        return title
    }

    private static func locationSortKey(_ title: String) -> String {
        let withoutNumber = stripSceneNumber(title)
        let pattern = #"^(INT\.|EXT\.)\s*"#
        if let range = withoutNumber.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            return String(withoutNumber[range.upperBound...])
        }
        return withoutNumber
    }

    private static func intExtSortKey(_ title: String) -> String {
        let withoutNumber = stripSceneNumber(title)
        if withoutNumber.uppercased().hasPrefix("INT.") { return "INT." }
        if withoutNumber.uppercased().hasPrefix("EXT.") { return "EXT." }
        return "ZZZ"
    }
}

// MARK: - Cache

/// Memoizes `DerivedScheduleState` for one editor. Held in `@State` as a reference so the
/// view keeps it for its lifetime; its contents are not observed, and need not be: the
/// body pass that reads it is already driven by the document's `changeCount`.
final class DerivedScheduleStateCache {
    private struct Key: Equatable {
        var changeCount:  Int
        var boneyardSort: BoneyardSort
    }
    private var key:   Key?
    private var value: DerivedScheduleState?

    init() {}

    /// The derived state for `project` as of `changeCount`, computed only if the count or
    /// the sort differs from the last call. `project` is not inspected when the key matches.
    func state(for project: ProjectData, changeCount: Int, boneyardSort: BoneyardSort) -> DerivedScheduleState {
        let wanted = Key(changeCount: changeCount, boneyardSort: boneyardSort)
        if let value, key == wanted { return value }
        let fresh = DerivedScheduleState(project: project, boneyardSort: boneyardSort)
        key   = wanted
        value = fresh
        return fresh
    }
}

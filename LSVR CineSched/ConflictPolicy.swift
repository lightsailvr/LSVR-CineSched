// ConflictPolicy.swift
// What CineSched does when iCloud Drive reports that the same project was edited on two
// devices (#15, story of #1): keep the most recently modified version, mark the rest
// resolved, and retain the version that lost for the session so the notice can name the
// device and time it came from and "Restore other version" can bring it back. Nothing is
// discarded silently.
//
// The decision is pure, over plain values: a `ConflictVersion` per version (the current
// one and the system's other versions), each with its modification date, the name of the
// device that saved it and, once read, its snapshot. The wiring maps `NSFileVersion` to it
// (`modificationDate`, `localizedNameOfSavingComputer`, the `url` read through the
// coordinator the document configuration provides, never uncoordinated) and acts on the
// decision: apply the winner's snapshot when it is not the current one, set `isResolved`
// on every other version, keep `retained` for the notice, and put the restore through
// `ProjectDocument.perform` so it is one undo step like any edit. Every row has a test
// (`ConflictPolicyTests`).
//
// Rules:
//   - The newest modification date wins. On an equal date the current version wins (what
//     this device shows stays); among the others, the smaller `id` wins, so the outcome
//     does not depend on the order the system listed them in.
//   - `resolved` is every version but the winner, the current one included when it lost:
//     it is "resolved" by the winner's snapshot replacing it through the funnel. The
//     others are the conflict versions the wiring flags resolved.
//   - `retained` is the version the notice is about: the newest loser when the current
//     version won, or the current version itself when another won (it is this device's
//     own work, so it is what the user would want back). Nil, with no notice, when there
//     is nothing to lose: a single version.

import Foundation

// MARK: - Version

/// One version of the project in a conflict, in the terms the decision needs.
nonisolated struct ConflictVersion: Identifiable, Equatable {
    typealias ID = String

    /// Whatever the wiring uses to find the `NSFileVersion` again; `"current"` by
    /// convention for the current version.
    var id:               ID
    var modificationDate: Date
    /// `NSFileVersion.localizedNameOfSavingComputer`; nil when the system has none.
    var deviceName:       String?
    /// The version's contents once read; nil until the wiring has read them through
    /// the coordinator. The decision never looks inside it.
    var snapshot:         ProjectData?

    init(id: ID, modificationDate: Date, deviceName: String? = nil, snapshot: ProjectData? = nil) {
        self.id               = id
        self.modificationDate = modificationDate
        self.deviceName       = deviceName
        self.snapshot         = snapshot
    }

    /// Two values are the same version when their identity matches; the snapshot is
    /// payload. (Also why this is hand-written: `ProjectData`'s `Equatable` is main-actor
    /// isolated, and a synthesized `==` here would call it from a nonisolated context.)
    static func == (a: ConflictVersion, b: ConflictVersion) -> Bool {
        a.id == b.id && a.modificationDate == b.modificationDate && a.deviceName == b.deviceName
    }
}

// MARK: - Policy

nonisolated enum ConflictPolicy {

    /// What the notice says: which device saved the version that lost, and when.
    struct Notice: Equatable {
        var deviceName:       String?
        var modificationDate: Date
    }

    struct Decision: Equatable {
        /// The version to keep. When `currentWins` is false its snapshot replaces the
        /// document's through the funnel.
        var winner:      ConflictVersion
        /// Every version but the winner, in the order they were given, the current one
        /// first when it lost.
        var resolved:    [ConflictVersion.ID]
        /// The losing version kept for the session, for the notice and the restore; nil
        /// when there was nothing to lose.
        var retained:    ConflictVersion?
        var currentWins: Bool

        /// The notice to show, or nil when no version lost.
        var notice: Notice? {
            retained.map { Notice(deviceName: $0.deviceName, modificationDate: $0.modificationDate) }
        }
    }

    /// The decision for `current` (this device's version) against `others` (the
    /// system's unresolved conflict versions). Others that share the current version's
    /// `id` are ignored.
    static func decide(current: ConflictVersion, others: [ConflictVersion]) -> Decision {
        let others = others.filter { $0.id != current.id }
        guard let newestOther = others.max(by: Self.isOlder) else {
            return Decision(winner: current, resolved: [], retained: nil, currentWins: true)
        }
        if newestOther.modificationDate <= current.modificationDate {
            return Decision(
                winner:      current,
                resolved:    others.map(\.id),
                retained:    newestOther,
                currentWins: true
            )
        }
        return Decision(
            winner:      newestOther,
            resolved:    [current.id] + others.filter { $0.id != newestOther.id }.map(\.id),
            retained:    current,
            currentWins: false
        )
    }

    /// The strict order `max(by:)` picks the winner with: by date, then by `id` so that
    /// equal dates resolve the same way whatever order the versions arrived in.
    private static func isOlder(_ a: ConflictVersion, _ b: ConflictVersion) -> Bool {
        if a.modificationDate != b.modificationDate { return a.modificationDate < b.modificationDate }
        return a.id > b.id
    }
}

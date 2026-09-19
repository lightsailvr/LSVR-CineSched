// ConflictNotice.swift
// The conflict notice's lifecycle (#15): what the sync indicator says after a version of
// the project lost to another, and when it stops saying it. Pure values, so every
// transition has a test (`ConflictNoticeTests`); `SyncMonitor` owns one per editor and
// drives it from the document's change count.
//
// A notice is raised by one of two paths, and says which:
//   - `.policy`: `ConflictPolicy.decide` ran over the system's unresolved conflict
//     versions and one lost; the notice names its device and time, and the loser's
//     snapshot is retained for the session so Restore other version can apply it.
//   - `.replacedUnsavedEdits`: the pre-agreed fallback. The document infrastructure
//     applied a snapshot from disk (iCloud, or the Mac's own conflict sheet) over edits
//     this device had not written yet; nothing was observable as a conflict version, so
//     the notice cannot name the other device, but the replaced edits were in memory and
//     are retained the same way.
//
// The state clears when the notice is acted on (restore or dismiss) or when the document
// changes for any reason other than the resolution itself: `raise` records the change
// count right after the resolution's own `perform`, and `documentDidChange` with any
// other count is the user's next edit (or undo, or a reload), which retires the notice
// and, through `SyncState.derive`'s `conflictResolved`, the state beside the title.

import Foundation

// MARK: - Notice

nonisolated struct ConflictNotice: Equatable {
    enum Origin: Equatable {
        /// The conflict policy kept one version over another.
        case policy
        /// A snapshot from disk replaced unsaved local edits (the fallback).
        case replacedUnsavedEdits
    }

    var origin:           Origin
    /// The device that saved the version that lost; nil when the system has no name for
    /// it (and always for the fallback, where the loser is this device's own edits).
    var deviceName:       String?
    /// When the version that lost was last modified.
    var modificationDate: Date
    /// Whether the losing snapshot is retained, so Restore other version can be offered.
    var canRestore:       Bool

    /// The notice for a policy decision, or nil when no version lost.
    init?(decision: ConflictPolicy.Decision) {
        guard let notice = decision.notice else { return nil }
        self.init(origin: .policy, deviceName: notice.deviceName, modificationDate: notice.modificationDate, canRestore: decision.retained?.snapshot != nil)
    }

    init(origin: Origin, deviceName: String?, modificationDate: Date, canRestore: Bool) {
        self.origin           = origin
        self.deviceName       = deviceName
        self.modificationDate = modificationDate
        self.canRestore       = canRestore
    }
}

// MARK: - Lifecycle

nonisolated struct ConflictNoticeState: Equatable {
    /// The notice on display, or nil.
    private(set) var notice: ConflictNotice?
    /// The document's change count right after the resolution, i.e. the count that does
    /// not retire the notice.
    private(set) var changeCountAtResolution: Int?

    init() {}

    /// What `SyncState.derive` takes as `conflictResolved`.
    var isShowing: Bool { notice != nil }

    /// A resolution happened: `changeCount` is the document's count once the winner's
    /// snapshot was applied (or, when the current version won, the unchanged count).
    mutating func raise(_ notice: ConflictNotice, changeCount: Int) {
        self.notice                  = notice
        self.changeCountAtResolution = changeCount
    }

    /// The document's change count moved. The resolution's own count keeps the notice;
    /// any other count is the next edit, undo or reload, which retires it.
    mutating func documentDidChange(changeCount: Int) {
        guard notice != nil, changeCount != changeCountAtResolution else { return }
        clear()
    }

    /// Restore other version was applied.
    mutating func restored() { clear() }

    /// The notice was dismissed without a restore.
    mutating func dismiss() { clear() }

    private mutating func clear() {
        notice                  = nil
        changeCountAtResolution = nil
    }
}

// MARK: - The current version

extension ConflictVersion {
    /// The convention for the current version's `id`. (`nonisolated` because an
    /// extension does not inherit the struct's isolation, and `ConflictResolutionPlan`
    /// reads it off the main actor.)
    nonisolated static let currentID: ID = "current"

    /// The version the document shows, as the policy sees it. While the document holds
    /// edits the file does not, it is this device's work: dated by the last local edit
    /// (newer than anything on disk, which the file's date would undersell) and unnamed,
    /// since the system only names saved versions. Otherwise it is the file's current
    /// version, which may have been saved by another device and applied here already
    /// (the system chose it before the app looked): its date and saving computer are
    /// the file's. `now` is the last resort for a document with neither date.
    static func current(
        project:              ProjectData,
        fileModificationDate: Date?,
        fileDeviceName:       String?,
        hasUnsavedEdits:      Bool,
        lastEditDate:         Date?,
        now:                  Date
    ) -> ConflictVersion {
        if hasUnsavedEdits, let lastEditDate {
            return ConflictVersion(id: currentID, modificationDate: lastEditDate, deviceName: nil, snapshot: project)
        }
        return ConflictVersion(id: currentID, modificationDate: fileModificationDate ?? now, deviceName: fileDeviceName, snapshot: project)
    }
}

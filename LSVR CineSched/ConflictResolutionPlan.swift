// ConflictResolutionPlan.swift
// What the wiring does with a `ConflictPolicy.Decision` (#15): which of the system's
// conflict versions it marks resolved and removes at once, which one it must keep on disk
// until the file holds the contents that replaced it, and when it may do nothing at all.
// Pure values, so each rule has a test (`ConflictNoticeTests`); `SyncMonitor` maps the
// ids back to `NSFileVersion`s and does the coordinated work.
//
// The rules follow from what the `NSFileVersion` header prescribes ("after you resolve
// the conflict, set `isResolved` … you must then remove any versions of the file that
// are no longer useful") and from one fact about the document: a `perform` only puts the
// winner's snapshot in memory. The file gets it when the infrastructure autosaves from
// the undo action the `perform` registered, which is seconds on the Mac and up to a minute
// on iOS (learnings, 2026-09-18 #12), and never when there was no undo manager to
// register with. So:
//   - A losing conflict version is no longer useful the moment the policy decides: its
//     contents are retained in memory for the session (the notice's Restore) or
//     discarded by the policy's own rule, and the file never needed them. Resolved and
//     removed at once, under one coordinated write.
//   - The winner's own conflict version, when another version won, is the only copy of
//     the winning contents on disk until the write lands. It is left unresolved and
//     untouched until the document reports a write at or past the change count the
//     application produced (`ProjectDocument.writtenChangeCount`), then resolved and
//     removed. A kill in between costs nothing: the next launch lists the version as
//     unresolved, the policy picks it again, and the notice is raised again.
//   - With no undo manager the winner cannot be applied in a way that autosaves, so the
//     decision is not acted on at all: no `perform`, nothing resolved, no notice; the
//     versions stay listed for the next check, once a manager is attached.

import Foundation

// MARK: - Plan

nonisolated struct ConflictResolutionPlan: Equatable {
    /// Whether the winner's snapshot replaces the document's through the funnel.
    var appliesWinner:    Bool
    /// The conflict versions to mark resolved and remove at once: the losers among the
    /// system's versions (`Decision.resolved` without the current version, which is no
    /// conflict version and needs no flag).
    var removeNow:        [ConflictVersion.ID]
    /// The winner's own conflict version, when another version won: kept until the file
    /// holds its contents, then resolved and removed.
    var removeAfterWrite: ConflictVersion.ID?

    /// The plan for `decision`, or nil when it cannot be acted on yet: another version
    /// wins and `canRegisterEdits` is false (no undo manager), so applying it would leave
    /// the winning contents in memory only.
    static func make(for decision: ConflictPolicy.Decision, canRegisterEdits: Bool) -> ConflictResolutionPlan? {
        let losers = decision.resolved.filter { $0 != ConflictVersion.currentID }
        if decision.currentWins {
            return ConflictResolutionPlan(appliesWinner: false, removeNow: losers, removeAfterWrite: nil)
        }
        guard canRegisterEdits else { return nil }
        return ConflictResolutionPlan(appliesWinner: true, removeNow: losers, removeAfterWrite: decision.winner.id)
    }
}

// MARK: - The removal that waits on the write

/// The winner's version awaiting the write that makes it useless: kept by the monitor
/// from the application until `isDue`.
nonisolated struct PendingConflictRemoval: Equatable {
    var versionID:               ConflictVersion.ID
    /// The document's change count once the winner's snapshot was applied.
    var changeCountAtResolution: Int

    /// Whether a file holding `writtenChangeCount` (the document's `writtenChangeCount`)
    /// holds the winner's contents or a later edit of them, so the version may go.
    func isDue(writtenChangeCount: Int) -> Bool {
        writtenChangeCount >= changeCountAtResolution
    }
}

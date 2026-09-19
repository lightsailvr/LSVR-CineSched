// PlatformConflictResolution.swift
// Platform seam: whether the document infrastructure presents its own UI for an iCloud
// conflict, which decides who resolves one (#15).
//
// On the Mac the document scene runs on NSDocument (learnings, 2026-09-16 #8), which is
// the file's presenter: when the item gains a conflict version it presents the system's
// conflict sheet and the Versions browser for the user to pick a version, and issue #15
// asks for exactly that dialog there. CineSched must not resolve first, or the sheet
// never appears and the user's choice is taken from them, so the Mac's `SyncMonitor`
// only observes: the indicator shows the states, and the fallback notice covers a
// snapshot that replaced unsaved edits once the system has chosen.
//
// On iOS and visionOS nothing presents a conflict; the app is expected to resolve it
// (the `NSFileVersion` recipe: pick a version, mark the rest resolved, remove them
// under a coordinated write). There `SyncMonitor` runs `ConflictPolicy` and raises
// the notice with Restore other version.

import Foundation

nonisolated enum PlatformConflictResolution {
    /// True where the system resolves conflicts through its own dialog, so CineSched
    /// must leave the versions alone.
    #if os(macOS)
    static let systemPresentsConflictUI = true
    #else
    static let systemPresentsConflictUI = false
    #endif
}

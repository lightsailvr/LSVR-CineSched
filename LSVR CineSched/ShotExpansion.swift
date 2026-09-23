// ShotExpansion.swift
// Which strips on the Stripboard show their shots (#42), as one pure value. Show Shots
// (the View menu's and the toolbar's toggle) sets every strip at once; a strip's chevron
// flips that one strip against it. So the state is the switch plus the strips that differ
// from it: a strip is expanded when Show Shots is on and it is not an exception, or Show
// Shots is off and it is one. Turning Show Shots either way clears the exceptions, so
// "Show Shots expands every strip" holds the moment it is chosen, and the chevron still
// collapses one afterwards (and expands one while it is off).
//
// Per window and never in the file (story 42 of #36): `ContentView` keeps `showAll` as a
// `@WindowPreference` (the next window opens the way this one was) and the exceptions as
// plain `@State`, because they are scene ids of this project and would mean nothing to
// the next window, which may hold another project.

import Foundation

nonisolated struct ShotExpansion: Hashable, Sendable {
    /// Show Shots: every strip expanded, apart from the exceptions.
    private(set) var showAll: Bool
    /// The scenes whose chevron was flipped since Show Shots last changed.
    private(set) var exceptions: Set<UUID>

    init(showAll: Bool = false, exceptions: Set<UUID> = []) {
        self.showAll    = showAll
        self.exceptions = exceptions
    }

    /// Whether the strip of the scene with `sceneID` shows its shots.
    func isExpanded(_ sceneID: UUID) -> Bool {
        showAll != exceptions.contains(sceneID)
    }

    /// The chevron: flips one strip, whatever Show Shots says.
    mutating func toggle(_ sceneID: UUID) {
        if exceptions.contains(sceneID) {
            exceptions.remove(sceneID)
        } else {
            exceptions.insert(sceneID)
        }
    }

    /// Show Shots: every strip expanded or collapsed at once, the chevrons' exceptions
    /// dropped. Setting the value it already has still drops them, so choosing Show Shots
    /// again folds every strip back into line.
    mutating func setShowAll(_ on: Bool) {
        showAll    = on
        exceptions = []
    }
}

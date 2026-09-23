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
// the next window, which may hold another project. `PhoneEditor` keeps the same pair. Both
// build their bindings with `binding(showAll:exceptions:)` and `showAllBinding(_:)` below.

import SwiftUI

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

// MARK: - Bindings

extension ShotExpansion {
    /// The expansion over where an editor keeps its two halves: Show Shots (a
    /// `@WindowPreference`) and the chevrons' exceptions (`@State`). What the board and
    /// the phone's lists are handed.
    static func binding(showAll: Binding<Bool>, exceptions: Binding<Set<UUID>>) -> Binding<ShotExpansion> {
        Binding(
            get: { ShotExpansion(showAll: showAll.wrappedValue, exceptions: exceptions.wrappedValue) },
            set: { new in
                if new.showAll != showAll.wrappedValue { showAll.wrappedValue = new.showAll }
                exceptions.wrappedValue = new.exceptions
            }
        )
    }

    /// Show Shots over that binding, for the View menu, the toolbar and the phone's row:
    /// every strip at once, the chevrons' exceptions dropped (`setShowAll`), under
    /// `animation` when one is given.
    static func showAllBinding(_ expansion: Binding<ShotExpansion>, animation: Animation? = nil) -> Binding<Bool> {
        Binding(
            get: { expansion.wrappedValue.showAll },
            set: { on in
                var value = expansion.wrappedValue
                value.setShowAll(on)
                if let animation {
                    withAnimation(animation) { expansion.wrappedValue = value }
                } else {
                    expansion.wrappedValue = value
                }
            }
        )
    }
}

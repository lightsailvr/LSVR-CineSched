// PlatformListEditing.swift
// Platform seam: a `List`'s edit mode (#25, #27). The iPhone's Day screen reorders its
// strips with the drag handles a `List` shows for `onMove` rows in edit mode; a long
// press alone cannot start that drag there because the strip's long press is its context
// menu. The Boneyard tab multi-selects with the selection circles a `List(selection:)`
// shows in the same mode (#27). `EditMode` and the `editMode` environment key exist on
// iOS, iPadOS and visionOS and are marked unavailable on macOS, where no window is ever
// compact and neither view ever shows, so the Mac side does nothing. `DayScreen` calls
// `listReordering(_:)`, `BoneyardTab` `listSelecting(_:)`, and both stay free of the
// conditional. The scene editor's Shots section (#39) reorders with `listReordering` too,
// and asks `PlatformListEditing.reorderingNeedsEditMode` whether to offer the toggle.

import SwiftUI

extension View {
    /// Puts the list in edit mode while `isActive`, so its `onMove` rows show drag
    /// handles; nothing on the Mac. The binding is constant: the view's own Reorder /
    /// Done button is what flips `isActive`, not a system `EditButton`.
    func listReordering(_ isActive: Bool) -> some View {
        listEditMode(isActive)
    }

    /// Puts the list in edit mode while `isActive`, so a `List(selection:)` over a set
    /// shows its selection circles and a tap toggles a row (#27); nothing on the Mac.
    /// The view's own Select / Done button flips `isActive`.
    func listSelecting(_ isActive: Bool) -> some View {
        listEditMode(isActive)
    }

    private func listEditMode(_ isActive: Bool) -> some View {
        #if os(macOS)
        self
        #else
        environment(\.editMode, .constant(isActive ? .active : .inactive))
        #endif
    }
}

enum PlatformListEditing {
    /// Whether `onMove` rows need `listReordering` for their drag handles (#39): true
    /// where edit mode exists, false on the Mac, where a list's rows drag without it. The
    /// scene editor's Shots section shows its Reorder / Done button only where it does
    /// something.
    static var reorderingNeedsEditMode: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }
}

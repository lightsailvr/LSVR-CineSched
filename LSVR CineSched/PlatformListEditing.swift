// PlatformListEditing.swift
// Platform seam: a `List`'s edit mode (#25). The iPhone's Day screen reorders its strips
// with the drag handles a `List` shows for `onMove` rows in edit mode; a long press alone
// cannot start that drag there because the strip's long press is its context menu.
// `EditMode` and the `editMode` environment key exist on iOS, iPadOS and visionOS and are
// marked unavailable on macOS, where no window is ever compact and the Day screen never
// shows, so the Mac side does nothing. `DayScreen` calls `listReordering(_:)` and stays
// free of the conditional.

import SwiftUI

extension View {
    /// Puts the list in edit mode while `isActive`, so its `onMove` rows show drag
    /// handles; nothing on the Mac. The binding is constant: the view's own Reorder /
    /// Done button is what flips `isActive`, not a system `EditButton`.
    func listReordering(_ isActive: Bool) -> some View {
        #if os(macOS)
        self
        #else
        environment(\.editMode, .constant(isActive ? .active : .inactive))
        #endif
    }
}

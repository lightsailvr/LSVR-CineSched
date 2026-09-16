// ModifierKeys.swift
// Platform seam: polling which modifier keys are held at the moment a row is clicked.
// The Boneyard, calendar and Stripboard all use ⌘-click / ⇧-click for multi-select, and
// SwiftUI's tap gestures don't report modifiers, so the Mac reads NSEvent.modifierFlags
// directly. iOS and visionOS have no equivalent to poll (a hardware keyboard's modifiers
// arrive with key events, not with taps), so there the answer is always "none" and a
// tap is a plain single select; touch multi-select is a milestone 3/4 concern.

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum ModifierKeys {
    /// The modifier keys held right now, expressed in SwiftUI's own `EventModifiers`.
    static var current: EventModifiers {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        // Only the two keys the selection code reads; add others when a caller needs them.
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        return modifiers
        #else
        return []
        #endif
    }
}

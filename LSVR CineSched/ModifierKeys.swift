// ModifierKeys.swift
// Platform seam: which modifier keys were held at the moment a row or a strip was
// clicked. The Boneyard, calendar and Stripboard all use ⌘-click / ⇧-click for
// multi-select, and SwiftUI's tap gestures don't report modifiers, so the Mac reads
// `NSEvent.modifierFlags` directly. iOS and visionOS have nothing to poll, so there the
// answer comes from the latest press the editor's root observed (InputPress.swift,
// `PlatformPressObserver`, #22): the keys a pointer's click carried, and
// none for a finger or a Pencil, so a touch is a plain single select as before and a
// trackpad or mouse with a hardware keyboard multi-selects like the Mac's.

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
        guard let press = InputPressRecorder.shared.latest else { return [] }
        return press.selectionModifiers.intersection([.command, .shift])
        #endif
    }

    /// Whether the editor's root should observe presses for `current` (the Mac polls the
    /// event instead and installs nothing).
    #if os(macOS)
    static let recordsPresses = false
    #else
    static let recordsPresses = true
    #endif
}

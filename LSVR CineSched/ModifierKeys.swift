// ModifierKeys.swift
// Platform seam: which modifier keys were held at the moment a row or a strip was
// clicked. The Boneyard, calendar and Stripboard all use ⌘-click / ⇧-click for
// multi-select, and SwiftUI's tap gestures don't report modifiers, so the Mac reads
// `NSEvent.modifierFlags` directly. iOS and visionOS have nothing to poll, so there the
// answer comes from the latest press the editor's root recorded through
// `SpatialEventGesture` (InputPress.swift, #22): the keys a pointer's click carried, and
// none for a finger or a Pencil, so a touch is a plain single select as before and a
// trackpad or mouse with a hardware keyboard multi-selects like the Mac's. The mapping
// of the event's kind is here too, because `.pencil` exists only on iOS.

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

    /// Whether the editor's root should record presses for `current` (the Mac polls the
    /// event instead and needs no gesture in the way of its own).
    #if os(macOS)
    static let recordsPresses = false
    #else
    static let recordsPresses = true
    #endif

    /// The app's input kind for a spatial event's.
    static func inputKind(of kind: SpatialEventCollection.Event.Kind) -> InputKind {
        #if os(iOS)
        switch kind {
        case .touch:   return .touch
        case .pencil:  return .pencil
        case .pointer: return .pointer
        default:       return .other
        }
        #else
        switch kind {
        case .touch:   return .touch
        case .pointer: return .pointer
        default:       return .other
        }
        #endif
    }
}

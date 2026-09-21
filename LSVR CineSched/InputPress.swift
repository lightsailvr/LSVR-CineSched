// InputPress.swift
// Which kind of input pressed the board last, and with which modifier keys (#22, story
// 63 of #1): a finger, an Apple Pencil, or a pointer (a trackpad or a mouse). Where the
// behaviour differs between them is the selection: a pointer click with ⌘ or ⇧ builds a
// multi-selection, which then drags, copies and acts as a group, while a finger or a
// Pencil (no modifier keys) selects one strip; the Mac has always read the keys from
// `NSEvent`, and the iPad had no way to read them at a tap (`ModifierKeys`, a seam,
// answered "none"). SwiftUI's tap gestures still carry no modifiers on iOS, but the 27
// SDK's `SpatialEventGesture` (iOS 18) reports every press with its `kind` and its
// `modifierKeys`, so one gesture at the editor's root records the latest press and the
// seam reads it back when a strip's tap fires (a press begins before its tap ends).
//
// The drag itself cannot be told apart: `draggable` and `DragSession` carry no input kind
// on 27.0, and the `GestureInputKinds` filter (`TapGesture(count:inputKinds:)`,
// `DragGesture(inputKinds:)`) only restricts which inputs a gesture accepts. So the
// distinction is made at the press that selects; the system's own lift (a long press by
// touch and Pencil, an immediate drag by pointer) is unchanged.
//
// Platform-free except for the mapping of the event's kind, which lives in the
// `ModifierKeys` seam because `.pencil` is an iOS-only case.

import SwiftUI

// MARK: - The press

enum InputKind: Hashable, Sendable {
    /// A finger.
    case touch
    /// An Apple Pencil.
    case pencil
    /// A trackpad or a mouse.
    case pointer
    /// Anything else the platform reports (a visionOS pinch).
    case other
}

struct InputPress: Equatable, Sendable {
    var kind:      InputKind
    var modifiers: EventModifiers

    init(kind: InputKind, modifiers: EventModifiers = []) {
        self.kind      = kind
        self.modifiers = modifiers
    }

    /// Whether this press can carry the modifier keys a multi-selection needs: only a
    /// pointer's click does (a finger and a Pencil have no keys, and the keys a hardware
    /// keyboard holds during a touch are not a click's).
    var carriesModifiers: Bool { kind == .pointer }

    /// The modifier keys the selection reads: the click's for a pointer, none otherwise.
    var selectionModifiers: EventModifiers { carriesModifiers ? modifiers : [] }
}

// MARK: - The recorder

/// The latest press on the board, app-wide like the modifier flags it stands in for.
@MainActor
final class InputPressRecorder {
    static let shared = InputPressRecorder()

    private(set) var latest: InputPress?

    func record(_ press: InputPress) {
        latest = press
    }
}

// MARK: - The gesture

/// Records every press's kind and modifiers as it begins, without claiming it: the taps,
/// long presses and drags below keep working as they do. Off where the platform polls
/// its flags instead (`enabled` false), so the Mac carries no gesture it does not need.
struct InputPressRecording: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                SpatialEventGesture().onChanged { events in
                    for event in events where event.phase == .active {
                        InputPressRecorder.shared.record(
                            InputPress(kind: ModifierKeys.inputKind(of: event.kind), modifiers: event.modifierKeys)
                        )
                    }
                }
            )
        } else {
            content
        }
    }
}

extension View {
    /// Records the presses on this view for `ModifierKeys.current` where the platform has
    /// no flags to poll (`ModifierKeys.recordsPresses`, a seam constant).
    func recordsInputPresses(_ enabled: Bool = ModifierKeys.recordsPresses) -> some View {
        modifier(InputPressRecording(enabled: enabled))
    }
}

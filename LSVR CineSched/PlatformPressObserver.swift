// PlatformPressObserver.swift
// Platform seam: how the editor learns the kind and the modifier keys of each press on
// iOS and visionOS (#22, InputPress.swift). Not a SwiftUI gesture: a
// `SpatialEventGesture` added as a `simultaneousGesture` over the whole editor swallowed
// every `Button` under it on iPadOS 27 (the toolbar's inspector and sidebar toggles, the
// segmented picker, the calendar's own buttons; `Menu`s survived because they open on
// touch-down). Instead a `UIGestureRecognizer` on the window reads `touchesBegan`'s
// `UITouch.type` and `UIEvent.modifierFlags` and fails at once, so it observes every
// press and never claims one: `cancelsTouchesInView` off, simultaneous with everything.
// The Mac polls `NSEvent` and installs nothing (`ModifierKeys.recordsPresses`).

import SwiftUI
#if !os(macOS)
import UIKit
#endif

/// A zero-sized view that installs the observer on its window. Placed in the editor's
/// background by `recordsInputPresses()`.
struct PressObserver {
    let onPress: (InputPress) -> Void
}

#if os(macOS)
extension PressObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {}
}
#else
extension PressObserver: UIViewRepresentable {
    final class Coordinator {
        var recognizer: PressObservingRecognizer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ObserverHostView {
        let view = ObserverHostView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onMoveToWindow = { window in
            if let old = context.coordinator.recognizer, let oldWindow = old.view {
                oldWindow.removeGestureRecognizer(old)
            }
            guard let window else { return }
            let recognizer = PressObservingRecognizer(onPress: onPress)
            window.addGestureRecognizer(recognizer)
            context.coordinator.recognizer = recognizer
        }
        return view
    }

    func updateUIView(_ view: ObserverHostView, context: Context) {
        context.coordinator.recognizer?.onPress = onPress
    }

    static func dismantleUIView(_ view: ObserverHostView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer, let window = recognizer.view {
            window.removeGestureRecognizer(recognizer)
        }
        coordinator.recognizer = nil
    }
}

/// Reports its window so the recognizer can be moved with it.
final class ObserverHostView: UIView {
    var onMoveToWindow: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?(window)
    }
}

/// Records each press as it begins and fails immediately, so the touch continues to
/// whatever is under it exactly as if the recognizer were not there.
final class PressObservingRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onPress: (InputPress) -> Void

    init(onPress: @escaping (InputPress) -> Void) {
        self.onPress = onPress
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan   = false
        delaysTouchesEnded   = false
        delegate             = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            onPress(InputPress(kind: Self.inputKind(of: touch.type), modifiers: Self.modifiers(of: event.modifierFlags)))
        }
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private static func inputKind(of type: UITouch.TouchType) -> InputKind {
        switch type {
        case .direct:          return .touch
        case .pencil:          return .pencil
        case .indirectPointer: return .pointer
        default:               return .other
        }
    }

    private static func modifiers(of flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
#endif

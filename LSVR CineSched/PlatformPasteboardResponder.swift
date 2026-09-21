// PlatformPasteboardResponder.swift
// Platform seam: the responder that answers the system's Edit ▸ Cut, Copy and Paste for
// scenes (#22). Those three menu items and their shortcuts are the document scene's own
// on the Mac and in the iPad's menu bar, and both platforms send them down the responder
// chain from the first responder: a text field being edited takes them for its text, and
// otherwise this view takes them for the selected scenes. SwiftUI's `copyable`,
// `cuttable` and `pasteDestination` do the same through the focus system, but on iPadOS
// 27 a `focusable` view cannot be focused unless that system is engaged (a hardware
// keyboard in use), and the menu bar is reachable by touch as well, so they went dead
// exactly when a finger opened Edit; a first responder works either way. The editor
// asks for first-responder status on every selection (`focusRequest`), which also ends
// any field's editing, so the shortcuts act on the selection the user just made.
//
// The bytes on the pasteboard are the drag payload's own JSON (`ScheduleDragPayload`'s
// pasteboard representation, ScheduleClipboard.swift) under the drag payload's type, so
// a paste in another window of the app, on either platform, reads them back.

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - What the editor supplies

/// The editor's side of the three actions. `copy` and `cut` return the bytes to put on
/// the pasteboard, nil when nothing is selected (the items are then disabled through
/// `canCopy`); `paste` receives the bytes found there.
struct PasteboardActions {
    var canCopy: () -> Bool
    var copy:    () -> Data?
    var cut:     () -> Data?
    var paste:   (Data) -> Void
}

// MARK: - The pasteboard

enum PlatformPasteboard {
    private static var type: String { UTType.cineschedDragPayload.identifier }

    static func write(_ data: Data) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        #else
        UIPasteboard.general.setData(data, forPasteboardType: type)
        #endif
    }

    static func read() -> Data? {
        #if os(macOS)
        NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(type))
        #else
        UIPasteboard.general.data(forPasteboardType: type)
        #endif
    }

    /// Whether the pasteboard holds scenes, for enabling Paste; a metadata check only.
    static var holdsPayload: Bool {
        #if os(macOS)
        NSPasteboard.general.types?.contains(NSPasteboard.PasteboardType(type)) ?? false
        #else
        UIPasteboard.general.contains(pasteboardTypes: [type])
        #endif
    }
}

// MARK: - The responder

/// A zero-sized view that becomes first responder when `focusRequest` changes and
/// answers Cut, Copy and Paste with `actions`. Placed in the editor's background.
struct PasteboardResponder {
    let actions: PasteboardActions
    /// Incremented by the editor each time it wants first-responder status.
    let focusRequest: Int

    final class Coordinator {
        var handledRequest = 0
    }
}

#if os(macOS)
extension PasteboardResponder: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ResponderView {
        ResponderView(actions: actions)
    }

    func updateNSView(_ view: ResponderView, context: Context) {
        view.actions = actions
        guard context.coordinator.handledRequest != focusRequest else { return }
        context.coordinator.handledRequest = focusRequest
        // Deferred: taking first responder ends a field's editing, which writes SwiftUI
        // state, and this runs inside a view update.
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class ResponderView: NSView, NSUserInterfaceValidations {
        var actions: PasteboardActions

        init(actions: PasteboardActions) {
            self.actions = actions
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        @objc func copy(_ sender: Any?) {
            if let data = actions.copy() { PlatformPasteboard.write(data) }
        }

        @objc func cut(_ sender: Any?) {
            if let data = actions.cut() { PlatformPasteboard.write(data) }
        }

        @objc func paste(_ sender: Any?) {
            if let data = PlatformPasteboard.read() { actions.paste(data) }
        }

        func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            switch item.action {
            case #selector(copy(_:)), #selector(cut(_:)): return actions.canCopy()
            case #selector(paste(_:)):                    return PlatformPasteboard.holdsPayload
            default:                                      return true
            }
        }
    }
}
#else
extension PasteboardResponder: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ResponderView {
        ResponderView(actions: actions)
    }

    func updateUIView(_ view: ResponderView, context: Context) {
        view.actions = actions
        guard context.coordinator.handledRequest != focusRequest else { return }
        context.coordinator.handledRequest = focusRequest
        // Deferred for the same reason as the Mac's: resigning a field writes state.
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
    }

    final class ResponderView: UIView {
        var actions: PasteboardActions

        init(actions: PasteboardActions) {
            self.actions = actions
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override var canBecomeFirstResponder: Bool { true }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            switch action {
            case #selector(copy(_:)), #selector(cut(_:)): return actions.canCopy()
            case #selector(paste(_:)):                    return PlatformPasteboard.holdsPayload
            default:                                      return false
            }
        }

        override func copy(_ sender: Any?) {
            if let data = actions.copy() { PlatformPasteboard.write(data) }
        }

        override func cut(_ sender: Any?) {
            if let data = actions.cut() { PlatformPasteboard.write(data) }
        }

        override func paste(_ sender: Any?) {
            if let data = PlatformPasteboard.read() { actions.paste(data) }
        }
    }
}
#endif

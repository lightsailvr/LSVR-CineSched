// PlatformPasteboardResponder.swift
// Platform seam: the first responder behind the editor, with two duties.
//
// The first (#22): it answers the system's Edit ▸ Cut, Copy and Paste for scenes. Those
// three menu items and their shortcuts are the document scene's own on the Mac and in the
// iPad's menu bar, and both platforms send them down the responder chain from the first
// responder: a text field being edited takes them for its text, and otherwise this view
// takes them for the selected scenes. SwiftUI's `copyable`, `cuttable` and
// `pasteDestination` do the same through the focus system, but on iPadOS 27 a `focusable`
// view cannot be focused unless that system is engaged (a hardware keyboard in use), and
// the menu bar is reachable by touch as well, so they went dead exactly when a finger
// opened Edit; a first responder works either way. The editor asks for first-responder
// status on every selection (`focusRequest`), which also ends any field's editing, so the
// shortcuts act on the selection the user just made.
//
// The second (the shake-to-undo fix after M4): on iOS it keeps a first responder under
// SwiftUI's hosting view, so the undo gestures reach the document. Shake to undo and the
// three-finger undo and redo gestures ask the first responder for `undoManager` and walk
// `next` up the chain. Every responder inside the hosting view answers with the SwiftUI
// environment's manager (the one `perform` registers with), but above it the window
// answers with an empty manager of its own, and a SwiftUI editor with no field focused
// has no first responder at all, so a shake started at the window and found nothing to
// undo (a focused field's shake undid only its typing). `ResponderView.undoManager`
// answers with the manager it is handed, rather than rely on the hosting view's, and
// the view takes first-responder status whenever nothing holds it. No notification says
// when that is: the undo alert itself is the first responder while it is up and leaves
// none behind when it closes, and a menu or a dismissed sheet leave none either. So a
// `CFRunLoopObserver` checks once per turn of the main run loop, before it waits (nothing
// while idle, one `isFirstResponder` read per turn otherwise), and takes the status when
// the view is in the key window and UIKit reports no first responder. It never takes it
// from a field being edited, an alert or a menu; and while a long-press menu is up it
// gives the status away (#36's review): a context menu presented over this responder
// raised the software keyboard behind itself on the iPhone (every Days-list menu, found
// in #43), and resigning while the menu's container is in the window keeps it down; the
// reclaim takes the status back once the menu is gone. Only the editor's own `focusRequest` (a
// selection on the iPad's board) takes it outright, as before, which is also how the
// iPad's inspector editor hands a shake back to the document after a Save. One responder
// rather than two: a second zero-sized first responder for the undo duty would compete
// with this one on the iPad, where every selection takes it. The iPhone editor installs
// the same view with inert actions (`undoGestures(_:)`), the three-column layout hands it
// the manager beside the actions, and the Mac's window already wires Edit ▸ Undo through
// NSDocument, so the Mac side carries no undo duty and is unchanged.
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

    /// No scenes to copy, nothing accepted: the iPhone editor's, which has no selection
    /// and installs the responder for its undo duty alone.
    static let inert = PasteboardActions(canCopy: { false }, copy: { nil }, cut: { nil }, paste: { _ in })
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
/// answers Cut, Copy and Paste with `actions`; on iOS it also carries `undoManager` for
/// the undo gestures and takes first-responder status whenever nothing else holds it.
/// Placed in the editor's background.
struct PasteboardResponder {
    let actions: PasteboardActions
    /// Incremented by the editor each time it wants first-responder status.
    let focusRequest: Int
    /// The document's undo manager (the SwiftUI environment's), for the shake and the
    /// three-finger gestures; nil where the window wires Undo itself (the Mac).
    var undoManager: UndoManager? = nil

    final class Coordinator {
        var handledRequest = 0
    }
}

extension View {
    /// Puts `undoManager` on the responder chain behind this view, so shake to undo and
    /// the three-finger gestures reach the document's edits (iOS and visionOS; nothing
    /// on the Mac, whose window already answers Undo). The iPhone editor's root.
    func undoGestures(_ undoManager: UndoManager?) -> some View {
        background {
            PasteboardResponder(actions: .inert, focusRequest: 0, undoManager: undoManager)
                .frame(width: 0, height: 0)
        }
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
        ResponderView(actions: actions, undoManager: undoManager)
    }

    func updateUIView(_ view: ResponderView, context: Context) {
        view.actions             = actions
        view.documentUndoManager = undoManager
        guard context.coordinator.handledRequest != focusRequest else { return }
        context.coordinator.handledRequest = focusRequest
        // Deferred for the same reason as the Mac's: resigning a field writes state.
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
    }

    final class ResponderView: UIView {
        var actions: PasteboardActions
        /// What the undo gestures find; nil leaves the chain as UIKit has it.
        var documentUndoManager: UndoManager?
        /// The reclaim hook, installed while the view is in a window.
        private var runLoopObserver: CFRunLoopObserver?

        init(actions: PasteboardActions, undoManager: UndoManager?) {
            self.actions             = actions
            self.documentUndoManager = undoManager
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        deinit {
            MainActor.assumeIsolated { removeRunLoopObserver() }
        }

        override var canBecomeFirstResponder: Bool { true }

        // MARK: The undo duty

        override var undoManager: UndoManager? {
            documentUndoManager ?? super.undoManager
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { installRunLoopObserver() } else { removeRunLoopObserver() }
        }

        /// The reclaim runs each time the main run loop is about to wait, so it follows
        /// whatever just resigned or was dismissed without a notification of its own (the
        /// undo alert leaves no first responder behind, nor does a menu or a sheet), and
        /// costs one `isFirstResponder` read per turn while this view holds the status.
        private func installRunLoopObserver() {
            guard runLoopObserver == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reclaimFirstResponderIfFree() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            runLoopObserver = observer
        }

        private func removeRunLoopObserver() {
            guard let runLoopObserver else { return }
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), runLoopObserver, .commonModes)
            self.runLoopObserver = nil
        }

        /// Takes first-responder status unless something else holds it: a field being
        /// edited, an alert or a menu keep it, and the view stands down.
        private func reclaimFirstResponderIfFree() {
            guard let window else { return }
            if Self.showsContextMenu(window) {
                if isFirstResponder { resignFirstResponder() }
                return
            }
            guard window.isKeyWindow, !isFirstResponder else { return }
            guard UIResponder.current == nil else { return }
            becomeFirstResponder()
        }

        /// Whether a long-press (context) menu is up in `window`. UIKit adds its container
        /// as a direct subview of the window while the menu shows and removes it after;
        /// there is no public "a menu is presented" query, so the check is by the
        /// container's class name, a handful of top-level subviews read once per turn.
        private static func showsContextMenu(_ window: UIWindow) -> Bool {
            window.subviews.contains { String(describing: type(of: $0)).contains("ContextMenu") }
        }

        // MARK: The pasteboard duty

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            switch action {
            case #selector(copy(_:)), #selector(cut(_:)): return actions.canCopy()
            case #selector(paste(_:)):                    return PlatformPasteboard.holdsPayload
            // The first-responder query below, which must reach this view when it holds
            // the status rather than walk past it to the hosting view.
            case #selector(UIResponder.captureFirstResponder): return true
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

private extension UIResponder {
    static weak var captured: UIResponder?

    /// The key window's first responder, nil when there is none. UIKit exposes no
    /// property for it; an action sent to a nil target goes to the first responder,
    /// which reports itself.
    static var current: UIResponder? {
        captured = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder), to: nil, from: nil, for: nil)
        return captured
    }

    @objc func captureFirstResponder() {
        UIResponder.captured = self
    }
}
#endif

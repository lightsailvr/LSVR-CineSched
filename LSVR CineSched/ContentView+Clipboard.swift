// ContentView+Clipboard.swift
// Edit ▸ Copy, Cut and Paste for scenes (#22), on the Mac and the iPad alike. The system
// owns the three menu items and their shortcuts (they are the document scene's
// `.pasteboard` command group, on the iPad's menu bar as on the Mac's), and sends them
// down the responder chain: a text field being edited takes them for its text, and
// otherwise the editor's pasteboard responder (`PasteboardResponder`, a seam) takes them
// for scenes. Every selection on the board (a tap on a strip, a Boneyard row or a day)
// makes that responder the first responder, which ends any field's editing, so the
// shortcuts act on the selection the user just made. No menu Button is added: one with
// ⌘C would replace the system item and take Copy away from every text field, and SwiftUI's
// `copyable` family needs the focus system, which the iPad engages only for a hardware
// keyboard (see the seam's header).
//
// What travels is the typed drag payload with the scenes by value (`.sceneCopies`), so a
// paste into another open project inserts the same scenes under new ids; the pure part is
// ScheduleClipboard.swift. Copy and Cut act on the multi-selection (the strips outlined
// in the accent color, on the board or in the Boneyard) or, failing that, on the scene the
// inspector shows; Paste lands after the selected strip, at the end of the selected day,
// or in the Boneyard. Cut removes as one edit ("Undo Cut"), Paste inserts as one ("Undo
// Paste") and selects what it inserted.

import SwiftUI

extension ContentView {

    // MARK: - The modifier

    /// The responder behind the board, with the three actions.
    func applyClipboard<Content: View>(_ content: Content) -> some View {
        content
            .background {
                PasteboardResponder(actions: pasteboardActions, focusRequest: pasteboardFocusRequest)
                    .frame(width: 0, height: 0)
            }
    }

    /// Makes the pasteboard responder the first responder, so Copy, Cut and Paste act on
    /// the board rather than on whichever field was being edited. Every selection path
    /// calls it.
    func focusEditor() {
        pasteboardFocusRequest += 1
    }

    private var pasteboardActions: PasteboardActions {
        PasteboardActions(
            canCopy: { !clipboardSceneIDs.isEmpty },
            copy:    { copyPayload().flatMap { try? $0.pasteboardData() } },
            cut:     { cutPayload().flatMap { try? $0.pasteboardData() } },
            paste:   { data in
                if let payload = try? ScheduleDragPayload(pasteboardData: data) { paste([payload]) }
            }
        )
    }

    // MARK: - What the actions do

    /// The scenes Copy and Cut act on: the multi-selection, or the inspector's scene.
    var clipboardSceneIDs: Set<UUID> {
        if !selectedSceneIDs.isEmpty { return selectedSceneIDs }
        if case .scene(let id) = selection { return [id] }
        return []
    }

    /// Copy: the selected scenes by value, or nil (the pasteboard is then left alone).
    func copyPayload() -> ScheduleDragPayload? {
        ScheduleClipboard.payload(copying: clipboardSceneIDs, in: document.project)
    }

    /// Cut: Copy, then the removal as one edit. The ids removed are those of the scenes
    /// actually copied (an auto-meal in the selection is neither copied nor removed).
    func cutPayload() -> ScheduleDragPayload? {
        guard let payload = copyPayload() else { return nil }
        let ids = Set(payload.copiedScenes.map(\.id))
        edit(L("Cut")) { ScheduleClipboard.remove(ids, from: &$0) }
        return payload
    }

    /// Paste: the copies inserted where the selection says, as one edit, then selected
    /// (the inspector shows the first of them).
    func paste(_ items: [ScheduleDragPayload]) {
        let scenes = items.flatMap(\.copiedScenes)
        guard !scenes.isEmpty else { return }
        let destination = ScheduleClipboard.destination(for: selection, in: document.project)
        var inserted: [UUID] = []
        edit(L("Paste")) { inserted = ScheduleClipboard.paste(scenes, at: destination, into: &$0) }
        guard let first = inserted.first else { return }
        selectedSceneIDs    = Set(inserted)
        lastSelectedSceneID = first
        selection           = .scene(id: first)
    }
}

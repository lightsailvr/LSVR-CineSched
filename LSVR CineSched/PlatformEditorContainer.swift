// PlatformEditorContainer.swift
// Platform seam: the container an adaptive editor (#19) is presented in. The editors are
// one `Form` with the same chrome everywhere; a sheet's size is the platform's choice.
// On the Mac a sheet is sized by its content, so the editor keeps the fixed frame its
// `EditorSheetSize` names (the sizes the fixed-frame sheets had, so the new forms sit
// where the old sheets sat); on the iPhone the sheet takes the editor's detents with a
// drag indicator (the iPhone companion of milestone 4 presents the same editors); on
// the iPad and Vision Pro it takes the system's form sizing, and a short editor keeps
// the form width at its own height (a fitted sheet around a form's scroll view would
// otherwise collapse to the chrome alone). In the inspector column
// (`editorPresentation == .inspector`) nothing is applied: the form fills the column.
//
// The iPhone is told apart by the interface idiom, not by the size class: inside a
// sheet on the iPad the horizontal size class reads compact whatever the window's, so
// an editor cannot tell a phone from a form sheet that way (learnings, 2026-09-20 #19).
//
// Applied by each editor at its root, so a `.sheet { SceneEditSheet(...) }` call site
// needs nothing per platform. The presentation modifiers are preferences read by the
// enclosing sheet and ignored outside one.

import SwiftUI
#if !os(macOS)
import UIKit
#endif

extension View {
    /// Sizes the sheet this editor is presented in, per platform; nothing in the inspector.
    func editorContainer(_ size: EditorSheetSize) -> some View {
        modifier(EditorContainerModifier(size: size))
    }
}

private struct EditorContainerModifier: ViewModifier {
    let size: EditorSheetSize
    @Environment(\.editorPresentation) private var presentation

    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(
            width:  presentation == .sheet ? size.width  : nil,
            height: presentation == .sheet ? size.height : nil
        )
        #else
        if presentation == .inspector {
            content
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            content
                .presentationDetents(size.compactDetents)
                .presentationDragIndicator(.visible)
        } else if size.fitsHeight {
            content
                .frame(height: size.height)
                .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        } else {
            content.presentationSizing(.form)
        }
        #endif
    }
}

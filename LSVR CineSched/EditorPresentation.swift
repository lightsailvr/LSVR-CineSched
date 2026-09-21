// EditorPresentation.swift
// How an editor view is being shown (#17, #19): as a modal sheet, or inside the iPad's
// inspector column. The adaptive editors are one `Form` in every container; what
// differs is the chrome around it. In a sheet the platform container (`editorContainer`,
// the `PlatformEditorContainer` seam) sizes the sheet from `EditorSheetSize`; in the
// inspector the same modifier applies nothing and the form fills the column. The scene
// editor also reads the value to skip its auto-focus in the inspector, where raising the
// keyboard on every tap of a strip would squeeze the board. Set once by the inspector on
// its content; every sheet keeps the default.

import SwiftUI

enum EditorPresentation {
    /// A modal sheet, sized by the platform container.
    case sheet
    /// The inspector column: the editor fills the column's width and height.
    case inspector
}

extension EnvironmentValues {
    @Entry var editorPresentation: EditorPresentation = .sheet
}

// MARK: - Sheet sizing

/// What an editor asks of its sheet, platform-free. The values are the editor's; which
/// applies where is the `PlatformEditorContainer` seam's: the Mac's sheet is sized by
/// its content, so `width` and `height` are its frame (the sizes the fixed-frame sheets
/// had, so the forms sit where the old sheets sat); an iPhone sheet offers
/// `compactDetents`; an iPad or Vision Pro sheet takes the system's form sizing, and a
/// short editor that `fitsHeight` keeps the form width but takes `height` rather than
/// the full form height (a form's scroll view has no height of its own to fit).
struct EditorSheetSize {
    var width:          CGFloat
    var height:         CGFloat
    var compactDetents: Set<PresentationDetent> = [.large]
    var fitsHeight:     Bool = false
}

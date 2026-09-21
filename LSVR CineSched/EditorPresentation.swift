// EditorPresentation.swift
// How an editor view is being shown (#17): as the modal sheet it was written for, or
// inside the iPad's inspector column. The scene and day editors carry the fixed frames
// their Mac sheets need (a sheet takes its size from its content); in a column those
// frames would push past the column's width, so an editor reads this value and drops
// them. Set once by the inspector on its content; every sheet keeps the default. The
// adaptive form rewrite (#19) replaces the fixed frames themselves and, with them, most
// uses of this value.

import SwiftUI

enum EditorPresentation {
    /// A modal sheet, sized by its content.
    case sheet
    /// The inspector column: the editor fills the column's width and height.
    case inspector
}

extension EnvironmentValues {
    @Entry var editorPresentation: EditorPresentation = .sheet
}

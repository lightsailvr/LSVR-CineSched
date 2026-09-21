// ProjectEditor.swift
// What a project document shows on iOS, iPadOS and visionOS (#17): in regular width
// (an iPad in landscape or portrait on its own, a wide Split View pane, the Vision Pro
// window) the three-column `ContentView`, sidebar, schedule and inspector; in compact
// width (an iPhone, a narrow Split View or Slide Over pane) the iPhone editor
// (`PhoneEditor`, #24: the Days, Boneyard, Production and Search tabs; story 54 of #1:
// the phone layout appears whenever a window is compact). The switch is the
// environment's horizontal size class, so a window resized across the boundary swaps
// editors; each keeps its own view state, and the document is the same object underneath.
//
// Platform-free SwiftUI: the size class exists on the Mac too, so this compiles there;
// the Mac's scene in CineSchedApp does not use it (its editor is `ContentView` alone).

import SwiftUI

struct ProjectEditor: View {
    let document: ProjectDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            PhoneEditor(document: document)
        } else {
            ContentView(document: document, layout: .threeColumn)
        }
    }
}

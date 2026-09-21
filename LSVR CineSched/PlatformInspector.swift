// PlatformInspector.swift
// Platform seam: the trailing inspector column of the three-column editor (#17). iPadOS
// and macOS have `.inspector(isPresented:)`, a system column that collapses to a sheet in
// compact width and carries its own width rules; visionOS has no such modifier at all
// (the SDK marks it unavailable there), so on that platform the inspector is a plain
// trailing pane beside the content, divided from it, of the same width the iPad's column
// takes by default. `ContentView` calls `trailingInspector` and stays free of the
// conditional; the visionOS pass (milestone 5 of #1) can give the pane its ornaments.

import SwiftUI

extension View {
    /// The inspector column at the trailing edge of this view, shown while `isPresented`.
    func trailingInspector<Inspector: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Inspector
    ) -> some View {
        #if os(visionOS)
        HStack(spacing: 0) {
            self
            if isPresented.wrappedValue {
                Divider()
                content()
                    .frame(width: 380)
            }
        }
        #else
        inspector(isPresented: isPresented) {
            content()
                // Wide enough for the two editors' button rows as they are; their
                // adaptive rewrite (#19) can bring this down.
                .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        #endif
    }
}

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
                    .frame(width: 340)
            }
        }
        #else
        inspector(isPresented: isPresented) {
            content()
                // The adaptive editors (#19) fit their forms and button rows in 300 pt
                // (the scene editor's trash, Cancel and Save row is the widest); 340 is
                // the width the calendar can spare beside a 300 pt sidebar.
                .inspectorColumnWidth(min: 300, ideal: 340, max: 560)
        }
        #endif
    }
}

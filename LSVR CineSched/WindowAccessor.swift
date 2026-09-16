// WindowAccessor.swift
// Platform seam: reaching the hosting NSWindow from SwiftUI so the theme's canvas color
// can also paint the window background and make the title bar transparent — otherwise
// the Mac shows a grey band above a tinted canvas. Only the Mac has a window to reach;
// on iOS and visionOS the accessor renders nothing and the theme color on the views is
// the whole story.

import SwiftUI

#if os(macOS)
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let backgroundColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(backgroundColor)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(backgroundColor)
            }
        }
    }
}

#else

struct WindowAccessor: View {
    let backgroundColor: Color

    var body: some View { Color.clear }
}

#endif

// PlatformColors.swift
// Platform seam: the two semantic system backgrounds the views used to read straight
// off AppKit (`NSColor.windowBackgroundColor` / `.controlBackgroundColor`). UIKit has no
// colors by those names, so this is the one place that picks the per-platform
// equivalent; every view and ThemeManager reads `Color.windowBackground` and
// `Color.controlBackground` and stays free of platform conditionals.
//
// Mapping: on the Mac the window background is the light grey chrome and the control
// background is the white content surface, so on iOS/visionOS the grouped background
// plays the window and the plain system background plays the control surface.

import SwiftUI

extension Color {
    /// The window's own chrome color (AppKit: `windowBackgroundColor`).
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// The surface content panels sit on (AppKit: `controlBackgroundColor`).
    static var controlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

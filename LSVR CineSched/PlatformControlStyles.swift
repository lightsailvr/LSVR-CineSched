// PlatformControlStyles.swift
// Platform seam: the three control styles the Mac UI uses that don't exist in UIKit-land
// (`.checkbox` toggles, `.radioGroup` pickers, `.borderlessButton` menus), and the one
// list style the iPhone editor uses that AppKit-land lacks (`.insetGrouped`, #24), plus
// the two toolbar touches of the window toolbar redesign that visionOS lacks (a window
// subtitle, and an item without the bar's shared glass). Views
// call these helpers instead of the styles directly, so they keep the Mac look on the Mac
// and fall back to the platform default elsewhere without a conditional at each call site.

import SwiftUI

extension View {
    /// `.toggleStyle(.checkbox)` on the Mac; the platform's default toggle elsewhere.
    func checkboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }

    /// `.pickerStyle(.radioGroup)` on the Mac; an inline list of choices elsewhere.
    func radioGroupPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.radioGroup)
        #else
        pickerStyle(.inline)
        #endif
    }

    /// `.menuStyle(.borderlessButton)` on the Mac; the platform's default menu elsewhere.
    func borderlessButtonMenuStyle() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton)
        #else
        self
        #endif
    }

    /// `.listStyle(.insetGrouped)` where it exists (iOS, visionOS): the iPhone's Days list
    /// and Day screen draw each day as a card (#24). The Mac, which never shows them,
    /// gets its `.inset` list.
    func insetGroupedListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }
}

extension View {
    /// `.navigationSubtitle` under the window title (the Mac's statistics line); nothing
    /// on visionOS, which has no such modifier.
    func windowSubtitle(_ subtitle: String) -> some View {
        #if os(visionOS)
        self
        #else
        navigationSubtitle(subtitle)
        #endif
    }
}

extension ToolbarContent {
    /// The item without the toolbar's shared Liquid Glass capsule, for a control that
    /// draws its own (the segmented view switcher: inside the capsule it showed as a pill
    /// within a pill) or a status that should read as text. visionOS has no such capsule
    /// modifier and leaves the item as it is.
    @ToolbarContentBuilder
    func withoutSharedToolbarBackground() -> some ToolbarContent {
        #if os(visionOS)
        self
        #else
        sharedBackgroundVisibility(.hidden)
        #endif
    }
}

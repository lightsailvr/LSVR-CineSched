// PlatformControlStyles.swift
// Platform seam: the three control styles the Mac UI uses that don't exist in UIKit-land
// (`.checkbox` toggles, `.radioGroup` pickers, `.borderlessButton` menus). Views call
// these helpers instead of the styles directly, so they keep the Mac look on the Mac and
// fall back to the platform default elsewhere without a conditional at each call site.

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
}

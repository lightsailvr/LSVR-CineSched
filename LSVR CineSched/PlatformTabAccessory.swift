// PlatformTabAccessory.swift
// Platform seam: the iPhone editor's tab bar (#24): it minimizes as the list scrolls down
// and carries the Today control as its bottom accessory, folded in beside the minimized
// bar. Both are iOS alone in the 27 SDK: `tabViewBottomAccessory` is marked unavailable on
// macOS and visionOS, and `TabBarMinimizeBehavior.onScrollDown` is too (the modifier
// itself compiles everywhere, its case does not). `PhoneEditor` compiles on every
// platform; the Mac never shows a compact editor and a Vision Pro window is never
// compact, so there the modifier does nothing and the control is not drawn.
// `PhoneEditor` calls `phoneTabBar(accessory:)` and stays free of the conditional.

import SwiftUI

extension View {
    /// The iPhone's tab bar behaviour: minimize on scroll, with `accessory` as the bar's
    /// bottom accessory on iOS; nothing elsewhere.
    func phoneTabBar<Accessory: View>(@ViewBuilder accessory: @escaping () -> Accessory) -> some View {
        #if os(iOS)
        self
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory { accessory() }
        #else
        self
        #endif
    }
}

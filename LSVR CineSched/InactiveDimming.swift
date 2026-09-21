// InactiveDimming.swift
// The inactive window's dimmed board (#22). With two projects open side by side (two Mac
// windows, two iPad windows in Stage Manager or Split View) the strips and the Boneyard
// are what make a window look "on", and they are custom-drawn, so nothing dims them the
// way the system dims a window's own controls; the user typing into the wrong project is
// the failure mode (story 66 of #1). The environment's `appearsActive` says whether the
// scene's window appears active on every platform (macOS 10.15, iOS 18, visionOS 2; the
// older `controlActiveState` is the Mac's alone and deprecated for it), so one
// platform-free modifier follows it: full strength while active, faded otherwise. The
// board keeps taking drops and taps while dimmed; only its look changes.

import SwiftUI

struct InactiveDimming: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive

    /// What an inactive window's board fades to: dim enough to read as inactive at a
    /// glance, light enough that the schedule is still legible for reference.
    static let inactiveOpacity = 0.55

    func body(content: Content) -> some View {
        content
            .opacity(appearsActive ? 1 : Self.inactiveOpacity)
            .animation(.easeInOut(duration: 0.15), value: appearsActive)
    }
}

extension View {
    /// Fades this view while its window is not the active one.
    func dimsWhenInactive() -> some View {
        modifier(InactiveDimming())
    }
}

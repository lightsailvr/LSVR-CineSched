// ActiveProjectCommands.swift
// How the iPad's menu bar reaches the active project (#22). On the Mac a menu item reads
// the key window's `ProjectCommands` through `@FocusedValue(\.projectCommands)`; on iPadOS
// 27 that value is nil unless the focus system is engaged (a hardware keyboard in use),
// and the menu bar is also reachable by touch, so the commands would be disabled exactly
// when a finger opens the menu. This holder is the other channel: the editor whose window
// appears active publishes its commands here, retires them when the window goes
// inactive or the editor disappears, and `CineSchedApp` falls back to it when the
// focused value is nil. Owners are keyed so two windows trading activation cannot clear
// each other: a retire only clears the commands its owner published.
//
// Platform-free; the Mac never puts one in the environment, so its editor publishes
// nothing and its menus keep the focused value alone.

import Observation
import SwiftUI

@Observable
final class ActiveProjectCommands {
    /// The active window's commands, nil while no project window is active.
    private(set) var commands: ProjectCommands?
    /// Which editor published `commands`.
    private var owner: UUID?

    /// Makes `owner`'s commands the active ones.
    func publish(_ commands: ProjectCommands, from owner: UUID) {
        self.commands = commands
        self.owner    = owner
    }

    /// Clears the commands if `owner` is still the one that published them.
    func retire(_ owner: UUID) {
        guard self.owner == owner else { return }
        commands   = nil
        self.owner = nil
    }
}

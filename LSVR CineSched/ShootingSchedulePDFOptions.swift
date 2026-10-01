// ShootingSchedulePDFOptions.swift
// What the Shooting Schedule export asks before it runs: whether each scene row adds its
// shot count and its description (the scene's summary). Both are remembered app-wide in
// UserDefaults through `@AppStorage` (the Shot List's pattern, ShotListPDFOptions.swift),
// never in the project file, so the sheet opens on the last choice in every project. Both
// start off, so the printout is the one the export always made until someone asks for more.
// Which days print is the call site's (the Stripboard header's one day, or the whole
// schedule), not an option. Pure.

import Foundation

struct ShootingSchedulePDFOptions: Equatable {
    /// "4 shots" on the row of a scene with a shot list.
    var includeShotCount:   Bool
    /// The scene's summary, one line under its cast.
    var includeDescription: Bool

    /// The first export: the rows as they always printed.
    static let `default` = ShootingSchedulePDFOptions(includeShotCount: false, includeDescription: false)
}

/// The UserDefaults keys, `@AppStorage`-friendly.
enum ShootingSchedulePDFOptionSettings {
    static let includeShotCountKey   = "CineSchedShootingScheduleIncludeShotCount"
    static let includeDescriptionKey = "CineSchedShootingScheduleIncludeDescription"
}

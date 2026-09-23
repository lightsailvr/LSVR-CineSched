// ShotListPDFOptions.swift
// What the Shot List export (#40) asks before it runs: the scope (the whole project or one
// shoot day) and whether the storyboard frames print. Both are remembered app-wide in
// UserDefaults through `@AppStorage` (the month export's pattern, MonthPDFOptions.swift),
// never in the project file, so the sheet opens on the last choice in every project.
//
// The remembered scope is a string: "project", or "day:" and the day's id. A day id belongs
// to one project, so read back in another project (or after the day left the range) it
// names nothing, and `scope(fromRaw:in:)` falls back to the whole project rather than
// offering a day that is not there. Pure; tested in ShotListPDFOptionsTests.

import Foundation

struct ShotListPDFOptions: Equatable {
    var scope:         ShotListScope
    var includeFrames: Bool

    /// The first export: the whole project, frames printed.
    static let `default` = ShotListPDFOptions(scope: .project, includeFrames: true)

    /// The days the sheet's day picker offers: the shoot days with a scene that prints, in
    /// schedule order (an empty or events-only day would export nothing).
    static func pickableDays(in shootDays: [ShootDay]) -> [ShootDay] {
        shootDays.filter { day in day.scenes.contains { ShotListExporter.prints($0) } }
    }
}

/// The UserDefaults keys and the scope's string form, `@AppStorage`-friendly.
enum ShotListPDFOptionSettings {
    static let scopeKey         = "CineSchedShotListScope"
    static let includeFramesKey = "CineSchedShotListIncludeFrames"

    static let projectRaw = "project"
    private static let dayPrefix = "day:"

    static func raw(for scope: ShotListScope) -> String {
        switch scope {
        case .project:      return projectRaw
        case .day(let id):  return dayPrefix + id.uuidString
        }
    }

    /// The remembered scope, if it still names something to export in `shootDays`: a day
    /// that is gone, or has nothing to print, and anything unreadable are the whole project.
    static func scope(fromRaw raw: String, in shootDays: [ShootDay]) -> ShotListScope {
        guard raw.hasPrefix(dayPrefix),
              let id = UUID(uuidString: String(raw.dropFirst(dayPrefix.count))),
              ShotListPDFOptions.pickableDays(in: shootDays).contains(where: { $0.id == id }) else { return .project }
        return .day(id)
    }
}

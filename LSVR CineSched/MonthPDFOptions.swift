// MonthPDFOptions.swift
// What the month PDF's breakdown pages print for every scene, chosen in the export
// dialog CalendarView shows before the save panel. Reuses StripboardField for the
// per-scene chips so the dialog, the Stripboard picker, and the scene editor all
// speak the same field names.
//
// Same reasoning as StripboardFieldSettings: this is an app-wide export preference,
// persisted in UserDefaults, not project data — the project file format is untouched.

import Foundation

struct MonthPDFOptions {
    /// Per-scene chips appended to each breakdown line, in StripboardField declaration order.
    var fields: Set<StripboardField>
    /// "2/8 pgs" after the slugline.
    var includePageCount: Bool
    /// The scene's estimated shooting time ("1 hr 30 min").
    var includeEstimatedTime: Bool

    /// Exactly what the breakdown printed before the dialog existed, so a user who
    /// just hits Export gets the same PDF they always did.
    static let `default` = MonthPDFOptions(
        fields: [.cast, .realLocation],
        includePageCount: true,
        includeEstimatedTime: false
    )
}

/// UserDefaults keys, `@AppStorage`-friendly (the field set rides on
/// StripboardFieldSettings' comma-joined string encoding).
enum MonthPDFOptionSettings {
    static let fieldsKey = "CineSchedMonthPDFFields"
    static let pagesKey  = "CineSchedMonthPDFShowPages"
    static let timeKey   = "CineSchedMonthPDFShowTime"

    static var defaultFieldsRaw: String { StripboardFieldSettings.encode(MonthPDFOptions.default.fields) }
}

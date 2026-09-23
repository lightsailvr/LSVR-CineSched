// ProjectCodec.swift
// The one place a project becomes bytes and back. Every save path (the manual Save, the
// UserDefaults working copy, the document writer) and every load path (Open, the working
// copy, the document reader, the legacy `.json` import) goes through these two functions,
// so the file format is defined exactly once. Extracted from the old `ProjectFile`
// FileDocument wrapper in ProjectStore.swift (#7) so the project document could read and
// write off the main actor with the same encoding.
//
// The format is ADR 0001's: pretty-printed JSON with ISO-8601 dates, evolved only by
// additive optional fields. `decode` also reads the two older shapes still in the wild:
// files whose dates are Foundation timestamps (written before the ISO formatter), and the
// original lineage's file that had only `allScenes` and `shootDays`.
//
// Nonisolated on purpose: the document reader and writer call it from `@concurrent`
// functions, and the model's Codable conformances are nonisolated so that is warning-free.

import Foundation

nonisolated enum ProjectCodec {

    /// The title given to a project read from the pre-title file shape. ProjectStore has
    /// always shown this, so it stays.
    static let legacyProjectTitle = "Loaded Project"

    // MARK: - Encode

    /// Keys sorted (#37): without `.sortedKeys` the encoder writes each object's keys in
    /// an order that differs from one object, and one save, to the next, so the same
    /// project never saved to the same bytes twice. With storyboard frames in the file
    /// (ADR 0007) a save is large and iCloud uploads it whole; a stable order means an
    /// unchanged project writes identical bytes. Readers never depended on the order.
    static func encode(_ project: ProjectData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .formatted(makeISODateFormatter())
        return try encoder.encode(project)
    }

    // MARK: - Decode

    /// Tries the current shape with ISO dates first, then with timestamp dates, then the
    /// legacy scenes-and-days shape. Throws only when none of the three fits.
    static func decode(_ data: Data) throws -> ProjectData {
        let formattedDecoder = JSONDecoder()
        formattedDecoder.dateDecodingStrategy = .formatted(makeISODateFormatter())
        if let result = try? formattedDecoder.decode(ProjectData.self, from: data) { return result }
        if let result = try? JSONDecoder().decode(ProjectData.self, from: data) { return result }
        let legacy = try JSONDecoder().decode(LegacyProjectData.self, from: data)
        return ProjectData(
            allScenes:    legacy.allScenes,
            shootDays:    legacy.shootDays,
            projectTitle: legacyProjectTitle
        )
    }

    // MARK: - Date format

    /// `2026-11-02T12:00:00-0800`: the pattern every file written since the ISO switch
    /// uses. Deliberately the formatter's default zone and locale, so the bytes match what
    /// the app has always written on this machine (see ADR 0001). A fresh instance per
    /// call because `DateFormatter` is not Sendable.
    private static func makeISODateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }
}

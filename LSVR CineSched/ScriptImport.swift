// ScriptImport.swift
// What the two script-import entry points share (#13): the file types a screenplay may
// have, the dispatch from a chosen file to the Final Draft or Fountain importer, and the
// mapping of Final Draft's parsed scenes into `Scene`s. The Mac's File ▸ Import Script…
// (ContentView+ScriptImport.swift) and the launch screen's Import Script… on iOS and
// visionOS (LaunchImportFlow.swift) both come here, so a format is supported, or a scene
// mapped, in exactly one place. Pure Swift: no panels, no views, no platform conditionals.
// The caller owns the file's security scope.

import Foundation
import UniformTypeIdentifiers

enum ScriptImport {

    // MARK: - Types

    /// Every screenplay type a chooser offers: Final Draft (`.fdx`, and `.xml` for an
    /// FDX saved under the generic extension) and the Fountain family, Highland
    /// included (`FountainImporter.supportedExtensions`). Dispatch is by extension: a
    /// Fountain-family extension goes to `FountainImporter`, anything else to
    /// `FinalDraftParser`, which is how the Mac's panel has always routed a choice.
    static var contentTypes: [UTType] {
        var types: [UTType] = []
        if let fdx = UTType(filenameExtension: "fdx") { types.append(fdx) }
        types.append(.xml)
        for ext in FountainImporter.supportedExtensions {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    /// Whether `url`'s extension routes to the Fountain importer (else Final Draft).
    static func isFountainFamily(_ url: URL) -> Bool {
        FountainImporter.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Parsing

    /// Reads and parses the screenplay at `url` in whichever format its extension says,
    /// as one `FountainImportResult` so the summary sheet can show any of them. A Final
    /// Draft script has no pagination pass or heuristics of its own, so its totals are
    /// summed from the scenes and it carries no warnings. Throws
    /// `FountainImportError.noScenesFound` for a script without scenes, whatever the
    /// format, and the parser's own error for a file it cannot read.
    static func parse(at url: URL) throws -> FountainImportResult {
        if isFountainFamily(url) {
            return try FountainImporter.parse(from: url)
        }
        let parsed = try FinalDraftParser.parseScenes(from: url)
        guard !parsed.isEmpty else { throw FountainImportError.noScenesFound }
        let scenes = self.scenes(from: parsed)
        let totalEighths = scenes.reduce(0) { $0 + $1.duration }
        var cast: [String] = []
        var seen: Set<String> = []
        for scene in scenes {
            for name in scene.cast where seen.insert(name).inserted { cast.append(name) }
        }
        return FountainImportResult(
            scenes:       scenes,
            totalPages:   (totalEighths + 7) / 8,
            totalEighths: totalEighths,
            castList:     cast.sorted(),
            warnings:     [],
            fileName:     url.lastPathComponent,
            title:        nil
        )
    }

    // MARK: - Final Draft mapping

    /// Final Draft's parsed scenes as Boneyard scenes: the location as the title, the
    /// time of day folded onto `DayNightType` (unknown reads as day), and the estimate
    /// derived from the eighths, which are floored at one so a heading-only scene still
    /// has a length.
    static func scenes(from parsed: [FinalDraftParser.ParsedScene]) -> [Scene] {
        parsed.map { ps in
            let type: DayNightType
            switch ps.timeOfDay {
            case .night:         type = .night
            case .dawn:          type = .dawn
            case .dusk:          type = .dusk
            case .afternoon:     type = .afternoon
            case .day, .unknown: type = .day
            }
            let duration = max(1, ps.duration)
            return Scene(
                title:         ps.location,
                sceneNumber:   ps.sceneNumber,
                duration:      duration,
                estimatedTime: TimeParser.estimatedMinutes(forEighths: duration),
                dayNightType:  type,
                cast:          ps.cast
            )
        }
    }
}

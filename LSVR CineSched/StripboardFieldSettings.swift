// StripboardFieldSettings.swift
// Which per-scene fields the Stripboard prints on each strip beside the slugline. Cast used
// to be the only one, hardwired into SceneStripRow; now it is one entry in this list so the
// user can add the Real Location / Set, Special Equipment, and the other breakdown tags to
// group strips by what actually drives the shoot day (one house, one drone rental, ...).
//
// The selection is an app-wide view preference, not project data: it lives in UserDefaults
// (like the strip color overrides and "Show Cast in Calendar") so the project file format
// is untouched and old files keep opening unchanged.

import SwiftUI

/// Every scene field that can be shown on a strip, in the order they appear left-to-right.
/// Keep this order stable: it is the display order, not the order the user ticked them.
enum StripboardField: String, CaseIterable, Identifiable {
    case cast
    case realLocation
    case summary
    case extras
    case props
    case setDressing
    case wardrobe
    case makeupHair
    case vehicles
    case specialEquipment
    case stunts
    case sfx
    case vfx
    case breakdownNotes

    var id: String { rawValue }

    /// Labels match SceneEditSheet so the sheet and the editor use the same words.
    var label: String {
        switch self {
        case .cast:             return L("Cast")
        case .realLocation:     return L("Real Location / Set")
        case .summary:          return L("Scene Summary")
        case .extras:           return L("Extras / Background")
        case .props:            return L("Props")
        case .setDressing:      return L("Set Dressing")
        case .wardrobe:         return L("Wardrobe")
        case .makeupHair:       return L("Hair & Makeup")
        case .vehicles:         return L("Vehicles")
        case .specialEquipment: return L("Special Equipment")
        case .stunts:           return L("Stunts")
        case .sfx:              return L("SFX")
        case .vfx:              return L("VFX")
        case .breakdownNotes:   return L("Breakdown Notes")
        }
    }

    /// One-line hint shown under the label in the picker sheet.
    var detail: String {
        switch self {
        case .cast:             return L("Character names on the scene")
        case .realLocation:     return L("The physical set or address the scene is shot at, e.g. Reseda House")
        case .summary:          return L("The scene's synopsis, truncated to one line")
        case .extras:           return L("Background performers")
        case .props:            return L("Hand props")
        case .setDressing:      return L("Set dressing and furniture")
        case .wardrobe:         return L("Costume notes")
        case .makeupHair:       return L("Hair and makeup notes")
        case .vehicles:         return L("Picture vehicles")
        case .specialEquipment: return L("Drone, crane, Steadicam, underwater housing...")
        case .stunts:           return L("Stunt requirements")
        case .sfx:              return L("Practical effects")
        case .vfx:              return L("Visual effects")
        case .breakdownNotes:   return L("Free-text breakdown notes")
        }
    }

    /// SF Symbol drawn in front of the value on the strip so the reader can tell which
    /// field a chip belongs to without a text label eating strip width.
    var icon: String {
        switch self {
        case .cast:             return "person.2"
        case .realLocation:     return "mappin.and.ellipse"
        case .summary:          return "text.alignleft"
        case .extras:           return "person.3"
        case .props:            return "hammer"
        case .setDressing:      return "sofa"
        case .wardrobe:         return "tshirt"
        case .makeupHair:       return "comb"
        case .vehicles:         return "car"
        case .specialEquipment: return "video"
        case .stunts:           return "figure.fall"
        case .sfx:              return "flame"
        case .vfx:              return "sparkles"
        case .breakdownNotes:   return "note.text"
        }
    }

    /// Emoji stand-in for `icon` in PDF output, where SF Symbols can't be drawn as
    /// text. Leads each pill on the month PDF breakdown pages so a reader can tell
    /// location from equipment from cast at a glance.
    var pdfEmoji: String {
        switch self {
        case .cast:             return "👥"
        case .realLocation:     return "📍"
        case .summary:          return "📖"
        case .extras:           return "🧍"
        case .props:            return "🔨"
        case .setDressing:      return "🛋️"
        case .wardrobe:         return "👕"
        case .makeupHair:       return "💄"
        case .vehicles:         return "🚗"
        case .specialEquipment: return "🎥"
        case .stunts:           return "🤸"
        case .sfx:              return "🔥"
        case .vfx:              return "✨"
        case .breakdownNotes:   return "📝"
        }
    }

    /// The text to print for this field on a strip; empty when the scene has nothing set,
    /// in which case the strip omits the chip entirely (same rule Cast always followed).
    /// Props, Special Equipment and SFX are the breakdown unions, the scene's items then
    /// its shots' (#37).
    func displayValue(for scene: Scene) -> String {
        switch self {
        case .cast:             return scene.cast.joined(separator: ", ")
        case .realLocation:     return scene.realLocation.trimmingCharacters(in: .whitespaces)
        case .summary:          return scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        case .extras:           return scene.extras.joined(separator: ", ")
        case .props:            return scene.allProps.joined(separator: ", ")
        case .setDressing:      return scene.setDressing.joined(separator: ", ")
        case .wardrobe:         return scene.wardrobe.joined(separator: ", ")
        case .makeupHair:       return scene.makeupHair.joined(separator: ", ")
        case .vehicles:         return scene.vehicles.joined(separator: ", ")
        case .specialEquipment: return scene.allSpecialEquipment.joined(separator: ", ")
        case .stunts:           return scene.stunts.joined(separator: ", ")
        case .sfx:              return scene.allSFX.joined(separator: ", ")
        case .vfx:              return scene.vfx.joined(separator: ", ")
        case .breakdownNotes:   return scene.breakdownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// What a fresh install shows: exactly what the Stripboard printed before this
    /// setting existed, so nobody's board changes on upgrade.
    static let defaultSelection: Set<StripboardField> = [.cast]
}

/// Persists the selection as a comma-joined list of raw values under one UserDefaults key.
/// A single string (rather than an array) keeps it `@AppStorage`-friendly, and an empty
/// string is a legitimate "show nothing extra" choice, distinct from the key being absent.
enum StripboardFieldSettings {
    static let defaultsKey = "CineSchedStripboardFields"

    static func encode(_ fields: Set<StripboardField>) -> String {
        // Encode in declaration order so equal sets always produce equal strings; @AppStorage
        // compares the raw string to decide whether the view needs to re-render.
        StripboardField.allCases.filter { fields.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    static func decode(_ raw: String) -> Set<StripboardField> {
        Set(raw.split(separator: ",").compactMap { StripboardField(rawValue: String($0)) })
    }

    /// The `@AppStorage` initial value: used only when the key has never been written.
    static var defaultRaw: String { encode(StripboardField.defaultSelection) }
}

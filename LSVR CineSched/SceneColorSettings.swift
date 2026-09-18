// SceneColorSettings.swift
// The scene strip color palette (#11): the eleven color slots, `ScenePalette` (the
// production's colors, an optional field of the project file), and the reader for the
// per-device overrides the pre-#11 builds kept in UserDefaults, which a project without a
// palette adopts once (see `ProjectDocument`). `Scene.stripColor(in:)` is the single
// resolver for every scene color in the app — the calendar, Stripboard, and the exporters
// all go through it — so the palette it is handed is the only thing that decides a color.
//
// Pure core: no platform types, nonisolated so `ProjectCodec` can encode a palette off
// the main actor.

import SwiftUI

// MARK: - Slots

/// Every distinct color slot `Scene.stripColor(in:)`'s (interior/exterior × time-of-day)
/// matrix can produce, plus Custom. Matches that matrix exactly so customizing a slot here changes
/// the same cell everywhere it's used. The raw value is the key in the project file.
nonisolated enum SceneColorSlot: String, CaseIterable, Identifiable {
    case intDay, extDay, intNight, extNight, intDawn, extDawn, intDusk, extDusk, intAfternoon, extAfternoon, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .intDay:       return "INT. Day"
        case .extDay:       return "EXT. Day"
        case .intNight:     return "INT. Night"
        case .extNight:     return "EXT. Night"
        case .intDawn:      return "INT. Dawn"
        case .extDawn:      return "EXT. Dawn"
        case .intDusk:      return "INT. Dusk"
        case .extDusk:      return "EXT. Dusk"
        case .intAfternoon: return "INT. Afternoon"
        case .extAfternoon: return "EXT. Afternoon"
        case .custom:       return "Custom"
        }
    }

    /// The original hardcoded values the strip color resolver always used — unchanged, just
    /// moved here so a non-customized slot still looks exactly like it did before.
    var defaultHex: String {
        switch self {
        case .intDay:       return "F3F4F6"
        case .extDay:       return "FEF08A"
        case .intNight:     return "86EFAC"
        case .extNight:     return "93C5FD"
        case .intDawn:      return "FDE68A"
        case .extDawn:      return "FCD34D"
        case .intDusk:      return "E9D5FF"
        case .extDusk:      return "C084FC"
        case .intAfternoon: return "FFE4C4"
        case .extAfternoon: return "FDBA74"
        case .custom:       return "D1D5DB"
        }
    }
}

// MARK: - Palette

/// The production's strip colors: a hex string per slot. Travels in the project file as a
/// flat object keyed by slot name (`"palette" : { "intDay" : "F3F4F6", … }`), so it reads
/// the same on every device. A slot the file leaves out resolves to the slot's default
/// and is not written back, so a hand-edited or partial palette round-trips as written;
/// the palettes the app itself makes (`standard`, an adoption, the editor's writes)
/// carry every slot.
nonisolated struct ScenePalette: Codable, Equatable {
    private var hexBySlot: [SceneColorSlot: String]

    /// The industry code with no customization, every slot written out.
    static let standard = ScenePalette(hexBySlot: Dictionary(uniqueKeysWithValues: SceneColorSlot.allCases.map { ($0, $0.defaultHex) }))

    init(hexBySlot: [SceneColorSlot: String]) {
        self.hexBySlot = hexBySlot
    }

    func hex(for slot: SceneColorSlot) -> String {
        hexBySlot[slot] ?? slot.defaultHex
    }

    /// For the views and the color pickers; `Color(hex:)` is main-actor, and nothing off
    /// it needs a `Color` (the exporters convert through `CGColor.of` on the main actor).
    @MainActor func color(for slot: SceneColorSlot) -> Color {
        Color(hex: hex(for: slot))
    }

    mutating func setHex(_ hex: String, for slot: SceneColorSlot) {
        hexBySlot[slot] = hex
    }

    // MARK: Codable

    /// Slot names as keys, so the file reads `"intDay" : "F3F4F6"`.
    private struct SlotKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ slot: SceneColorSlot) { stringValue = slot.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SlotKey.self)
        var hexBySlot: [SceneColorSlot: String] = [:]
        for slot in SceneColorSlot.allCases {
            // A key from a later build's slot, or a stray one, is dropped rather than an error.
            if let hex = try c.decodeIfPresent(String.self, forKey: SlotKey(slot)) {
                hexBySlot[slot] = hex
            }
        }
        self.hexBySlot = hexBySlot
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SlotKey.self)
        // Walked in slot order; the encoder orders the keys its own way, as it does the
        // rest of the file (ProjectCodec sets no `sortedKeys`).
        for slot in SceneColorSlot.allCases {
            if let hex = hexBySlot[slot] {
                try c.encode(hex, forKey: SlotKey(slot))
            }
        }
    }
}

// MARK: - Legacy device overrides

/// The per-device overrides the pre-#11 builds wrote to UserDefaults, one key per slot.
/// Nothing writes them any more: the editor edits the project's palette. They are read
/// once, when a project without a palette opens on a device that has them, and adopted
/// into that project (story 19 of #1); afterward the keys are ignored. Nonisolated because
/// the legacy handoff reads them inside the system's off-main-actor document factory.
nonisolated enum SceneColorSettings {
    static func key(for slot: SceneColorSlot) -> String {
        "CineSchedSceneColor_\(slot.rawValue)"
    }

    /// The device's overrides as a complete palette (the overridden slots plus the
    /// defaults for the rest), or nil when the device never customized a color, so a
    /// project opened here keeps waiting for a device that did.
    static func deviceOverrides(in defaults: UserDefaults = .standard) -> ScenePalette? {
        var palette = ScenePalette.standard
        var found   = false
        for slot in SceneColorSlot.allCases {
            if let hex = defaults.string(forKey: key(for: slot)) {
                palette.setHex(hex, for: slot)
                found = true
            }
        }
        return found ? palette : nil
    }
}

// MARK: - Environment

/// The palette of the document a view belongs to, set once at the editor's root so every
/// strip, card and sheet below it resolves colors from the same project (#11). Defaults
/// to the standard code for a view shown outside a document.
extension EnvironmentValues {
    @Entry var scenePalette: ScenePalette = .standard
}

extension Color {
    /// Best-effort hex string for persisting a user-picked color from a ColorPicker.
    /// Rounds to 8-bit sRGB, which is plenty of precision for a strip-color swatch.
    /// Goes through `Color.Resolved` instead of NSColor so it is platform-neutral;
    /// a wide-gamut pick is clamped into sRGB rather than producing a garbage byte.
    /// Resolving in a default `EnvironmentValues()` is fine for a picker color, which
    /// carries no appearance-dependent component.
    var hexString: String {
        let c = resolve(in: EnvironmentValues())
        func byte(_ component: Float) -> Int { Int((Double(min(max(component, 0), 1)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
    }
}

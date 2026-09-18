//
//  ScenePaletteTests.swift
//  LSVR CineSchedTests
//
//  The strip color palette (#11): `Scene.stripColor(in:)` is the single resolver and
//  draws only from the palette it is handed, and `SceneColorSettings.deviceOverrides`
//  turns the pre-#11 per-device keys into the palette a project adopts.
//

import SwiftUI
import Testing
@testable import LSVR_CineSched

@MainActor
struct ScenePaletteTests {

    // MARK: - Resolver

    @Test func stripColorResolvesEachSlotFromTheGivenPalette() {
        var palette = ScenePalette.standard
        palette.setHex("112233", for: .extDay)
        palette.setHex("445566", for: .intNight)
        palette.setHex("778899", for: .custom)

        let extDay   = Scene(title: "EXT. BEACH - DAY", sceneNumber: "1", duration: 8, estimatedTime: 30, dayNightType: .day)
        let intNight = Scene(title: "INT. KITCHEN - NIGHT", sceneNumber: "2", duration: 8, estimatedTime: 30, dayNightType: .night)
        let custom   = Scene(title: "INT. KITCHEN - LATER", sceneNumber: "3", duration: 8, estimatedTime: 30, dayNightType: .custom)
        let intDay   = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "4", duration: 8, estimatedTime: 30, dayNightType: .day)

        #expect(extDay.stripColor(in: palette).hexString   == "112233")
        #expect(intNight.stripColor(in: palette).hexString == "445566")
        #expect(custom.stripColor(in: palette).hexString   == "778899")
        // An untouched slot is the industry code.
        #expect(intDay.stripColor(in: palette).hexString   == SceneColorSlot.intDay.defaultHex)
        // The same scenes under the standard palette: the device it runs on plays no part.
        #expect(extDay.stripColor(in: .standard).hexString == SceneColorSlot.extDay.defaultHex)
    }

    @Test func completedAndNoticeStripsIgnoreThePalette() {
        var palette = ScenePalette.standard
        palette.setHex("FF0000", for: .intDay)
        var done = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "1", duration: 8, estimatedTime: 30, dayNightType: .day)
        done.isCompleted = true
        #expect(done.stripColor(in: palette).hexString == "9CA3AF")
    }

    // MARK: - Device overrides

    private func makeDefaults() throws -> UserDefaults {
        let name = "ScenePaletteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aDeviceWithNoOverridesHasNoPaletteToAdopt() throws {
        #expect(SceneColorSettings.deviceOverrides(in: try makeDefaults()) == nil)
    }

    @Test func deviceOverridesBecomeACompletePalette() throws {
        let defaults = try makeDefaults()
        defaults.set("ABCDEF", forKey: SceneColorSettings.key(for: .extNight))

        let palette = try #require(SceneColorSettings.deviceOverrides(in: defaults))
        #expect(palette.hex(for: .extNight) == "ABCDEF")
        #expect(palette.hex(for: .intDay)   == SceneColorSlot.intDay.defaultHex)
        var expected = ScenePalette.standard
        expected.setHex("ABCDEF", for: .extNight)
        #expect(palette == expected)
    }
}

//
//  StripboardFieldSettingsTests.swift
//  LSVR CineSchedTests
//
//  Round-trips the Stripboard field selection through its UserDefaults string form and
//  checks that each field reads the matching Scene property.
//

import Testing
@testable import LSVR_CineSched

struct StripboardFieldSettingsTests {

    @Test func encodeIsDeterministicAndInDeclarationOrder() {
        let a = StripboardFieldSettings.encode([.specialEquipment, .cast, .realLocation])
        let b = StripboardFieldSettings.encode([.realLocation, .specialEquipment, .cast])
        #expect(a == b)
        #expect(a == "cast,realLocation,specialEquipment")
    }

    @Test func decodeRoundTripsEverySubset() {
        let all = Set(StripboardField.allCases)
        #expect(StripboardFieldSettings.decode(StripboardFieldSettings.encode(all)) == all)
        #expect(StripboardFieldSettings.decode(StripboardFieldSettings.encode([])) == [])
        #expect(StripboardFieldSettings.decode("") == [])
    }

    @Test func decodeIgnoresUnknownRawValues() {
        #expect(StripboardFieldSettings.decode("cast,bogus,props") == [.cast, .props])
    }

    @Test func defaultSelectionIsCastOnly() {
        #expect(StripboardField.defaultSelection == [.cast])
        #expect(StripboardFieldSettings.defaultRaw == "cast")
    }

    @Test func displayValueReadsMatchingSceneProperty() {
        let scene = Scene(
            title: "INT. KITCHEN - DAY",
            sceneNumber: "12",
            cast: ["ANNA", "BEN"],
            summary: "  Anna burns the toast.\n",
            realLocation: " Reseda House ",
            props: ["Toaster"],
            specialEquipment: ["Drone", "Crane"]
        )
        #expect(StripboardField.cast.displayValue(for: scene) == "ANNA, BEN")
        #expect(StripboardField.realLocation.displayValue(for: scene) == "Reseda House")
        #expect(StripboardField.summary.displayValue(for: scene) == "Anna burns the toast.")
        #expect(StripboardField.props.displayValue(for: scene) == "Toaster")
        #expect(StripboardField.specialEquipment.displayValue(for: scene) == "Drone, Crane")
        // Fields the scene leaves blank come back empty so the strip can skip the chip.
        #expect(StripboardField.vehicles.displayValue(for: scene) == "")
        #expect(StripboardField.breakdownNotes.displayValue(for: scene) == "")
    }

    /// Props, Special Equipment and SFX chips read the breakdown unions (#37): the
    /// scene's items, then each shot's, case-insensitive duplicates dropped.
    @Test func displayValueReadsTheShotUnionsForTheirThreeFields() {
        var scene = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12", props: ["Lantern"], specialEquipment: ["Rain rig"])
        scene.shots = [
            Shot(details: "Wide",  equipment: ["Dolly"], props: ["lantern", "Mug"], sfx: ["Rain"]),
            Shot(details: "Close", equipment: ["dolly", "Ronin"]),
        ]
        #expect(StripboardField.props.displayValue(for: scene) == "Lantern, Mug")
        #expect(StripboardField.specialEquipment.displayValue(for: scene) == "Rain rig, Dolly, Ronin")
        #expect(StripboardField.sfx.displayValue(for: scene) == "Rain")
    }

    // MARK: - The Shots field (#42)

    @Test func theShotsFieldHasItsLabelIconAndEmoji() {
        #expect(StripboardField.shots.label == "Shots")
        #expect(StripboardField.shots.icon == "film.stack")
        #expect(!StripboardField.shots.detail.isEmpty)
        #expect(!StripboardField.shots.pdfEmoji.isEmpty)
        #expect(StripboardField.allCases.last == .shots)
    }

    @Test func theShotsFieldEncodesUnderItsOwnRawValue() {
        #expect(StripboardFieldSettings.encode([.shots]) == "shots")
        #expect(StripboardFieldSettings.encode([.cast, .shots]) == "cast,shots")
        #expect(StripboardFieldSettings.decode("cast,shots") == [.cast, .shots])
    }

    /// Off by default, and off for a user whose selection was saved before it existed:
    /// the saved string simply does not name it.
    @Test func theShotsFieldIsOffByDefaultAndForASavedSelection() {
        #expect(!StripboardField.defaultSelection.contains(.shots))
        let savedBeforeShots = StripboardFieldSettings.encode(Set(StripboardField.allCases).subtracting([.shots]))
        #expect(!StripboardFieldSettings.decode(savedBeforeShots).contains(.shots))
    }

    @Test func theShotsFieldCountsTheShotsAndIsEmptyForNone() {
        var scene = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12")
        #expect(StripboardField.shots.displayValue(for: scene) == "")
        scene.shots = [Shot(details: "Wide")]
        #expect(StripboardField.shots.displayValue(for: scene) == "1 shot")
        scene.shots = [Shot(details: "Wide"), Shot(details: "Close"), Shot(details: "Insert"), Shot(details: "Over")]
        #expect(StripboardField.shots.displayValue(for: scene) == "4 shots")
    }
}

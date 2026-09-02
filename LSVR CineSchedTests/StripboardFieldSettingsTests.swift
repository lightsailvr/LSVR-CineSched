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
}

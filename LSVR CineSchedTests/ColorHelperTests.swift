//
//  ColorHelperTests.swift
//  LSVR CineSchedTests
//
//  Pins the two Color helpers that used to go through AppKit — `hexString` (how a
//  ColorPicker choice is persisted) and `lightened(by:)` — so the platform-neutral
//  versions behave identically on every platform the app builds for.
//

import SwiftUI
import Testing
@testable import LSVR_CineSched

@MainActor
struct ColorHelperTests {

    @Test func hexStringRoundTripsEveryDefaultStripColor() {
        for slot in SceneColorSlot.allCases {
            #expect(Color(hex: slot.defaultHex).hexString == slot.defaultHex, "\(slot)")
        }
    }

    @Test func hexStringRoundsComponentsToEightBits() {
        #expect(Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1).hexString == "808080")
        #expect(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).hexString == "FF0000")
    }

    @Test func hexStringIgnoresOpacity() {
        #expect(Color(hex: "3DA65C").opacity(0.5).hexString == "3DA65C")
    }

    @Test func lightenedByZeroIsIdentity() {
        #expect(Color(hex: "808080").lightened(by: 0).hexString == "808080")
    }

    @Test func lightenedByOneIsWhite() {
        #expect(Color(hex: "000000").lightened(by: 1).hexString == "FFFFFF")
        #expect(Color(hex: "3DA65C").lightened(by: 1).hexString == "FFFFFF")
    }

    @Test func lightenedMixesTowardWhite() {
        #expect(Color(hex: "000000").lightened(by: 0.5).hexString == "808080")
    }

    @Test func lightenedKeepsOpacity() {
        let lightened = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.25).lightened(by: 0.5)
        #expect(lightened.resolve(in: EnvironmentValues()).opacity == 0.25)
    }
}

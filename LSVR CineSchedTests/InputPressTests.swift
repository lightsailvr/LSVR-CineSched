//
//  InputPressTests.swift
//  LSVR CineSchedTests
//
//  The press that selects (#22): only a pointer's click carries the modifier keys a
//  multi-selection reads; a finger and a Pencil select one strip whatever a hardware
//  keyboard holds. And the spatial event kinds the platform reports map to the app's.
//

import SwiftUI
import Testing
@testable import LSVR_CineSched

@MainActor
struct InputPressTests {

    @Test func aPointerClickCarriesItsModifiers() {
        let press = InputPress(kind: .pointer, modifiers: [.command])
        #expect(press.carriesModifiers)
        #expect(press.selectionModifiers == [.command])
        #expect(InputPress(kind: .pointer, modifiers: [.shift, .option]).selectionModifiers == [.shift, .option])
    }

    @Test func aTouchOrAPencilCarriesNone() {
        #expect(InputPress(kind: .touch,  modifiers: [.command]).selectionModifiers == [])
        #expect(InputPress(kind: .pencil, modifiers: [.shift]).selectionModifiers == [])
        #expect(InputPress(kind: .other,  modifiers: [.command]).selectionModifiers == [])
        #expect(!InputPress(kind: .touch).carriesModifiers)
    }

    @Test func theRecorderKeepsTheLatestPress() {
        let recorder = InputPressRecorder.shared
        recorder.record(InputPress(kind: .touch))
        #expect(recorder.latest == InputPress(kind: .touch))
        recorder.record(InputPress(kind: .pointer, modifiers: [.shift]))
        #expect(recorder.latest == InputPress(kind: .pointer, modifiers: [.shift]))
    }

    @Test func theEventKindsMapToTheAppsKinds() {
        #expect(ModifierKeys.inputKind(of: .touch)   == .touch)
        #expect(ModifierKeys.inputKind(of: .pointer) == .pointer)
    }
}

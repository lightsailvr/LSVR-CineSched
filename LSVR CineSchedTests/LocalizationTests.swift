//
//  LocalizationTests.swift
//  LSVR CineSchedTests
//
//  `L(_:)` is called from nearly every view body (menus, tooltips, labels), so it must be
//  a table lookup, not a table build (#34). Language switching itself is disabled.
//

import Testing
@testable import LSVR_CineSched

@MainActor
struct LocalizationTests {

    @Test func knownKeysResolveInBothLanguagesAndUnknownKeysPassThrough() {
        #expect(L("Boneyard") == "Boneyard")
        #expect(L("Boneyard", lang: .english) == "Boneyard")
        #expect(L("Boneyard", lang: .spanish) == "Escenas no asignadas")
        #expect(L("Not a key in the table") == "Not a key in the table")
    }

    @Test func lookupsReadTheGlobalTable() {
        #expect(localizationTable.count > 100)
        #expect(localizationTable["Boneyard"]?[.english] == L("Boneyard"))
    }
}

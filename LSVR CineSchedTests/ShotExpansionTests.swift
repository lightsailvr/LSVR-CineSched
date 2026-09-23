//
//  ShotExpansionTests.swift
//  LSVR CineSchedTests
//
//  Which Stripboard strips show their shots (#42): collapsed by default, Show Shots
//  expands every strip, a chevron flips one against it, and changing Show Shots folds the
//  chevrons' exceptions back into line.
//

import SwiftUI
import Testing
@testable import LSVR_CineSched

struct ShotExpansionTests {

    private let a = UUID()
    private let b = UUID()

    @Test func everyStripIsCollapsedByDefault() {
        let expansion = ShotExpansion()
        #expect(!expansion.isExpanded(a))
        #expect(!expansion.isExpanded(b))
    }

    @Test func aChevronExpandsOneStripAndCollapsesItAgain() {
        var expansion = ShotExpansion()
        expansion.toggle(a)
        #expect(expansion.isExpanded(a))
        #expect(!expansion.isExpanded(b))
        expansion.toggle(a)
        #expect(!expansion.isExpanded(a))
        #expect(expansion == ShotExpansion())
    }

    @Test func showShotsExpandsEveryStrip() {
        var expansion = ShotExpansion()
        expansion.toggle(a)
        expansion.setShowAll(true)
        #expect(expansion.isExpanded(a))
        #expect(expansion.isExpanded(b))
        #expect(expansion.exceptions.isEmpty)
    }

    @Test func aChevronStillCollapsesOneWhileShowShotsIsOn() {
        var expansion = ShotExpansion(showAll: true)
        expansion.toggle(b)
        #expect(expansion.isExpanded(a))
        #expect(!expansion.isExpanded(b))
    }

    @Test func turningShowShotsOffCollapsesEveryStrip() {
        var expansion = ShotExpansion(showAll: true)
        expansion.toggle(b)
        expansion.setShowAll(false)
        #expect(!expansion.isExpanded(a))
        #expect(!expansion.isExpanded(b))
        #expect(expansion == ShotExpansion())
    }

    // MARK: - The editors' bindings (#36 review)

    /// The binding the Mac window and the phone build over their two halves: a chevron
    /// writes the exceptions only, Show Shots writes the switch and drops the exceptions.
    @MainActor
    @Test func theBindingsWriteBackToTheEditorsTwoHalves() {
        final class Store { var showAll = false; var exceptions: Set<UUID> = [] }
        let store      = Store()
        let showAll    = Binding(get: { store.showAll },    set: { store.showAll = $0 })
        let exceptions = Binding(get: { store.exceptions }, set: { store.exceptions = $0 })
        let expansion  = ShotExpansion.binding(showAll: showAll, exceptions: exceptions)
        let showShots  = ShotExpansion.showAllBinding(expansion)

        expansion.wrappedValue.toggle(a)
        #expect(store.exceptions == [a])
        #expect(store.showAll == false)
        #expect(expansion.wrappedValue.isExpanded(a))

        showShots.wrappedValue = true
        #expect(store.showAll == true)
        #expect(store.exceptions == [])
        #expect(showShots.wrappedValue)
        #expect(expansion.wrappedValue.isExpanded(b))

        ShotExpansion.showAllBinding(expansion, animation: .default).wrappedValue = false
        #expect(store.showAll == false)
        #expect(!expansion.wrappedValue.isExpanded(a))
    }
}

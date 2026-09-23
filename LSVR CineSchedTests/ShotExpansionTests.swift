//
//  ShotExpansionTests.swift
//  LSVR CineSchedTests
//
//  Which Stripboard strips show their shots (#42): collapsed by default, Show Shots
//  expands every strip, a chevron flips one against it, and changing Show Shots folds the
//  chevrons' exceptions back into line.
//

import Foundation
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
}

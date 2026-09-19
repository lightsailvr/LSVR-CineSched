//
//  CineSchedFolderTests.swift
//  LSVR CineSchedTests
//
//  The CineSched folder is the iCloud Documents container the iOS, iPadOS and visionOS
//  builds own (#12, ADR 0006). The Mac has no iCloud entitlement, so it derives where
//  iCloud Drive keeps the folder instead of asking `FileManager`; these tests pin that
//  derivation and the identifier it starts from. What the Mac does with the path (seed the
//  Open and Save panels once, `MacAppDelegate`) is checked by hand.
//

import Foundation
import Testing
@testable import LSVR_CineSched

struct CineSchedFolderTests {

    /// The identifier is what the iOS entitlements and `NSUbiquitousContainers` name; a
    /// change here without a change there would point the Mac at a folder no device makes.
    @Test func containerIdentifierIsTheBundleIdentifierUnderICloud() {
        #expect(CineSchedFolder.containerIdentifier == "iCloud.com.lsvr.LSVR-CineSched")
        #expect(CineSchedFolder.displayName == "CineSched")
    }

    /// iCloud Drive materializes a container as `~/Library/Mobile Documents/<id with "~"
    /// for every ".">`, and the public, user-visible part of it is its `Documents` folder.
    @Test func macDocumentsFolderIsUnderMobileDocumentsWithTildesForDots() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let folder = CineSchedFolder.macDocumentsURL(home: home)
        #expect(folder.path == "/Users/someone/Library/Mobile Documents/iCloud~com~lsvr~LSVR-CineSched/Documents")
        #expect(folder.hasDirectoryPath)
    }

    /// The password database answers even inside a sandbox, where the process's own home
    /// is its container; the path is only ever used as a place for the panels to start.
    /// Mac-only: the simulators' password database is the host's, which is not an answer
    /// the iOS side ever asks for.
    #if os(macOS)
    @Test func realHomeDirectoryIsAnAbsoluteDirectory() throws {
        let home = try #require(CineSchedFolder.realHomeDirectory)
        #expect(home.path.hasPrefix("/Users/") || home.path.hasPrefix("/var/"))
        #expect(home.hasDirectoryPath)
    }
    #endif
}

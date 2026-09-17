//
//  LegacyWorkingCopyRecoveryTests.swift
//  LSVR CineSchedTests
//
//  The Mac's first launch after the document model recovers the working copy the previous
//  builds kept in UserDefaults (#10, story 15 of #1). The decision of what to open is a
//  pure function of the two legacy values; these tests pin one row of its table each.
//  What the Mac then does with the decision (resolve the bookmark, open through the
//  document controller, remove the keys) is `MacAppDelegate`'s and is checked by hand.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct LegacyWorkingCopyRecoveryTests {

    private let project = ProjectCodecTests.project
    private let fileURL = URL(fileURLWithPath: "/Users/someone/Documents/Long Way Home.json")

    private func bytes(of project: ProjectData) throws -> Data {
        try ProjectCodec.encode(project)
    }

    // MARK: - The decision table

    @Test func noWorkingCopyLaunchesNormally() throws {
        let bookmarked = LegacyWorkingCopyRecovery.BookmarkedFile(url: fileURL, contents: try bytes(of: project))
        #expect(LegacyWorkingCopyRecovery.decide(workingCopy: nil, bookmarkedFile: bookmarked) == .launchNormally)
        #expect(LegacyWorkingCopyRecovery.decide(workingCopy: nil, bookmarkedFile: nil) == .launchNormally)
    }

    @Test func workingCopyEqualToTheBookmarkedFileOpensThatFile() throws {
        let bookmarked = LegacyWorkingCopyRecovery.BookmarkedFile(url: fileURL, contents: try bytes(of: project))
        let decision   = LegacyWorkingCopyRecovery.decide(workingCopy: try bytes(of: project), bookmarkedFile: bookmarked)
        #expect(decision == .openFile(fileURL))
    }

    @Test func workingCopyDifferingFromTheBookmarkedFileOpensItUntitled() throws {
        var edited = project
        edited.projectTitle = "The Longer Way Home"
        let bookmarked = LegacyWorkingCopyRecovery.BookmarkedFile(url: fileURL, contents: try bytes(of: project))
        let decision   = LegacyWorkingCopyRecovery.decide(workingCopy: try bytes(of: edited), bookmarkedFile: bookmarked)
        #expect(decision == .openUntitled(edited))
    }

    @Test func unresolvableBookmarkOpensTheWorkingCopyUntitled() throws {
        let decision = LegacyWorkingCopyRecovery.decide(workingCopy: try bytes(of: project), bookmarkedFile: nil)
        #expect(decision == .openUntitled(project))
    }

    @Test func undecodableWorkingCopyLaunchesNormally() throws {
        let garbage    = Data("not a project".utf8)
        let bookmarked = LegacyWorkingCopyRecovery.BookmarkedFile(url: fileURL, contents: try bytes(of: project))
        #expect(LegacyWorkingCopyRecovery.decide(workingCopy: garbage, bookmarkedFile: bookmarked) == .launchNormally)
        #expect(LegacyWorkingCopyRecovery.decide(workingCopy: Data(), bookmarkedFile: nil) == .launchNormally)
    }

    /// A bookmark that resolves to something other than a project (the file was replaced,
    /// say) is no better than one that does not resolve: the working copy is what counts.
    @Test func undecodableBookmarkedFileOpensTheWorkingCopyUntitled() throws {
        let bookmarked = LegacyWorkingCopyRecovery.BookmarkedFile(url: fileURL, contents: Data("{}".utf8))
        let decision   = LegacyWorkingCopyRecovery.decide(workingCopy: try bytes(of: project), bookmarkedFile: bookmarked)
        #expect(decision == .openUntitled(project))
    }

    // MARK: - The legacy keys

    /// The names the previous builds wrote under (ProjectStore.swift on main); a typo here
    /// would silently recover nothing.
    @Test func keysAreThePreviousBuildsNames() {
        #expect(LegacyWorkingCopyRecovery.workingCopyKey == "SavedProject")
        #expect(LegacyWorkingCopyRecovery.bookmarkKey    == "CineSchedCurrentFileBookmark")
    }
}

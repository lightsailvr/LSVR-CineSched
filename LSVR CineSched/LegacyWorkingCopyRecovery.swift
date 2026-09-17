// LegacyWorkingCopyRecovery.swift
// What the Mac's first launch on the document model does with the working copy the
// previous builds kept in UserDefaults (#10, story 15 of #1). Those builds autosaved the
// window's project as a JSON blob two seconds after every change and only wrote a `.json`
// file on a manual Save, remembering that file as a security-scoped bookmark; a user who
// never pressed Save has their whole project in the blob. The document infrastructure
// replaced both (#8), so the upgrade must recover the blob once or the project is lost.
//
// The decision is pure, so every row of its table has a test
// (`LegacyWorkingCopyRecoveryTests`): no working copy, or one that does not decode, and the
// app launches as usual; a working copy equal to the bookmarked file's contents, and that
// file is opened (nothing unsaved exists); anything else, and the working copy opens as an
// untitled document so the user chooses where it lives. Reading the defaults, resolving the
// bookmark, opening and removing the keys afterward are the Mac's (`MacAppDelegate`).

import Foundation

enum LegacyWorkingCopyRecovery {

    // MARK: - Legacy keys

    /// The working copy: `ProjectCodec` JSON, written by `saveDefaultProject` on main.
    static let workingCopyKey = "SavedProject"
    /// The file last saved or opened, as a security-scoped bookmark (`setCurrentFileURL`).
    static let bookmarkKey    = "CineSchedCurrentFileBookmark"

    // MARK: - Decision

    /// The bookmarked file once resolved and read; nil when there was no bookmark, it no
    /// longer resolves, or the file could not be read.
    struct BookmarkedFile: Equatable {
        let url:      URL
        let contents: Data
    }

    enum Decision: Equatable {
        /// Nothing to recover.
        case launchNormally
        /// The working copy is what is in this file: open the file.
        case openFile(URL)
        /// The working copy holds edits no file has: open it as an untitled document.
        case openUntitled(ProjectData)
    }

    static func decide(workingCopy: Data?, bookmarkedFile: BookmarkedFile?) -> Decision {
        guard let workingCopy, let project = try? ProjectCodec.decode(workingCopy) else {
            return .launchNormally
        }
        if let bookmarkedFile, let saved = try? ProjectCodec.decode(bookmarkedFile.contents), saved == project {
            return .openFile(bookmarkedFile.url)
        }
        return .openUntitled(project)
    }
}

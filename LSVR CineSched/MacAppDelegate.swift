// MacAppDelegate.swift
// Platform seam: the Mac's application delegate. It has two launch-time jobs.
//
// The first is the first launch after the document model (#10, story 15 of #1): recover
// the working copy the previous builds autosaved to UserDefaults, which the document
// infrastructure never reads. The decision of what to open is `LegacyWorkingCopyRecovery`'s
// (pure, tested); this file reads the two legacy defaults, resolves the file bookmark
// under its security scope, opens what the decision says through the document controller
// `DocumentGroup` runs on, and removes the keys once that open has succeeded.
//
// The second is pointing the system's Open and Save panels at the CineSched folder in
// iCloud Drive (#12, ADR 0006) once it exists on this Mac; see `seedPanelsWithCineSchedFolder`.
//
// Why a delegate and not a view: with iCloud Drive on, a document app launched with
// nothing to open shows the Open panel rather than an untitled window (learnings,
// 2026-09-16 #8), so no editor view exists at launch to run this from, and SwiftUI's
// `openDocument` and `newDocument` actions need one. `NSDocumentController` is what those
// actions drive anyway. The recovery runs in `applicationDidFinishLaunching`, which comes
// before AppKit's launch-time "open untitled" step; a document already open (or opening)
// by then is what keeps that step from adding the Open panel or a blank window. SwiftUI's
// own delegate does not forward `applicationShouldOpenUntitledFile`, so that is not a
// hook here (learnings, 2026-09-17 #10).
//
// Mac-only because the working copy only ever existed on the Mac, and because the panels
// are; iOS and visionOS have nothing to recover and open the CineSched folder through
// their iCloud entitlement.

#if os(macOS)
import AppKit
import os

final class MacAppDelegate: NSObject, NSApplicationDelegate {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lsvr.LSVR-CineSched", category: "Launch")

    // MARK: - Untitled document seed

    /// The project the next untitled document should hold instead of File ▸ New's blank
    /// month. `makeDocument` in CineSchedApp takes it. Set only by the recovery, right
    /// before it asks the document controller for an untitled document; the
    /// infrastructure builds the SwiftUI document after that call returns, not inside it,
    /// so the seed stays set until `makeDocument` runs.
    private static var pendingUntitledProject: ProjectData?

    /// Taking the seed is the moment the working copy exists in a document, so it is also
    /// the moment the legacy keys go: a failure anywhere before it leaves them for the
    /// next launch to retry.
    static func takePendingUntitledProject() -> ProjectData? {
        guard let project = pendingUntitledProject else { return nil }
        pendingUntitledProject = nil
        removeLegacyKeys()
        return project
    }

    // MARK: - Launch

    /// The bookmarked file's URL while its security-scoped access is started: from
    /// resolution until the recovery is done with the file (the read, and the open when
    /// that is the decision).
    private var accessedBookmarkURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        seedPanelsWithCineSchedFolder()
        recoverLegacyWorkingCopy()
    }

    // MARK: - CineSched folder

    /// The defaults key `NSSavePanel` and `NSOpenPanel` keep their last directory in; an
    /// absolute path steers the next panel there, and each confirmed panel rewrites it.
    private static let panelDirectoryKey = "NSNavLastRootDirectory"
    /// Set once the nudge below has happened, so it happens exactly once per Mac.
    private static let folderSeededKey   = "CineSchedFolderPanelSeeded"

    /// Points the system's Open and Save panels at the CineSched folder in iCloud Drive
    /// the first time it exists on this Mac (ADR 0006). The Mac has no iCloud entitlement,
    /// so `FileManager` cannot name the container and no code of ours runs inside the
    /// system's panels (`DocumentGroup` owns them and `directoryURL` is out of reach);
    /// what works under the sandbox is the panels' own memory: they start in
    /// `NSNavLastRootDirectory`, honour a path outside the container (the panel runs out
    /// of process), and the app may `stat` the folder even though it may not read it.
    /// One nudge, not a pin: a Mac that has saved projects for years already has a
    /// remembered directory, so the nudge is keyed on its own flag rather than on the key
    /// being unset, and after it the panels remember wherever the user last saved, as in
    /// every Mac app. Runs before AppKit's launch-time "open untitled" step, which is
    /// what shows the Open panel when iCloud Drive is on, so that panel is steered too.
    private func seedPanelsWithCineSchedFolder() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.folderSeededKey),
              let home = CineSchedFolder.realHomeDirectory else { return }
        let folder = CineSchedFolder.macDocumentsURL(home: home)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        defaults.set(folder.path, forKey: Self.panelDirectoryKey)
        defaults.set(true, forKey: Self.folderSeededKey)
        Self.log.notice("Pointed the Open and Save panels at the CineSched folder: \(folder.path, privacy: .public)")
    }

    // MARK: - Recovery

    private func recoverLegacyWorkingCopy() {
        let defaults   = UserDefaults.standard
        let bookmarked = resolveBookmarkedFile(defaults.data(forKey: LegacyWorkingCopyRecovery.bookmarkKey))
        let decision   = LegacyWorkingCopyRecovery.decide(
            workingCopy:    defaults.data(forKey: LegacyWorkingCopyRecovery.workingCopyKey),
            bookmarkedFile: bookmarked
        )

        switch decision {
        case .launchNormally:
            // Nothing to recover. With no blob, the bookmark alone is dead weight and goes.
            // A blob that does not decode is left where it is (the keys are cheap to check
            // on every launch): the previous builds could not read it either, but deleting
            // it would foreclose a later decoder reading it.
            releaseBookmarkedFile()
            if defaults.data(forKey: LegacyWorkingCopyRecovery.workingCopyKey) == nil {
                Self.removeLegacyKeys()
            } else {
                Self.log.error("The working copy in UserDefaults does not decode; leaving it in place")
            }

        case .openFile(let url):
            // The working copy is exactly what is in the file, so the file is the project.
            // A legacy .json opens the way File ▸ Open opens one: its contents move to an
            // untitled .cinesched document (LegacyProjectHandoff) and the .json is never
            // written. The keys go only once the open has succeeded; on failure they stay
            // for the next launch to retry.
            Self.log.notice("Recovering the working copy by opening \(url.path, privacy: .public)")
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [self] _, _, error in
                releaseBookmarkedFile()
                if let error {
                    Self.log.error("Opening the bookmarked file failed: \(error.localizedDescription, privacy: .public)")
                    NSDocumentController.shared.presentError(error)
                } else {
                    Self.removeLegacyKeys()
                }
            }

        case .openUntitled(let project):
            // Edits no file has: an untitled document holding them, marked edited so that
            // closing it asks to save (the infrastructure marks edits from registered undo
            // actions, and a seeded project registers none). As after any edit, the title's
            // "Edited" clears once the draft has autosaved; the document stays edited. The
            // keys go when `makeDocument` takes the seed, not here.
            releaseBookmarkedFile()
            Self.pendingUntitledProject = project
            do {
                let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                document.updateChangeCount(.changeDone)
                Self.log.notice("Recovered the working copy into an untitled document")
            } catch {
                Self.pendingUntitledProject = nil
                Self.log.error("Opening the working copy untitled failed: \(error.localizedDescription, privacy: .public)")
                NSDocumentController.shared.presentError(error)
            }
        }
    }

    // MARK: - Legacy defaults

    /// Resolves the previous builds' current-file bookmark and reads the file. The
    /// bookmark was made `.withSecurityScope` (FilePanels on main), so it resolves the
    /// same way and the file is readable only while its access is started; that access
    /// stays open until `releaseBookmarkedFile`.
    private func resolveBookmarkedFile(_ bookmark: Data?) -> LegacyWorkingCopyRecovery.BookmarkedFile? {
        guard let bookmark else { return nil }
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            // A deleted file resolves as "not in the correct format" (259), not "no such file".
            Self.log.notice("The current-file bookmark did not resolve: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // The result is not checked: it is false outside the sandbox, where no scope is
        // needed, and a file that is really unreadable fails the read below.
        _ = url.startAccessingSecurityScopedResource()
        accessedBookmarkURL = url
        guard let contents = try? Data(contentsOf: url) else {
            Self.log.notice("The bookmarked file could not be read: \(url.path, privacy: .public)")
            releaseBookmarkedFile()
            return nil
        }
        return LegacyWorkingCopyRecovery.BookmarkedFile(url: url, contents: contents)
    }

    private func releaseBookmarkedFile() {
        accessedBookmarkURL?.stopAccessingSecurityScopedResource()
        accessedBookmarkURL = nil
    }

    private static func removeLegacyKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: LegacyWorkingCopyRecovery.workingCopyKey)
        defaults.removeObject(forKey: LegacyWorkingCopyRecovery.bookmarkKey)
    }
}
#endif

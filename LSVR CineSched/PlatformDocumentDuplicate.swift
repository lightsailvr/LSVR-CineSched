// PlatformDocumentDuplicate.swift
// Platform seam: File ▸ Duplicate on the Mac, rerouted around a SwiftUI deadlock.
//
// The system's Duplicate hangs the app for good on macOS 27.0 (Xcode 27A266a). After it
// saves the document, `URLPlatformDocument.duplicate(withDelegate:…)` calls
// `-[NSDocumentController duplicateDocumentWithContentsOfURL:copying:displayName:error:]`,
// which makes the copy with the synchronous `-[NSDocument readFromURL:ofType:error:]` on
// the main thread. SwiftUI's document answers that read by starting a task for the async
// read and blocking the main thread on a semaphore until it ends; the task needs the main
// actor (`makeDocument` and `apply` are main-actor by the API), so it never runs. Nothing
// in `ProjectDocument` changes that, and the action cannot be caught earlier: the hosting
// view hands `duplicateDocument:` straight to the document (`supplementalTarget`, so a
// responder after the window never sees it) and the SwiftUI menu item ignores a target.
//
// The one step that can be replaced is the controller's: `install()` swaps
// `duplicateDocumentWithContentsOfURL:…` on the shared controller's class (SwiftUI's
// private `PlatformDocumentController`, so not a subclass of our own) for a version that
// reads the file AppKit just saved through `ProjectCodec` (no main-actor hop) and opens it
// untitled through `openUntitledDocumentAndDisplay`, whose `makeDocument` takes the
// project from `MacAppDelegate`'s untitled seed, as the working-copy recovery does. The
// copy is marked edited, so closing it asks to save, and its first Save asks where.
// Remove this once SwiftUI's own Duplicate stops hanging (check after each Xcode update:
// delete the `install()` call and press ⇧⌘S on an open project).
//
// Mac-only because the document controller is; on iOS and visionOS the document browser
// duplicates files itself.

#if os(macOS)
import AppKit
import ObjectiveC
import os

enum DocumentDuplicateRoute {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lsvr.LSVR-CineSched", category: "Duplicate")

    private typealias DuplicateBlock = @convention(block) (
        NSDocumentController, NSURL, Bool, NSString?, NSErrorPointer
    ) -> NSDocument?

    /// Replaces the shared controller's duplicate step, once. Call it after launch, when
    /// `NSDocumentController.shared` is SwiftUI's.
    static func install() {
        let controllerClass: AnyClass = type(of: NSDocumentController.shared)
        let selector = #selector(NSDocumentController.duplicateDocument(withContentsOf:copying:displayName:))
        guard let method = class_getInstanceMethod(controllerClass, selector) else {
            log.error("No duplicate method on \(String(describing: controllerClass), privacy: .public); Duplicate is left as the system has it")
            return
        }
        let block: DuplicateBlock = { controller, url, _, displayName, error in
            MainActor.assumeIsolated {
                duplicate(url as URL, displayName: displayName as String?, controller: controller, error: error)
            }
        }
        // `class_replaceMethod` adds the method to the subclass when only NSDocumentController
        // implements it, so the base class stays untouched.
        class_replaceMethod(controllerClass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    @MainActor
    private static func duplicate(_ url: URL, displayName: String?, controller: NSDocumentController, error: NSErrorPointer) -> NSDocument? {
        do {
            let project = try ProjectCodec.decode(Data(contentsOf: url))
            MacAppDelegate.seedUntitledProject(project)
            let document = try controller.openUntitledDocumentAndDisplay(true)
            document.updateChangeCount(.changeDone)
            return document
        } catch let failure as NSError {
            MacAppDelegate.clearUntitledProjectSeed()
            log.error("Duplicate failed: \(failure.localizedDescription, privacy: .public)")
            error?.pointee = failure
            return nil
        }
    }
}
#endif

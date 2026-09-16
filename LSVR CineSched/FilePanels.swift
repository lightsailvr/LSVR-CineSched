// FilePanels.swift
// Platform seam: how the app reaches files the user chooses. On the Mac that is
// NSOpenPanel / NSSavePanel plus the security-scoped bookmarks that let a sandboxed app
// reopen a chosen file in a later launch. iOS and visionOS have neither the panels nor
// `.withSecurityScope` (their bookmarks are implicitly scoped), so this file is the one
// place that knows; callers (ProjectStore, RecentFilesStore, the PDF export actions)
// stay free of platform conditionals.
//
// On iOS and visionOS the panels are deliberately inert: the system document browser
// replaces them when the project document lands (milestone 2 of #1), and until then
// nothing on those platforms offers a way to open or save a file.

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum FilePanels {

    // MARK: - Bookmarks

    /// Options for `URL.bookmarkData(options:…)` when remembering a user-chosen file.
    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    /// Options for `URL(resolvingBookmarkData:options:…)` on a bookmark made above.
    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    // MARK: - Panels

    /// Asks the user for one existing file. `completion` runs on the main queue only when
    /// a file was chosen; cancelling calls nothing.
    static func chooseFile(
        title: String,
        prompt: String,
        allowedTypes: [UTType],
        directory: URL?,
        completion: @escaping (URL) -> Void
    ) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title                   = title
        panel.prompt                  = prompt
        panel.allowedContentTypes     = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        if let directory { panel.directoryURL = directory }
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }
        #endif
    }

    /// Asks the user where to write a new file. `completion` runs on the main queue only
    /// when a location was chosen; cancelling calls nothing. A nil `prompt` keeps the
    /// system's default button title.
    static func chooseSaveLocation(
        title: String,
        prompt: String? = nil,
        nameFieldLabel: String? = nil,
        defaultName: String,
        allowedTypes: [UTType],
        directory: URL?,
        completion: @escaping (URL) -> Void
    ) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title                = title
        if let prompt         { panel.prompt         = prompt }
        if let nameFieldLabel { panel.nameFieldLabel = nameFieldLabel }
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes  = allowedTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden    = false
        if let directory { panel.directoryURL = directory }
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }
        #endif
    }
}

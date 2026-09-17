// FilePanels.swift
// Platform seam: how the app reaches files the user chooses for something other than the
// project itself — a script to import, a place to write a PDF. On the Mac that is
// NSOpenPanel / NSSavePanel; iOS and visionOS have no panels, so this file is the one
// place that knows and the callers (the script import and the PDF export actions) stay
// free of platform conditionals. The project's own open and save are the document
// infrastructure's (#8), which also handles the sandbox's security scope for them.
//
// On iOS and visionOS the panels are deliberately inert: the share sheet replaces the
// save panel in milestone 3 (#23), and the script chooser is the launch scene's (#13).

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum FilePanels {

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

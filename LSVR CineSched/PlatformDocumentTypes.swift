// PlatformDocumentTypes.swift
// Platform seam: which file types the project document opens on each platform (#12,
// ADR 0006). The Mac reads a legacy `.json` in a viewer role (File ▸ Open lists it,
// `LegacyProjectHandoff` moves its contents to an untitled `.cinesched`, the original is
// never written; ADR 0005). iOS and visionOS have no such role: their document browser
// and launch screen offer exactly the readable types, so listing `.json` there would show
// every JSON on the device as a project and hand the editor a document its writer refuses
// to save. On those platforms a legacy file is imported into a new project instead (#13),
// and the only readable type is the native one. `ProjectDocument` asks here so that it
// stays free of `#if os`.

import UniformTypeIdentifiers

nonisolated enum PlatformDocumentTypes {
    /// The types `ProjectDocument.readableContentTypes` reports, native type first.
    static var readable: [UTType] {
        #if os(macOS)
        return [.cineschedProject, .json]
        #else
        return [.cineschedProject]
        #endif
    }
}

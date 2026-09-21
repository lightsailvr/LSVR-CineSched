// PlatformExportPresentation.swift
// Platform seam: where a PDF export goes, and the view that shows one (#23).
//
// The Mac keeps its save panels (`FilePanels`, in ContentView+PDFExports.swift): a PDF
// is an export, and a Mac user expects to be asked where it goes. iOS and visionOS have
// no save panel; there the export opens in a preview sheet with a Share button, whose
// share sheet is how the file reaches AirDrop, Messages, Mail, Print and Save to Files
// (`PDFExportPresentation`). `previewsExports` is that choice, so the call sites in
// ContentView+PDFExports.swift stay free of the conditional.
//
// The preview itself is PDFKit's `PDFView` wrapped for SwiftUI: a `UIViewRepresentable`
// on iOS and visionOS (PDFKit ships on both; UIKit is the visionOS view layer too, so
// one wrapper serves the iPad and the Vision Pro) and an `NSViewRepresentable` on the
// Mac, where it compiles and is never shown. Quick Look would also render a PDF on
// every platform, but it takes a file URL rather than data, presents in its own window
// on visionOS, and owns its toolbar; PDFKit keeps the preview inside the app's sheet
// with the app's Done and Share buttons on all three.

import PDFKit
import SwiftUI

nonisolated enum PlatformExportPresentation {
    /// True where an export is shown in the preview sheet with Share; false where the
    /// save panel takes it.
    #if os(macOS)
    static let previewsExports = false
    #else
    static let previewsExports = true
    #endif
}

// MARK: - PDF view

/// PDFKit's view over the export's bytes: every page, scrolled vertically, scaled to
/// the width of the sheet.
struct PlatformPDFView {
    let data: Data

    /// The bytes the view was last loaded with, so an update can tell a new export from
    /// SwiftUI's own re-render. (PDFKit re-serialises a document, so comparing
    /// `document.dataRepresentation()` to the source never matched and reloaded, and reset
    /// the scroll position, on every update.)
    final class Coordinator {
        var loaded: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(_ view: PDFView, coordinator: Coordinator) {
        view.autoScales       = true
        view.displayMode      = .singlePageContinuous
        view.displayDirection = .vertical
        load(view, coordinator: coordinator)
    }

    /// Replaces the document only when the bytes changed (`updateView` runs on every
    /// SwiftUI update of the sheet, and reloading would reset the scroll position).
    private func update(_ view: PDFView, coordinator: Coordinator) {
        guard coordinator.loaded != data else { return }
        load(view, coordinator: coordinator)
    }

    private func load(_ view: PDFView, coordinator: Coordinator) {
        view.document      = PDFDocument(data: data)
        coordinator.loaded = data
    }
}

#if os(macOS)
extension PlatformPDFView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        update(view, coordinator: context.coordinator)
    }
}
#else
extension PlatformPDFView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        update(view, coordinator: context.coordinator)
    }
}
#endif

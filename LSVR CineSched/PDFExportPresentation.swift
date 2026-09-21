// PDFExportPresentation.swift
// Where an export goes on the iPad, the iPhone and the Vision Pro (#23): a sheet that
// shows the PDF (PDFKit, through the `PlatformExportPresentation` seam) with Done and a
// Share button, whose share sheet offers AirDrop, Messages, Mail, Print, Save to Files
// and the rest for the file under its export name. The Mac never presents it: its save
// panels stay in ContentView+PDFExports.swift, and the seam says which way to go.
//
// The request is `Transferable` as a file so the share sheet, Files and Mail all see
// "The_Long_Way_Home_StripSchedule.pdf", not "PDF document": a data representation
// carries no name. The file is written on demand into the app's temporary directory,
// which the system clears; nothing is written before the user shares.
//
// Platform-free SwiftUI, sized for a compact screen too (the iPhone wiring is a later
// ticket): the preview fills the sheet and the two buttons are in the toolbar.

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sharing

extension PDFExportRequest: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { request in
            let url = try request.writeTemporaryFile()
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        }
    }

    /// Writes the bytes under the export name in a directory of their own (two exports
    /// of the same document must not overwrite each other while one is still being
    /// sent) inside the temporary directory.
    nonisolated func writeTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFExports", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - The preview sheet

/// The exported PDF, its document's name as the title, Done and Share.
struct PDFExportPreviewSheet: View {
    let request: PDFExportRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlatformPDFView(data: request.data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(request.kind.title)
                .toolbarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: request,
                            preview: SharePreview(request.fileName, image: Image(systemName: "doc.richtext"))
                        )
                    }
                }
        }
        // A page-sized sheet on the iPad and the Vision Pro: the form size the sheet
        // would take by default shows a letter page at a third of its width.
        .presentationSizing(.page)
    }
}

// MARK: - The modifier

extension View {
    /// Presents the preview sheet for `request` while it is non-nil; the sheet clears it.
    /// Attached at the editor's root by `ContentView`, on every platform (the Mac never
    /// sets a request, so it never presents).
    func pdfExportPresentation(_ request: Binding<PDFExportRequest?>) -> some View {
        sheet(item: request) { request in
            PDFExportPreviewSheet(request: request)
        }
    }
}

// LegacyProjectHandoff.swift
// Platform seam: what the Mac shows in place of the editor when the document it opened is
// a legacy `.json` (#8, story 13 of #1). The document infrastructure autosaves an opened
// file in place within seconds of an edit and does not treat a readable-but-unwritable
// type as read-only, so editing the `.json` document itself would rewrite the user's
// legacy file. Instead, once the file's contents have arrived, this view hands them to the
// system's new-document action, which opens them as an untitled `.cinesched` document
// whose first Save asks where to go, and closes the `.json` window. The original is never
// written. Mac-only because `newDocument` is; iOS and visionOS import a legacy file from
// their launch screen instead (#13).

#if os(macOS)
import SwiftUI

struct LegacyProjectHandoff: View {
    let document: ProjectDocument
    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismiss) private var dismiss
    @State private var handedOff = false

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L("Opening legacy project…"))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, minHeight: 200)
        .onAppear(perform: handOff)
        // The contents may land after the window appears; `hasLoadedSnapshot` flips then.
        .onChange(of: document.hasLoadedSnapshot) { _, _ in handOff() }
    }

    private func handOff() {
        guard !handedOff, document.hasLoadedSnapshot else { return }
        handedOff = true
        let project = document.project
        newDocument(ProjectDocument(untitled: project))
        dismiss()
    }
}
#endif

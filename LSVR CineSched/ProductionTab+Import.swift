// ProductionTab+Import.swift
// The Production tab's Import section (#28): Import Script… into this project. The
// `fileImporter` picks a Fountain, Final Draft or Highland file (`ScriptImport.contentTypes`),
// the script is parsed (`ScriptImport.parse`, any format to one result) and shown in
// `ImportSummaryView`'s `.existingProject` confirmation, and only Add to Boneyard writes:
// one `edit` appending the scenes to `allScenes`. Cancel, on the picker or the summary,
// leaves the project as it was; a parse failure is the tab's alert.

import SwiftUI

extension ProductionTab {

    // MARK: - The section

    var importSection: some View {
        Section {
            actionRow(L("Import Script…"), systemImage: "square.and.arrow.down", detail: L("Fountain, Final Draft, Highland")) {
                showingImportPicker = true
            }
        } header: {
            Text(L("Import"))
        } footer: {
            Text(L("The script's scenes are added to this project's Boneyard after you review the summary."))
        }
    }

    // MARK: - Import

    // MARK: - Import

    /// The picker returned: parse the script (any format, `ScriptImport`) and show the
    /// summary; nothing is written until Add to Boneyard.
    func importPickerFinished(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try ScriptImport.parse(at: url)
                activeSheet   = .importSummary
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    /// Add to Boneyard: the one write, and the summary closes.
    func commitImport(_ result: FountainImportResult) {
        edit(L("Import Script")) { $0.allScenes.append(contentsOf: result.scenes) }
        activeSheet = nil
    }

    /// The summary before the write, with Add to Boneyard and Cancel.
    @ViewBuilder
    var importSummarySheet: some View {
        if let result = pendingImport {
            ImportSummaryView(
                result:       result,
                onDismiss:    { activeSheet = nil },
                onConfirm:    { commitImport(result) },
                confirmation: .existingProject
            )
        }
    }

    // MARK: - The picker

    /// The script picker, hung off the tab's list.
    func applyImportPicker<Content: View>(_ content: Content) -> some View {
        content.fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: ScriptImport.contentTypes,
            allowsMultipleSelection: false,
            onCompletion: importPickerFinished
        )
    }
}

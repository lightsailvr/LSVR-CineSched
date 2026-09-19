// ContentView+ScriptImport.swift
// File ▸ Import Script…: choose a screenplay (Final Draft, Fountain, Highland) and add its
// scenes to the frontmost project's Boneyard through the edit funnel. Project open and
// save are the document infrastructure's (#8); this file only ever adds scenes. The
// file chooser is the `FilePanels` seam; the formats and the Final Draft scene mapping
// are `ScriptImport`, shared with the launch screen's import on iOS and visionOS (#13);
// the PDF export actions live in ContentView+PDFExports.swift.

import SwiftUI
import Foundation
import UniformTypeIdentifiers

extension ContentView {

    // MARK: - Script import

    /// Single "Import Script…" entry point for every supported screenplay format —
    /// dispatches by extension to the Final Draft (.fdx/.xml) or Fountain
    /// (.fountain/.md/.spmd) importer once a file is chosen.
    func showScriptImportPanel() {
        FilePanels.chooseFile(
            title: "Import Script",
            prompt: "Import",
            allowedTypes: ScriptImport.contentTypes,
            directory: defaultPanelDirectory
        ) { url in
            if ScriptImport.isFountainFamily(url) {
                beginFountainImport(from: url)
            } else {
                importFDXScript(from: url)
            }
        }
    }

    func importFDXScript(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = "Unable to access the selected file."
            showingImportAlert = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let parsed = try FinalDraftParser.parseScenes(from: url)
            guard !parsed.isEmpty else {
                importMessage = "No scenes found in the script."
                showingImportAlert = true
                return
            }
            let imported = ScriptImport.scenes(from: parsed)
            edit(L("Import Script")) { $0.allScenes.append(contentsOf: imported) }
            let count = imported.count
            importMessage = "Imported \(count) scene\(count == 1 ? "" : "s") from '\(url.lastPathComponent)' with automatically calculated page eighths and character lists."
            showingImportAlert = true
        } catch {
            importMessage = "Failed to import script: \(error.localizedDescription)"
            showingImportAlert = true
        }
    }

    // MARK: - Fountain import

    func beginFountainImport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = "Unable to access the selected file."
            showingImportAlert = true
            return
        }
        FountainImporter.importScript(from: url) { [self] outcome in
            url.stopAccessingSecurityScopedResource()
            switch outcome {
            case .failure(let error):
                importMessage = error.localizedDescription
                showingImportAlert = true
            case .success(let result):
                applyFountainImport(result)
            }
        }
    }

    /// Fountain import only ever adds scenes to the Boneyard — it never touches
    /// existing scenes, shoot days, or the project title — but if a project
    /// already has content in it, confirm first rather than silently dropping
    /// a new batch of scenes into it.
    private func applyFountainImport(_ result: FountainImportResult) {
        let hasExistingProject = !allScenes.isEmpty
            || shootDays.contains { !$0.scenes.isEmpty }
            || projectTitle != "Untitled Movie"
        if hasExistingProject {
            pendingFountainImport = result
            showingFountainImportConfirmation = true
        } else {
            commitFountainImport(result)
        }
    }

    func confirmPendingFountainImport() {
        guard let result = pendingFountainImport else { return }
        pendingFountainImport = nil
        commitFountainImport(result)
    }

    func cancelPendingFountainImport() {
        pendingFountainImport = nil
    }

    private func commitFountainImport(_ result: FountainImportResult) {
        edit(L("Import Script")) { $0.allScenes.append(contentsOf: result.scenes) }
        completedFountainImport = result
        showingImportSummary = true
    }
}

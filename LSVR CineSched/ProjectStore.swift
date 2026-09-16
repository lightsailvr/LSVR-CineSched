// ProjectStore.swift
// Handles all project persistence: auto-save, manual save/load, script import, and the
// FileDocument wrapper used by the native file importer/exporter. File choosing goes
// through FilePanels (the platform seam); the PDF export actions live in
// ProjectStore+PDFExports.swift because the exporters are Mac-only for now.

import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - ProjectFile (FileDocument for JSON import/export)

struct ProjectFile: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    var projectData: ProjectData

    init(allScenes: [Scene], shootDays: [ShootDay], projectTitle: String = "Untitled Movie") {
        self.projectData = ProjectData(
            allScenes: allScenes,
            shootDays: shootDays,
            projectTitle: projectTitle
        )
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Try current format first, fall back to legacy
        do {
            self.projectData = try Self.decode(data)
        } catch {
            let legacy = try JSONDecoder().decode(LegacyProjectData.self, from: data)
            self.projectData = ProjectData(
                allScenes: legacy.allScenes,
                shootDays: legacy.shootDays,
                projectTitle: "Imported Project"
            )
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Self.encode(projectData)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Shared encode/decode helpers

    static func encode(_ projectData: ProjectData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .formatted(isoDateFormatter)
        return try encoder.encode(projectData)
    }

    /// Tries formatted-date decoder first, then plain decoder for backwards compatibility.
    static func decode(_ data: Data) throws -> ProjectData {
        let formattedDecoder = JSONDecoder()
        formattedDecoder.dateDecodingStrategy = .formatted(isoDateFormatter)
        if let result = try? formattedDecoder.decode(ProjectData.self, from: data) { return result }
        return try JSONDecoder().decode(ProjectData.self, from: data)
    }

    private static var isoDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }
}

// MARK: - Auto-save / UserDefaults persistence

extension ContentView {

    /// Marks the project as having unsaved changes.
    func markDirty() {
        hasUnsavedChanges = true
    }

    func saveDefaultProject() {
        let projectData = ProjectData(
            allScenes: allScenes,
            shootDays: shootDays,
            projectTitle: projectTitle,
            isShiftModeEnabled: isShiftModeEnabled,
            createdDate: projectCreatedDate,
            productionInfo: productionInfo
        )
        do {
            let data = try ProjectFile.encode(projectData)
            UserDefaults.standard.set(data, forKey: "SavedProject")
            print("Auto-saved project to UserDefaults")
        } catch {
            print("Failed to auto-save project: \(error)")
        }
    }

    func loadDefaultProject() {
        guard let data = UserDefaults.standard.data(forKey: "SavedProject") else {
            print("No saved project found in UserDefaults")
            return
        }
        applyLoadedData(from: data, source: "UserDefaults")
    }

    // MARK: - Current file tracking (persisted across launches)

    private static let currentFileBookmarkKey = "CineSchedCurrentFileBookmark"

    /// Sets currentFileURL and remembers it as a security-scoped bookmark.
    func setCurrentFileURL(_ url: URL) {
        currentFileURL = url
        if let bookmark = try? url.bookmarkData(
            options: FilePanels.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Self.currentFileBookmarkKey)
        }
    }

    /// Restores the last-known file location on launch. Called from .onAppear.
    func restoreCurrentFileURL() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.currentFileBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: FilePanels.bookmarkResolutionOptions,
                                  relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return }
        currentFileURL = url
        if isStale {
            if let refreshed = try? url.bookmarkData(options: FilePanels.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: Self.currentFileBookmarkKey)
            }
        }
    }

    /// The folder to default file panels to.
    var defaultPanelDirectory: URL? {
        currentFileURL?.deletingLastPathComponent()
    }

    // MARK: - Manual save (native save panel)

    /// "Save": writes silently to the file this project was last saved to or loaded from.
    func saveProject() {
        if let url = currentFileURL {
            saveProjectDirectly(to: url)
        } else {
            showNativeSaveDialog()
        }
    }

    func showNativeSaveDialog() {
        FilePanels.chooseSaveLocation(
            title: "Save CineSched Project",
            prompt: "Save",
            nameFieldLabel: "Project Name:",
            defaultName: sanitizeFilename(projectTitle.isEmpty ? "MovieSchedule" : projectTitle),
            allowedTypes: [.json],
            directory: defaultPanelDirectory
        ) { url in
            saveProjectDirectly(to: url)
        }
    }

    func saveProjectDirectly(to url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        let projectData = ProjectData(
            allScenes: allScenes,
            shootDays: shootDays,
            projectTitle: projectTitle,
            isShiftModeEnabled: isShiftModeEnabled,
            createdDate: projectCreatedDate,
            productionInfo: productionInfo
        )
        do {
            let data = try ProjectFile.encode(projectData)
            try data.write(to: url)
            setCurrentFileURL(url)
            recentFiles.record(url)
            alertMessage = "Schedule saved successfully to: \(url.lastPathComponent)"
            showingAlert = true
            print("Saved to: \(url.path)")
        } catch {
            alertMessage = "Failed to save schedule: \(error.localizedDescription)"
            showingAlert = true
            print("Save error: \(error)")
        }
    }

    // MARK: - Load from file

    func loadProject(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()

        do {
            let data = try Data(contentsOf: url)
            applyLoadedData(from: data, source: url.lastPathComponent)
            setCurrentFileURL(url)
            recentFiles.record(url)
        } catch {
            alertMessage = "Failed to load project: \(error.localizedDescription)"
            showingAlert = true
            print("Load error: \(error)")
        }
    }

    // MARK: - Apply loaded data to state

    private func applyLoadedData(from data: Data, source: String) {
        func apply(_ loaded: ProjectData) {
            allScenes          = loaded.allScenes
            shootDays          = loaded.shootDays
            projectTitle       = loaded.projectTitle
            isShiftModeEnabled = loaded.isShiftModeEnabled ?? false
            projectCreatedDate = loaded.createdDate
            productionInfo     = loaded.productionInfo ?? ProductionInfo()
            if let first = shootDays.first?.date, let last = shootDays.last?.date {
                startDate = first
                endDate   = last
            }
            print("Loaded project '\(loaded.projectTitle)' from \(source)")
        }

        if let loaded = try? ProjectFile.decode(data) {
            apply(loaded)
            return
        }
        if let legacy = try? JSONDecoder().decode(LegacyProjectData.self, from: data) {
            allScenes    = legacy.allScenes
            shootDays    = legacy.shootDays
            projectTitle = "Loaded Project"
            isShiftModeEnabled = false
            if let first = shootDays.first?.date, let last = shootDays.last?.date {
                startDate = first
                endDate   = last
            }
            print("Loaded legacy project from \(source)")
            return
        }
        alertMessage = "Failed to decode project file."
        showingAlert = true
        print("Failed to decode data from \(source)")
    }

    // MARK: - Utilities

    func clearAllScenes() {
        allScenes.removeAll()
        for i in shootDays.indices {
            shootDays[i].scenes    = []
            shootDays[i].callSheet = CallSheetData()
        }
        projectTitle       = "Untitled Movie"
        productionInfo     = ProductionInfo()
        projectCreatedDate = Date()
        markDirty()
    }

    func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - File open panels

    func showJSONOpenPanel() {
        FilePanels.chooseFile(
            title: "Load CineSched Project",
            prompt: "Load",
            allowedTypes: [.json],
            directory: defaultPanelDirectory
        ) { url in
            loadProject(from: url)
        }
    }

    /// Single "Import Script…" entry point for every supported screenplay format —
    /// dispatches by extension to the Final Draft (.fdx/.xml) or Fountain
    /// (.fountain/.md/.spmd) importer once a file is chosen.
    func showScriptImportPanel() {
        var allowedTypes: [UTType] = []
        if let fdxType = UTType(filenameExtension: "fdx") { allowedTypes.append(fdxType) }
        allowedTypes.append(.xml)
        for ext in FountainImporter.supportedExtensions {
            if let type = UTType(filenameExtension: ext) { allowedTypes.append(type) }
        }
        FilePanels.chooseFile(
            title: "Import Script",
            prompt: "Import",
            allowedTypes: allowedTypes,
            directory: defaultPanelDirectory
        ) { url in
            let ext = url.pathExtension.lowercased()
            if FountainImporter.supportedExtensions.contains(ext) {
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
            var count = 0
            for ps in parsed {
                let type: DayNightType
                switch ps.timeOfDay {
                case .night:         type = .night
                case .dawn:          type = .dawn
                case .dusk:          type = .dusk
                case .afternoon:     type = .afternoon
                case .day, .unknown: type = .day
                }
                let duration = max(1, ps.duration)
                allScenes.append(Scene(
                    title:         ps.location,
                    sceneNumber:   ps.sceneNumber,
                    duration:      duration,
                    estimatedTime: TimeParser.estimatedMinutes(forEighths: duration),
                    dayNightType:  type,
                    cast:          ps.cast
                ))
                count += 1
            }
            markDirty()
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
        allScenes.append(contentsOf: result.scenes)
        markDirty()
        completedFountainImport = result
        showingImportSummary = true
    }
}

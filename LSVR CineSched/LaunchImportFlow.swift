// LaunchImportFlow.swift
// Import Script… and Import Project… on the iOS and visionOS launch screen (#13): a new
// project from a screenplay (Fountain, Final Draft, Highland) or from a legacy `.json`,
// created in the CineSched folder like any New Project. The originals are never written.
//
// How it plugs into the system's launch screen. Each import is a `NewDocumentButton` with
// a `DocumentCreationSource` (CineSchedApp). A tap runs `DocumentGroup`'s `makeDocument`
// with that source in its context; the closure is `async throws`, so it can await this
// flow for the `ProjectData` the new document starts with, or throw, on which the launch
// screen stays as it was: no document, no file, no alert (verified on the 27.0
// simulators; learnings.md 2026-09-19). The button's own `prepareDocumentURL` closure,
// which the SDK documents for exactly this, is never invoked by the 27.0 launch scene,
// in the More… menu or as a visible button, so the flow lives here. The steps:
//
//   1. `LaunchImportFlow.prepareProject(for:)`, awaited by `makeDocument`, suspends on a
//      continuation and asks the presentation layer for a file (`stage == .picking`).
//   2. The `launchImportPresentation` modifier, attached to a view in the launch screen's
//      actions, hangs a `fileImporter`, the summary sheet and the failure alert off that
//      stage; its callbacks feed the picked file, the confirmation or the cancellation
//      back into the flow.
//   3. The pure steps (`LaunchImport`) parse the file and build the `ProjectData`; the
//      continuation resumes with it, and `makeDocument` hands it to `ProjectDocument`.
//      Any cancellation resumes by throwing `CancellationError`.
//
// `LaunchImport` is pure and tested (`LaunchImportTests`); `LaunchImportFlow` is the
// coordinator, tested without a view through its callbacks; the modifier is the only
// SwiftUI. All three are platform-free (`fileImporter` and `sheet` exist everywhere), so
// no `#if os`; the Mac compiles them and never runs them, since the buttons that start
// the flow live in CineSchedApp's launch scene.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - What is imported

/// The two imports the launch screen offers.
enum LaunchImportKind: Equatable {
    /// A screenplay whose scenes become the new project's Boneyard.
    case script
    /// A legacy `.json` project, opened as a new `.cinesched`.
    case project

    /// The file types the picker offers: the screenplay formats the Mac's Import Script…
    /// panel takes, or JSON.
    var contentTypes: [UTType] {
        switch self {
        case .script:  return ScriptImport.contentTypes
        case .project: return [.json]
        }
    }
}

// MARK: - Pure steps

/// The parts of the launch-screen import that need no view: from a chosen file to the
/// `ProjectData` the new document holds.
enum LaunchImport {

    /// Parses the screenplay at `url` (any supported format); the caller holds the file's
    /// security scope. Same parse as the Mac's menu.
    static func parseScript(at url: URL) throws -> FountainImportResult {
        try ScriptImport.parse(at: url)
    }

    /// A new project holding the parsed scenes in its Boneyard: the New Project template
    /// (its run of empty shoot days around `date`) with the script's scenes and, when the
    /// title page names it, the script's title.
    static func newProject(from result: FountainImportResult, around date: Date = Date(), calendar: Calendar = .current) -> ProjectData {
        var project = ProjectData.newProject(around: date, calendar: calendar)
        project.allScenes = result.scenes
        if let title = result.title, !title.isEmpty {
            project.projectTitle = title
        }
        return project
    }

    /// The legacy project at `url`, decoded through the one codec (current shape and both
    /// older ones); the caller holds the file's security scope. Reads only: the source
    /// file is never modified, and the project comes back exactly as the codec decodes it,
    /// so the new `.cinesched` equals the source.
    static func readLegacyProject(at url: URL) throws -> ProjectData {
        try ProjectCodec.decode(try Data(contentsOf: url))
    }
}

// MARK: - Flow

/// Runs one launch-screen import from the tap to the new document's project, holding the
/// state the presentation layer shows. One instance serves both buttons; a tap while a
/// flow is already running cancels the earlier one.
@MainActor @Observable
final class LaunchImportFlow {

    /// Where the running import is, for the presentation layer.
    enum Stage: Equatable {
        case idle
        /// The picker is up (or about to be) for this kind of file.
        case picking(LaunchImportKind)
        /// A script parsed; the summary is up, waiting for Create Project or Cancel.
        case reviewing(FountainImportResult)
        /// Something failed; the message is up, and dismissing it ends the flow.
        case failed(String)

        static func == (lhs: Stage, rhs: Stage) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):                        return true
            case (.picking(let a), .picking(let b)):    return a == b
            case (.reviewing(let a), .reviewing(let b)): return a.fileName == b.fileName && a.scenes.map(\.id) == b.scenes.map(\.id)
            case (.failed(let a), .failed(let b)):      return a == b
            default:                                    return false
            }
        }
    }

    private(set) var stage: Stage = .idle

    /// The suspended `makeDocument`, resumed once with the project or with a thrown error.
    private var continuation: CheckedContinuation<ProjectData, Error>?

    init() {}

    // MARK: - Entry

    /// What `makeDocument` awaits for an import source: presents the picker (through
    /// `stage`), then the summary for a script, and returns the project the new document
    /// starts with. Throws `CancellationError` when the user cancels either, or dismisses
    /// the failure message for a file that could not be read or parsed.
    func prepareProject(for kind: LaunchImportKind) async throws -> ProjectData {
        cancelRunningFlow()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.stage        = .picking(kind)
        }
    }

    // MARK: - Picker callbacks

    /// The picker returned; `urls` is what the user chose (one file, or none).
    func pickerFinished(_ result: Result<[URL], Error>) {
        guard case .picking(let kind) = stage else { return }
        let url: URL
        switch result {
        case .failure(let error):
            fail(error.localizedDescription)
            return
        case .success(let urls):
            guard let first = urls.first else {
                cancel()
                return
            }
            url = first
        }
        // A picked file is outside the app's container; the scope is held only for the
        // read, and the file itself is never written.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        switch kind {
        case .script:
            do {
                stage = .reviewing(try LaunchImport.parseScript(at: url))
            } catch {
                fail(error.localizedDescription)
            }
        case .project:
            do {
                finish(with: try LaunchImport.readLegacyProject(at: url))
            } catch {
                fail(String(format: L("Couldn't read '%@' as a CineSched project."), url.lastPathComponent))
            }
        }
    }

    /// The user cancelled the picker.
    func pickerCancelled() {
        guard case .picking = stage else { return }
        cancel()
    }

    /// The picker closed; if no completion arrived by the next turn of the run loop, the
    /// user dismissed it some other way and the flow ends as a cancellation. The check is
    /// deferred because SwiftUI may clear the presentation binding before it delivers the
    /// completion, and a synchronous cancel here would race a successful pick.
    func pickerDismissed() {
        Task { @MainActor in
            if case .picking = stage { cancel() }
        }
    }

    // MARK: - Summary callbacks

    /// Create Project on the summary: the parsed scenes become the new project.
    func confirmReview() {
        guard case .reviewing(let result) = stage else { return }
        finish(with: LaunchImport.newProject(from: result))
    }

    /// Cancel on the summary, or the sheet swiped away.
    func cancelReview() {
        guard case .reviewing = stage else { return }
        cancel()
    }

    /// The failure message was dismissed; the flow ends as a cancellation, so the launch
    /// screen creates nothing.
    func dismissFailure() {
        guard case .failed = stage else { return }
        cancel()
    }

    // MARK: - Ending the flow

    private func finish(with project: ProjectData) {
        resume(.success(project))
    }

    private func fail(_ message: String) {
        stage = .failed(message)
    }

    private func cancel() {
        resume(.failure(CancellationError()))
    }

    private func cancelRunningFlow() {
        guard continuation != nil else { return }
        cancel()
    }

    private func resume(_ outcome: Result<ProjectData, Error>) {
        stage        = .idle
        let pending  = continuation
        continuation = nil
        pending?.resume(with: outcome)
    }
}

// MARK: - Presentation

extension View {
    /// Hangs the launch-screen import's picker, summary and failure message off this view,
    /// driven by `flow.stage`. Attach it to the launch screen's actions once.
    func launchImportPresentation(_ flow: LaunchImportFlow) -> some View {
        modifier(LaunchImportPresentation(flow: flow))
    }
}

private struct LaunchImportPresentation: ViewModifier {
    let flow: LaunchImportFlow

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: pickerPresented,
                allowedContentTypes: pickingKind?.contentTypes ?? [],
                allowsMultipleSelection: false,
                onCompletion: { flow.pickerFinished($0) },
                onCancellation: { flow.pickerCancelled() }
            )
            .sheet(isPresented: summaryPresented) {
                if case .reviewing(let result) = flow.stage {
                    // Sized by the summary's own container (#21): a form sheet on iPad
                    // and Vision Pro, detents on iPhone.
                    ImportSummaryView(
                        result:    result,
                        onDismiss: { flow.cancelReview() },
                        onConfirm: { flow.confirmReview() }
                    )
                }
            }
            .alert(L("Import Failed"), isPresented: failurePresented) {
                Button(L("OK")) { flow.dismissFailure() }
            } message: {
                if case .failed(let message) = flow.stage { Text(message) }
            }
    }

    private var pickingKind: LaunchImportKind? {
        if case .picking(let kind) = flow.stage { return kind }
        return nil
    }

    private var pickerPresented: Binding<Bool> {
        Binding(get: { pickingKind != nil }, set: { if !$0 { flow.pickerDismissed() } })
    }

    private var summaryPresented: Binding<Bool> {
        Binding(get: {
            if case .reviewing = flow.stage { return true }
            return false
        }, set: { if !$0 { flow.cancelReview() } })
    }

    private var failurePresented: Binding<Bool> {
        Binding(get: {
            if case .failed = flow.stage { return true }
            return false
        }, set: { if !$0 { flow.dismissFailure() } })
    }
}

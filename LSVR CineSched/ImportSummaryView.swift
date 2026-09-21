// ImportSummaryView.swift
// The script import's summary sheet: scene count, total pages/eighths, cast detected,
// and any parse warnings (#21: one adaptive `Form`, the same on every platform). Two
// moments show it. On the Mac it follows a Fountain import into the current project
// (Done). On the iOS and visionOS launch screen (#13) it comes first, as the
// confirmation before the new project is created: given `onConfirm`, the footer is
// Cancel / Create Project and the copy speaks of what will happen; the iPhone's
// Production tab (#28) shows the same confirmation before adding a script to the open
// project (`confirmation: .existingProject`: Cancel / Add to Boneyard). Only the size
// around the form changes per container (`editorContainer`): the Mac's sheet at the
// frame it had, a form sheet on iPad and Vision Pro, detents on iPhone.

import SwiftUI

struct ImportSummaryView: View {
    let result: FountainImportResult
    let onDismiss: () -> Void
    /// Set for the confirmation before an import (the launch screen, the phone's
    /// Production tab); nil for the Mac's summary after one.
    var onConfirm: (() -> Void)? = nil
    /// What confirming does, for the copy and the button: a new project (the launch
    /// screen's default) or the open project's Boneyard.
    var confirmation: Confirmation = .newProject

    enum Confirmation {
        case newProject
        case existingProject
    }

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 460, height: 460, compactDetents: [.large])

    private var isConfirmation: Bool { onConfirm != nil }

    private var explanation: String {
        let count = result.scenes.count
        let plural = count == 1 ? "" : "s"
        switch (isConfirmation, confirmation) {
        case (false, _):
            return String(format: L("All %d scene%@ landed in the Boneyard, unscheduled. Time estimates are a rough guess from page count — edit before scheduling."), count, plural)
        case (true, .newProject):
            return String(format: L("A new project will hold all %d scene%@ in its Boneyard, unscheduled. Time estimates are a rough guess from page count — edit before scheduling."), count, plural)
        case (true, .existingProject):
            return String(format: L("All %d scene%@ will be added to this project's Boneyard, unscheduled; nothing already in the project changes. Time estimates are a rough guess from page count — edit before scheduling."), count, plural)
        }
    }

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    isConfirmation ? L("Import Script") : L("Script Imported"),
                subtitle: result.fileName
            )
        } content: {
            Form {
                Section {
                    HStack(spacing: 16) {
                        statTile(icon: "film",     value: "\(result.scenes.count)",                                 label: L("scenes"))
                        statTile(icon: "doc.text", value: FountainPaginator.formatEighths(result.totalEighths), label: L("pages"))
                        statTile(icon: "number",   value: "\(result.totalEighths)",                              label: L("total 1/8ths"))
                        statTile(icon: "person.2", value: "\(result.castList.count)",                           label: L("cast"))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(explanation)
                }

                if !result.castList.isEmpty {
                    Section {
                        Text(result.castList.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(L("Cast Detected"))
                    }
                }

                if !result.warnings.isEmpty {
                    Section {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        Text("\(L("Warnings")) (\(result.warnings.count))")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Spacer()
                if let onConfirm {
                    Button(L("Cancel"), role: .cancel) { onDismiss() }
                    Button(confirmation == .newProject ? L("Create Project") : L("Add to Boneyard")) { onConfirm() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L("Done")) { onDismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .editorContainer(Self.sheetSize)
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

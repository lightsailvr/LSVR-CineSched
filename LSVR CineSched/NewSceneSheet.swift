// NewSceneSheet.swift
// The iPhone's New Scene entry (#27): the Mac's sidebar form (`NewSceneInputView`,
// untouched) as an adaptive form, the same in every container. The fields are a
// `NewSceneDraft` (EditorDrafts.swift: number, slugline, real location, pages, estimate
// and the type, validated the Mac's way, tested); Add Scene hands `draft.makeScene()`
// to the tab, which appends it to the Boneyard in one edit. The type picker's default
// reads the time of day off the slugline as it is typed ("INT. KITCHEN - NIGHT" shows
// "From slugline · NIGHT"), so the common case is number, slugline, pages, Add.
//
// The chrome is `EditorChrome` and the sizing is the `editorContainer` seam's: no
// navigation bar, no fixed frame here (CLAUDE.md, "Adding or rewriting an editor").

import SwiftUI

struct NewSceneSheet: View {
    /// The location roster and the locations in use, for the field's suggestions.
    let knownLocations: [String]
    let onAdd:    (Scene) -> Void
    let onCancel: () -> Void

    @State private var draft = NewSceneDraft()
    @FocusState private var titleFocused: Bool

    static let sheetSize = EditorSheetSize(width: 480, height: 600, compactDetents: [.large])

    var body: some View {
        EditorChrome {
            EditorTitle(title: L("New Scene"), subtitle: L("Added to the Boneyard"))
        } content: {
            form
        } footer: {
            HStack {
                Button(L("Cancel")) { onCancel() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("Add Scene")) { onAdd(draft.makeScene()) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("NewSceneAdd")
            }
        }
        .editorContainer(Self.sheetSize)
        .onAppear {
            // A new scene starts with its slugline; the keyboard comes up with the sheet.
            DispatchQueue.main.async { titleFocused = true }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                LabeledContent(L("Scene #")) {
                    TextField("#", text: $draft.sceneNumber)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("NewSceneNumber")
                }
                TextField(L("Scene Title"), text: $draft.title, prompt: Text(L("e.g. INT. KITCHEN - NIGHT")))
                    .focused($titleFocused)
                    .accessibilityIdentifier("NewSceneTitle")
                LocationAutocompleteField(
                    title:       L("Real Location / Set"),
                    placeholder: L("e.g. Hotel Renaissance, Room 204"),
                    text:        $draft.realLocation,
                    suggestions: knownLocations,
                    style:       .formRow
                )
            }

            Section {
                LabeledContent(L("Duration (pages)")) {
                    TextField(FractionParser.placeholderText, text: $draft.duration)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("NewSceneDuration")
                }
                LabeledContent(L("Estimated Time")) {
                    TextField(TimeParser.placeholderText, text: $draft.estimatedTime)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("NewSceneEstimate")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let hint = durationHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                    }
                    if let hint = estimatedTimeHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                    }
                }
            }

            Section {
                Picker(L("Type"), selection: $draft.dayNightType) {
                    Text("\(L("From slugline")) · \(L(draft.resolvedSluglineType.rawValue.uppercased()))")
                        .tag(DayNightType?.none)
                    ForEach(DayNightType.allCases, id: \.self) { type in
                        Text(L(type.rawValue.uppercased())).tag(DayNightType?.some(type))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("NewSceneType")
            } footer: {
                Text(L("Leave the type on From slugline and the scene takes the time of day its heading names."))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hints

    private struct Hint { let text: String; let isError: Bool }

    private var durationHint: Hint? {
        if !draft.durationIsValid {
            return Hint(text: L("Invalid format. Use: 15 (eighths), 1 7/8 (mixed), or 7/8 (fraction)"), isError: true)
        }
        if let eighths = draft.parsedEighths, !draft.duration.isEmpty {
            return Hint(text: "= \(FractionParser.formatEighths(eighths)) \(L("pages")) (\(eighths) \(L("eighths")))", isError: false)
        }
        return Hint(text: L("Leave blank for no page count"), isError: false)
    }

    private var estimatedTimeHint: Hint? {
        if !draft.estimatedTimeIsValid {
            return Hint(text: L("Invalid format. Use: 4 (4 hours), 15 (15 minutes), or 2:30 (2hr 30min)"), isError: true)
        }
        if let hint = TimeParser.getInputHint(draft.estimatedTime), !draft.estimatedTime.isEmpty {
            return Hint(text: hint, isError: false)
        }
        if let eighths = draft.parsedEighths, eighths > 0 {
            return Hint(text: "\(L("Leave blank to estimate")) \(formattedTimeHM(TimeParser.estimatedMinutes(forEighths: eighths))) \(L("from the pages"))", isError: false)
        }
        return Hint(text: L("Leave blank for no time estimate"), isError: false)
    }
}

private extension NewSceneDraft {
    /// The type the slugline names, for the picker's default row.
    var resolvedSluglineType: DayNightType { Self.dayNightType(inSlugline: title) }
}

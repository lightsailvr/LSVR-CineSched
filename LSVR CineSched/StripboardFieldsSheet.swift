// StripboardFieldsSheet.swift
// Picker for which scene fields the Stripboard prints on every strip (#21: one adaptive
// `Form`, the same on every platform). Toggles write straight through the binding, so
// the board behind the sheet updates as each switch flips — the same live-preview feel
// as SceneColorSettingsSheet. The selection is the app-wide `@AppStorage` preference
// (StripboardFieldSettings), by design: it is a view preference, not project data.
// Only the size around the form changes per container (`editorContainer`).

import SwiftUI

struct StripboardFieldsSheet: View {
    @Binding var selectedFields: Set<StripboardField>
    let onDismiss: () -> Void

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 520, height: 560, compactDetents: [.large])

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Stripboard Fields"),
                subtitle: L("Choose what each strip shows beside the scene heading. Fields a scene leaves blank are skipped.")
            )
        } content: {
            Form {
                Section {
                    ForEach(StripboardField.allCases) { field in
                        FieldToggleRow(isOn: binding(for: field), icon: field.icon, label: field.label, detail: field.detail)
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            // The three bulk actions, then Done. Where the row is too narrow for four
            // buttons (an iPhone), the bulk actions fold into one menu.
            ViewThatFits(in: .horizontal) {
                HStack {
                    bulkButtons
                    Spacer()
                    doneButton
                }
                HStack {
                    Menu {
                        bulkButtons
                    } label: {
                        Label(L("Selection"), systemImage: "checklist")
                    }
                    Spacer()
                    doneButton
                }
            }
        }
        .editorContainer(Self.sheetSize)
    }

    @ViewBuilder
    private var bulkButtons: some View {
        Button(L("Reset to Default")) { selectedFields = StripboardField.defaultSelection }
        Button(L("Select All")) { selectedFields = Set(StripboardField.allCases) }
        Button(L("Select None")) { selectedFields = [] }
    }

    private var doneButton: some View {
        Button(L("Done")) { onDismiss() }
            .buttonStyle(.borderedProminent)
    }

    private func binding(for field: StripboardField) -> Binding<Bool> {
        Binding<Bool>(
            get: { selectedFields.contains(field) },
            set: { isOn in
                if isOn { selectedFields.insert(field) } else { selectedFields.remove(field) }
            }
        )
    }
}

// MARK: - Field toggle row

/// One switch in a grouped form with the field's icon, its name and a one-line hint
/// under it. The Stripboard picker and the month PDF options dialog list the same
/// fields with the same words, so they share the row.
struct FieldToggleRow: View {
    @Binding var isOn: Bool
    let icon:   String
    let label:  String
    let detail: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

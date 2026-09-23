// MonthPDFOptionsSheet.swift
// Options dialog shown before the month PDF export: which month (when the caller lets the
// sheet choose) and which per-scene details the breakdown pages print (#21: one adaptive `Form`, the same on every platform).
// Toggles write straight through the bindings (they land in UserDefaults via
// @AppStorage in ContentView and the phone's Production tab), so the choice sticks between exports — same pattern
// as StripboardFieldsSheet, whose field rows it shares. Only the size around the form
// changes per container (`editorContainer`).

import SwiftUI

struct MonthPDFOptionsSheet: View {
    @Binding var selectedFields: Set<StripboardField>
    @Binding var includePageCount: Bool
    @Binding var includeEstimatedTime: Bool
    let onCancel: () -> Void
    let onExport: () -> Void
    /// Which month to export, when the sheet chooses it (the window toolbar's Share ▸
    /// Month Calendar…): a picker over `months` heads the form. Nil where the month was
    /// chosen before the sheet opened (the phone's Production tab).
    var month: Binding<Date>? = nil
    var months: [Date] = []

    /// The Mac frame: the height the fixed-frame sheet had, 40 pt wider so the five
    /// footer buttons stay one row beside the chrome's padding.
    static let sheetSize = EditorSheetSize(width: 560, height: 600, compactDetents: [.large])

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Month PDF Options"),
                subtitle: L("Choose what the breakdown pages print for every scene. Fields a scene leaves blank are skipped.")
            )
        } content: {
            Form {
                if let month, !months.isEmpty {
                    Section {
                        Picker(L("Month"), selection: month) {
                            ForEach(months, id: \.self) { candidate in
                                Text(formattedDate(candidate, pattern: "LLLL yyyy")).tag(candidate)
                            }
                        }
                    }
                }
                Section {
                    FieldToggleRow(isOn: $includePageCount,
                                   icon: "doc.text",
                                   label: L("Page Count"),
                                   detail: L("The scene's script length in eighths, e.g. 2/8 pgs"))
                    FieldToggleRow(isOn: $includeEstimatedTime,
                                   icon: "clock",
                                   label: L("Estimated Time"),
                                   detail: L("The scene's estimated shooting time"))
                }
                Section {
                    ForEach(StripboardField.allCases) { field in
                        FieldToggleRow(isOn: binding(for: field), icon: field.icon, label: field.label, detail: field.detail)
                    }
                } header: {
                    Text(L("Breakdown Fields"))
                }
            }
            .formStyle(.grouped)
        } footer: {
            // The three bulk actions, then Cancel and Export. Where the row is too narrow
            // for five buttons (an iPhone), the bulk actions fold into one menu.
            ViewThatFits(in: .horizontal) {
                HStack {
                    bulkButtons
                    Spacer()
                    cancelButton
                    exportButton
                }
                HStack {
                    Menu {
                        bulkButtons
                    } label: {
                        Label(L("Selection"), systemImage: "checklist")
                    }
                    Spacer()
                    cancelButton
                    exportButton
                }
            }
        }
        .editorContainer(Self.sheetSize)
    }

    @ViewBuilder
    private var bulkButtons: some View {
        Button(L("Reset to Default")) {
            selectedFields = MonthPDFOptions.default.fields
            includePageCount = MonthPDFOptions.default.includePageCount
            includeEstimatedTime = MonthPDFOptions.default.includeEstimatedTime
        }
        Button(L("Select All")) { selectedFields = Set(StripboardField.allCases) }
        Button(L("Select None")) { selectedFields = [] }
    }

    private var cancelButton: some View {
        Button(L("Cancel")) { onCancel() }
    }

    private var exportButton: some View {
        Button(L("Export…")) { onExport() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
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

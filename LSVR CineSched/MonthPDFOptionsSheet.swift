// MonthPDFOptionsSheet.swift
// Options dialog shown before the month PDF save panel: which per-scene details the
// breakdown pages print. Toggles write straight through the bindings (they land in
// UserDefaults via @AppStorage in CalendarView), so the choice sticks between exports —
// same pattern as StripboardFieldsSheet.

import SwiftUI

struct MonthPDFOptionsSheet: View {
    @Binding var selectedFields: Set<StripboardField>
    @Binding var includePageCount: Bool
    @Binding var includeEstimatedTime: Bool
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Month PDF Options")).font(.title2).fontWeight(.bold)
                    Text(L("Choose what the breakdown pages print for every scene. Fields a scene leaves blank are skipped."))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    optionRow(isOn: $includePageCount,
                              icon: "doc.text",
                              label: L("Page Count"),
                              detail: L("The scene's script length in eighths, e.g. 2/8 pgs"))
                    optionRow(isOn: $includeEstimatedTime,
                              icon: "clock",
                              label: L("Estimated Time"),
                              detail: L("The scene's estimated shooting time"))

                    Text(L("Breakdown Fields"))
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        .padding(.top, 10)

                    ForEach(StripboardField.allCases) { field in
                        optionRow(isOn: binding(for: field),
                                  icon: field.icon,
                                  label: field.label,
                                  detail: field.detail)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button(L("Reset to Default")) {
                    selectedFields = MonthPDFOptions.default.fields
                    includePageCount = MonthPDFOptions.default.includePageCount
                    includeEstimatedTime = MonthPDFOptions.default.includeEstimatedTime
                }
                Button(L("Select All")) { selectedFields = Set(StripboardField.allCases) }
                Button(L("Select None")) { selectedFields = [] }
                Spacer()
                Button(L("Cancel")) { onCancel() }
                Button(L("Export…")) { onExport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
    }

    private func optionRow(isOn: Binding<Bool>, icon: String, label: String, detail: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.body)
                    Text(detail).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
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

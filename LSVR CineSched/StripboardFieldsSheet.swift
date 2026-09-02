// StripboardFieldsSheet.swift
// Picker for which scene fields the Stripboard prints on every strip. Toggles write straight
// through the binding, so the board behind the sheet updates as each box is ticked — same
// live-preview feel as SceneColorSettingsSheet.

import SwiftUI

struct StripboardFieldsSheet: View {
    @Binding var selectedFields: Set<StripboardField>
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Stripboard Fields")).font(.title2).fontWeight(.bold)
                    Text(L("Choose what each strip shows beside the scene heading. Fields a scene leaves blank are skipped."))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(StripboardField.allCases) { field in
                        Toggle(isOn: binding(for: field)) {
                            HStack(spacing: 10) {
                                Image(systemName: field.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(field.label).font(.body)
                                    Text(field.detail).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button(L("Reset to Default")) { selectedFields = StripboardField.defaultSelection }
                Button(L("Select All")) { selectedFields = Set(StripboardField.allCases) }
                Button(L("Select None")) { selectedFields = [] }
                Spacer()
                Button(L("Done")) { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
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

// SceneColorSettingsSheet.swift
// Lets the user override any of the industry-standard scene strip colors. Since #11 the
// colors belong to the project, not the device: each pick goes straight to `onSetColor`,
// which the editor routes through the document's edit funnel, so the board behind the
// sheet updates live (the same feel as StripboardFieldsSheet) and every change undoes.
// The sheet keeps no copy of the palette; it draws the one it is handed, so an Undo
// while it is open shows in the pickers too.

import SwiftUI

struct SceneColorSettingsSheet: View {
    let palette: ScenePalette
    /// A slot's new color, as the hex the project file stores.
    let onSetColor: (SceneColorSlot, String) -> Void
    let onReset: () -> Void
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Customize Scene Colors")).font(.title2).fontWeight(.bold)
                    Text(L("These colors are saved with the project and used by every device and export."))
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
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SceneColorSlot.allCases) { slot in
                        HStack(spacing: 10) {
                            ColorPicker("", selection: binding(for: slot), supportsOpacity: false)
                                .labelsHidden()
                            Text(slot.label)
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button(L("Reset All to Defaults")) { onReset() }
                Spacer()
                Button(L("Done")) { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
    }

    /// Reads from the palette and writes through `onSetColor`; `hexString` rounds a pick
    /// to 8-bit sRGB, which is what the file holds and what every strip draws.
    private func binding(for slot: SceneColorSlot) -> Binding<Color> {
        Binding<Color>(
            get: { palette.color(for: slot) },
            set: { newColor in onSetColor(slot, newColor.hexString) }
        )
    }
}

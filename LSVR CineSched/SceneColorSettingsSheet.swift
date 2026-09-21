// SceneColorSettingsSheet.swift
// Lets the user override any of the industry-standard scene strip colors (#21: one
// adaptive `Form`, the same on every platform). Since #11 the colors belong to the
// project, not the device: each pick goes straight to `onSetColor`, which the editor
// routes through the document's edit funnel, so the board behind the sheet updates live
// (the same feel as StripboardFieldsSheet) and every change undoes, one step per slot.
// The sheet keeps no copy of the palette; it draws the one it is handed, so an Undo
// while it is open shows in the pickers too. Only the size around the form changes per
// container (`editorContainer`).

import SwiftUI

struct SceneColorSettingsSheet: View {
    let palette: ScenePalette
    /// A slot's new color, as the hex the project file stores.
    let onSetColor: (SceneColorSlot, String) -> Void
    let onReset: () -> Void
    let onDismiss: () -> Void

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 520, height: 480, compactDetents: [.large])

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Customize Scene Colors"),
                subtitle: L("These colors are saved with the project and used by every device and export.")
            )
        } content: {
            Form {
                Section {
                    ForEach(SceneColorSlot.allCases) { slot in
                        ColorPicker(slot.label, selection: binding(for: slot), supportsOpacity: false)
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Button(L("Reset All to Defaults")) { onReset() }
                Spacer()
                Button(L("Done")) { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .editorContainer(Self.sheetSize)
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

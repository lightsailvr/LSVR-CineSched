// ColorLegendView.swift
// Color legend explaining the Movie Magic Scheduling strip color code CineSched uses
// (#21: one adaptive `Form`, the same on every platform). Each row names a slot of the
// palette and draws that slot's color from the project's palette (the `scenePalette`
// environment the editor sets at its root), so a project with customized colors sees
// the colors its board actually shows; with the standard code the swatches are the
// ones the legend always drew. Only the size around the form changes per container
// (`editorContainer`).

import SwiftUI

struct ColorLegendView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePalette) private var palette

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 440, height: 500, compactDetents: [.large])

    struct LegendItem: Identifiable {
        /// The palette slot the swatch is read from.
        let slot: SceneColorSlot
        let title: String
        let description: String

        var id: String { slot.rawValue }
    }

    private var legendItems: [LegendItem] {
        [
            LegendItem(slot: .intDay,       title: "INT. DAY",
                       description: L("Day scenes taking place inside a building, room, or vehicle.")),
            LegendItem(slot: .extDay,       title: "EXT. DAY",
                       description: L("Day scenes taking place outdoors under sunlight.")),
            LegendItem(slot: .intNight,     title: "INT. NIGHT",
                       description: L("Night scenes taking place inside a building or room.")),
            LegendItem(slot: .extNight,     title: "EXT. NIGHT",
                       description: L("Night scenes taking place outside in the dark.")),
            LegendItem(slot: .intAfternoon, title: "INT. AFTERNOON",
                       description: L("Afternoon scenes taking place indoors.")),
            LegendItem(slot: .extAfternoon, title: "EXT. AFTERNOON",
                       description: L("Afternoon scenes outdoors during golden hour.")),
            LegendItem(slot: .intDawn,      title: "DAWN",
                       description: L("Magic hour scenes taking place during sunrise.")),
            LegendItem(slot: .intDusk,      title: "DUSK",
                       description: L("Magic hour scenes taking place during sunset.")),
            LegendItem(slot: .custom,       title: "CUSTOM / NOTICE",
                       description: L("Company moves, meal breaks, holidays, or special non-scene strips."))
        ]
    }

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Color Legend"),
                subtitle: L("Standard Movie Magic Scheduling color code used across the Stripboard, Calendar, and Boneyard.")
            )
        } content: {
            Form {
                Section {
                    ForEach(legendItems) { item in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(palette.color(for: item.slot))
                                .frame(width: 32, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.subheadline.bold())
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Spacer()
                Button(L("Close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .editorContainer(Self.sheetSize)
    }
}

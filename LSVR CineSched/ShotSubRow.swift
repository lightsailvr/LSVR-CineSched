// ShotSubRow.swift
// One shot under its scene's strip (#42): the shot number (the scene number and the
// letter, `Scene.shotNumber(at:)`), the description, the equipment dimmed, and the
// duration ("20 min", `TimeParser.formatMinutes`, the scene editor's shot rows' words).
// Never a start or end time: a shot plans the same before and after it is scheduled
// (story 39 of #36). No thumbnail: the board reads at a glance, the frames are the
// editor's and the Shot List's.
//
// Only the content: the Mac Stripboard puts its own indent, background, gestures and
// drag around it, and the phone's lists (#43) will put theirs. Platform-free, and nothing
// here builds a formatter or a table, since a board of 200 expanded strips draws one of
// these per shot on every redraw.

import SwiftUI

struct ShotSubRow: View {
    let number: String
    let shot:   Shot
    /// The adaptive primary color, not the strip's black: the sub-row sits on a
    /// translucent tint of the strip's color (`tint(for:palette:colorScheme:)`) over the
    /// board, which is dark in dark appearance, so the strip's own text color would be
    /// black on near-black there (#36's review). `Color.primary`, the color, because a
    /// tinted `List` row resolves the hierarchical `.primary` to the tint.
    private var textColor: Color { Color.primary }

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(textColor.opacity(0.75))
                .lineLimit(1)
                .frame(minWidth: 34, alignment: .leading)

            Text(shot.details.isEmpty ? L("No description") : shot.details)
                .font(.system(size: 11))
                .foregroundColor(textColor.opacity(shot.details.isEmpty ? 0.45 : 0.9))
                .lineLimit(1)
                .layoutPriority(1)

            if !shot.equipment.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: StripboardField.specialEquipment.icon)
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(shot.equipment.joined(separator: ", "))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundColor(textColor.opacity(0.5))
            }

            Spacer(minLength: 4)

            Text(TimeParser.formatMinutes(shot.durationMinutes))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// The fill behind a scene's sub-rows (and its "No shots" line): the strip's color,
    /// lightened, a little stronger in dark appearance where the board behind is dark. The
    /// one rule for the Mac Stripboard and both phone lists.
    static func tint(for scene: Scene, palette: ScenePalette, colorScheme: ColorScheme) -> Color {
        scene.stripColor(in: palette).opacity(colorScheme == .dark ? 0.35 : 0.28)
    }
}

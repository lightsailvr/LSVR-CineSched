// BoneyardListView.swift
// The Boneyard: the sidebar's list of unscheduled scenes in Movie Magic strip styling,
// with the drag out to a day, the drop back from one, the hover tooltip, the double-tap
// editor and the right-click (long-press) menu. Extracted from ContentView for #17 so the
// Mac window and the iPad's three-column editor draw the same list; every action is a
// closure the editor supplies, and every write happens in the editor's edit funnel.
//
// Drag and drop (#18): each row is `draggable` with a `ScheduleDragPayload` of scenes,
// widened by the editor to the whole multi-selection when the row is part of it; the whole
// list is the drop destination for strips coming back from a day. (Not the drag container
// with selection: on 27.0 a `dragContainer(for: ScheduleDragPayload.self)` here captured
// the schedule's plain draggables of the same type and crashed their lift at
// `DragContainerStorage.payload(for:)`, so every drag on the schedule uses plain
// `draggable`, and the Boneyard matches it. See CalendarView's header note.)
//
// View-body cost (#34): this body is evaluated for every Boneyard row on every redraw,
// and SwiftUI builds `.contextMenu` eagerly, so nothing here builds a formatter or scans
// the project. The sorted rows and the duplicate set arrive computed once per change
// (`DerivedScheduleState`).

import SwiftUI

struct BoneyardListView: View {
    /// The Boneyard's script scenes in display order, each with its index in `allScenes`,
    /// which is what the edit and delete actions address.
    let items: [(index: Int, scene: Scene)]
    let duplicateSceneNumberIDs: Set<UUID>
    let selectedSceneIDs: Set<UUID>

    /// A single tap or click; the editor applies its modifier-key rules.
    let onSelect:    (UUID) -> Void
    /// Double tap, or Edit Scene in the menu: open the full editor for the row.
    let onEdit:      (Int, Scene) -> Void
    let onDuplicate: (Scene) -> Void
    let onDelete:    (Int) -> Void
    /// The payload a row carries when it is lifted (the selection widened, or the row).
    let dragPayload: (Scene) -> ScheduleDragPayload
    /// Strips dropped back from a day.
    let onDropFromSchedule: ([ScheduleDragPayload]) -> Void

    @Environment(\.scenePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(items, id: \.scene.id) { item in
                    let isDup = duplicateSceneNumberIDs.contains(item.scene.id)
                    HStack(spacing: 6) {
                        if !item.scene.sceneNumber.isEmpty {
                            Text(item.scene.sceneNumber)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(item.scene.stripTextColor.opacity(0.6))
                                .lineLimit(1)
                                .frame(minWidth: 18, alignment: .leading)
                        }

                        Text(item.scene.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(item.scene.stripTextColor)
                            .lineLimit(1)

                        if isDup {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                        }

                        Spacer(minLength: 4)

                        Text(FractionParser.formatEighths(item.scene.duration))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(item.scene.stripTextColor.opacity(0.8))
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background(item.scene.stripColor(in: palette))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(selectedSceneIDs.contains(item.scene.id) ? Color.accentColor : item.scene.stripTextColor.opacity(0.2), lineWidth: selectedSceneIDs.contains(item.scene.id) ? 2 : 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .opacity(isDup ? 1 : 0)
                    )
                    .draggable(dragPayload(item.scene))
                    .fastTooltip(item.scene.tooltipText)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onEdit(item.index, item.scene)
                        }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            onSelect(item.scene.id)
                        }
                    )
                    .contextMenu {
                        Button(L("Edit Scene")) {
                            onEdit(item.index, item.scene)
                        }
                        Button(L("Duplicate Scene")) {
                            onDuplicate(item.scene)
                        }
                        Divider()
                        Button(L("Delete Scene"), role: .destructive) {
                            onDelete(item.index)
                        }
                    }
                }
            }
            .padding(4)
        }
        .tooltipContainer()
        .dropDestination(for: ScheduleDragPayload.self) { items, _ in
            onDropFromSchedule(items)
        }
    }
}

// AddScenesSheet.swift
// Add Scenes on the iPhone's Day screen (#25: one adaptive `Form`, the same on every
// platform): the Boneyard as a checklist, in the order the Boneyard tab shows it, and one
// button that places every checked scene at the end of the day in that order (not the
// order they were checked in), as one edit. The rows carry the strip's color, number,
// slugline, pages and cast so a scene is recognized the way it is on the board. The
// checked set is this view's own state — there is nothing to validate or write back but
// the ids, so no draft. Only the size around the form changes per container
// (`editorContainer`).

import SwiftUI

struct AddScenesSheet: View {
    /// "Day 3 · Mon Nov 2", the day the scenes go to.
    let dayName: String
    /// The Boneyard's script scenes in display order (the sorted Boneyard).
    let boneyard: [Scene]
    let onAdd:    (Set<UUID>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<UUID> = []
    @Environment(\.scenePalette) private var palette

    static let sheetSize = EditorSheetSize(width: 440, height: 600, compactDetents: [.large])

    private var addTitle: String {
        switch selected.count {
        case 0:  return L("Add Scenes")
        case 1:  return L("Add 1 Scene")
        default: return String(format: L("Add %d Scenes"), selected.count)
        }
    }

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Add Scenes"),
                subtitle: dayName.isEmpty ? L("From the Boneyard") : "\(L("From the Boneyard to")) \(dayName)"
            )
        } content: {
            Form {
                if boneyard.isEmpty {
                    Section {
                        ContentUnavailableView(
                            L("Boneyard Is Empty"),
                            systemImage: "tray",
                            description: Text(L("Every scene is already on a day."))
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(boneyard) { scene in
                            row(scene)
                        }
                    } header: {
                        Text(boneyard.count == 1 ? L("1 scene in the Boneyard") : String(format: L("%d scenes in the Boneyard"), boneyard.count))
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Button(L("Cancel")) { onCancel() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(addTitle) { onAdd(selected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("AddScenesConfirm")
            }
        }
        .editorContainer(Self.sheetSize)
    }

    // MARK: - Row

    /// One Boneyard scene: a check, its strip color, number, slugline, pages and cast.
    private func row(_ scene: Scene) -> some View {
        let isChecked = selected.contains(scene.id)
        return Button {
            if isChecked { selected.remove(scene.id) } else { selected.insert(scene.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(scene.stripColor(in: palette))
                    .frame(width: 6, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !scene.sceneNumber.isEmpty {
                            Text(scene.sceneNumber)
                                .font(.subheadline.weight(.bold).monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(scene.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text("\(FractionParser.formatEighths(scene.duration)) \(L("pgs"))")
                        if scene.estimatedTime > 0 {
                            Text(formattedTimeHM(scene.estimatedTime))
                        }
                        if !scene.cast.isEmpty {
                            Text(scene.cast.count == 1 ? L("1 cast") : String(format: L("%d cast"), scene.cast.count))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityLabel(Text("\(scene.sceneNumber) \(scene.title)"))
    }
}

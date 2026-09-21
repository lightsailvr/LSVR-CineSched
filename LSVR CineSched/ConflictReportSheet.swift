// ConflictReportSheet.swift
// Lists every scene where a scheduled character's actor is marked unavailable in
// Production Setup (#21: one adaptive `Form`, the same on every platform). Conflicts
// are also detected continuously in the background (the affected scene strips turn red
// on the calendar as soon as a conflict exists) — this sheet is for pulling up the full
// list on demand, e.g. before locking a schedule. A row jumps the schedule to its date.
// Only the size around the form changes per container (`editorContainer`).

import SwiftUI

struct ConflictReportSheet: View {
    let conflicts: [ScheduleConflict]
    let onSelectDate: (Date) -> Void
    let onDismiss: () -> Void

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 420, height: 460, compactDetents: [.medium, .large])

    private var summary: String {
        conflicts.isEmpty
            ? L("No conflicts found")
            : "\(conflicts.count) \(conflicts.count == 1 ? L("conflict") : L("conflicts")) \(L("found"))"
    }

    var body: some View {
        EditorChrome {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Schedule Conflicts"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(conflicts.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } content: {
            Form {
                if conflicts.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(L("No Conflicts"), systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        } description: {
                            Text(L("Nobody scheduled against their own unavailable dates."))
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(conflicts) { conflict in
                            Button {
                                onSelectDate(conflict.date)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formattedDate(conflict.date))
                                            .fontWeight(.medium)
                                        Text("\(conflict.actorDisplayName) — \(conflict.sceneTitle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("Jump to this date"))
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Spacer()
                Button(L("Close")) { onDismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .editorContainer(Self.sheetSize)
    }
}

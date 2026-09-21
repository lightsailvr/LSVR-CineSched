// ScheduleLockReportSheet.swift
// Lists every character whose working days have changed since the schedule was locked —
// which days were added, which were removed — so a rearrangement doesn't silently shift
// someone's days without you noticing (#21: one adaptive `Form`, the same on every
// platform). A row jumps the schedule to the first changed date. Only the size around
// the form changes per container (`editorContainer`).

import SwiftUI

struct ScheduleLockReportSheet: View {
    let changes: [ScheduleLockChange]
    let lockedAt: Date?
    let onSelectDate: (Date) -> Void
    let onDismiss: () -> Void

    /// The Mac frame the fixed-frame sheet had.
    static let sheetSize = EditorSheetSize(width: 460, height: 480, compactDetents: [.medium, .large])

    var body: some View {
        EditorChrome {
            header
        } content: {
            Form {
                if lockedAt == nil {
                    Section {
                        ContentUnavailableView {
                            Label(L("Schedule Not Locked"), systemImage: "lock.open")
                        } description: {
                            Text(L("Lock the schedule from the Production menu to start tracking changes to actor working days."))
                        }
                        .listRowBackground(Color.clear)
                    }
                } else if changes.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(L("No Changes"), systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        } description: {
                            Text(L("No actor working days have changed since the lock."))
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(changes) { change in
                            Button {
                                if let first = (change.addedDays + change.removedDays).min() {
                                    onSelectDate(first)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(change.actorDisplayName)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    if !change.addedDays.isEmpty {
                                        changeRow(icon: "plus.circle.fill", color: .green,
                                                  label: L("Added"), dates: change.addedDays)
                                    }
                                    if !change.removedDays.isEmpty {
                                        changeRow(icon: "minus.circle.fill", color: .red,
                                                  label: L("Removed"), dates: change.removedDays)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("Jump to the first changed date"))
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Schedule Lock Changes"))
                .font(.title2)
                .fontWeight(.semibold)
            if let lockedAt {
                Text("\(L("Locked")) \(formattedDate(lockedAt)) · \(changes.count) \(changes.count == 1 ? L("actor") : L("actors")) \(L("affected"))")
                    .font(.subheadline)
                    .foregroundStyle(changes.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            } else {
                Text(L("No lock is currently set"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rows

    private func changeRow(icon: String, color: Color, label: String, dates: [Date]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text("\(label): \(dates.map { formattedDate($0) }.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

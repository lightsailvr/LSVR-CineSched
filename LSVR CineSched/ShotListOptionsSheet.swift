// ShotListOptionsSheet.swift
// The Shot List's options before its export (#40): the scope (the whole project, or one
// shoot day from a picker of the days that have scenes, each named the way the phone names
// a day, `DaySummary.label`) and Include Storyboard Frames. The month export's shape
// (MonthPDFOptionsSheet, #21): one adaptive form, the same on every platform, whose
// controls write straight through bindings to the app-wide `@AppStorage` keys
// (ShotListPDFOptions.swift), so the choice is remembered whether the user exports or
// cancels. Export hands the resolved options to the caller, which dismisses the sheet and
// builds the request through `PDFExport.shotList`; nothing here exports.

import SwiftUI

struct ShotListOptionsSheet: View {
    /// The project's shoot days; the picker offers those with a scene that prints.
    let shootDays: [ShootDay]
    /// The remembered scope, `ShotListPDFOptionSettings.raw(for:)`.
    @Binding var scopeRaw: String
    @Binding var includeFrames: Bool
    let onCancel: () -> Void
    let onExport: (ShotListPDFOptions) -> Void

    /// A short form: the Mac frame fits its two sections, the iPhone opens at medium.
    static let sheetSize = EditorSheetSize(width: 480, height: 400, compactDetents: [.medium, .large], fitsHeight: true)

    private var days: [ShootDay] { ShotListPDFOptions.pickableDays(in: shootDays) }
    private var scope: ShotListScope { ShotListPDFOptionSettings.scope(fromRaw: scopeRaw, in: shootDays) }

    var body: some View {
        // The day table once per body, not per picker row.
        let dayNumbers = productionDayNumbers(for: shootDays)
        EditorChrome {
            EditorTitle(
                title:    L("Shot List Options"),
                subtitle: L("Every shot of the scenes in scope, with their equipment, props and SFX.")
            )
        } content: {
            Form {
                Section {
                    Picker(L("Scope"), selection: scopeKind) {
                        Text(L("Whole Project")).tag(false)
                        Text(L("One Day")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(days.isEmpty)
                    if case .day(let id) = scope {
                        Picker(L("Day"), selection: dayBinding(current: id)) {
                            ForEach(days) { day in
                                Text(DaySummary.label(dayNumber: dayNumbers[day.id], date: day.date)).tag(day.id)
                            }
                        }
                    }
                } footer: {
                    if days.isEmpty {
                        Text(L("No shoot day has scenes yet, so the Shot List covers the whole project."))
                    }
                }
                Section {
                    FieldToggleRow(isOn: $includeFrames,
                                   icon: "photo",
                                   label: L("Include Storyboard Frames"),
                                   detail: L("Three shots a page with their frames; off prints a table, one line per shot"))
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Spacer()
                Button(L("Cancel")) { onCancel() }
                Button(L("Export…")) {
                    onExport(ShotListPDFOptions(scope: scope, includeFrames: includeFrames))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .editorContainer(Self.sheetSize)
    }

    // MARK: - Bindings onto the remembered scope

    /// True for one day. Switching to a day picks the first pickable one; the segment is
    /// disabled in effect when there is none (the scope stays the whole project).
    private var scopeKind: Binding<Bool> {
        Binding(
            get: {
                if case .day = scope { return true }
                return false
            },
            set: { isDay in
                if isDay, let first = days.first {
                    scopeRaw = ShotListPDFOptionSettings.raw(for: .day(first.id))
                } else {
                    scopeRaw = ShotListPDFOptionSettings.projectRaw
                }
            }
        )
    }

    private func dayBinding(current: UUID) -> Binding<UUID> {
        Binding(
            get: { current },
            set: { scopeRaw = ShotListPDFOptionSettings.raw(for: .day($0)) }
        )
    }
}

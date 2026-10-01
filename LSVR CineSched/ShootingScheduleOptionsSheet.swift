// ShootingScheduleOptionsSheet.swift
// The Shooting Schedule's options before its export: Include Shot Count and Include Scene
// Description. The Shot List's shape (ShotListOptionsSheet, #40): one adaptive form, the
// same on every platform, whose switches write straight through bindings to the app-wide
// `@AppStorage` keys (ShootingSchedulePDFOptions.swift), so the choice is remembered
// whether the user exports or cancels. Export hands the options to the caller, which runs
// the export from the `.sheet`'s `onDismiss` (`runPendingExport`); nothing here exports.

import SwiftUI

struct ShootingScheduleOptionsSheet: View {
    @Binding var includeShotCount:   Bool
    @Binding var includeDescription: Bool
    /// The subtitle's scope: one day's label, or nil for the whole schedule.
    let dayLabel: String?
    let onCancel: () -> Void
    let onExport: (ShootingSchedulePDFOptions) -> Void

    /// A short form: the Mac frame fits its one section, the iPhone opens at medium.
    static let sheetSize = EditorSheetSize(width: 480, height: 340, compactDetents: [.medium, .large], fitsHeight: true)

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    L("Shooting Schedule Options"),
                subtitle: dayLabel.map { "\(L("One day:")) \($0)" } ?? L("Every day of the schedule, each strip with its time, estimate, pages and cast.")
            )
        } content: {
            Form {
                Section {
                    FieldToggleRow(isOn: $includeShotCount,
                                   icon: "film.stack",
                                   label: L("Include Shot Count"),
                                   detail: L("\"4 shots\" on the row of each scene with a shot list"))
                    FieldToggleRow(isOn: $includeDescription,
                                   icon: "text.alignleft",
                                   label: L("Include Scene Description"),
                                   detail: L("Each scene's description, one line under its cast"))
                }
            }
            .formStyle(.grouped)
        } footer: {
            HStack {
                Spacer()
                Button(L("Cancel")) { onCancel() }
                Button(L("Export…")) {
                    onExport(ShootingSchedulePDFOptions(includeShotCount: includeShotCount, includeDescription: includeDescription))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .editorContainer(Self.sheetSize)
    }
}

// MARK: - Export after dismiss

extension ShootingScheduleOptionsSheet {
    /// The sheet as both editors present it (the Mac window's `ContentView`, the phone's
    /// Production tab): Export keeps the options in `pendingExport` and closes the sheet,
    /// and the caller's `.sheet(item:onDismiss:)` runs them through `runPendingExport`, so
    /// the preview or the failure alert is never presented over a sheet still going away.
    init(
        includeShotCount:   Binding<Bool>,
        includeDescription: Binding<Bool>,
        dayLabel:           String?,
        pendingExport:      Binding<ShootingSchedulePDFOptions?>,
        dismiss:            @escaping () -> Void
    ) {
        self.init(
            includeShotCount:   includeShotCount,
            includeDescription: includeDescription,
            dayLabel:           dayLabel,
            onCancel:           dismiss,
            onExport:           { options in
                pendingExport.wrappedValue = options
                dismiss()
            }
        )
    }

    /// The `.sheet`'s `onDismiss`: the export the sheet asked for, once it is gone (and
    /// nothing when it was cancelled or another sheet closed).
    static func runPendingExport(_ pendingExport: Binding<ShootingSchedulePDFOptions?>, _ export: (ShootingSchedulePDFOptions) -> Void) {
        guard let options = pendingExport.wrappedValue else { return }
        pendingExport.wrappedValue = nil
        export(options)
    }
}

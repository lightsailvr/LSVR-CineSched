// ProductionTab+Range.swift
// The Production tab's Project section (#28): the title field (one `EditGesture` per
// focus session, the `ContentView` rule), the production range's two date pickers,
// Shift Schedule and Update Calendar, with the confirmation the phone shows before a
// change that would send scenes back to the Boneyard (there is no visible Undo on a
// phone; the Mac applies without asking). The pickers' dates are `PhoneEditor`'s state
// (seeded from the shoot days' bounds, re-seeded on `restoreCount`), because the Day
// screen's Clear Day Type reads the same range; the change itself is one
// `updateProductionRange` edit (ProductionRange.swift), and the confirmation's copy
// follows `ProductionRangePreview.shifts`: with Shift Schedule on and the start moved,
// the call sheets, events, day types and notes move with the schedule, otherwise they
// stay on their dates.

import SwiftUI

extension ProductionTab {

    // MARK: - The section

    var projectSection: some View {
        Section {
            TextField(L("Movie Title"), text: projectTitleBinding)
                .font(.headline)
                .focused($titleFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("ProjectTitleField")
            DatePicker(L("Start Date"), selection: $startDate, displayedComponents: .date)
            DatePicker(L("End Date"), selection: $endDate, displayedComponents: .date)
            Toggle(L("Shift Schedule"), isOn: shiftModeBinding)
            Button {
                requestRangeUpdate()
            } label: {
                HStack {
                    Label(L("Update Calendar"), systemImage: "calendar.badge.clock")
                    Spacer()
                    Text(rangeDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!rangeIsApplicable)
            .accessibilityIdentifier("UpdateCalendar")
        } header: {
            Text(L("Project"))
        } footer: {
            Text(L("Shift Schedule: when the start date moves, every scene, event, call sheet, day type and note slides with it. Off, everything stays on its date and days outside the new range return their scenes to the Boneyard."))
        }
    }

    // MARK: - Project settings

    // MARK: - Project settings

    var projectTitleBinding: Binding<String> {
        Binding(
            get: { project.projectTitle },
            set: { new in editCoalescing(titleGesture, L("Rename Project")) { $0.projectTitle = new } }
        )
    }

    var shiftModeBinding: Binding<Bool> {
        Binding(
            get: { project.isShiftModeEnabled ?? false },
            set: { new in edit(L("Shift Schedule")) { $0.isShiftModeEnabled = new } }
        )
    }

    /// The project's range as it is (the exports draw it), today twice for a project
    /// without days.
    var currentRange: ClosedRange<Date> {
        Self.dateRange(of: shootDays) ?? Date()...Date()
    }

    var rangeIsApplicable: Bool {
        guard startDate <= endDate else { return false }
        let cal = Calendar.current
        guard let current = Self.dateRange(of: shootDays) else { return true }
        return !(cal.isDate(startDate, inSameDayAs: current.lowerBound) && cal.isDate(endDate, inSameDayAs: current.upperBound))
    }

    /// "Nov 2 – Nov 6 · 5 days", or what is wrong with the pending range.
    var rangeDetail: String {
        guard startDate <= endDate else { return L("End before start") }
        let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1
        return days == 1 ? L("1 day") : String(format: L("%d days"), days)
    }

    /// Update Calendar: a range that would send scenes back to the Boneyard is confirmed
    /// first (there is no visible Undo on a phone); any other applies at once.
    func requestRangeUpdate() {
        guard rangeIsApplicable else { return }
        let preview = project.previewProductionRange(from: startDate, to: endDate)
        if preview.displacedSceneCount > 0 {
            pendingRangePreview      = preview
            showingRangeConfirmation = true
        } else {
            applyRangeUpdate()
        }
    }

    /// One edit, so the whole regeneration is one undo step (`ProductionRange.swift`).
    func applyRangeUpdate() {
        pendingRangePreview = nil
        let newStart = startDate
        let newEnd   = endDate
        edit(L("Update Calendar")) { $0.updateProductionRange(from: newStart, to: newEnd) }
        seededRange = Self.dateRange(of: shootDays)
    }

    /// What the change does besides the displaced scenes: with Shift Schedule on and the
    /// start moved, everything slides with it; otherwise everything stays on its date.
    func rangeConfirmationMessage(_ preview: ProductionRangePreview) -> String {
        let scenes = preview.displacedSceneCount == 1
            ? L("1 scene on a day outside the new range will return to the Boneyard.")
            : String(format: L("%d scenes on days outside the new range will return to the Boneyard."), preview.displacedSceneCount)
        let rest = preview.shifts
            ? L("Call sheets, calendar events, day types and notes move with the schedule to the new start.")
            : L("Call sheets, calendar events, day types and notes stay on their dates.")
        return scenes + " " + rest
    }

    // MARK: - The confirmation

    /// The Update Calendar confirmation, hung off the tab's list.
    func applyRangeConfirmation<Content: View>(_ content: Content) -> some View {
        content.confirmationDialog(
            L("Update the production range?"),
            isPresented: $showingRangeConfirmation,
            titleVisibility: .visible,
            presenting: pendingRangePreview
        ) { _ in
            Button(L("Update Calendar")) { applyRangeUpdate() }
            Button(L("Cancel"), role: .cancel) { pendingRangePreview = nil }
        } message: { preview in
            Text(rangeConfirmationMessage(preview))
        }
    }
}

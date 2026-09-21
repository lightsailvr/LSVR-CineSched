// CallSheetEditor.swift
// The per-day call sheet editor (#20): one adaptive `Form` for every container, in the
// #19 chrome. The general call and schedule, the milestones and meals, the hospital, the
// weather, the basecamp and the day's locations, the notes are sections of one form;
// the cast calls and the crew calls are lists with a row per entry, and each row opens
// a detail page with the entry's fields, pushed inside the editor's own
// `NavigationStack` (the chrome's header shows Back and the entry, the footer Remove
// and Done) so the same view serves the Mac's 780 x 750 sheet, the iPad's form sheet
// and the iPhone's. The fields are a `CallSheetDraft`, pre-filled the way the old
// sheet did on appear, and Save assigns `draft.applied(to:)` through the day binding
// once: one `perform`, one undo step. Export PDF saves the same way first, then hands
// the saved day to the caller (the Mac's save panel, the iPad's preview, #23); the
// Stripboard's `onSave` then syncs its auto-meal strips from the new times.

import SwiftUI

struct CallSheetEditor: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var shootDay: ShootDay
    let productionInfo: ProductionInfo
    @Binding var isPresented: Bool
    let onSave: () -> Void
    let onExportPDF: (ShootDay) -> Void
    let dayNumber: Int?
    let totalProductionDays: Int

    @State private var draft: CallSheetDraft
    @State private var path: [Route] = []
    // The add-location row (a location has no detail page: name and address only).
    @State private var newLocationName:    String = ""
    @State private var newLocationAddress: String = ""

    static let sheetSize = EditorSheetSize(width: 780, height: 750, compactDetents: [.large])

    private enum Route: Hashable {
        case castCall(UUID)
        case crewCall(UUID)
    }

    init(
        shootDay: Binding<ShootDay>,
        productionInfo: ProductionInfo,
        isPresented: Binding<Bool>,
        onSave: @escaping () -> Void,
        onExportPDF: @escaping (ShootDay) -> Void,
        dayNumber: Int?,
        totalProductionDays: Int
    ) {
        _shootDay                = shootDay
        self.productionInfo      = productionInfo
        _isPresented             = isPresented
        self.onSave              = onSave
        self.onExportPDF         = onExportPDF
        self.dayNumber           = dayNumber
        self.totalProductionDays = totalProductionDays
        // Populated here rather than on appear so the first frame shows the day.
        _draft = State(initialValue: CallSheetDraft(day: shootDay.wrappedValue, productionInfo: productionInfo))
    }

    var body: some View {
        EditorChrome {
            EditorStackTitle(title: title, subtitle: subtitle, page: pageTitle) {
                path.removeLast()
            }
        } content: {
            NavigationStack(path: $path) {
                form
                    .editorStackPage()
                    .navigationDestination(for: Route.self) { route in
                        page(for: route)
                            .editorStackPage()
                    }
            }
        } footer: {
            if path.isEmpty {
                rootFooter
            } else {
                pageFooter
            }
        }
        .editorContainer(Self.sheetSize)
    }

    // MARK: - Header

    private var title: String {
        if let dayNumber {
            return "\(L("Call Sheet")) #\(String(format: "%02d", dayNumber))"
        }
        return L("Call Sheet")
    }

    private var subtitle: String {
        let date = formattedFullDate(shootDay.date)
        if let dayNumber {
            return "\(L("Day")) \(dayNumber) \(L("of")) \(totalProductionDays) · \(date)"
        }
        return date
    }

    private var pageTitle: String? {
        switch path.last {
        case .castCall(let id):
            let name = draft.castCalls.first { $0.id == id }?.characterName.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? L("Cast Call") : name
        case .crewCall(let id):
            let entry = draft.crewCalls.first { $0.id == id }
            let name  = entry?.name.trimmingCharacters(in: .whitespaces) ?? ""
            let role  = entry?.role.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? (role.isEmpty ? L("Crew Call") : role) : name
        case nil:
            return nil
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            generalSection
            milestonesSection
            hospitalSection
            weatherSection
            basecampSection
            locationsSection
            castSection
            crewSection
            notesSection
        }
        .formStyle(.grouped)
    }

    private var generalSection: some View {
        Section(L("General Call & Schedule")) {
            timeField(L("General Call"), example: "07:30 AM", text: $draft.generalCallTime)
            LabeledContent(L("Estimated Schedule")) {
                TextField("07:30 AM to 09:30 PM", text: $draft.workDaySchedule)
                    .multilineTextAlignment(.trailing)
            }
            TextField(L("Quote of the Day"), text: $draft.quoteOfTheDay,
                      prompt: Text(L("e.g. \"Every great film begins with a great schedule.\"")))
        }
    }

    private var milestonesSection: some View {
        Section {
            timeField(L("Ready to Shoot (On Set)"), example: "08:00 AM", text: $draft.readyToShootTime)
            timeField(L("Lunch"),                   example: "01:30 PM", text: $draft.lunchTime)
            timeField(L("Snack"),                   example: "05:00 PM", text: $draft.snackTime)
            timeField(L("Dinner"),                  example: "08:30 PM", text: $draft.dinnerTime)
            timeField(L("Wrap / Fin de Rodaje"),    example: "09:30 PM", text: $draft.wrapTime)
        } header: {
            Text(L("Milestones & Meal Times"))
        } footer: {
            Text(L("12-hour times. The Stripboard's call, meal and wrap strips follow these."))
        }
    }

    private var hospitalSection: some View {
        Section(L("Nearest Hospital")) {
            TextField(L("Nearest Hospital"), text: $draft.nearestHospital,
                      prompt: Text(L("Hospital name, address, emergency phone number")))
        }
    }

    private var weatherSection: some View {
        Section {
            LabeledContent(L("Temperature")) {
                TextField("68°F - 55°F / 15°C - 12°C", text: $draft.weatherTemp)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(L("Sky Condition")) {
                TextField(L("Partly cloudy"), text: $draft.weatherCondition)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(L("Precipitation & Wind")) {
                TextField("Rain: 10%, Wind: 10 km/h", text: $draft.weatherPrecipWind)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(L("Sunrise / Sunset")) {
                TextField("06:45 AM / 07:30 PM", text: $draft.sunTimes)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text(L("Weather Forecast & Sun Times"))
        } footer: {
            Text(L("Leave blank if not needed."))
        }
    }

    private var basecampSection: some View {
        Section {
            TextField(L("Basecamp"), text: $draft.basecampLocation,
                      prompt: Text(L("e.g. Parking Basecamp — 123 Studio Way, Lot B")))
        } header: {
            Text(L("Basecamp Location / Address"))
        } footer: {
            Text(L("Appears prominently on the call sheet above the hospital."))
        }
    }

    // MARK: Locations

    private var availableRosterLocations: [Location] {
        draft.availableRosterLocations(in: productionInfo)
    }

    private var locationsSection: some View {
        Section {
            if draft.locations.isEmpty {
                Text(L("No locations added for this day yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(draft.locations.enumerated()), id: \.element.id) { index, location in
                locationRow(location, number: index + 1)
            }
            .onDelete { draft.locations.remove(atOffsets: $0) }

            if !availableRosterLocations.isEmpty {
                Menu {
                    ForEach(availableRosterLocations) { location in
                        Button(location.name) { draft.addRosterLocation(location) }
                    }
                } label: {
                    Label(L("Add from Roster"), systemImage: "list.bullet.rectangle")
                }
            }

            TextField(L("Location Name"), text: $newLocationName, prompt: Text(L("New location, e.g. Airport Hangar")))
            TextField(L("Address"), text: $newLocationAddress, prompt: Text(L("Address, e.g. 123 Runway St, City")))
            Button {
                draft.addLocation(name: newLocationName, address: newLocationAddress)
                newLocationName    = ""
                newLocationAddress = ""
            } label: {
                Label(L("Add Location"), systemImage: "plus.circle.fill")
            }
            .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text(L("Today's Shooting Locations"))
        } footer: {
            Text(L("Each location is numbered (LOC 1, LOC 2, …) and appears on the scene breakdown."))
        }
    }

    private func locationRow(_ location: Location, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("LOC \(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue)
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name.isEmpty ? L("Unnamed Location") : location.name)
                    .fontWeight(.medium)
                if !location.address.isEmpty {
                    Text(location.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                draft.removeLocation(id: location.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("Remove Location"))
            .accessibilityLabel(L("Remove Location"))
        }
    }

    // MARK: Cast calls

    private var castSection: some View {
        Section {
            Button {
                draft.populateCast(from: shootDay, productionInfo: productionInfo)
            } label: {
                Label(L("Auto-populate from Scenes"), systemImage: "wand.and.stars")
            }
            .help(L("Pulls all characters scheduled today with their assigned actors and scene numbers"))

            if draft.castCalls.isEmpty {
                Text(L("No cast members listed. Auto-populate from the scenes or add one."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.castCalls) { entry in
                NavigationLink(value: Route.castCall(entry.id)) {
                    castCallRow(entry)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        draft.removeCastCall(id: entry.id)
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                }
            }
            .onDelete { draft.castCalls.remove(atOffsets: $0) }

            Button {
                let id = draft.addCastCall(day: shootDay)
                path.append(.castCall(id))
            } label: {
                Label(L("Add Cast Member"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L("Cast Call Times"))
        }
    }

    private func castCallRow(_ entry: CastCallEntry) -> some View {
        let character = entry.characterName.trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        if !entry.sceneNumbers.isEmpty    { parts.append("\(L("Sc.")) \(entry.sceneNumbers)") }
        if !entry.ecdt.isEmpty            { parts.append(entry.ecdt) }
        if !entry.pickupTime.isEmpty      { parts.append("\(L("PU")) \(entry.pickupTime)") }
        if !entry.hmuWardrobeTime.isEmpty { parts.append("\(L("H/MU")) \(entry.hmuWardrobeTime)") }
        if !entry.onSetTime.isEmpty       { parts.append("\(L("On Set")) \(entry.onSetTime)") }
        if !entry.wrapTime.isEmpty        { parts.append("\(L("Wrap")) \(entry.wrapTime)") }
        return EditorRowSummary(
            title:   character.isEmpty ? L("Unnamed Character") : character,
            detail:  entry.actorName,
            caption: parts.joined(separator: " · "),
            badge:   entry.locationIndex.isEmpty ? nil : "LOC \(entry.locationIndex)"
        )
    }

    // MARK: Crew calls

    private var crewSection: some View {
        Section {
            Button {
                draft.loadCrew(from: productionInfo)
            } label: {
                Label(L("Load Crew from Setup"), systemImage: "person.3")
            }
            .help(L("Loads all crew members from Production Setup with their roles and phone numbers"))

            if draft.crewCalls.isEmpty {
                Text(L("No crew members added yet. Load the crew from the setup or add one."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.crewCalls) { entry in
                NavigationLink(value: Route.crewCall(entry.id)) {
                    crewCallRow(entry)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        draft.removeCrewCall(id: entry.id)
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                }
            }
            .onDelete { draft.crewCalls.remove(atOffsets: $0) }

            Button {
                let id = draft.addCrewCall()
                path.append(.crewCall(id))
            } label: {
                Label(L("Add Crew Member"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L("Crew Call Times"))
        }
    }

    private func crewCallRow(_ entry: CrewCallEntry) -> some View {
        let name = entry.name.trimmingCharacters(in: .whitespaces)
        let role = entry.role.trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        if !entry.callTime.isEmpty { parts.append(entry.callTime) }
        if !entry.phone.isEmpty    { parts.append(entry.phone) }
        return EditorRowSummary(
            title:   name.isEmpty ? (role.isEmpty ? L("Unnamed Crew Member") : role) : name,
            detail:  name.isEmpty ? nil : role,
            caption: parts.joined(separator: " · ")
        )
    }

    // MARK: Notes

    private var notesSection: some View {
        Section {
            FormTextEditor(prompt: L("All production notes and instructions in one text block"), text: $draft.notes, minHeight: 140)
        } header: {
            Text(L("General Notes"))
        }
    }

    // MARK: - Detail pages

    @ViewBuilder
    private func page(for route: Route) -> some View {
        switch route {
        case .castCall(let id):
            CastCallPage(entry: castCallBinding(id), locations: draft.locations) {
                draft.refreshSceneNumbers(ofCastCall: id, in: shootDay)
            }
        case .crewCall(let id):
            CrewCallPage(entry: crewCallBinding(id))
        }
    }

    /// Looked up by id on every get and set, never by a captured index, so a removal
    /// under the open page cannot index out of range.
    private func castCallBinding(_ id: UUID) -> Binding<CastCallEntry> {
        Binding(
            get: { draft.castCalls.first { $0.id == id } ?? CastCallEntry(id: id) },
            set: { new in
                if let i = draft.castCalls.firstIndex(where: { $0.id == id }) { draft.castCalls[i] = new }
            }
        )
    }

    private func crewCallBinding(_ id: UUID) -> Binding<CrewCallEntry> {
        Binding(
            get: { draft.crewCalls.first { $0.id == id } ?? CrewCallEntry(id: id) },
            set: { new in
                if let i = draft.crewCalls.firstIndex(where: { $0.id == id }) { draft.crewCalls[i] = new }
            }
        )
    }

    // MARK: - Footers

    private var rootFooter: some View {
        HStack(spacing: 12) {
            Button(L("Export PDF")) {
                let saved = draft.applied(to: shootDay.callSheet)
                var day   = shootDay
                day.callSheet = saved
                shootDay = day
                onExportPDF(day)
            }
            .buttonStyle(.bordered)
            .help(L("Generates a clean call sheet PDF"))

            Spacer()

            Button(L("Cancel")) { isPresented = false }
                .buttonStyle(.bordered)

            Button(L("Save")) {
                save()
                onSave()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var pageFooter: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                switch path.last {
                case .castCall(let id): draft.removeCastCall(id: id)
                case .crewCall(let id): draft.removeCrewCall(id: id)
                case nil:               break
                }
                path.removeLast()
            } label: {
                Label(L("Remove"), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(L("Remove"))

            Spacer()

            Button(L("Done")) { path.removeLast() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    /// The one write: the whole day back through the binding (the binding's setter is
    /// the trip through the document's edit funnel).
    private func save() {
        var day = shootDay
        day.callSheet = draft.applied(to: shootDay.callSheet)
        shootDay = day
    }

    private func timeField(_ label: String, example: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(example, text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Cast call page

/// One cast call's fields. The scene numbers follow the character while blank, so an
/// entry added from the list gets them once the character is typed.
private struct CastCallPage: View {
    @Binding var entry: CastCallEntry
    let locations: [Location]
    let onCharacterChanged: () -> Void

    var body: some View {
        Form {
            Section(L("Cast Member")) {
                TextField(L("Character"), text: $entry.characterName, prompt: Text(L("Character")))
                TextField(L("Actor / Actress"), text: $entry.actorName, prompt: Text(L("Actor / Actress")))
            }
            Section {
                LabeledContent(L("Scenes")) {
                    TextField("1, 4", text: $entry.sceneNumbers)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("Status")) {
                    TextField("E", text: $entry.ecdt)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("Location")) {
                    TextField("1", text: $entry.locationIndex)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if locations.isEmpty {
                    Text(L("Location is the LOC number from today's shooting locations."))
                } else {
                    Text(locations.enumerated().map { "LOC \($0.offset + 1): \($0.element.name)" }.joined(separator: " · "))
                }
            }
            Section(L("Times")) {
                LabeledContent(L("Pick Up")) {
                    TextField("07:00 AM", text: $entry.pickupTime)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("H/MU & Wardrobe")) {
                    TextField("07:30 AM", text: $entry.hmuWardrobeTime)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("On Set")) {
                    TextField("08:00 AM", text: $entry.onSetTime)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("Wrap")) {
                    TextField("09:30 PM", text: $entry.wrapTime)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: entry.characterName) { _, _ in onCharacterChanged() }
    }
}

// MARK: - Crew call page

private struct CrewCallPage: View {
    @Binding var entry: CrewCallEntry

    var body: some View {
        Form {
            Section(L("Crew Member")) {
                TextField(L("Department / Role"), text: $entry.role, prompt: Text(L("Role, e.g. DP")))
                TextField(L("Name"), text: $entry.name, prompt: Text(L("Name")))
            }
            Section {
                LabeledContent(L("Call Time")) {
                    TextField("07:30 AM", text: $entry.callTime)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("Phone")) {
                    TextField(L("Phone"), text: $entry.phone)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

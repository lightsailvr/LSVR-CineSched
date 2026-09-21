// ProductionSetupSheet.swift
// The project-wide production setup (#20): one adaptive `Form` for every container, in
// the #19 chrome. The company, the key contacts and the call sheet's lunch default are
// rows; the cast, crew and location rosters are lists with a row per member, and each
// row opens a detail page pushed inside the editor's own `NavigationStack` (the chrome's
// header shows Back and the member, the footer Remove and Done): the cast member's names
// and the date ranges they are unavailable, the crew member's name, role, phone and
// daily flag, the location's name and address. The fields are a `ProductionSetupDraft`
// (the roster pulled from the breakdown when empty, as before), and Save reports the
// character renames to the caller, which propagates them into every scene's cast and
// the call sheets, then assigns `draft.applied(to:)` through the binding once; the
// caller's gesture folds both into one undo step. Opened from the toolbar and the
// Production menu.

import SwiftUI

struct ProductionSetupSheet: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var productionInfo: ProductionInfo
    var scenes: [Scene] = []
    @Binding var isPresented: Bool
    let onSave: () -> Void
    /// Called once per renamed character (oldName, newName) when Save is pressed, so the
    /// caller can propagate the rename into every scene's cast list and existing call sheets.
    var onCharacterRenamed: (String, String) -> Void = { _, _ in }

    @State private var draft: ProductionSetupDraft
    @State private var path: [Route] = []

    static let sheetSize = EditorSheetSize(width: 620, height: 720, compactDetents: [.large])

    private enum Route: Hashable {
        case cast(UUID)
        case crew(UUID)
        case location(UUID)
    }

    init(
        productionInfo: Binding<ProductionInfo>,
        scenes: [Scene] = [],
        isPresented: Binding<Bool>,
        onSave: @escaping () -> Void,
        onCharacterRenamed: @escaping (String, String) -> Void = { _, _ in }
    ) {
        _productionInfo         = productionInfo
        self.scenes             = scenes
        _isPresented            = isPresented
        self.onSave             = onSave
        self.onCharacterRenamed = onCharacterRenamed
        // Populated here rather than on appear so the first frame shows the project.
        _draft = State(initialValue: ProductionSetupDraft(info: productionInfo.wrappedValue, scenes: scenes))
    }

    var body: some View {
        EditorChrome {
            EditorStackTitle(
                title:    L("Production Setup"),
                subtitle: L("These details appear on every call sheet"),
                page:     pageTitle
            ) {
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

    private var pageTitle: String? {
        switch path.last {
        case .cast(let id):
            let label = draft.castList.first { $0.id == id }?.displayString.trimmingCharacters(in: .whitespaces) ?? ""
            return label.isEmpty ? L("Cast Member") : label
        case .crew(let id):
            let label = draft.crew.first { $0.id == id }?.displayString.trimmingCharacters(in: .whitespaces) ?? ""
            return label.isEmpty ? L("Crew Member") : label
        case .location(let id):
            let name = draft.locationRoster.first { $0.id == id }?.name.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? L("Location") : name
        case nil:
            return nil
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            detailsSection
            contactsSection
            defaultsSection
            castSection
            crewSection
            locationsSection
        }
        .formStyle(.grouped)
    }

    private var detailsSection: some View {
        Section(L("Production Details")) {
            TextField(L("Production Company"), text: $draft.companyName, prompt: Text(L("e.g. Tempel Films")))
        }
    }

    private var contactsSection: some View {
        Section(L("Key Contacts")) {
            contactField(L("Director"),       text: $draft.directorName)
            phoneField(L("Director Phone"),   text: $draft.directorPhone)
            contactField(L("Producer"),       text: $draft.producerName)
            phoneField(L("Producer Phone"),   text: $draft.producerPhone)
            contactField(L("1st AD"),         text: $draft.adName)
            phoneField(L("1st AD Phone"),     text: $draft.adPhone)
        }
    }

    private var defaultsSection: some View {
        Section {
            LabeledContent(L("Default Lunch Time")) {
                TextField("01:30 PM", text: $draft.defaultLunchTime)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text(L("Call Sheet Defaults"))
        } footer: {
            Text(L("Pre-filled as the lunch time of a call sheet that has none."))
        }
    }

    // MARK: Cast

    private var castSection: some View {
        Section {
            if draft.castList.isEmpty {
                Text(L("No cast added yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.castList) { member in
                NavigationLink(value: Route.cast(member.id)) {
                    castRow(member)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        draft.removeCastMember(id: member.id)
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                }
            }
            .onDelete { draft.castList.remove(atOffsets: $0) }

            Button {
                let id = draft.addCastMember()
                path.append(.cast(id))
            } label: {
                Label(L("Add Cast Member"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L("Cast Roster"))
        }
    }

    private func castRow(_ member: CastMember) -> some View {
        let actor     = member.actorName.trimmingCharacters(in: .whitespaces)
        let character = member.characterName.trimmingCharacters(in: .whitespaces)
        let count     = member.unavailableRanges.count
        return EditorRowSummary(
            title:   actor.isEmpty ? (character.isEmpty ? L("Unnamed") : character) : actor,
            detail:  actor.isEmpty ? nil : character,
            caption: count == 0 ? nil : (count == 1 ? L("1 unavailable date range") : "\(count) \(L("unavailable date ranges"))")
        )
    }

    // MARK: Crew

    private var crewSection: some View {
        Section {
            if draft.crew.isEmpty {
                Text(L("No crew added yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.crew) { member in
                NavigationLink(value: Route.crew(member.id)) {
                    crewRow(member)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        draft.removeCrewMember(id: member.id)
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                }
            }
            .onDelete { draft.crew.remove(atOffsets: $0) }

            Button {
                let id = draft.addCrewMember()
                path.append(.crew(id))
            } label: {
                Label(L("Add Crew Member"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L("Crew Roster"))
        }
    }

    private func crewRow(_ member: CrewMember) -> some View {
        let name = member.name.trimmingCharacters(in: .whitespaces)
        let role = member.role.trimmingCharacters(in: .whitespaces)
        return EditorRowSummary(
            title:   name.isEmpty ? (role.isEmpty ? L("Unnamed") : role) : name,
            detail:  name.isEmpty ? nil : role,
            caption: member.phone,
            badge:   member.isDailyDefault ? L("Daily") : nil
        )
    }

    // MARK: Locations

    private var locationsSection: some View {
        Section {
            if draft.locationRoster.isEmpty {
                Text(L("No locations added yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.locationRoster) { location in
                NavigationLink(value: Route.location(location.id)) {
                    EditorRowSummary(
                        title:   location.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Unnamed Location") : location.name,
                        caption: location.address
                    )
                }
                .contextMenu {
                    Button(role: .destructive) {
                        draft.removeLocation(id: location.id)
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                }
            }
            .onDelete { draft.locationRoster.remove(atOffsets: $0) }

            Button {
                draft.pullLocationsFromBreakdown(scenes: scenes)
            } label: {
                Label(L("Pull from Breakdown"), systemImage: "sparkles")
            }
            .help(L("Extract and import all locations from scene breakdown"))

            Button {
                let id = draft.addLocation()
                path.append(.location(id))
            } label: {
                Label(L("Add Location"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L("Location Roster"))
        }
    }

    // MARK: - Detail pages

    @ViewBuilder
    private func page(for route: Route) -> some View {
        switch route {
        case .cast(let id):
            CastMemberPage(member: castBinding(id)) { start, end in
                draft.addUnavailableRange(start: start, end: end, toCastMember: id)
            } onRemoveRange: { rangeID in
                draft.removeUnavailableRange(id: rangeID, fromCastMember: id)
            }
        case .crew(let id):
            CrewMemberPage(member: crewBinding(id))
        case .location(let id):
            LocationPage(location: locationBinding(id))
        }
    }

    /// Looked up by id on every get and set, never by a captured index, so a removal
    /// under the open page cannot index out of range.
    private func castBinding(_ id: UUID) -> Binding<CastMember> {
        Binding(
            get: { draft.castList.first { $0.id == id } ?? CastMember() },
            set: { new in
                if let i = draft.castList.firstIndex(where: { $0.id == id }) { draft.castList[i] = new }
            }
        )
    }

    private func crewBinding(_ id: UUID) -> Binding<CrewMember> {
        Binding(
            get: { draft.crew.first { $0.id == id } ?? CrewMember() },
            set: { new in
                if let i = draft.crew.firstIndex(where: { $0.id == id }) { draft.crew[i] = new }
            }
        )
    }

    private func locationBinding(_ id: UUID) -> Binding<Location> {
        Binding(
            get: { draft.locationRoster.first { $0.id == id } ?? Location() },
            set: { new in
                if let i = draft.locationRoster.firstIndex(where: { $0.id == id }) { draft.locationRoster[i] = new }
            }
        )
    }

    // MARK: - Footers

    private var rootFooter: some View {
        HStack {
            Button(L("Cancel")) { isPresented = false }
                .buttonStyle(.bordered)
            Spacer()
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
                case .cast(let id):     draft.removeCastMember(id: id)
                case .crew(let id):     draft.removeCrewMember(id: id)
                case .location(let id): draft.removeLocation(id: id)
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

    /// The renames first, then the one write of the whole value: the caller opens a
    /// gesture on the first rename and its binding write follows in the same turn, so
    /// all of it is one undo step.
    private func save() {
        for rename in draft.renamedCharacters(against: productionInfo) {
            onCharacterRenamed(rename.old, rename.new)
        }
        productionInfo = draft.applied(to: productionInfo)
    }

    private func contactField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(L("Name"), text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func phoneField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(L("Phone"), text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Cast member page

/// One cast member's names and the date ranges they are unavailable, which feed the
/// schedule-wide conflict scan and the red strips on the calendar.
private struct CastMemberPage: View {
    @Binding var member: CastMember
    let onAddRange:    (Date, Date) -> Void
    let onRemoveRange: (UUID) -> Void

    @State private var newStart: Date = Date()
    @State private var newEnd:   Date = Date()

    var body: some View {
        Form {
            Section(L("Cast Member")) {
                TextField(L("Actor Name"), text: $member.actorName, prompt: Text(L("Actor Name")))
                TextField(L("Character"), text: $member.characterName, prompt: Text(L("Character")))
            }
            Section {
                if member.unavailableRanges.isEmpty {
                    Text(L("No dates marked yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(member.unavailableRanges) { range in
                    HStack {
                        Text(rangeLabel(range))
                        Spacer()
                        Button(role: .destructive) {
                            onRemoveRange(range.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove Range"))
                        .accessibilityLabel(L("Remove Range"))
                    }
                }
                DatePicker(L("From"), selection: $newStart, displayedComponents: .date)
                DatePicker(L("To"), selection: $newEnd, in: newStart..., displayedComponents: .date)
                Button {
                    onAddRange(newStart, newEnd)
                } label: {
                    Label(L("Add Range"), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(L("Unavailable Dates"))
            } footer: {
                Text(L("Scenes with this character on these dates are flagged by the conflict scan and shown in red on the calendar."))
            }
        }
        .formStyle(.grouped)
        .onChange(of: newStart) { _, start in
            if newEnd < start { newEnd = start }
        }
    }

    private func rangeLabel(_ range: DateRange) -> String {
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return formattedDate(range.start)
        }
        return "\(formattedDate(range.start)) – \(formattedDate(range.end))"
    }
}

// MARK: - Crew member page

private struct CrewMemberPage: View {
    @Binding var member: CrewMember

    var body: some View {
        Form {
            Section(L("Crew Member")) {
                TextField(L("Crew Member Name"), text: $member.name, prompt: Text(L("Name")))
                TextField(L("Role / Department"), text: $member.role, prompt: Text(L("Role / Department")))
                LabeledContent(L("Phone")) {
                    TextField(L("Phone"), text: $member.phone)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section {
                Toggle(L("Daily"), isOn: $member.isDailyDefault)
            } footer: {
                Text(L("Marks a crew member who is called every shoot day."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Location page

private struct LocationPage: View {
    @Binding var location: Location

    var body: some View {
        Form {
            Section(L("Location")) {
                TextField(L("Location Name"), text: $location.name, prompt: Text(L("Location Name")))
                TextField(L("Address"), text: $location.address, prompt: Text(L("Address")))
            }
        }
        .formStyle(.grouped)
    }
}

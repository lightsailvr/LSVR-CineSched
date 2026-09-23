// SceneEditSheet.swift
// The scene editor (#19): one adaptive `Form` for every container. The Mac's sheets
// (a strip's double-click, the Boneyard's Edit, the Breakdown Browser), the iPad's
// inspector column (#17) and the iPad's and iPhone's sheets all show this view; only the
// size around it changes (`editorContainer`). The fields are a `SceneDraft`, populated
// from the scene when the editor appears and whenever the scene's id changes (Previous /
// Next, a new inspector selection), and Save assigns `draft.applied(to:)` to the
// binding once: one `perform`, one undo step, whatever the container (the old sheet
// wrote thirty properties through the binding, one `perform` each). On the iPhone
// (#26) the footer also carries Duplicate Scene when `onDuplicate` is supplied.
//
// The shot list (#39) is the call sheet editor's list pattern (#20): a `NavigationStack`
// around the form alone, a Shots section whose rows push a `ShotPage` bound by id, the
// header switching to Back and the shot's number (`EditorStackTitle`) and the footer to
// Remove / Duplicate Shot / Add Another / Done while a page is up. Every shot edit runs
// #37's rules on the scene draft (`SceneDraft.addShot` and the rest), so the estimate
// field shows the sum, read-only with "From N shots", and the scene's frame row (shown
// only while there are no shots) empties into shot A; the pages write into the draft as
// they are typed, so however a page is left the list is current, and Save is still the
// one assignment. Add Another and Duplicate Shot replace the page on top rather than
// stacking pages, so Back always returns to the list. `initialRoute` opens the editor on
// a shot's page or a new shot's (#42, #43 call it).

import SwiftUI

struct SceneEditSheet: View {
    @Binding var scene: Scene
    @Binding var isPresented: Bool
    let onSave:   () -> Void
    let onDelete: () -> Void
    @Environment(\.editorPresentation) private var presentation

    // Optional Previous/Next navigation — when supplied, arrow buttons appear
    // next to the title so scenes can be edited in sequence without closing the sheet.
    var canGoPrevious: Bool          = false
    var canGoNext:     Bool          = false
    var onPrevious:    (() -> Void)? = nil
    var onNext:        (() -> Void)? = nil
    var positionLabel: String?       = nil
    /// The Breakdown section starts expanded by default so breakdown fields are always directly accessible.
    var breakdownExpandedByDefault: Bool = true
    /// Whether Delete Scene closes the sheet afterward. True everywhere this sheet is
    /// normally used (deleting a single scene you were editing should close it) — false
    /// for the Breakdown Browser, where closing on every delete would kick you out of a
    /// script you might be halfway through tagging, forcing a restart from scene one.
    var closeAfterDelete: Bool = true
    var knownLocations: [String] = []
    /// Duplicate Scene from inside the editor (#26, the iPhone, where the strip's
    /// right-click menu has no home): saves the draft, calls this, closes. Nil at the
    /// Mac's call sites, which offer it on the strip's menu, so the footer is unchanged.
    var onDuplicate: (() -> Void)? = nil
    /// What the shot page's Equipment, Props and SFX fields suggest (#39):
    /// `ProjectData.breakdownSuggestions`, computed at the call site per presentation.
    var breakdownSuggestions: BreakdownSuggestions = .none
    /// The page the editor opens on (#39): a shot's, or a new shot's. Applied once, to the
    /// scene the editor first shows.
    var initialRoute: SceneEditorRoute? = nil

    @State private var draft: SceneDraft
    @State private var breakdownExpanded: Bool
    @State private var focusDurationTrigger: Bool = false
    // The shot list (#39): the pushed pages, each page's fields by shot id (held here so
    // a page's text survives the stack's redraws; dropped as its page is left), the
    // phone's reorder mode, and whether `initialRoute` has been applied.
    @State private var path: [Route] = []
    @State private var shotDrafts: [UUID: ShotDraft] = [:]
    @State private var reorderingShots: Bool = false
    @State private var appliedInitialRoute: Bool = false

    private enum Route: Hashable {
        case shot(UUID)
    }

    static let sheetSize = EditorSheetSize(width: 560, height: 680, compactDetents: [.large])

    init(
        scene: Binding<Scene>,
        isPresented: Binding<Bool>,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        canGoPrevious: Bool = false,
        canGoNext: Bool = false,
        onPrevious: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        positionLabel: String? = nil,
        breakdownExpandedByDefault: Bool = true,
        closeAfterDelete: Bool = true,
        knownLocations: [String] = [],
        onDuplicate: (() -> Void)? = nil,
        breakdownSuggestions: BreakdownSuggestions = .none,
        initialRoute: SceneEditorRoute? = nil
    ) {
        _scene                     = scene
        _isPresented               = isPresented
        self.onSave                = onSave
        self.onDelete              = onDelete
        self.canGoPrevious         = canGoPrevious
        self.canGoNext             = canGoNext
        self.onPrevious            = onPrevious
        self.onNext                = onNext
        self.positionLabel         = positionLabel
        self.breakdownExpandedByDefault = breakdownExpandedByDefault
        self.closeAfterDelete      = closeAfterDelete
        self.knownLocations        = knownLocations
        self.onDuplicate           = onDuplicate
        self.breakdownSuggestions  = breakdownSuggestions
        self.initialRoute          = initialRoute
        // Populated here rather than on appear so the first frame shows the scene.
        _draft                     = State(initialValue: SceneDraft(scene: scene.wrappedValue))
        _breakdownExpanded         = State(initialValue: breakdownExpandedByDefault)
    }

    var body: some View {
        EditorChrome {
            if let page = pageTitle {
                EditorStackTitle(title: L("Edit Scene"), page: page) {
                    path.removeLast()
                }
            } else {
                header
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
            if case .shot(let id)? = path.last {
                pageFooter(shotID: id)
            } else {
                footer
            }
        }
        .editorContainer(Self.sheetSize)
        .onAppear {
            applyInitialRoute()
            if path.isEmpty { focusDurationField() }
        }
        .onChange(of: path) { _, new in
            // A page left by any route (Back, Done, a swipe) drops its fields; they are
            // already in the scene draft.
            let open = Set(new.map { route -> UUID in
                switch route { case .shot(let id): return id }
            })
            shotDrafts = shotDrafts.filter { open.contains($0.key) }
        }
        .onChange(of: scene) { old, new in
            if old.id != new.id {
                // Previous / Next, or a new selection: a new editor.
                draft             = SceneDraft(scene: new)
                breakdownExpanded = breakdownExpandedByDefault
                path              = []
                shotDrafts        = [:]
                reorderingShots   = false
                focusDurationField()
            } else if draft == SceneDraft(scene: old) {
                // The same scene changed under an untouched editor (an undo, a drag, a
                // sync): follow it. Typing in progress is never replaced.
                draft = SceneDraft(scene: new)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if onPrevious != nil {
                Button {
                    navigate(onPrevious)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .disabled(!canGoPrevious || !draft.isValid)
                .help(L("Previous Scene"))
                .accessibilityLabel(L("Previous Scene"))
            }

            // Centred between the arrows when there are arrows; leading, like the other
            // editors' titles, when there are none (the inspector).
            let centred = onPrevious != nil || onNext != nil
            VStack(alignment: centred ? .center : .leading, spacing: 2) {
                Text(L("Edit Scene"))
                    .font(.title2)
                    .fontWeight(.semibold)
                if let positionLabel {
                    Text(positionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)

            if onNext != nil {
                Button {
                    navigate(onNext)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .disabled(!canGoNext || !draft.isValid)
                .help(L("Next Scene"))
                .accessibilityLabel(L("Next Scene"))
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                LabeledContent(L("Scene #")) {
                    TextField("#", text: $draft.sceneNumber)
                        .multilineTextAlignment(.trailing)
                }
                TextField(L("Scene Title"), text: $draft.title, prompt: Text(L("e.g. INT. KITCHEN - NIGHT")))
                LocationAutocompleteField(
                    title:       L("Real Location / Set"),
                    placeholder: L("e.g. Playa de la Concha, Airport Hangar"),
                    text:        $draft.realLocation,
                    suggestions: knownLocations,
                    style:       .formRow
                )
            }

            Section {
                LabeledContent(L("Duration (pages)")) {
                    SelectAllTextField(
                        placeholder:  FractionParser.placeholderText,
                        text:         $draft.duration,
                        focusTrigger: $focusDurationTrigger
                    )
                    .multilineTextAlignment(.trailing)
                }
                if draft.hasShots {
                    // The sum of the shots (#37's estimate rule), not typed.
                    LabeledContent(L("Estimated Time")) {
                        Text(draft.estimatedTime)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent(L("Estimated Time")) {
                        TextField(TimeParser.placeholderText, text: $draft.estimatedTime)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let hint = durationHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                    }
                    if let hint = estimatedTimeHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                    }
                    if draft.hasShots {
                        Text(shotCountCaption).foregroundStyle(Color.secondary)
                    }
                }
            }

            Section {
                TextField(L("Cast"), text: $draft.castText, prompt: Text("John, Mary, Bob"))
            } header: {
                Text(L("Cast"))
            } footer: {
                Text(L("Separate names with commas"))
            }

            Section(L("Scene Summary")) {
                FormTextEditor(prompt: L("What happens in the scene"), text: $draft.summary)
            }

            Section {
                Picker(L("Type"), selection: $draft.dayNightType) {
                    ForEach(DayNightType.allCases, id: \.self) { type in
                        Text(L(type.rawValue.uppercased())).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            if !draft.hasShots {
                Section {
                    StoryboardFrameSlot(frame: $draft.frame)
                } header: {
                    Text(L("Storyboard Frame"))
                } footer: {
                    Text(L("The first shot added takes this frame."))
                }
            }

            shotsSection

            Section {
                DisclosureGroup(isExpanded: $breakdownExpanded) {
                    breakdownField(L("Extras / Background"), text: $draft.extras)
                    breakdownField(L("Props"),               text: $draft.props)
                    fromShotsLine(draft.propsFromShots)
                    breakdownField(L("Set Dressing"),        text: $draft.setDressing)
                    breakdownField(L("Wardrobe"),            text: $draft.wardrobe)
                    breakdownField(L("Hair & Makeup"),       text: $draft.makeupHair)
                    breakdownField(L("Vehicles"),            text: $draft.vehicles)
                    breakdownField(L("Special Equipment"),   text: $draft.specialEquipment)
                    fromShotsLine(draft.equipmentFromShots)
                    breakdownField(L("Stunts"),              text: $draft.stunts)
                    breakdownField(L("SFX"),                 text: $draft.sfx)
                    fromShotsLine(draft.sfxFromShots)
                    breakdownField(L("VFX"),                 text: $draft.vfx)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Breakdown Notes"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        FormTextEditor(prompt: L("Notes for the breakdown sheet"), text: $draft.breakdownNotes, minHeight: 60)
                    }
                } label: {
                    Text(L("Breakdown")).font(.headline)
                }
            }
        }
        .formStyle(.grouped)
        .listReordering(reorderingShots)
    }

    // MARK: - Shots (#39)

    private var shotsSection: some View {
        Section {
            ForEach(draft.shots) { shot in
                NavigationLink(value: Route.shot(shot.id)) {
                    ShotRow(number: draft.shotNumber(forShotID: shot.id) ?? "", shot: shot)
                }
                .contextMenu {
                    // Move Up / Move Down are the drag's keyboard- and pointer-free twin,
                    // through the same `onMove` offsets rule.
                    if let index = draft.shots.firstIndex(where: { $0.id == shot.id }) {
                        Button {
                            draft.moveShots(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                        } label: {
                            Label(L("Move Up"), systemImage: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button {
                            draft.moveShots(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                        } label: {
                            Label(L("Move Down"), systemImage: "arrow.down")
                        }
                        .disabled(index == draft.shots.count - 1)
                    }
                    Button {
                        draft.duplicateShot(withID: shot.id)
                    } label: {
                        Label(L("Duplicate Shot"), systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        draft.removeShot(withID: shot.id)
                    } label: {
                        Label(L("Remove Shot"), systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                draft.moveShots(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { draft.shots.indices.contains($0) ? draft.shots[$0].id : nil }
                for id in ids { draft.removeShot(withID: id) }
                if draft.shots.count < 2 { reorderingShots = false }
            }

            Button {
                if let id = draft.addShot() { path.append(.shot(id)) }
            } label: {
                Label(L("Add Shot"), systemImage: "plus.circle.fill")
            }
            .disabled(reorderingShots)
        } header: {
            HStack {
                Text(L("Shots"))
                Spacer()
                if PlatformListEditing.reorderingNeedsEditMode && draft.shots.count > 1 {
                    Button(reorderingShots ? L("Done") : L("Reorder")) {
                        reorderingShots.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func page(for route: Route) -> some View {
        switch route {
        case .shot(let id):
            ShotPage(draft: shotDraftBinding(id), suggestions: breakdownSuggestions)
                .id(id)
        }
    }

    /// A page's fields, looked up by id on every get and set (never a captured index).
    /// Each set writes the shot into the scene draft at once, through #37's rules, so the
    /// rows, the letters and the sum follow the typing; a gone shot writes nothing.
    private func shotDraftBinding(_ id: UUID) -> Binding<ShotDraft> {
        Binding(
            get: {
                shotDrafts[id] ?? ShotDraft(shot: draft.shot(withID: id) ?? Shot(id: id))
            },
            set: { new in
                shotDrafts[id] = new
                if let current = draft.shot(withID: id) {
                    draft.updateShot(new.applied(to: current))
                }
            }
        )
    }

    /// The shot's number ("12B") while its page is up; nil at the root.
    private var pageTitle: String? {
        guard case .shot(let id)? = path.last else { return nil }
        return draft.shotNumber(forShotID: id) ?? L("Shot")
    }

    private var shotCountCaption: String {
        draft.shots.count == 1 ? L("From 1 shot") : String(format: L("From %d shots"), draft.shots.count)
    }

    /// Under Props, Special Equipment and SFX: the items the shots add, read-only; nothing
    /// when they add none.
    @ViewBuilder
    private func fromShotsLine(_ items: [String]) -> some View {
        if !items.isEmpty {
            Text("\(L("From shots:")) \(items.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Opens the editor on `initialRoute`'s page, once: a shot's, or a new shot's (added
    /// through the draft, so Cancel leaves the scene without it).
    private func applyInitialRoute() {
        guard !appliedInitialRoute else { return }
        appliedInitialRoute = true
        switch initialRoute {
        case .shot(let id)?:
            if draft.shot(withID: id) != nil { path = [.shot(id)] }
        case .newShot?:
            if let id = draft.addShot() { path = [.shot(id)] }
        case nil:
            break
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                onDelete()
                if closeAfterDelete { isPresented = false }
            } label: {
                Label(L("Delete Scene"), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(L("Delete Scene"))

            if let onDuplicate {
                // Saves first, like Previous and Next, so the copy is of what is on screen.
                Button {
                    guard draft.isValid else { return }
                    saveChanges()
                    onSave()
                    onDuplicate()
                    isPresented = false
                } label: {
                    Label(L("Duplicate Scene"), systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .disabled(!draft.isValid)
                .help(L("Duplicate Scene"))
                .accessibilityLabel(L("Duplicate Scene"))
            }

            Spacer()

            Button(L("Cancel")) { isPresented = false }
                .buttonStyle(.bordered)

            Button(L("Save Changes")) {
                saveChanges()
                onSave()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.isValid)
        }
    }

    /// A shot page's footer: Remove (destructive, leading), Duplicate Shot, Add Another
    /// and Done. Duplicate and Add Another replace the page on top, so Back returns to the
    /// list however many shots were typed in a row; neither is offered while the duration
    /// does not parse (the page's other fields are already in the draft either way).
    private func pageFooter(shotID: UUID) -> some View {
        let valid = shotDrafts[shotID]?.isValid ?? true
        return HStack(spacing: 12) {
            Button(role: .destructive) {
                draft.removeShot(withID: shotID)
                path.removeLast()
            } label: {
                Label(L("Remove Shot"), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(L("Remove Shot"))
            .accessibilityLabel(L("Remove Shot"))

            Button {
                if let copy = draft.duplicateShot(withID: shotID) { replaceTopPage(with: copy) }
            } label: {
                Label(L("Duplicate Shot"), systemImage: "plus.square.on.square")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .disabled(!valid)
            .help(L("Duplicate Shot"))
            .accessibilityLabel(L("Duplicate Shot"))

            Spacer()

            Button(L("Add Another")) {
                if let id = draft.addShot(after: shotID) { replaceTopPage(with: id) }
            }
            .buttonStyle(.bordered)
            .disabled(!valid)

            Button(L("Done")) { path.removeLast() }
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
        }
    }

    private func replaceTopPage(with shotID: UUID) {
        guard !path.isEmpty else { path = [.shot(shotID)]; return }
        path[path.count - 1] = .shot(shotID)
    }

    // MARK: - Helpers

    private struct Hint { let text: String; let isError: Bool }

    private var durationHint: Hint? {
        if !draft.durationIsValid {
            return Hint(text: L("Invalid format. Use: 15 (eighths), 1 7/8 (mixed), or 7/8 (fraction)"), isError: true)
        }
        if let eighths = draft.parsedEighths, !draft.duration.isEmpty {
            return Hint(text: "= \(FractionParser.formatEighths(eighths)) \(L("pages")) (\(eighths) \(L("eighths")))", isError: false)
        }
        if draft.dayNightType == .custom {
            return Hint(text: L("Leave blank for no page count"), isError: false)
        }
        return nil
    }

    private var estimatedTimeHint: Hint? {
        if !draft.estimatedTimeIsValid {
            return Hint(text: L("Invalid format. Use: 4 (4 hours), 15 (15 minutes), or 2:30 (2hr 30min)"), isError: true)
        }
        if let hint = TimeParser.getInputHint(draft.estimatedTime), !draft.estimatedTime.isEmpty {
            return Hint(text: hint, isError: false)
        }
        return nil
    }

    /// Duration is the field users almost always need to correct — even on imported
    /// scenes where every field already has a default value — so focus starts there
    /// instead of landing on whatever the first empty field happens to be. Not in the
    /// inspector, where the editor appears on every tap of a strip and focusing a field
    /// would raise the on-screen keyboard over the board each time.
    private func focusDurationField() {
        guard presentation != .inspector else { return }
        DispatchQueue.main.async {
            focusDurationTrigger = true
        }
    }

    /// Saves the current edits (so they aren't lost) and moves to the adjacent scene.
    private func navigate(_ direction: (() -> Void)?) {
        guard let direction, draft.isValid else { return }
        saveChanges()
        onSave()
        direction()
    }

    /// The one write: the whole scene back through the binding.
    private func saveChanges() {
        scene = draft.applied(to: scene)
    }

    private func breakdownField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(L("Comma-separated"), text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Initial route (#39)

/// Where the scene editor opens: a shot's page, or a new shot's (appended and pushed).
/// The Stripboard's shot rows and Add Shot… (#42) and the phone's (#43) pass one.
enum SceneEditorRoute: Hashable {
    case shot(UUID)
    case newShot
}

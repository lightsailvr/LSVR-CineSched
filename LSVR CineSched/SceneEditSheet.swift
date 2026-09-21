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

    @State private var draft: SceneDraft
    @State private var breakdownExpanded: Bool
    @State private var focusDurationTrigger: Bool = false

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
        onDuplicate: (() -> Void)? = nil
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
        // Populated here rather than on appear so the first frame shows the scene.
        _draft                     = State(initialValue: SceneDraft(scene: scene.wrappedValue))
        _breakdownExpanded         = State(initialValue: breakdownExpandedByDefault)
    }

    var body: some View {
        EditorChrome {
            header
        } content: {
            form
        } footer: {
            footer
        }
        .editorContainer(Self.sheetSize)
        .onAppear {
            focusDurationField()
        }
        .onChange(of: scene) { old, new in
            if old.id != new.id {
                // Previous / Next, or a new selection: a new editor.
                draft             = SceneDraft(scene: new)
                breakdownExpanded = breakdownExpandedByDefault
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
                LabeledContent(L("Estimated Time")) {
                    TextField(TimeParser.placeholderText, text: $draft.estimatedTime)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let hint = durationHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                    }
                    if let hint = estimatedTimeHint {
                        Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
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

            Section {
                DisclosureGroup(isExpanded: $breakdownExpanded) {
                    breakdownField(L("Extras / Background"), text: $draft.extras)
                    breakdownField(L("Props"),               text: $draft.props)
                    breakdownField(L("Set Dressing"),        text: $draft.setDressing)
                    breakdownField(L("Wardrobe"),            text: $draft.wardrobe)
                    breakdownField(L("Hair & Makeup"),       text: $draft.makeupHair)
                    breakdownField(L("Vehicles"),            text: $draft.vehicles)
                    breakdownField(L("Special Equipment"),   text: $draft.specialEquipment)
                    breakdownField(L("Stunts"),              text: $draft.stunts)
                    breakdownField(L("SFX"),                 text: $draft.sfx)
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

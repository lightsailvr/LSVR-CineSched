// BoneyardTab.swift
// The iPhone's Boneyard tab (#27): the unscheduled scenes as a list of strips, in the
// Mac's six sorts (`BoneyardSort`, the same app-wide preference the Mac's sidebar menu
// writes, so the phone and the Mac agree on the order) and narrowed by a text filter
// (`SceneSearch.filter`: number, slugline, cast, summary, real location). A tap opens
// the scene editor (`PhoneSceneEditor`, stepping through the displayed rows with
// Previous and Next as the Mac's Boneyard editor does); a long press is the Mac's
// Boneyard menu (Edit, Duplicate, Send to Day…, Delete) with the strip preview; the
// trailing swipe sends one scene to a day or deletes it. Select puts the list in edit
// mode (`listSelecting`, the seam over `editMode`) for a multi-selection that one Send
// to Day places on the chosen day, all of them, in the order the list shows them
// (`BoneyardSelection.ordered`; never widened from the set at the drop, learnings
// 2026-09-20). "+" is the New Scene form (`NewSceneSheet`), whose scene lands in the
// Boneyard in one edit and is scrolled to.
//
// The rows come from the editor's derived state (`DerivedScheduleState.sortedBoneyard`,
// computed once per change for the sort the editor holds), so this body sorts nothing;
// the filter runs over that list per redraw, which is a string scan per row. Send to
// Day is `PhoneMoves.presentSendToDay` (#25), the same picker and the same move the
// Days list uses. No stack of its own and no toolbar: the document infrastructure's bar
// is the phone's one bar (PhoneEditor's note), so the filter, the sort, Select and "+"
// are a control row above the list.
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

struct BoneyardTab: View {
    let document: ProjectDocument
    /// The sorted Boneyard and the duplicate scene numbers, computed once per change.
    let derived:  DerivedScheduleState
    /// The Boneyard's sort, the editor's app-wide preference (the Mac's key).
    @Binding var sort: BoneyardSort
    /// A scene to show: the filter clears and the list scrolls to it. Set by the Search
    /// tab's Show in Boneyard and by a scene just added; cleared here once acted on.
    @Binding var revealSceneID: UUID?
    let edit:  ProjectEdit
    let moves: PhoneMoves
    @Environment(\.scenePalette) private var palette

    @State private var filter        = ""
    @State private var isSelecting   = false
    @State private var selectedIDs:  Set<UUID> = []
    @State private var editorRequest: PhoneSceneEditorRequest? = nil
    @State private var showingNewScene = false
    @FocusState private var filterFocused: Bool

    private var project: ProjectData { document.project }

    /// The Boneyard in display order, before the filter.
    private var boneyard: [Scene] { derived.sortedBoneyard.map(\.scene) }
    /// What the list shows: the Boneyard narrowed by the filter, in display order.
    private var displayed: [Scene] { SceneSearch.filter(boneyard, query: filter) }

    // MARK: - Body

    var body: some View {
        let displayed = displayed
        VStack(spacing: 0) {
            controls(displayedCount: displayed.count, totalEighths: displayed.reduce(0) { $0 + $1.duration })
            ScrollViewReader { proxy in
                list(displayed)
                    .onChange(of: revealSceneID) { _, id in reveal(id, with: proxy) }
                    .onAppear { reveal(revealSceneID, with: proxy) }
            }
            if isSelecting {
                selectionBar(displayed)
            }
        }
        .background(Color.windowBackground)
        .sheet(item: $editorRequest) { request in
            editor(for: request.sceneID, in: displayed)
        }
        .sheet(isPresented: $showingNewScene) {
            NewSceneSheet(
                knownLocations: knownLocations,
                onAdd: { scene in
                    showingNewScene = false
                    addScene(scene)
                },
                onCancel: { showingNewScene = false }
            )
        }
        .onChange(of: document.changeCount) { _, _ in pruneSelection() }
    }

    // MARK: - Controls

    /// The row above the list: the filter field, Select / Done and "+"; under it the
    /// sort menu and what the list holds.
    private func controls(displayedCount: Int, totalEighths: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                filterField
                Button(isSelecting ? L("Done") : L("Select")) {
                    filterFocused = false
                    if isSelecting { selectedIDs = [] }
                    isSelecting.toggle()
                }
                .buttonStyle(.bordered)
                .disabled(boneyard.isEmpty && !isSelecting)
                .accessibilityIdentifier("BoneyardSelect")
                Button {
                    filterFocused = false
                    showingNewScene = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSelecting)
                .accessibilityLabel(L("New Scene"))
                .accessibilityIdentifier("BoneyardAdd")
            }
            HStack {
                Menu {
                    Picker(L("Sort"), selection: $sort) {
                        ForEach(BoneyardSort.allCases, id: \.self) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    }
                } label: {
                    Label("\(L("Sort")): \(sort.localizedTitle)", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("BoneyardSort")
                Spacer(minLength: 8)
                Text(countText(displayedCount, eighths: totalEighths))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("Filter"), text: $filter, prompt: Text(L("Number, slugline, cast, summary")))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($filterFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("BoneyardFilter")
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear filter"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    /// "12 scenes · 24 3/8 pgs", or the empty and filtered cases.
    private func countText(_ count: Int, eighths: Int) -> String {
        let scenes = count == 1 ? L("1 scene") : String(format: L("%d scenes"), count)
        guard count > 0 else { return scenes }
        return "\(scenes) · \(FractionParser.formatEighths(eighths)) \(L("pgs"))"
    }

    // MARK: - The list

    private func list(_ displayed: [Scene]) -> some View {
        List(selection: $selectedIDs) {
            if boneyard.isEmpty {
                ContentUnavailableView {
                    Label(L("Boneyard Is Empty"), systemImage: "tray")
                } description: {
                    Text(L("Every scene is on a day. Tap + to add one."))
                }
                .listRowBackground(Color.clear)
            } else if displayed.isEmpty {
                ContentUnavailableView.search(text: filter)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(displayed) { scene in
                        row(scene)
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .listSelecting(isSelecting)
    }

    /// One Boneyard scene as its strip: a tap opens the editor (not while selecting,
    /// when the list's own tap toggles the row), a long press is the menu, the trailing
    /// swipe Send to Day and Delete. A duplicate number wears the Mac's dashed red edge.
    @ViewBuilder
    private func row(_ scene: Scene) -> some View {
        let isDuplicate = derived.duplicateSceneNumberIDs.contains(scene.id)
        let strip = PhoneStripRow(scene: scene, timeText: "")
            .overlay {
                if isDuplicate {
                    Rectangle()
                        .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .accessibilityLabel(L("Duplicate scene number"))
                }
            }
        Group {
            if isSelecting {
                strip
            } else {
                Button {
                    editorRequest = PhoneSceneEditorRequest(sceneID: scene.id)
                } label: {
                    strip
                }
                .buttonStyle(.plain)
            }
        }
        .stripListRow(color: PhoneStripRow.rowColor(for: scene, palette: palette))
        .contextMenu {
            Button {
                editorRequest = PhoneSceneEditorRequest(sceneID: scene.id)
            } label: {
                Label(L("Edit Scene"), systemImage: "pencil")
            }
            Button {
                duplicate(scene)
            } label: {
                Label(L("Duplicate Scene"), systemImage: "plus.square.on.square")
            }
            Button {
                moves.presentSendToDay(sceneIDs: [scene.id])
            } label: {
                Label(L("Send to Day…"), systemImage: "arrow.turn.down.right")
            }
            Divider()
            Button(role: .destructive) {
                delete(scene.id)
            } label: {
                Label(L("Delete Scene"), systemImage: "trash")
            }
        } preview: {
            StripPreview(scene: scene)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(scene.id)
            } label: {
                Label(L("Delete"), systemImage: "trash")
            }
            Button {
                moves.presentSendToDay(sceneIDs: [scene.id])
            } label: {
                Label(L("Send to Day"), systemImage: "arrow.turn.down.right")
            }
            .tint(.blue)
        }
    }

    // MARK: - Selection

    /// The bar under the list while selecting: the count, Select All, and the one Send
    /// to Day that places every selected scene in the list's order.
    private func selectionBar(_ displayed: [Scene]) -> some View {
        let ordered = BoneyardSelection.ordered(selectedIDs, inDisplayOrder: displayed.map(\.id))
        let allSelected = !displayed.isEmpty && ordered.count == displayed.count
        return HStack(spacing: 12) {
            Button(allSelected ? L("Deselect All") : L("Select All")) {
                selectedIDs = allSelected ? [] : Set(displayed.map(\.id))
            }
            .buttonStyle(.borderless)
            .disabled(displayed.isEmpty)
            Spacer()
            Text(ordered.count == 1 ? L("1 selected") : String(format: L("%d selected"), ordered.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                moves.presentSendToDay(sceneIDs: ordered)
            } label: {
                Label(L("Send to Day…"), systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(ordered.isEmpty)
            .accessibilityIdentifier("BoneyardSendToDay")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Drops selected scenes that left the Boneyard (a Send to Day, a delete, an undo);
    /// a selection that emptied that way is over, so Select mode ends with it.
    private func pruneSelection() {
        guard !selectedIDs.isEmpty else { return }
        let present = Set(project.allScenes.map(\.id))
        let pruned  = selectedIDs.intersection(present)
        if pruned != selectedIDs {
            selectedIDs = pruned
            if pruned.isEmpty { isSelecting = false }
        }
    }

    // MARK: - The editor

    /// The scene editor over the displayed rows: Previous and Next step through them.
    private func editor(for id: UUID, in displayed: [Scene]) -> some View {
        let ids      = displayed.map(\.id)
        let position = ids.firstIndex(of: id)
        return PhoneSceneEditor(
            sceneID:       id,
            document:      document,
            edit:          edit,
            moves:         moves,
            dismiss:       { editorRequest = nil },
            canGoPrevious: (position ?? 0) > 0,
            canGoNext:     position.map { $0 < ids.count - 1 } ?? false,
            onPrevious:    { if let position, position > 0 { editorRequest = PhoneSceneEditorRequest(sceneID: ids[position - 1]) } },
            onNext:        { if let position, position < ids.count - 1 { editorRequest = PhoneSceneEditorRequest(sceneID: ids[position + 1]) } },
            positionLabel: position.map { String(format: L("Scene %d of %d"), $0 + 1, ids.count) }
        )
    }

    /// The location roster plus every real location in use, for the new scene's field.
    private var knownLocations: [String] {
        var set = Set<String>()
        for day in project.shootDays {
            for scene in day.scenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        }
        for scene in project.allScenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        for location in project.productionInfo?.locationRoster ?? [] where !location.name.isEmpty { set.insert(location.name) }
        return Array(set).sorted()
    }

    // MARK: - Edits

    private func addScene(_ scene: Scene) {
        edit(L("Add Scene")) { $0.allScenes.append(scene) }
        revealSceneID = scene.id
    }

    private func delete(_ id: UUID) {
        edit(L("Delete Scene")) { $0.removeScene(withID: id) }
    }

    /// Duplicate Scene, the Mac's Boneyard menu item: a copy with a new id, " (Copy)"
    /// on the title and the breakdown carried over; scheduling state (completion,
    /// times) starts fresh. The Mac's copy of this rule is private to `ContentView`.
    private func duplicate(_ scene: Scene) {
        edit(L("Duplicate Scene")) { $0.allScenes.append(Scene(
            title:            scene.title + " (Copy)",
            sceneNumber:      scene.sceneNumber,
            duration:         scene.duration,
            estimatedTime:    scene.estimatedTime,
            dayNightType:     scene.dayNightType,
            cast:             scene.cast,
            summary:          scene.summary,
            realLocation:     scene.realLocation,
            extras:           scene.extras,
            props:            scene.props,
            setDressing:      scene.setDressing,
            wardrobe:         scene.wardrobe,
            makeupHair:       scene.makeupHair,
            vehicles:         scene.vehicles,
            specialEquipment: scene.specialEquipment,
            stunts:           scene.stunts,
            sfx:              scene.sfx,
            vfx:              scene.vfx,
            breakdownNotes:   scene.breakdownNotes
        )) }
    }

    // MARK: - Reveal

    /// Shows `id`: clears the filter that might hide it and scrolls to its row once the
    /// list holds it (the next turn, after an add or a tab switch).
    private func reveal(_ id: UUID?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        revealSceneID = nil
        filter = ""
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

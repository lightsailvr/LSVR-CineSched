// PhoneSceneEditor.swift
// The scene editor as the iPhone's tabs open it (#27: a Boneyard row's tap or Edit
// Scene, a search result's tap): `SceneEditSheet`, the one adaptive scene editor, bound
// to a scene by id wherever it is, so a scene moved, edited or undone under the open
// sheet is still the one shown (the inspector's rule, #17). Save is the editor's one
// assignment through `ProjectData.replaceScene`, so one `edit` and one undo step; Delete
// does what the Mac's sheets do with the same button: a Boneyard scene is deleted, a
// scheduled one goes back to the Boneyard (learnings 2026-09-20, the M3 review), the
// latter through `PhoneMoves.returnToBoneyard` so the day's auto-meals follow in the
// same edit. Previous and Next step through whatever list the tab shows (the Boneyard
// tab's displayed rows), when the tab supplies them.
//
// Presented with `.sheet(item:)` on a `PhoneSceneEditorRequest`, whose id is the scene's,
// so a step to the next scene swaps the item and the editor repopulates from the new id
// (`SceneEditSheet` watches its scene's id). Platform-free; the Mac compiles it and never
// shows it.

import SwiftUI

// MARK: - Request

/// Which scene a tab wants edited; the `.sheet(item:)` item, identified by the scene.
struct PhoneSceneEditorRequest: Identifiable, Hashable {
    let sceneID: UUID
    var id: UUID { sceneID }
}

// MARK: - Editor

struct PhoneSceneEditor: View {
    let sceneID:  UUID
    let document: ProjectDocument
    let edit:     ProjectEdit
    let moves:    PhoneMoves
    /// Closes the sheet (Save, Cancel and Delete alike).
    let dismiss:  () -> Void
    /// The tab's stepping through its list, when offered.
    var canGoPrevious: Bool          = false
    var canGoNext:     Bool          = false
    var onPrevious:    (() -> Void)? = nil
    var onNext:        (() -> Void)? = nil
    var positionLabel: String?       = nil

    private var project: ProjectData { document.project }

    var body: some View {
        if let scene = project.scene(withID: sceneID) {
            SceneEditSheet(
                scene:          sceneBinding(fallback: scene),
                isPresented:    presented,
                onSave:         {},
                onDelete:       deleteScene,
                canGoPrevious:  canGoPrevious,
                canGoNext:      canGoNext,
                onPrevious:     onPrevious,
                onNext:         onNext,
                positionLabel:  positionLabel,
                knownLocations: knownLocations
            )
        } else {
            // The scene left the project under the open sheet (an undo, a sync).
            EditorChrome {
                EditorTitle(title: L("Edit Scene"))
            } content: {
                ContentUnavailableView(
                    L("Scene Not Found"),
                    systemImage: "questionmark.square.dashed",
                    description: Text(L("The scene may have been deleted."))
                )
            } footer: {
                HStack {
                    Spacer()
                    Button(L("Close")) { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .editorContainer(EditorSheetSize(width: 400, height: 320, compactDetents: [.medium]))
        }
    }

    // MARK: - Bindings

    /// The scene wherever it is; the editor's Save is one assignment, so one `edit`.
    private func sceneBinding(fallback: Scene) -> Binding<Scene> {
        Binding(
            get: { project.scene(withID: sceneID) ?? fallback },
            set: { new in edit(L("Edit Scene")) { $0.replaceScene(new) } }
        )
    }

    /// The editor's `isPresented`: it sets this false after Save, Cancel and Delete.
    private var presented: Binding<Bool> {
        Binding(get: { true }, set: { if !$0 { dismiss() } })
    }

    // MARK: - Delete

    private func deleteScene() {
        switch project.locate(sceneID: sceneID) {
        case .boneyard:
            edit(L("Delete Scene")) { $0.removeScene(withID: sceneID) }
        case .scheduled:
            moves.returnToBoneyard([sceneID])
        case nil:
            break
        }
    }

    /// The location roster plus every real location in use, for the editor's
    /// suggestions (what the Stripboard's sheet and the Production tab pass).
    private var knownLocations: [String] {
        var set = Set<String>()
        for day in project.shootDays {
            for scene in day.scenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        }
        for scene in project.allScenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        for location in project.productionInfo?.locationRoster ?? [] where !location.name.isEmpty { set.insert(location.name) }
        return Array(set).sorted()
    }
}

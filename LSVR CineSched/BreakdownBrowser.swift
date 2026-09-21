// BreakdownBrowser.swift
// The Breakdown Browser's pure part (#28): which scenes it pages through and in what
// order, and the by-id write-back its Save and Delete make. The list is the one the Mac's
// browser has always built (`ContentView.populateBreakdownBrowserScenes`): every scene of
// the project, Boneyard first and then the days, once each, sorted by `scriptOrderKey`
// (12, 12A, 12B, 13; scenes without a number after them, by title). Banners count as the
// Mac counts them, so the two browsers show the same list for the same project.
//
// The phone drives `SceneEditSheet` by id rather than by a snapshot of scenes, so the
// browser is rebuilt from the project on every body and a scene edited under it (or
// moved, or undone) is the current one. `replaceScene` and `removeScene(withID:)` are the
// writes: they find the scene wherever it lives (`locate(sceneID:)`), so the caller
// never holds an index across an edit. Pure; tested in `BreakdownBrowserTests`.

import Foundation

// MARK: - The browser

struct BreakdownBrowser: Equatable {
    /// Every scene of the project, once, in script order.
    let sceneIDs: [UUID]

    init(project: ProjectData) {
        var seen     = Set<UUID>()
        var combined: [Scene] = []
        for scene in project.allScenes where seen.insert(scene.id).inserted { combined.append(scene) }
        for day in project.shootDays {
            for scene in day.scenes where seen.insert(scene.id).inserted { combined.append(scene) }
        }
        // `sort` is stable, so scenes with the same key keep their board order.
        combined.sort { $0.scriptOrderKey < $1.scriptOrderKey }
        sceneIDs = combined.map(\.id)
    }

    var isEmpty: Bool  { sceneIDs.isEmpty }
    var count:   Int   { sceneIDs.count }
    /// The scene the browser opens on.
    var first:   UUID? { sceneIDs.first }

    /// The scene's zero-based place in the list; nil when it left the project.
    func position(of id: UUID) -> Int? {
        sceneIDs.firstIndex(of: id)
    }

    /// Previous: the scene before `id` in script order, nil at the start or for a scene
    /// that is not in the list.
    func id(before id: UUID) -> UUID? {
        guard let index = position(of: id), index > 0 else { return nil }
        return sceneIDs[index - 1]
    }

    /// Next: the scene after `id`, nil at the end or for a scene that is not in the list.
    func id(after id: UUID) -> UUID? {
        guard let index = position(of: id), index < sceneIDs.count - 1 else { return nil }
        return sceneIDs[index + 1]
    }

    /// Where the browser lands after `id` is deleted: the next scene, else the previous
    /// (the Mac keeps the index, which shows the next and clamps at the end), nil when
    /// `id` was the last one left.
    func successor(of id: UUID) -> UUID? {
        self.id(after: id) ?? self.id(before: id)
    }
}

// MARK: - Write-back by id

extension ProjectData {
    /// Replaces the scene with `scene.id` wherever it is, in the Boneyard or on a day.
    /// Returns false, and changes nothing, when no scene has that id.
    @discardableResult
    nonisolated mutating func replaceScene(_ scene: Scene) -> Bool {
        switch locate(sceneID: scene.id) {
        case .boneyard(let index):                     allScenes[index] = scene
        case .scheduled(let dayIndex, let sceneIndex): shootDays[dayIndex].scenes[sceneIndex] = scene
        case nil:                                      return false
        }
        return true
    }

    /// Removes the scene with `id` from wherever it is (the Boneyard or a day) outright,
    /// what the breakdown browser's Delete does on the Mac. Returns false when no scene
    /// has that id.
    @discardableResult
    nonisolated mutating func removeScene(withID id: UUID) -> Bool {
        switch locate(sceneID: id) {
        case .boneyard(let index):                     allScenes.remove(at: index)
        case .scheduled(let dayIndex, let sceneIndex): shootDays[dayIndex].scenes.remove(at: sceneIndex)
        case nil:                                      return false
        }
        return true
    }
}

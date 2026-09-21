// EditorSelection.swift
// What the inspector column shows (#17): the one scene or the one shoot day the user last
// tapped, addressed by id so it survives every edit that keeps the target in the project
// (a move between days, a rename, an undo). Pure: resolving a selection against a
// `ProjectData` is a lookup, and a selection whose target is gone prunes itself to nil,
// which is what the editor does on every change count.
//
// Distinct from the multi-selection the drags and grouped actions use (`selectedSceneIDs`
// in the editor): that set says which strips move together; this value says which single
// thing the inspector is editing. On the Mac the inspector does not exist and the value is
// never set; on the iPad every single tap on a strip or a day writes it.
//
// Also here, beside `locate(sceneID:)`: the by-id write-back every editor bound by id
// makes (`replaceScene`, `removeScene(withID:)`, #28) and the location suggestions the
// scene editors share (`knownLocations`), because each is the same lookup over the
// Boneyard and the days.

import Foundation

// MARK: - Selection

nonisolated enum EditorSelection: Hashable {
    /// A script scene, in the Boneyard or on a day.
    case scene(id: UUID)
    /// A shoot day.
    case day(id: UUID)

    /// The same selection if its target is still in `project`, nil otherwise. A selected
    /// scene stays selected while it moves between the Boneyard and the days.
    func pruned(in project: ProjectData) -> EditorSelection? {
        switch self {
        case .scene(let id): return project.locate(sceneID: id) == nil ? nil : self
        case .day(let id):   return project.dayIndex(forDayID: id)  == nil ? nil : self
        }
    }
}

// MARK: - Locating the target

/// Where a scene lives in the project, as the indices the editors' bindings address.
nonisolated enum SceneLocation: Hashable {
    case boneyard(index: Int)
    case scheduled(dayIndex: Int, sceneIndex: Int)
}

extension ProjectData {
    /// The scene's place in `allScenes` or on a day; nil when no scene has that id. The
    /// Boneyard is searched first, matching the invariant that a scene is in exactly one.
    nonisolated func locate(sceneID: UUID) -> SceneLocation? {
        if let index = allScenes.firstIndex(where: { $0.id == sceneID }) {
            return .boneyard(index: index)
        }
        for (dayIndex, day) in shootDays.enumerated() {
            if let sceneIndex = day.scenes.firstIndex(where: { $0.id == sceneID }) {
                return .scheduled(dayIndex: dayIndex, sceneIndex: sceneIndex)
            }
        }
        return nil
    }

    /// The scene with that id, wherever it is; nil when gone.
    nonisolated func scene(withID id: UUID) -> Scene? {
        switch locate(sceneID: id) {
        case .boneyard(let index):                       return allScenes[index]
        case .scheduled(let dayIndex, let sceneIndex):   return shootDays[dayIndex].scenes[sceneIndex]
        case nil:                                        return nil
        }
    }

    /// The day's index in `shootDays`; nil when no day has that id.
    nonisolated func dayIndex(forDayID id: UUID) -> Int? {
        shootDays.firstIndex { $0.id == id }
    }

    // MARK: - Write-back by id

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

    // MARK: - Locations

    /// The location roster plus every real location a scene names, once each, sorted:
    /// what the scene editors' location field suggests (the inspector's and the
    /// Stripboard sheet's rule, which keep their own copies).
    nonisolated var knownLocations: [String] {
        var set = Set<String>()
        for day in shootDays {
            for scene in day.scenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        }
        for scene in allScenes where !scene.realLocation.isEmpty { set.insert(scene.realLocation) }
        for location in productionInfo?.locationRoster ?? [] where !location.name.isEmpty { set.insert(location.name) }
        return Array(set).sorted()
    }
}

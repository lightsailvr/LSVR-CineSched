// SceneSearch.swift
// Finding a scene by what it says (#27): the Boneyard tab's text filter and the Search
// tab's search over the whole project, one pure function each, so the rules are pinned
// in `SceneSearchTests` without a view. A query is trimmed and split on whitespace, and
// every word must appear somewhere in the scene: as its number (exactly or as a prefix,
// so "12" finds 12, 12A and 120 the way a scene list reads), in its slugline, in a cast
// name (the character name join's terms: case-insensitive, trimmed), in its summary or
// in its real location. Only script scenes match: a banner, an auto-meal or a calendar
// event is not something a scheduler looks up by name, and none has a place in the
// Boneyard.
//
// The search returns each hit with where it is (`SceneLocation`, EditorSelection.swift),
// scheduled scenes first in schedule order and then the Boneyard in script order, so the
// Search tab can group them and offer "Show in Days" for a scheduled one. Also here:
// the display order the Boneyard tab hands a multi-selection to Send to Day in
// (`BoneyardSelection.ordered`), because a `Set` has no order and the pure moves honour
// the order of the ids they are given (learnings 2026-09-20, the M3 review).

import Foundation

// MARK: - Search

enum SceneSearch {

    /// Whether `scene` matches `query`: a script scene every word of the query appears
    /// in. A blank query matches every script scene and no notice strip.
    static func matches(_ scene: Scene, query: String) -> Bool {
        matches(scene, terms: terms(of: query))
    }

    /// `scenes` narrowed to those matching `query`, in the order given (the Boneyard
    /// tab's filter over the sorted Boneyard). A blank query keeps every script scene.
    static func filter(_ scenes: [Scene], query: String) -> [Scene] {
        let terms = terms(of: query)
        return scenes.filter { matches($0, terms: terms) }
    }

    /// Every scene in `project` matching `query`, with where each one is: the scheduled
    /// scenes first, day by day in the order they are shot, then the Boneyard's in
    /// script order. A blank query finds nothing.
    static func results(for query: String, in project: ProjectData) -> [SceneSearchResult] {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return [] }
        var results: [SceneSearchResult] = []
        for (dayIndex, day) in project.shootDays.enumerated() {
            for (sceneIndex, scene) in day.scenes.enumerated() where matches(scene, terms: terms) {
                results.append(SceneSearchResult(scene: scene, location: .scheduled(dayIndex: dayIndex, sceneIndex: sceneIndex)))
            }
        }
        let boneyard = project.allScenes.enumerated()
            .filter { matches($0.element, terms: terms) }
            .sorted {
                let a = $0.element.scriptOrderKey
                let b = $1.element.scriptOrderKey
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1 < b.1
            }
        for (index, scene) in boneyard {
            results.append(SceneSearchResult(scene: scene, location: .boneyard(index: index)))
        }
        return results
    }

    // MARK: The rules

    /// The query's words, lowercased; empty for a blank query.
    private static func terms(of query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func matches(_ scene: Scene, terms: [String]) -> Bool {
        guard !scene.isBanner, !scene.isCalendarEvent else { return false }
        guard !terms.isEmpty else { return true }
        let number   = scene.sceneNumber.trimmingCharacters(in: .whitespaces).lowercased()
        let title    = scene.title.lowercased()
        let summary  = scene.summary.lowercased()
        let location = scene.realLocation.lowercased()
        let cast     = scene.cast.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return terms.allSatisfy { term in
            (!number.isEmpty && number.hasPrefix(term))
                || title.contains(term)
                || summary.contains(term)
                || location.contains(term)
                || cast.contains { $0.contains(term) }
        }
    }
}

// MARK: - A result

/// One scene the search found and where it lives, identified by the scene.
nonisolated struct SceneSearchResult: Identifiable, Hashable {
    let scene:    Scene
    let location: SceneLocation

    var id: UUID { scene.id }

    var isInBoneyard: Bool {
        if case .boneyard = location { return true }
        return false
    }

    /// The index of the day the scene is on; nil in the Boneyard.
    var dayIndex: Int? {
        if case .scheduled(let dayIndex, _) = location { return dayIndex }
        return nil
    }
}

// MARK: - The Boneyard's selection

nonisolated enum BoneyardSelection {
    /// `selected` in the order the Boneyard shows them, ids the list does not show
    /// dropped: what a multi-select Send to Day hands the move, since the move lands
    /// the scenes in the order it is given.
    static func ordered(_ selected: Set<UUID>, inDisplayOrder displayed: [UUID]) -> [UUID] {
        displayed.filter { selected.contains($0) }
    }
}

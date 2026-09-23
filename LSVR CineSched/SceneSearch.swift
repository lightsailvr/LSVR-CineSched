// SceneSearch.swift
// Finding a scene by what it says (#27): the Boneyard tab's text filter and the Search
// tab's search over the whole project, one pure function each, so the rules are pinned
// in `SceneSearchTests` without a view. A query is trimmed and split on whitespace, and
// every word must appear somewhere in the scene: as its number (exactly or as a prefix,
// so "12" finds 12, 12A and 120 the way a scene list reads), in its slugline, in a cast
// name (the character name join's terms: case-insensitive, trimmed), in its summary or
// in its real location, or in any of its shots' descriptions, equipment, props or SFX
// (#37: "dolly" finds every scene with a dolly shot). Only script scenes match: a banner, an auto-meal or a calendar
// event is not something a scheduler looks up by name, and none has a place in the
// Boneyard.
//
// The search returns each hit with where it is (`SceneLocation`, EditorSelection.swift),
// scheduled scenes first in schedule order and then the Boneyard in script order, so the
// Search tab can group them and offer "Show in Days" for a scheduled one, and with the
// shot that found it when the match came from the shot list (#43: `matchedShotID` and
// `matchedShotNumber`, the first shot, in shot order, holding a word of the query the
// scene's own fields do not; nil when the scene's own fields hold every word), for the
// row's "in shot 12B" caption. Also here:
// the display order the Boneyard tab hands a multi-selection to Send to Day in
// (`BoneyardSelection.ordered`), because a `Set` has no order and the pure moves honour
// the order of the ids they are given (learnings 2026-09-20, the M3 review), and the
// Mac toolbar's older rule (`toolbarMatches`: the query as one phrase in the title, the
// summary or a cast name, any strip, and since #36's review in a shot's text too), kept
// apart so what the Mac already found is found exactly as before.

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
                results.append(result(scene, at: .scheduled(dayIndex: dayIndex, sceneIndex: sceneIndex), terms: terms))
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
            results.append(result(scene, at: .boneyard(index: index), terms: terms))
        }
        return results
    }

    /// A hit with the shot that found it: the first shot holding a word the scene's own
    /// fields do not; none when they hold every word.
    private static func result(_ scene: Scene, at location: SceneLocation, terms: [String]) -> SceneSearchResult {
        let own       = ownText(scene)
        let shotTerms = terms.filter { !ownFieldsHold($0, own) }
        guard !shotTerms.isEmpty, !scene.shots.isEmpty,
              let index = scene.shots.firstIndex(where: { shot in
                  let text = shotText(shot)
                  return shotTerms.contains { shotTextHolds($0, text) }
              })
        else { return SceneSearchResult(scene: scene, location: location) }
        return SceneSearchResult(scene: scene, location: location,
                                 matchedShotID: scene.shots[index].id,
                                 matchedShotNumber: scene.shotNumber(at: index))
    }

    /// The Mac toolbar's search (ContentView's results popover): the trimmed query,
    /// lowercased, as one phrase contained in the scene's title, summary or a cast name, or
    /// in any shot's description, equipment, props or SFX. Any strip, banners included, as
    /// it always did; the shot text is what #36 adds ("search finds scenes by what their
    /// shots say"). A blank query matches nothing.
    static func toolbarMatches(_ scene: Scene, query: String) -> Bool {
        let phrase = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !phrase.isEmpty else { return false }
        return scene.title.lowercased().contains(phrase)
            || scene.summary.lowercased().contains(phrase)
            || scene.cast.contains { $0.lowercased().contains(phrase) }
            || scene.shots.contains { shotTextHolds(phrase, shotText($0)) }
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
        let own   = ownText(scene)
        let shots = scene.shots.map { shotText($0) }
        return terms.allSatisfy { term in
            ownFieldsHold(term, own) || shots.contains { shotTextHolds(term, $0) }
        }
    }

    /// A scene's own searchable fields, lowercased: its number, slugline, summary, real
    /// location and cast names.
    private struct OwnText {
        let number:   String
        let title:    String
        let summary:  String
        let location: String
        let cast:     [String]
    }

    private static func ownText(_ scene: Scene) -> OwnText {
        OwnText(
            number:   scene.sceneNumber.trimmingCharacters(in: .whitespaces).lowercased(),
            title:    scene.title.lowercased(),
            summary:  scene.summary.lowercased(),
            location: scene.realLocation.lowercased(),
            cast:     scene.cast.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        )
    }

    /// Whether the scene's own fields hold `term`: the number exactly or as a prefix, or
    /// any other field by containment.
    private static func ownFieldsHold(_ term: String, _ own: OwnText) -> Bool {
        (!own.number.isEmpty && own.number.hasPrefix(term))
            || own.title.contains(term)
            || own.summary.contains(term)
            || own.location.contains(term)
            || own.cast.contains { $0.contains(term) }
    }

    /// A shot's searchable fields, lowercased.
    private static func shotText(_ shot: Shot) -> [String] {
        [shot.details.lowercased()]
            + shot.equipment.map { $0.lowercased() }
            + shot.props.map { $0.lowercased() }
            + shot.sfx.map { $0.lowercased() }
    }

    /// Whether a shot's fields (`shotText`) hold `term`, by containment: the one rule the
    /// match and a result's shot share.
    private static func shotTextHolds(_ term: String, _ text: [String]) -> Bool {
        text.contains { $0.contains(term) }
    }
}

// MARK: - A result

/// One scene the search found and where it lives, identified by the scene, with the shot
/// that found it when the match came from the shot list (#43).
nonisolated struct SceneSearchResult: Identifiable, Hashable {
    let scene:    Scene
    let location: SceneLocation
    /// The first shot holding a word of the query the scene's own fields do not; nil when
    /// they hold every word.
    var matchedShotID:     UUID?   = nil
    /// That shot's displayed number ("12B"), for the row's caption.
    var matchedShotNumber: String? = nil

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

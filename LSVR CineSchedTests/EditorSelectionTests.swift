//
//  EditorSelectionTests.swift
//  LSVR CineSchedTests
//
//  The inspector's selection (#17): resolving a selected scene or day against the
//  project, and pruning a selection whose target is gone.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct EditorSelectionTests {

    private let boneyardScene  = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "1")
    private let scheduledScene = Scene(title: "EXT. YARD - DAY",    sceneNumber: "2")
    private let day            = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))

    private var project: ProjectData {
        var day = self.day
        day.scenes = [Scene.createBanner(type: .mealBreak, title: "Lunch"), scheduledScene]
        return ProjectData(allScenes: [boneyardScene], shootDays: [ShootDay(date: Date(timeIntervalSince1970: 1_799_900_000)), day])
    }

    // MARK: - Locating

    @Test func locatesABoneyardSceneByIndex() {
        #expect(project.locate(sceneID: boneyardScene.id) == .boneyard(index: 0))
        #expect(project.scene(withID: boneyardScene.id)?.title == "INT. KITCHEN - DAY")
    }

    @Test func locatesAScheduledSceneByDayAndPosition() {
        #expect(project.locate(sceneID: scheduledScene.id) == .scheduled(dayIndex: 1, sceneIndex: 1))
        #expect(project.scene(withID: scheduledScene.id)?.title == "EXT. YARD - DAY")
    }

    @Test func aMissingSceneLocatesNowhere() {
        #expect(project.locate(sceneID: UUID()) == nil)
        #expect(project.scene(withID: UUID()) == nil)
    }

    @Test func locatesADayByID() {
        #expect(project.dayIndex(forDayID: day.id) == 1)
        #expect(project.dayIndex(forDayID: UUID()) == nil)
    }

    // MARK: - Known locations

    @Test func knownLocationsAreTheRosterAndEveryRealLocationInUseSortedOnce() {
        var project = self.project
        project.allScenes[0].realLocation = "Stage 4"
        project.shootDays[1].scenes[1].realLocation = "Alameda Warehouse"
        project.shootDays[1].scenes.append(Scene(title: "INT. HALL - DAY", sceneNumber: "3", realLocation: "Stage 4"))
        project.productionInfo = ProductionInfo(locationRoster: [Location(name: "City Hall"), Location(name: ""), Location(name: "Stage 4")])
        #expect(project.knownLocations == ["Alameda Warehouse", "City Hall", "Stage 4"])
    }

    @Test func knownLocationsSkipBlanksAndAreEmptyForABareProject() {
        #expect(project.knownLocations.isEmpty)
    }

    // MARK: - Pruning

    @Test func aSelectionWhoseTargetExistsIsKept() {
        #expect(EditorSelection.scene(id: boneyardScene.id).pruned(in: project)  == .scene(id: boneyardScene.id))
        #expect(EditorSelection.scene(id: scheduledScene.id).pruned(in: project) == .scene(id: scheduledScene.id))
        #expect(EditorSelection.day(id: day.id).pruned(in: project)              == .day(id: day.id))
    }

    @Test func aSelectionWhoseTargetIsGonePrunesToNil() {
        #expect(EditorSelection.scene(id: UUID()).pruned(in: project) == nil)
        #expect(EditorSelection.day(id: UUID()).pruned(in: project)   == nil)
    }

    @Test func aSceneStaysSelectedWhenItMovesBetweenBoneyardAndDay() {
        var moved = project
        let scene = moved.allScenes.removeFirst()
        moved.shootDays[0].scenes.append(scene)
        let selection = EditorSelection.scene(id: scene.id)
        #expect(selection.pruned(in: moved) == selection)
        #expect(moved.locate(sceneID: scene.id) == .scheduled(dayIndex: 0, sceneIndex: 0))
    }

    // MARK: - The Mac's copies, pinned (#35)

    /// `ContentView+Inspector.knownLocations` and `StripboardView.allProjectLocations` (the
    /// same lines) as they stood before both moved to `knownLocations`, as an oracle.
    private func macKnownLocations(shootDays: [ShootDay], allScenes: [Scene], productionInfo: ProductionInfo) -> [String] {
        var set = Set<String>()
        for d in shootDays {
            for s in d.scenes where !s.realLocation.isEmpty { set.insert(s.realLocation) }
        }
        for s in allScenes where !s.realLocation.isEmpty { set.insert(s.realLocation) }
        for loc in productionInfo.locationRoster where !loc.name.isEmpty { set.insert(loc.name) }
        return Array(set).sorted()
    }

    @Test func knownLocationsMatchTheMacsCopies() {
        var dressed = self.project
        dressed.allScenes[0].realLocation = "Stage 4"
        dressed.shootDays[1].scenes[1].realLocation = "alameda Warehouse"
        dressed.shootDays[1].scenes.append(Scene(title: "INT. HALL - DAY", sceneNumber: "3", realLocation: "Stage 4"))
        dressed.productionInfo = ProductionInfo(locationRoster: [Location(name: "City Hall"), Location(name: ""), Location(name: "Stage 4")])
        for project in [self.project, dressed] {
            let expected = macKnownLocations(shootDays: project.shootDays, allScenes: project.allScenes,
                                             productionInfo: project.productionInfo ?? ProductionInfo())
            #expect(project.knownLocations == expected)
            #expect(ProjectData.knownLocations(shootDays: project.shootDays, allScenes: project.allScenes,
                                               productionInfo: project.productionInfo) == expected)
        }
    }
}

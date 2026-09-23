//
//  StoryboardFrameTotalsTests.swift
//  LSVR CineSchedTests
//
//  The project's storyboard frame bytes (#41, StoryboardFrameTotals.swift): every scene's
//  own frame and every shot's, across the Boneyard and the days, 0 without frames; the
//  same over the pieces the Stripboard holds; the editor's view of the total with its
//  draft's frames in place of the saved scene's; and the shot page's caption, which says
//  nothing until the total passes 20 MB. The frames are opaque bytes of a known length:
//  the sum reads `Data.count`, never the pixels.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct StoryboardFrameTotalsTests {

    // MARK: - Fixture

    private func bytes(_ count: Int) -> Data { Data(repeating: 0xAB, count: count) }

    /// The Boneyard: a shotless scene with a 100-byte frame, a scene with no frame at all.
    /// Day 1: a scene with two shots (30 and 5 bytes, one shot unframed) and a 7-byte frame
    /// of its own left over, and a banner. Day 2: a shot with a 1,000-byte frame.
    private func project() -> (ProjectData, framed: Scene) {
        var kitchen = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "3")
        kitchen.frame = bytes(100)
        let hallway = Scene(title: "INT. HALLWAY - DAY", sceneNumber: "4")

        var porch = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12")
        porch.frame = bytes(7)
        porch.shots = [Shot(details: "Wide", frame: bytes(30)),
                       Shot(details: "Close"),
                       Shot(details: "Insert", frame: bytes(5))]
        var dayOne = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        dayOne.scenes = [porch, Scene.createBanner(type: .companyMove, title: "Move")]

        var yard = Scene(title: "EXT. YARD - NIGHT", sceneNumber: "20")
        yard.shots = [Shot(details: "Crane", frame: bytes(1_000))]
        var dayTwo = ShootDay(date: Date(timeIntervalSince1970: 1_800_086_400))
        dayTwo.scenes = [yard]

        return (ProjectData(allScenes: [kitchen, hallway], shootDays: [dayOne, dayTwo], projectTitle: "Fixture"), porch)
    }

    // MARK: - The sum

    @Test func aProjectWithoutFramesHasNone() {
        var day = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        var scene = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12")
        scene.shots = [Shot(details: "Wide")]
        day.scenes = [scene]
        let data = ProjectData(allScenes: [Scene(title: "INT. KITCHEN - DAY", sceneNumber: "3")],
                               shootDays: [day], projectTitle: "Fixture")
        #expect(data.storyboardFrameBytes == 0)
        #expect(ProjectData(allScenes: [], shootDays: [], projectTitle: "Empty").storyboardFrameBytes == 0)
    }

    @Test func theSumCountsEverySceneFrameAndEveryShotFrameInTheBoneyardAndTheDays() {
        let (data, _) = project()
        #expect(data.storyboardFrameBytes == 100 + 7 + 30 + 5 + 1_000)
    }

    @Test func aScenesBytesAreItsOwnFramePlusItsShots() {
        let (_, porch) = project()
        #expect(porch.storyboardFrameBytes == 7 + 30 + 5)
        #expect(Scene(title: "INT. HALLWAY - DAY").storyboardFrameBytes == 0)
    }

    @Test func thePiecesGiveTheSameSumAsTheProject() {
        let (data, _) = project()
        #expect(ProjectData.storyboardFrameBytes(shootDays: data.shootDays, allScenes: data.allScenes)
                == data.storyboardFrameBytes)
    }

    // MARK: - The editor's total

    @Test func theEditorsTotalPutsTheDraftsFramesInPlaceOfTheSavedScenes() {
        let (data, porch) = project()
        let total = data.storyboardFrameBytes

        let untouched = SceneDraft(scene: porch)
        #expect(StoryboardFrameTotals.bytes(inProject: total, replacing: porch, with: untouched) == total)

        var added = untouched
        added.frame = bytes(500)
        #expect(StoryboardFrameTotals.bytes(inProject: total, replacing: porch, with: added) == total - 7 + 500)

        var removed = untouched
        removed.frame = nil
        #expect(StoryboardFrameTotals.bytes(inProject: total, replacing: porch, with: removed) == total - 7)
    }

    @Test func theEditorsTotalNeverGoesBelowZero() {
        let (_, porch) = project()
        #expect(StoryboardFrameTotals.bytes(inProject: 0, replacing: porch, with: SceneDraft(scene: Scene(title: "INT. HALLWAY - DAY"))) == 0)
    }

    // MARK: - The caption

    @Test(arguments: [0, 1_000, 19_999_999, 20_000_000])
    func theCaptionSaysNothingUpToTwentyMegabytes(bytes: Int) {
        #expect(StoryboardFrameTotals.caption(forBytes: bytes) == nil)
    }

    @Test func theCaptionNamesTheTotalPastTwentyMegabytes() throws {
        let caption = try #require(StoryboardFrameTotals.caption(forBytes: 24_000_000))
        #expect(caption.hasPrefix("Storyboard frames: "))
        #expect(caption.contains("24"))
        #expect(caption.contains("MB"))
        #expect(StoryboardFrameTotals.caption(forBytes: 20_000_001) != nil)
    }
}

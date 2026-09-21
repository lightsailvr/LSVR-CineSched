//
//  BreakdownBrowserTests.swift
//  LSVR CineSchedTests
//
//  The Breakdown Browser's pure part (#28): the scene ids in script order across the
//  Boneyard and the days, stepping between them, and the by-id write-back and removal
//  the browser's Save and Delete make. The order is the Mac browser's (Boneyard first,
//  then the days, de-duplicated by id, sorted by `scriptOrderKey`), pinned here so the
//  phone and the Mac page through the same list.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct BreakdownBrowserTests {

    private func scene(_ number: String, title: String = "INT. ROOM - DAY") -> Scene {
        Scene(title: title, sceneNumber: number)
    }

    private func day(_ offset: Int, scenes: [Scene]) -> ShootDay {
        ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset) * 86_400), scenes: scenes)
    }

    // MARK: - Order

    @Test func ordersByScriptOrderAcrossBoneyardAndDays() {
        let s13  = scene("13")
        let s12  = scene("12")
        let s12A = scene("12A")
        let s2   = scene("2")
        let s1   = scene("1")
        let project = ProjectData(
            allScenes: [s13, s2],
            shootDays: [day(0, scenes: [s12A, s1]), day(1, scenes: [s12])]
        )
        let browser = BreakdownBrowser(project: project)
        #expect(browser.sceneIDs == [s1.id, s2.id, s12.id, s12A.id, s13.id])
        #expect(browser.count == 5)
        #expect(!browser.isEmpty)
    }

    @Test func letterSuffixesFollowTheirNumber() {
        let s12  = scene("12")
        let s12A = scene("12A")
        let s12B = scene("12B")
        let s13  = scene("13")
        let project = ProjectData(allScenes: [s13, s12B, s12, s12A], shootDays: [])
        #expect(BreakdownBrowser(project: project).sceneIDs == [s12.id, s12A.id, s12B.id, s13.id])
    }

    @Test func scenesWithoutANumberSortLastByTitle() {
        let numbered = scene("3")
        let banner   = Scene.createBanner(type: .mealBreak, title: "Lunch")
        let untitled = scene("", title: "Zeta")
        let alpha    = scene("", title: "Alpha")
        let project  = ProjectData(allScenes: [untitled, alpha], shootDays: [day(0, scenes: [banner, numbered])])
        let ids = BreakdownBrowser(project: project).sceneIDs
        // The number comes first; the rest sort by title (the Mac's key), and the banner is
        // a scene of the project too, as on the Mac.
        #expect(ids.first == numbered.id)
        #expect(ids.contains(banner.id))
        #expect(ids.firstIndex(of: alpha.id)! < ids.firstIndex(of: untitled.id)!)
    }

    @Test func aSceneListedTwiceAppearsOnce() {
        let s = scene("4")
        let project = ProjectData(allScenes: [s], shootDays: [day(0, scenes: [s])])
        #expect(BreakdownBrowser(project: project).sceneIDs == [s.id])
    }

    @Test func anEmptyProjectIsEmpty() {
        let browser = BreakdownBrowser(project: ProjectData(allScenes: [], shootDays: [day(0, scenes: [])]))
        #expect(browser.isEmpty)
        #expect(browser.count == 0)
        #expect(browser.first == nil)
    }

    // MARK: - Stepping

    @Test func stepsForwardAndBackInScriptOrder() {
        let s1 = scene("1"), s2 = scene("2"), s3 = scene("3")
        let browser = BreakdownBrowser(project: ProjectData(allScenes: [s3, s1, s2], shootDays: []))
        #expect(browser.first == s1.id)
        #expect(browser.position(of: s2.id) == 1)
        #expect(browser.id(after: s1.id) == s2.id)
        #expect(browser.id(after: s3.id) == nil)
        #expect(browser.id(before: s3.id) == s2.id)
        #expect(browser.id(before: s1.id) == nil)
        #expect(browser.position(of: UUID()) == nil)
        #expect(browser.id(after: UUID()) == nil)
    }

    @Test func theSuccessorAfterARemovalIsTheNextElseThePrevious() {
        let s1 = scene("1"), s2 = scene("2"), s3 = scene("3")
        let browser = BreakdownBrowser(project: ProjectData(allScenes: [s1, s2, s3], shootDays: []))
        #expect(browser.successor(of: s2.id) == s3.id)
        #expect(browser.successor(of: s3.id) == s2.id)
        #expect(BreakdownBrowser(project: ProjectData(allScenes: [s1], shootDays: [])).successor(of: s1.id) == nil)
    }

    // MARK: - Write-back by id

    @Test func replacingASceneFindsItInTheBoneyardOrOnADay() {
        var boneyard  = scene("1")
        var scheduled = scene("2")
        var project   = ProjectData(allScenes: [boneyard], shootDays: [day(0, scenes: [scheduled])])
        boneyard.props  = ["Lamp"]
        scheduled.props = ["Chair"]
        // A mutating call inside `#expect` is captured immutably; call, then check.
        let replacedBoneyard  = project.replaceScene(boneyard)
        let replacedScheduled = project.replaceScene(scheduled)
        let replacedMissing   = project.replaceScene(scene("9"))
        #expect(replacedBoneyard && replacedScheduled && !replacedMissing)
        #expect(project.allScenes[0].props == ["Lamp"])
        #expect(project.shootDays[0].scenes[0].props == ["Chair"])
    }

    @Test func removingASceneTakesItFromWhereverItIs() {
        let boneyard  = scene("1")
        let scheduled = scene("2")
        var project   = ProjectData(allScenes: [boneyard], shootDays: [day(0, scenes: [scheduled])])
        let removedScheduled = project.removeScene(withID: scheduled.id)
        #expect(removedScheduled)
        #expect(project.shootDays[0].scenes.isEmpty)
        #expect(project.allScenes.count == 1)
        let removedBoneyard = project.removeScene(withID: boneyard.id)
        #expect(removedBoneyard)
        #expect(project.allScenes.isEmpty)
        let removedAgain = project.removeScene(withID: boneyard.id)
        #expect(!removedAgain)
    }
}

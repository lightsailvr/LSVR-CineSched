//
//  ShotEditsTests.swift
//  LSVR CineSchedTests
//
//  A scene's shot list (#37), the pure part (ShotEdits.swift): the letters a shot takes
//  from its position (A…Z, AA, AB, … like spreadsheet columns) and the displayed shot
//  number; every shot edit on `ProjectData`, addressed by scene id and shot id, on a
//  Boneyard scene and on a scheduled one, each refusing a gone scene or shot and changing
//  nothing then; the estimate rule (the sum of the durations written into the scene's
//  estimate after every edit while it has shots, the last sum left behind by removing the
//  last shot, a shotless scene never touched); the frame rule (the scene's own frame moves
//  onto the first shot added); and the three breakdown unions (the scene's items then the
//  shots', first-seen order, trimmed, blanks dropped, case-insensitive duplicates dropped).
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ShotEditsTests {

    // MARK: - Fixture

    /// Tiny opaque "JPEG" bytes: a frame is `Data` to the model and the edits.
    private let frameBytes  = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private let otherFrame  = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])

    private let wide  = Shot(details: "Wide on the porch",       durationMinutes: 20, equipment: ["Dolly"])
    private let close = Shot(details: "Close on Astrid",         durationMinutes: 10, props: ["Lantern"])
    private let insert = Shot(details: "Insert: the truck keys", durationMinutes: 5,  sfx: ["Rain"])

    /// Day 1 holds the porch scene (three shots) and a banner; the Boneyard holds the
    /// kitchen scene (no shots, a frame of its own, an estimate typed by hand).
    private var porch: Scene {
        var scene = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12", duration: 8, estimatedTime: 35)
        scene.shots = [wide, close, insert]
        return scene
    }
    private let kitchen = Scene(title: "INT. KITCHEN - DAY", sceneNumber: "3", duration: 4, estimatedTime: 45)
    private let banner  = Scene.createBanner(type: .companyMove, title: "Move to the yard")

    private func project() -> (ProjectData, porchID: UUID, kitchenID: UUID) {
        var kitchen = self.kitchen
        kitchen.frame = frameBytes
        let porch = self.porch
        var day = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day.scenes = [porch, banner]
        return (ProjectData(allScenes: [kitchen], shootDays: [day], projectTitle: "Fixture"), porch.id, kitchen.id)
    }

    private func shots(_ data: ProjectData, _ sceneID: UUID) -> [Shot] {
        data.scene(withID: sceneID)?.shots ?? []
    }

    // MARK: - Letters and numbers

    @Test(arguments: [(0, "A"), (1, "B"), (25, "Z"), (26, "AA"), (27, "AB"), (51, "AZ"), (52, "BA"), (701, "ZZ"), (702, "AAA")])
    func aShotsLetterComesFromItsPosition(index: Int, letter: String) {
        #expect(Shot.letter(forIndex: index) == letter)
    }

    @Test func aNegativePositionHasNoLetter() {
        #expect(Shot.letter(forIndex: -1) == "")
    }

    @Test func theShotNumberIsTheSceneNumberThenTheLetterWithNoSeparator() {
        var scene = Scene(title: "EXT. PORCH - DUSK", sceneNumber: "12")
        scene.shots = [wide, close]
        #expect(scene.shotNumber(at: 0) == "12A")
        #expect(scene.shotNumber(at: 1) == "12B")
        #expect(scene.shotNumber(forShotID: close.id) == "12B")
        #expect(scene.shotNumber(forShotID: UUID()) == nil)

        scene.sceneNumber = " 12A "
        #expect(scene.shotNumber(at: 0) == "12AA")
        #expect(scene.shotNumber(at: 27) == "12AAB")
    }

    @Test func aSceneNumberOnlyInTheTitleStillNumbersItsShots() {
        let legacy = Scene(title: "7B. INT. BARN - NIGHT")
        #expect(legacy.shotNumber(at: 2) == "7BC")
        let unnumbered = Scene(title: "INT. BARN - NIGHT")
        #expect(unnumbered.shotNumber(at: 0) == "A")
    }

    @Test func aNewShotLastsFifteenMinutesAndHasNothingElse() {
        let shot = Shot()
        #expect(shot.durationMinutes == 15)
        #expect(Shot.defaultDurationMinutes == 15)
        #expect(shot.details.isEmpty && shot.equipment.isEmpty && shot.props.isEmpty && shot.sfx.isEmpty)
        #expect(shot.frame == nil)
    }

    // MARK: - Add

    @Test func addAppendsAndWritesTheSum() {
        var (data, porchID, _) = project()
        let extra = Shot(details: "Pickup", durationMinutes: 7)
        let step1 = data.addShot(extra, toSceneID: porchID, after: nil)
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [wide.id, close.id, insert.id, extra.id])
        #expect(data.scene(withID: porchID)?.estimatedTime == 42)
    }

    @Test func addAfterAShotInsertsRightAfterIt() {
        var (data, porchID, _) = project()
        let extra = Shot(details: "Pickup", durationMinutes: 7)
        let step1 = data.addShot(extra, toSceneID: porchID, after: wide.id)
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [wide.id, extra.id, close.id, insert.id])
        #expect(data.scene(withID: porchID)?.estimatedTime == 42)
    }

    @Test func addRefusesAGoneSceneAGoneAnchorANoticeStripAndADuplicateID() {
        let (before, porchID, _) = project()
        var data = before
        let step1 = data.addShot(Shot(), toSceneID: UUID(), after: nil)
        #expect(!step1)
        let step2 = data.addShot(Shot(), toSceneID: porchID, after: UUID())
        #expect(!step2)
        let step3 = data.addShot(Shot(), toSceneID: banner.id, after: nil)
        #expect(!step3)
        let step4 = data.addShot(close, toSceneID: porchID, after: nil)
        #expect(!step4)
        #expect(data == before)
    }

    @Test func theFirstShotTakesTheScenesFrameAndTheSceneKeepsNone() throws {
        var (data, _, kitchenID) = project()
        let first = Shot(details: "Wide", durationMinutes: 30)
        let step1 = data.addShot(first, toSceneID: kitchenID, after: nil)
        #expect(step1)
        let scene = try #require(data.scene(withID: kitchenID))
        #expect(scene.frame == nil)
        #expect(scene.shots.first?.frame == frameBytes)
        // The first shot also starts the estimate rule: 45 typed by hand becomes 30.
        #expect(scene.estimatedTime == 30)

        // A second shot moves nothing.
        let step2 = data.addShot(Shot(details: "Close"), toSceneID: kitchenID, after: nil)
        #expect(step2)
        let again = try #require(data.scene(withID: kitchenID))
        #expect(again.shots.map(\.frame) == [frameBytes, nil])
        #expect(again.frame == nil)
        #expect(again.estimatedTime == 45)
    }

    @Test func aFirstShotWithAFrameOfItsOwnKeepsItAndTheSceneFrameIsCleared() throws {
        var (data, _, kitchenID) = project()
        let step1 = data.addShot(Shot(frame: otherFrame), toSceneID: kitchenID, after: nil)
        #expect(step1)
        let scene = try #require(data.scene(withID: kitchenID))
        #expect(scene.shots.first?.frame == otherFrame)
        #expect(scene.frame == nil)
    }

    // MARK: - Update

    @Test func updateReplacesTheShotInPlaceAndWritesTheSum() {
        var (data, porchID, _) = project()
        var edited = close
        edited.details = "Close on Astrid, rack to Sam"
        edited.durationMinutes = 25
        let step1 = data.updateShot(edited, inSceneID: porchID)
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [wide.id, close.id, insert.id])
        #expect(shots(data, porchID)[1].details == "Close on Astrid, rack to Sam")
        #expect(data.scene(withID: porchID)?.estimatedTime == 50)
    }

    @Test func updateRefusesAGoneSceneOrShot() {
        let (before, porchID, kitchenID) = project()
        var data = before
        let step1 = data.updateShot(close, inSceneID: UUID())
        #expect(!step1)
        let step2 = data.updateShot(Shot(details: "Stranger"), inSceneID: porchID)
        #expect(!step2)
        let step3 = data.updateShot(close, inSceneID: kitchenID)
        #expect(!step3)
        #expect(data == before)
    }

    // MARK: - Remove

    @Test func removeTakesTheShotOutAndWritesTheSum() {
        var (data, porchID, _) = project()
        let step1 = data.removeShot(withID: wide.id, fromSceneID: porchID)
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [close.id, insert.id])
        #expect(data.scene(withID: porchID)?.estimatedTime == 15)
    }

    @Test func removingTheLastShotLeavesTheLastSum() {
        var (data, porchID, _) = project()
        let step1 = data.removeShot(withID: wide.id,   fromSceneID: porchID)
        #expect(step1)
        let step2 = data.removeShot(withID: insert.id, fromSceneID: porchID)
        #expect(step2)
        #expect(data.scene(withID: porchID)?.estimatedTime == 10)
        let step3 = data.removeShot(withID: close.id,  fromSceneID: porchID)
        #expect(step3)
        #expect(shots(data, porchID).isEmpty)
        #expect(data.scene(withID: porchID)?.estimatedTime == 10)
    }

    @Test func removeRefusesAGoneSceneOrShot() {
        let (before, porchID, _) = project()
        var data = before
        let step1 = data.removeShot(withID: wide.id, fromSceneID: UUID())
        #expect(!step1)
        let step2 = data.removeShot(withID: UUID(), fromSceneID: porchID)
        #expect(!step2)
        #expect(data == before)
    }

    // MARK: - Reorder by offsets (onMove)

    @Test func moveByOffsetsFollowsOnMove() {
        var (data, porchID, _) = project()
        // Drag the insert (index 2) to the top.
        let step1 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [insert.id, wide.id, close.id])
        // Drag the (new) first shot to the end: onMove reports the count as the offset.
        let step2 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(step2)
        #expect(shots(data, porchID).map(\.id) == [wide.id, close.id, insert.id])
        // Two at once, keeping their order.
        let step3 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet([0, 2]), toOffset: 2)
        #expect(step3)
        #expect(shots(data, porchID).map(\.id) == [close.id, wide.id, insert.id])
        #expect(data.scene(withID: porchID)?.estimatedTime == 35)
    }

    @Test func moveByOffsetsRefusesNoChangeBadOffsetsAndAGoneScene() {
        let (before, porchID, _) = project()
        var data = before
        let step1 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(!step1)
        let step2 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(!step2)
        let step3 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 9), toOffset: 0)
        #expect(!step3)
        let step4 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(integer: 0), toOffset: 9)
        #expect(!step4)
        let step5 = data.moveShots(inSceneID: porchID, fromOffsets: IndexSet(), toOffset: 0)
        #expect(!step5)
        let step6 = data.moveShots(inSceneID: UUID(), fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(!step6)
        #expect(data == before)
    }

    // MARK: - Reorder by drop position

    @Test func moveToADropPositionLandsBeforeTheShotOrAtTheEnd() {
        var (data, porchID, _) = project()
        let step1 = data.moveShot(withID: insert.id, inSceneID: porchID, to: .before(wide.id))
        #expect(step1)
        #expect(shots(data, porchID).map(\.id) == [insert.id, wide.id, close.id])
        let step2 = data.moveShot(withID: insert.id, inSceneID: porchID, to: .end)
        #expect(step2)
        #expect(shots(data, porchID).map(\.id) == [wide.id, close.id, insert.id])
        let step3 = data.moveShot(withID: wide.id, inSceneID: porchID, to: .before(insert.id))
        #expect(step3)
        #expect(shots(data, porchID).map(\.id) == [close.id, wide.id, insert.id])
        #expect(data.scene(withID: porchID)?.estimatedTime == 35)
    }

    @Test func moveToADropPositionRefusesNoChangeAndGoneTargets() {
        let (before, porchID, _) = project()
        var data = before
        // Onto itself, or before the shot it already precedes, or to the end it is at.
        let step1 = data.moveShot(withID: close.id,  inSceneID: porchID, to: .before(close.id))
        #expect(!step1)
        let step2 = data.moveShot(withID: close.id,  inSceneID: porchID, to: .before(insert.id))
        #expect(!step2)
        let step3 = data.moveShot(withID: insert.id, inSceneID: porchID, to: .end)
        #expect(!step3)
        let step4 = data.moveShot(withID: UUID(),    inSceneID: porchID, to: .end)
        #expect(!step4)
        let step5 = data.moveShot(withID: wide.id,   inSceneID: porchID, to: .before(UUID()))
        #expect(!step5)
        let step6 = data.moveShot(withID: wide.id,   inSceneID: UUID(),  to: .end)
        #expect(!step6)
        #expect(data == before)
    }

    // MARK: - Duplicate

    @Test func duplicateInsertsACopyRightAfterItsSourceWithAFreshID() throws {
        var (data, porchID, _) = project()
        var framed = wide
        framed.frame = frameBytes
        let step1 = data.updateShot(framed, inSceneID: porchID)
        #expect(step1)

        let minted = data.duplicateShot(withID: wide.id, inSceneID: porchID)
        let copyID = try #require(minted)
        #expect(copyID != wide.id)
        let list = shots(data, porchID)
        #expect(list.map(\.id) == [wide.id, copyID, close.id, insert.id])
        let copy = list[1]
        #expect(copy.details == wide.details)
        #expect(copy.durationMinutes == wide.durationMinutes)
        #expect(copy.equipment == wide.equipment && copy.props == wide.props && copy.sfx == wide.sfx)
        #expect(copy.frame == frameBytes)
        #expect(data.scene(withID: porchID)?.estimatedTime == 55)
    }

    @Test func duplicateRefusesAGoneSceneOrShot() {
        let (before, porchID, _) = project()
        var data = before
        let first = data.duplicateShot(withID: UUID(), inSceneID: porchID)
        #expect(first == nil)
        let second = data.duplicateShot(withID: wide.id, inSceneID: UUID())
        #expect(second == nil)
        #expect(data == before)
    }

    // MARK: - The estimate rule

    @Test func theRuleNeverTouchesAShotlessScene() {
        var scene = kitchen
        scene.applyShotEstimate()
        #expect(scene.estimatedTime == 45)
        #expect(scene.shotEstimate == nil)

        var (data, _, kitchenID) = project()
        let step1 = data.removeShot(withID: UUID(), fromSceneID: kitchenID)
        #expect(!step1)
        #expect(data.scene(withID: kitchenID)?.estimatedTime == 45)
    }

    @Test func theSumIsWhatTheRuleWrites() {
        var scene = porch
        scene.estimatedTime = 999
        #expect(scene.shotEstimate == 35)
        scene.applyShotEstimate()
        #expect(scene.estimatedTime == 35)
    }

    @Test func theEditsWorkTheSameOnASceneValue() throws {
        // #39's scene draft holds a `Scene`, not a project: the same rules run there.
        var scene = kitchen
        scene.frame = frameBytes
        let step1 = scene.addShot(Shot(details: "Wide", durationMinutes: 12))
        #expect(step1)
        #expect(scene.frame == nil && scene.shots.first?.frame == frameBytes)
        let mintedCopyID = scene.duplicateShot(withID: scene.shots[0].id)
        let copyID = try #require(mintedCopyID)
        #expect(scene.shots.map(\.id).last == copyID)
        #expect(scene.estimatedTime == 24)
        let step2 = scene.moveShot(withID: copyID, to: .before(scene.shots[0].id))
        #expect(step2)
        #expect(scene.shots.first?.id == copyID)
        let step3 = scene.removeShot(withID: copyID)
        #expect(step3)
        #expect(scene.estimatedTime == 12)
    }

    // MARK: - The breakdown unions

    @Test func theUnionsAreTheScenesItemsThenEachShotsInFirstSeenOrder() {
        var scene = Scene(
            title: "EXT. PORCH - DUSK", sceneNumber: "12",
            props: ["Lantern", " Truck keys ", ""],
            specialEquipment: ["Rain rig"],
            sfx: []
        )
        scene.shots = [
            Shot(details: "Wide",  equipment: ["Dolly", "rain RIG"],   props: ["lantern", "Shotgun"], sfx: ["Rain", "  "]),
            Shot(details: "Close", equipment: ["Ronin", "Dolly"],      props: ["Mug"],                sfx: ["Thunder", "rain"]),
        ]
        #expect(scene.allProps            == ["Lantern", "Truck keys", "Shotgun", "Mug"])
        #expect(scene.allSpecialEquipment == ["Rain rig", "Dolly", "Ronin"])
        #expect(scene.allSFX              == ["Rain", "Thunder"])
    }

    @Test func aShotlessSceneUnionIsItsOwnListCleaned() {
        let scene = Scene(title: "INT. KITCHEN - DAY", props: ["Knife", "knife", " Toast "])
        #expect(scene.allProps == ["Knife", "Toast"])
        #expect(scene.allSpecialEquipment.isEmpty)
        #expect(scene.allSFX.isEmpty)
    }

    // MARK: - Fresh shot ids

    @Test func freshShotIDsKeepEverythingElse() {
        var scene = porch
        scene.frame = nil
        let original = scene
        scene.refreshShotIDs()
        #expect(scene.shots.count == 3)
        #expect(Set(scene.shots.map(\.id)).isDisjoint(with: original.shots.map(\.id)))
        #expect(scene.shots.map(\.details) == original.shots.map(\.details))
        #expect(scene.estimatedTime == original.estimatedTime)
    }
}

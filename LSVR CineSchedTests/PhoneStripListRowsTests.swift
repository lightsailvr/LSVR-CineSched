//
//  PhoneStripListRowsTests.swift
//  LSVR CineSchedTests
//
//  A day's strips as the iPhone's two lists show them (#43): a strip per scene, an
//  expanded script scene followed by one row per shot (numbered after the scene) or, with
//  none yet, one "no shots" row; banners never expand. And the list's `onMove` offsets,
//  which count those extra rows, mapped back onto the strips alone, so a reorder moves
//  strips and never a shot.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct PhoneStripListRowsTests {

    // MARK: - Fixture

    private let wide   = Shot(details: "Wide")
    private let dolly  = Shot(details: "Dolly in", equipment: ["Dolly"])
    private let insert = Shot(details: "Insert")

    private var twelve: Scene {
        var scene = Scene(title: "INT. KITCHEN - NIGHT", sceneNumber: "12")
        scene.shots = [wide, dolly]
        return scene
    }
    private var thirteen: Scene {
        var scene = Scene(title: "EXT. YARD - DAY", sceneNumber: "13A")
        scene.shots = [insert]
        return scene
    }
    private let shotless = Scene(title: "INT. GARAGE - NIGHT", sceneNumber: "14")
    private let banner   = Scene.createBanner(type: .notice, title: "Company move", note: "", estimatedTime: "0:30", colorHex: "")

    /// The strips once, so every id stays the same across the assertions.
    private func strips() -> [Scene] { [twelve, banner, thirteen, shotless] }

    private func ids(_ rows: [PhoneStripListRow]) -> [PhoneStripListRow.ID] { rows.map(\.id) }

    // MARK: - Rows

    @Test func collapsedStripsAreOneRowEach() {
        let strips = strips()
        let rows   = PhoneStripListRows.rows(for: strips, expansion: ShotExpansion())
        #expect(ids(rows) == strips.map { .strip($0.id) })
        #expect(rows.allSatisfy { $0.isStrip })
    }

    @Test func anExpandedSceneIsFollowedByItsShotsNumberedAfterIt() {
        let strips = strips()
        var expansion = ShotExpansion()
        expansion.toggle(strips[0].id)
        let rows = PhoneStripListRows.rows(for: strips, expansion: expansion)
        #expect(ids(rows) == [.strip(strips[0].id), .shot(wide.id), .shot(dolly.id),
                              .strip(strips[1].id), .strip(strips[2].id), .strip(strips[3].id)])
        #expect(rows[1].shotNumber == "12A")
        #expect(rows[2].shotNumber == "12B")
        #expect(rows[2].shot?.details == "Dolly in")
        #expect(rows[1].scene.id == strips[0].id)
        #expect(!rows[1].isStrip)
    }

    @Test func showShotsExpandsEveryScriptSceneAndNeverABanner() {
        let strips = strips()
        let rows   = PhoneStripListRows.rows(for: strips, expansion: ShotExpansion(showAll: true))
        #expect(ids(rows) == [.strip(strips[0].id), .shot(wide.id), .shot(dolly.id),
                              .strip(strips[1].id),
                              .strip(strips[2].id), .shot(insert.id),
                              .strip(strips[3].id), .noShots(strips[3].id)])
        #expect(rows[5].shotNumber == "13AA")
        // Even a banner the expansion names (a stray exception) shows no shot rows.
        var stray = ShotExpansion()
        stray.toggle(strips[1].id)
        #expect(ids(PhoneStripListRows.rows(for: strips, expansion: stray)) == strips.map { .strip($0.id) })
    }

    @Test func onlyScriptScenesShowShots() {
        #expect(PhoneStripListRows.showsShots(twelve))
        #expect(PhoneStripListRows.showsShots(shotless))
        #expect(!PhoneStripListRows.showsShots(banner))
        #expect(!PhoneStripListRows.showsShots(Scene.createAutoMeal(kind: .lunch, timeString: "1:00 PM")))
        #expect(!PhoneStripListRows.showsShots(Scene.createCalendarEvent(title: "Scout", time: "9:00 AM")))
    }

    // MARK: - Moves

    /// Rows: 0 strip 12, 1 shot 12A, 2 shot 12B, 3 banner, 4 strip 13A, 5 shot 13AA,
    /// 6 strip 14, 7 no shots 14. Strips: 0 12, 1 banner, 2 13A, 3 14.
    private func expandedRows() -> [PhoneStripListRow] {
        PhoneStripListRows.rows(for: strips(), expansion: ShotExpansion(showAll: true))
    }

    @Test func aStripMovedPastExpandedShotsLandsAmongTheStrips() {
        let rows = expandedRows()
        // Strip 12 dragged to the end of the list.
        let toEnd = PhoneStripListRows.stripMove(fromOffsets: [0], toOffset: rows.count, in: rows)
        #expect(toEnd?.source == IndexSet([0]))
        #expect(toEnd?.destination == 4)
        // Strip 14 dragged above the banner: in between 12's shots and the banner.
        let up = PhoneStripListRows.stripMove(fromOffsets: [6], toOffset: 3, in: rows)
        #expect(up?.source == IndexSet([3]))
        #expect(up?.destination == 1)
        // Dropped between a strip and its own shots: after that strip.
        let betweenStripAndShots = PhoneStripListRows.stripMove(fromOffsets: [6], toOffset: 5, in: rows)
        #expect(betweenStripAndShots?.destination == 3)
        // To the top.
        #expect(PhoneStripListRows.stripMove(fromOffsets: [4], toOffset: 0, in: rows)?.destination == 0)
    }

    @Test func aMoveThatCarriesNoStripIsNothing() {
        let rows = expandedRows()
        #expect(PhoneStripListRows.stripMove(fromOffsets: [1], toOffset: 7, in: rows) == nil)
        #expect(PhoneStripListRows.stripMove(fromOffsets: [7], toOffset: 0, in: rows) == nil)
        #expect(PhoneStripListRows.stripMove(fromOffsets: [], toOffset: 0, in: rows) == nil)
        #expect(PhoneStripListRows.stripMove(fromOffsets: [99], toOffset: 0, in: rows) == nil)
    }

    @Test func mappedOffsetsReorderTheStripsAndNeverAShot() {
        // The whole path: the mapped offsets through the pure reorder the phone runs.
        let strips = strips()
        var day = ShootDay(date: Date(timeIntervalSince1970: 1_800_000_000))
        day.scenes = strips
        let rows = PhoneStripListRows.rows(for: strips, expansion: ShotExpansion(showAll: true))
        let move = PhoneStripListRows.stripMove(fromOffsets: [0], toOffset: rows.count, in: rows)
        #expect(move != nil)
        guard let move else { return }
        var days = [day]
        let moved = ScheduleMoves.reorderStrips(strips.map(\.id), fromOffsets: move.source, toOffset: move.destination,
                                                in: day.id, days: &days)
        #expect(moved)
        #expect(days[0].scenes.map(\.id) == [strips[1].id, strips[2].id, strips[3].id, strips[0].id])
        // The shots travel inside their scene, in their order.
        #expect(days[0].scenes[3].shots.map(\.id) == [wide.id, dolly.id])
    }

    @Test func collapsedRowsMapOneForOne() {
        let strips = strips()
        let rows   = PhoneStripListRows.rows(for: strips, expansion: ShotExpansion())
        let move   = PhoneStripListRows.stripMove(fromOffsets: [1, 2], toOffset: 4, in: rows)
        #expect(move?.source == IndexSet([1, 2]))
        #expect(move?.destination == 4)
    }
}

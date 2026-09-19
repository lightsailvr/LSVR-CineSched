//
//  BreakdownPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  Renders the breakdown sheets (one page per scene, script order, Boneyard scenes
//  included) from the fixture project and reads them back through PDFKit.
//  BreakdownExporter draws on PDFCanvas, so this suite runs on the Mac and on the iOS
//  and visionOS simulators (#6). Set CINESCHED_PDF_DUMP_DIR to keep the PDFs for a
//  visual comparison (see PDFTestSupport).
//

import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct BreakdownPDFExporterTests {

    private func render(days: [ShootDay], boneyard: [Scene], dumpAs name: String) -> PDFDocument {
        pdfDocument(
            from: BreakdownExporter.generatePDF(shootDays: days, allScenes: boneyard, projectTitle: PDFFixture.title),
            dumpAs: name
        )
    }

    /// A Boneyard scene with every breakdown department filled in, a long summary (over
    /// the 160-character mark that widens the description row) and a title that carries
    /// its own scene number.
    private var taggedScene: Scene {
        var scene = Scene(
            title: "7A. INT./EXT. RANCH HOUSE PORCH - DUSK",
            sceneNumber: "7A",
            duration: 13,
            estimatedTime: 95,
            dayNightType: .dusk,
            cast: ["Alex Morgan", "Sam Rivera", "Jordan Lee", "Casey Kim", "Riley Chen", "Dana Whitfield", "Morgan Vale"]
        )
        scene.summary = "Alex and Sam wait out the storm on the porch while Jordan argues with the ranch hands about the truck; "
            + "the power goes out halfway through and the scene finishes by lantern light with the dog barking off screen."
        scene.extras           = ["3 ranch hands", "Storm chaser"]
        scene.wardrobe         = ["Rain slickers, muddy boots"]
        scene.makeupHair       = ["Wet-down for all cast"]
        scene.props            = ["Lantern", "Truck keys", "Shotgun (rubber)"]
        scene.setDressing      = ["Porch swing", "Feed sacks"]
        scene.vehicles         = ["1978 pickup truck"]
        scene.specialEquipment = ["Rain rig", "Lightning strobe"]
        scene.stunts           = ["Fall from porch rail"]
        scene.sfx              = ["Practical rain", "Power-out flicker"]
        scene.vfx              = ["Lightning enhancement"]
        scene.breakdownNotes   = "Dog wrangler on set from call. Cover set: barn interior."
        return scene
    }

    @Test func breakdownPrintsOneSheetPerSceneInScriptOrder() {
        let boneyard = [taggedScene]
        let doc = render(days: PDFFixture.days, boneyard: boneyard, dumpAs: "Breakdown.pdf")

        // Every script scene on the five shoot days (banners, events and the untitled
        // company-move line have no scene number but are still scenes to the exporter),
        // plus the one Boneyard scene: one page each.
        let sceneCount = PDFFixture.days.flatMap(\.scenes).count + boneyard.count
        #expect(doc.pageCount == sceneCount)

        // Script order puts 7A ahead of the fixture's 101…506.
        let first = doc.page(at: 0)?.string ?? ""
        #expect(first.contains("BREAKDOWN SHEET"))
        // The sheet-number label is "SHEET #" (the masthead carries the full name): the
        // old "BREAKDOWN SHEET #" was a point too wide for its column on the Mac, so its
        // "#" wrapped onto a line the label box clipped (#33). Label, then the number,
        // then a break: the number is the whole cell ("1", not "10"). What the break is
        // depends on the platform's PDFKit, not on the drawing: the Mac's extraction ends
        // the cell with a newline, the iOS and visionOS one runs it into the title cell
        // on the same baseline with a space ("1 The Long Way Home").
        #expect(first.contains(#/SHEET #\n1\s/#))
        #expect(!first.contains("SHEET\n#"))
        #expect(first.contains(PDFFixture.title))
        #expect(first.contains("SCENE #\n7A"))
        #expect(first.contains("INT./EXT"))
        #expect(first.contains("RANCH HOUSE PORCH - DUSK"))
        #expect(first.contains("DUSK"))
        #expect(first.contains("1 5/8"))
        #expect(first.contains("lantern light with the dog barking off screen."))
        // Every department, bulleted
        for label in ["CAST", "EXTRAS / BACKGROUND", "WARDROBE", "HAIR & MAKEUP", "PROPS", "SET DRESSING",
                      "VEHICLES", "SPECIAL EQUIPMENT", "STUNTS", "SFX", "VFX", "NOTES"] {
            #expect(first.contains(label), "\(label)")
        }
        #expect(first.contains("• Alex Morgan"))
        #expect(first.contains("• Morgan Vale"))
        #expect(first.contains("• 3 ranch hands"))
        #expect(first.contains("• Storm chaser"))
        #expect(first.contains("• Shotgun (rubber)"))
        #expect(first.contains("• Lightning enhancement"))
        #expect(first.contains("Cover set: barn interior."))
        #expect(first.contains("Est. Time: 1 hr 35 min"))
        #expect(first.contains("Scene 1 of \(sceneCount)"))

        // The second sheet is the first shoot day's first scene. Its number lives only in
        // `sceneNumber` (the fixture's titles carry no prefix); the SCENE # cell used to
        // read the title alone and print "—" for it (#33).
        let second = doc.page(at: 1)?.string ?? ""
        #expect(second.contains("BACKLOT SET 101"))
        #expect(second.contains("SCENE #\n101"))
        #expect(!second.contains("—"))
        #expect(second.contains("• Riley Chen"))
        #expect(second.contains("Scene 2 of \(sceneCount)"))
        // The unnumbered lines (events, the company move) sort last, in no particular
        // order, and are the only sheets whose SCENE # is a dash.
        let last = doc.page(at: sceneCount - 1)?.string ?? ""
        #expect(last.contains("SCENE #\n—"))
        #expect(last.contains("Scene \(sceneCount) of \(sceneCount)"))
    }

    /// SCENE # comes from `sceneNumber` first (where imports and the editor keep it) and
    /// from a numbered title only when the field is empty (projects saved before the
    /// field existed); a line with neither prints a dash. The pre-#33 exporter read only
    /// the title.
    @Test func breakdownPrintsTheSceneNumberFromTheFieldOrTheTitle() {
        let fieldOnly = Scene(title: "EXT. WOODS - DAY", sceneNumber: "42")
        let titleOnly = Scene(title: "12A. EXT. WOODS - DAY")
        let neither   = Scene.createCalendarEvent(title: "Producer visit", time: "3:00 PM")
        let doc = render(days: [], boneyard: [fieldOnly, titleOnly, neither], dumpAs: "Breakdown-Numbers.pdf")
        #expect(doc.pageCount == 3)

        // Script order: 12A, then 42, then the unnumbered event.
        let pages = (0..<3).map { doc.page(at: $0)?.string ?? "" }
        #expect(pages[0].contains("SCENE #\n12A"))
        #expect(pages[0].contains("SETTING\nWOODS - DAY"))
        #expect(pages[1].contains("SCENE #\n42"))
        #expect(pages[1].contains("SETTING\nWOODS - DAY"))
        #expect(pages[2].contains("SCENE #\n—"))
    }

    @Test func breakdownCountsASceneOnceAndReturnsNilWithNoScenes() {
        // A scene in the Boneyard and on a day at the same time (the invariant nothing
        // enforces) still gets one sheet.
        let scene = PDFFixture.makeScene(3)
        let day = ShootDay(date: PDFFixture.novemberDate(day: 2), scenes: [scene])
        let doc = render(days: [day], boneyard: [scene], dumpAs: "Breakdown-Single.pdf")
        #expect(doc.pageCount == 1)
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("Scene 1 of 1"))

        #expect(BreakdownExporter.generatePDF(shootDays: [], allScenes: [], projectTitle: "") == nil)
    }

    /// Long department lists shrink towards the 7pt floor to fit their cell, and what
    /// still does not fit is cut at the cell's bottom edge rather than spilling over:
    /// the sheet stays a single page.
    @Test func breakdownShrinksLongListsToFitTheirCells() {
        var scene = taggedScene
        scene.cast = (1...30).map { "Performer number \($0)" }
        scene.props = (1...24).map { "Prop item \($0) with a longer description" }
        let doc = render(days: [], boneyard: [scene], dumpAs: "Breakdown-Dense.pdf")
        #expect(doc.pageCount == 1)
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("• Performer number 5"))
        #expect(!text.contains("• Performer number 30"))
        #expect(text.contains("• Prop item 5 with a longer description"))
        #expect(!text.contains("• Prop item 24 with a longer description"))
        #expect(text.contains("• Lightning enhancement"))
    }
}

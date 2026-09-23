//
//  ShotListPDFExporterTests.swift
//  LSVR CineSchedTests
//
//  The Shot List (#40), rendered from the shared fixture with shots
//  (`PDFFixture.projectWithShots`: scene 101 with four framed shots and 102 with two
//  unframed ones on the first shoot day, a shotless Boneyard scene with its own frame) and
//  read back through PDFKit: the page rhythm with frames on (three entries a page) and off
//  (a table), the shot numbers in order, a shotless scene under its bare number, the
//  Boneyard only in the project scope, and the frames themselves as pixels. The pure parts
//  (`sections`, `entries`) are checked as values first. Runs on every platform, as the
//  other exporter suites do.
//

import CoreGraphics
import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct ShotListPDFExporterTests {

    private let project = PDFFixture.projectWithShots

    private var firstShootDay: ShootDay { project.shootDays[1] }

    private func render(_ scope: ShotListScope, frames: Bool, dumpAs name: String? = nil) -> PDFDocument {
        pdfDocument(
            from: ShotListExporter.generatePDF(
                shootDays: project.shootDays, boneyard: project.allScenes, projectTitle: project.projectTitle,
                scope: scope, includeFrames: frames),
            dumpAs: name
        )
    }

    // MARK: - What prints, as values

    @Test func aSceneWithShotsPrintsOneEntryPerShotLetteredByPosition() {
        let entries = ShotListExporter.entries(for: firstShootDay.scenes[0])
        #expect(entries.map(\.number) == ["101A", "101B", "101C", "101D"])
        #expect(entries.map(\.durationMinutes) == [20, 15, 10, 5])
        #expect(entries[0].equipment == ["Technocrane"])
        #expect(entries[0].props == ["Clipboard"])
        #expect(entries[0].sfx == ["Wind"])
        #expect(entries.allSatisfy { $0.frame != nil })
    }

    @Test func aShotlessSceneIsOneEntryUnderItsBareNumber() {
        let scene = project.allScenes[1]   // 900: no shots, its own frame
        let entries = ShotListExporter.entries(for: scene)
        #expect(entries.count == 1)
        #expect(entries[0].number == "900")
        #expect(entries[0].details == scene.summary)
        #expect(entries[0].durationMinutes == scene.estimatedTime)
        #expect(entries[0].props == ["Lantern"])
        #expect(entries[0].frame == scene.frame)
    }

    @Test func theProjectIsTheDaysInScheduleOrderThenTheBoneyardInScriptOrder() throws {
        let sections = try #require(ShotListExporter.sections(shootDays: project.shootDays, boneyard: project.allScenes, scope: .project))
        // The travel day has no scenes and prints nothing; five shoot days, then the Boneyard.
        #expect(sections.map(\.title) == (1...5).map { DaySummary.label(dayNumber: $0, date: project.shootDays[$0].date) } + ["Boneyard"])
        #expect(sections.last?.scenes.map(\.scene.sceneNumber) == ["900", "901"])
        // Banners, the auto-meal-like lunch, the event and the notice strip never print.
        #expect(sections[0].scenes.map(\.scene.sceneNumber) == ["101", "102", "103", "104", "105", "106"])
    }

    @Test func aDayScopeIsThatDayAloneAndAGoneDayIsNothing() throws {
        let sections = try #require(ShotListExporter.sections(shootDays: project.shootDays, boneyard: project.allScenes, scope: .day(firstShootDay.id)))
        #expect(sections.count == 1)
        #expect(sections[0].title == DaySummary.label(dayNumber: 1, date: firstShootDay.date))
        #expect(ShotListExporter.sections(shootDays: project.shootDays, boneyard: project.allScenes, scope: .day(UUID())) == nil)
        #expect(ShotListExporter.generatePDF(shootDays: project.shootDays, boneyard: [], projectTitle: "", scope: .day(UUID()), includeFrames: true) == nil)
        // A day with nothing that prints (the travel day) exports nothing.
        #expect(ShotListExporter.generatePDF(shootDays: project.shootDays, boneyard: [], projectTitle: "", scope: .day(project.shootDays[0].id), includeFrames: true) == nil)
    }

    // MARK: - The pages

    @Test func framesOnPrintThreeEntriesAPage() {
        // Day 1: four shots, two shots and four shotless scenes are ten slots.
        #expect(render(.day(firstShootDay.id), frames: true, dumpAs: "ShotList-Day-Frames.pdf").pageCount == 4)
        // The project: 10 + 4 × 6 + the Boneyard's 2 = 36 slots.
        #expect(render(.project, frames: true, dumpAs: "ShotList-Frames.pdf").pageCount == 12)
    }

    @Test func framesOffPrintATable() {
        let day = render(.day(firstShootDay.id), frames: false, dumpAs: "ShotList-Day-Table.pdf")
        #expect(day.pageCount == 1)
        let whole = render(.project, frames: false, dumpAs: "ShotList-Table.pdf")
        #expect(whole.pageCount >= 2)
        #expect(whole.pageCount < 12)
        let text = pdfFullText(whole)
        #expect(text.contains("DESCRIPTION"))
        #expect(text.contains("EQUIPMENT"))
    }

    @Test func theShotNumbersAppearInOrder() throws {
        for frames in [true, false] {
            let text = pdfFullText(render(.day(firstShootDay.id), frames: frames))
            var previous = text.startIndex
            for number in ["101A", "101B", "101C", "101D", "102A", "102B"] {
                let range = try #require(text.range(of: number, range: previous..<text.endIndex), "\(number), frames \(frames)")
                previous = range.upperBound
            }
            #expect(!text.contains("101E"))
            #expect(!text.contains("102C"))
        }
    }

    @Test func aShotlessSceneCarriesItsBareNumber() {
        for frames in [true, false] {
            let text = pdfFullText(render(.project, frames: frames))
            #expect(text.contains("103"))
            #expect(!text.contains("103A"))
            #expect(text.contains("900"))
            #expect(!text.contains("900A"))
            // The summary stands in for the description.
            #expect(text.contains("Scene 103: the crew regroups"))
        }
    }

    @Test func theBoneyardHeaderPrintsOnlyForTheProject() {
        for frames in [true, false] {
            #expect(pdfFullText(render(.project, frames: frames)).contains("Boneyard"))
            #expect(!pdfFullText(render(.day(firstShootDay.id), frames: frames)).contains("Boneyard"))
        }
    }

    @Test func notesAndBannersNeverPrint() {
        let text = pdfFullText(render(.project, frames: false))
        #expect(!text.contains("Producer visit"))
        #expect(!text.contains("Company move"))
        #expect(!text.contains("Lunch"))
    }

    @Test func theFooterCarriesTheTitleTheScopeAndThePage() throws {
        let doc = render(.day(firstShootDay.id), frames: true)
        let last = try #require(doc.page(at: 3)?.string)
        #expect(last.contains(PDFFixture.title))
        #expect(last.contains(DaySummary.label(dayNumber: 1, date: firstShootDay.date)))
        #expect(last.contains("Page 4"))
        #expect(pdfFullText(render(.project, frames: false)).contains("Whole Project"))
    }

    @Test func theFramesPrintWhenOnAndNotWhenOff() {
        // Page 1 of day 1 holds 101A–C: red frames, and 101C's blue portrait one.
        let on = render(.day(firstShootDay.id), frames: true)
        #expect(pageCount(on, 0, near: (217, 26, 26)) > 1000)
        #expect(pageCount(on, 0, near: (26, 51, 217)) > 500)
        let off = render(.day(firstShootDay.id), frames: false)
        #expect(pageCount(off, 0, near: (217, 26, 26)) == 0)
        // The Boneyard's shotless scene prints its own (green) frame on the last page.
        let whole = render(.project, frames: true)
        #expect(pageCount(whole, whole.pageCount - 1, near: (26, 179, 51)) > 1000)
    }

    // MARK: - Helpers

    /// How many pixels of page `index`, rasterized at 1 pt a pixel, lie within a few levels
    /// of `rgb` on every channel (JPEG moves a flat color by a level or two).
    private func pageCount(_ doc: PDFDocument, _ index: Int, near rgb: (Int, Int, Int), tolerance: Int = 10) -> Int {
        guard let page = doc.page(at: index)?.pageRef else { return 0 }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        var count = 0
        for i in stride(from: 0, to: width * height * 4, by: 4)
        where abs(Int(pixels[i]) - rgb.0) <= tolerance && abs(Int(pixels[i + 1]) - rgb.1) <= tolerance && abs(Int(pixels[i + 2]) - rgb.2) <= tolerance {
            count += 1
        }
        return count
    }
}

// ShotListExporter.swift
// The Shot List (#40, spec #36): every shot of the scenes in scope, portrait US Letter,
// for the camera department to carry. Two layouts from the same entries:
//
// - Frames on: three slots per page, all of one height, so the page rhythm holds whatever
//   a shot carries. A slot is a header band (the day's bar when a day starts, the scene's
//   line when a scene starts, both repeated "continued" at the top of a page) over a body:
//   the storyboard frame aspect-fit in a fixed box on the left about 3.3 inches wide
//   (never cropped; the box stays empty when there is no frame), and on the right the
//   shot number, the duration, the description and the equipment, props and SFX as
//   labelled lines. The band is reserved in every slot, used or not, so every frame box on
//   every page is the same size.
// - Frames off: a table, one row per shot (number, description, duration, equipment,
//   props, SFX), with the day bars and scene lines between; the column heads repeat on
//   every page and a scene line is never left alone at the foot of one.
//
// What prints: the project scope is every shoot day in schedule order (a day with no
// scenes prints nothing), then the Boneyard in script order under "Boneyard"; the day
// scope is that day alone. Banners, auto-meals, calendar events and the legacy notice
// strips (no number, Custom, no heading: "Company move…") never print: they are strips,
// not scenes. A scene with no shots is one entry: its bare number, its summary as the
// description, its estimate as the duration, its breakdown lists and its own frame. For a
// shotless scene the union lists (`allProps`, …, #37) are the scene's own, so the entry
// reads the unions for both kinds and says so once, here.
//
// Pure: CoreGraphics and CoreText through PDFCanvas (the one image call is
// `drawImage(_:aspectFitIn:)`), frames decoded synchronously with `StoryboardFrame.decode`.
// The call site is `PDFExport.shotList`; tested in ShotListPDFExporterTests.

import CoreGraphics
import Foundation

// MARK: - Scope

/// What a Shot List covers: the whole project, or one shoot day by id.
enum ShotListScope: Hashable {
    case project
    case day(UUID)
}

// MARK: - Exporter

struct ShotListExporter {

    // MARK: What prints

    /// One printed line of the list: a shot, or a shotless scene standing in for its only one.
    struct Entry: Equatable {
        /// "12A" for a shot; the bare scene number for a shotless scene.
        let number:          String
        let details:         String
        let durationMinutes: Int
        let equipment:       [String]
        let props:           [String]
        let sfx:             [String]
        let frame:           Data?
    }

    /// A scene and what prints for it.
    struct SceneBlock {
        let scene:   Scene
        let entries: [Entry]
    }

    /// A day (or the Boneyard) and its scenes.
    struct Section {
        let title:  String
        let scenes: [SceneBlock]
    }

    /// Whether `scene` is a script scene the list prints (not a banner, an auto-meal, a
    /// calendar event or a legacy notice strip).
    static func prints(_ scene: Scene) -> Bool {
        !scene.isBanner && !scene.isCalendarEvent && !scene.isNoticeStrip
    }

    /// The entries of one scene: one per shot, in shooting order, lettered by position;
    /// a scene with no shots is one entry under its bare number.
    static func entries(for scene: Scene) -> [Entry] {
        guard !scene.shots.isEmpty else {
            return [Entry(
                number:          scene.shotNumberPrefix,
                details:         scene.summary,
                durationMinutes: scene.estimatedTime,
                equipment:       scene.allSpecialEquipment,
                props:           scene.allProps,
                sfx:             scene.allSFX,
                frame:           scene.frame
            )]
        }
        return scene.shots.enumerated().map { index, shot in
            Entry(
                number:          scene.shotNumber(at: index),
                details:         shot.details,
                durationMinutes: shot.durationMinutes,
                equipment:       Scene.breakdownUnion(shot.equipment, []),
                props:           Scene.breakdownUnion(shot.props, []),
                sfx:             Scene.breakdownUnion(shot.sfx, []),
                frame:           shot.frame
            )
        }
    }

    /// The sections in print order for `scope`, empty sections dropped. Nil when the scope
    /// names a day that is not in `shootDays`.
    static func sections(shootDays: [ShootDay], boneyard: [Scene], scope: ShotListScope) -> [Section]? {
        let dayNumbers = productionDayNumbers(for: shootDays)
        func section(for day: ShootDay) -> Section {
            Section(
                title:  DaySummary.label(dayNumber: dayNumbers[day.id], date: day.date),
                scenes: day.scenes.filter { prints($0) }.map { SceneBlock(scene: $0, entries: entries(for: $0)) }
            )
        }
        switch scope {
        case .day(let id):
            guard let day = shootDays.first(where: { $0.id == id }) else { return nil }
            return [section(for: day)].filter { !$0.scenes.isEmpty }
        case .project:
            var result = shootDays.map { section(for: $0) }
            let unscheduled = boneyard.filter { prints($0) }.sorted { $0.scriptOrderKey < $1.scriptOrderKey }
            result.append(Section(title: L("Boneyard"), scenes: unscheduled.map { SceneBlock(scene: $0, entries: entries(for: $0)) }))
            return result.filter { !$0.scenes.isEmpty }
        }
    }

    // MARK: Entry point

    /// The Shot List's PDF, or nil when the scope's day is gone or nothing in scope prints.
    static func generatePDF(
        shootDays:     [ShootDay],
        boneyard:      [Scene],
        projectTitle:  String,
        scope:         ShotListScope,
        includeFrames: Bool
    ) -> Data? {
        guard let sections = sections(shootDays: shootDays, boneyard: boneyard, scope: scope), !sections.isEmpty,
              let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        let scopeTitle: String
        switch scope {
        case .project: scopeTitle = L("Whole Project")
        case .day:     scopeTitle = sections[0].title
        }
        var page = Page(canvas: canvas, projectTitle: projectTitle.isEmpty ? L("Untitled Movie") : projectTitle, scopeTitle: scopeTitle)

        if includeFrames {
            drawSlots(sections, on: &page)
        } else {
            drawTable(sections, on: &page)
        }
        page.finishPage()
        return canvas.finish()
    }

    // MARK: - Geometry

    private static let pageWidth:    CGFloat = 612   // US Letter portrait
    private static let pageHeight:   CGFloat = 792
    private static let margin:       CGFloat = 36
    private static let contentWidth: CGFloat = pageWidth - 2 * margin
    private static let contentTop:   CGFloat = pageHeight - margin
    /// The footer sits in the bottom margin's lower half; content stops above it.
    private static let contentBottom: CGFloat = 50

    private static let slotsPerPage  = 3
    private static let slotHeight:    CGFloat = (contentTop - contentBottom) / CGFloat(slotsPerPage)
    /// The part of every slot the day bar and the scene line may use.
    private static let bandHeight:    CGFloat = 46
    private static let dayBarHeight:  CGFloat = 16
    /// About 3.3 inches: the width of every frame box.
    private static let frameBoxWidth: CGFloat = 238
    private static let bodyGap:       CGFloat = 14

    // MARK: - Type and color

    private static let fontDayBar      = PDFFont.boldSystem(size: 9.5)
    private static let fontSceneNumber = PDFFont.boldSystem(size: 11)
    private static let fontSceneTitle  = PDFFont.semiboldSystem(size: 10)
    private static let fontSceneMeta   = PDFFont.system(size: 8.5)
    private static let fontShotNumber  = PDFFont.boldSystem(size: 16)
    private static let fontDuration    = PDFFont.semiboldSystem(size: 10)
    private static let fontDetails     = PDFFont.system(size: 10)
    private static let fontListLabel   = PDFFont.boldSystem(size: 8.5)
    private static let fontList        = PDFFont.system(size: 8.5)
    private static let fontTableHead   = PDFFont.boldSystem(size: 7.5)
    private static let fontTable       = PDFFont.system(size: 8.5)
    private static let fontTableNumber = PDFFont.boldSystem(size: 8.5)
    private static let fontFooter      = PDFFont.system(size: 7.5)

    private static let colorText     = CGColor.gray(0.1)
    private static let colorMeta     = CGColor.gray(0.4)
    private static let colorRule     = CGColor.gray(0.75)
    private static let colorDayBar   = CGColor.gray(0.88)
    private static let colorFrameBox = CGColor.gray(0.6)
    private static let colorTableBG  = CGColor.gray(0.94)

    // MARK: - Pages and the footer

    /// The page being drawn, with the footer every page ends on.
    private struct Page {
        let canvas:       PDFCanvas
        let projectTitle: String
        let scopeTitle:   String
        private(set) var number = 0
        private var isOpen = false

        init(canvas: PDFCanvas, projectTitle: String, scopeTitle: String) {
            self.canvas       = canvas
            self.projectTitle = projectTitle
            self.scopeTitle   = scopeTitle
        }

        mutating func startPage() {
            finishPage()
            canvas.beginPage()
            number += 1
            isOpen = true
        }

        /// Draws the footer and closes the page, if one is open.
        mutating func finishPage() {
            guard isOpen else { return }
            let y: CGFloat = 26
            canvas.line(from: CGPoint(x: margin, y: y + 12), to: CGPoint(x: pageWidth - margin, y: y + 12), color: colorRule, lineWidth: 0.5)
            let third = contentWidth / 3
            canvas.draw(projectTitle, at: CGPoint(x: margin, y: y), font: fontFooter, color: colorMeta, maxWidth: third - 8)
            canvas.draw("\(L("Shot List")) · \(scopeTitle)", at: CGPoint(x: pageWidth / 2, y: y), font: fontFooter, color: colorMeta, anchor: .center, maxWidth: third + 40)
            canvas.draw("\(L("Page")) \(number)", at: CGPoint(x: pageWidth - margin, y: y), font: fontFooter, color: colorMeta, anchor: .trailing)
            canvas.endPage()
            isOpen = false
        }
    }

    // MARK: - Shared pieces

    /// "Est. 35 min · 1 2/8 pgs": what a scene line says after the slugline.
    private static func sceneMeta(_ scene: Scene) -> String {
        "\(L("Est.")) \(formattedTime(scene.estimatedTime)) · \(formattedEighths(scene.duration)) \(L("pgs"))"
    }

    /// The slugline without a number the title itself leads with (scenes saved before the
    /// number had its own field), since the number prints beside it.
    private static func slugline(_ scene: Scene) -> String {
        let title = scene.title.trimmingCharacters(in: .whitespaces)
        guard let match = title.range(of: #"^#?\d+[A-Za-z]*\.\s*"#, options: .regularExpression) else { return title }
        return String(title[match.upperBound...])
    }

    /// A day bar across the content width, its top at `top`.
    private static func drawDayBar(_ title: String, continued: Bool, top: CGFloat, canvas: PDFCanvas) {
        let rect = CGRect(x: margin, y: top - dayBarHeight, width: contentWidth, height: dayBarHeight)
        canvas.fill(rect, color: colorDayBar)
        let text = continued ? "\(title) (\(L("continued")))" : title
        canvas.draw(text, at: CGPoint(x: margin + 6, y: rect.minY + 4.5), font: fontDayBar, color: colorText, maxWidth: contentWidth - 12)
    }

    /// The scene's number, slugline and meta on one baseline.
    private static func drawSceneLine(_ scene: Scene, continued: Bool, baseline: CGFloat, canvas: PDFCanvas) {
        let number = scene.shotNumberPrefix
        let meta   = sceneMeta(scene) + (continued ? " · \(L("continued"))" : "")
        let metaWidth = canvas.width(of: meta, font: fontSceneMeta)
        canvas.draw(meta, at: CGPoint(x: pageWidth - margin, y: baseline), font: fontSceneMeta, color: colorMeta, anchor: .trailing)
        var x = margin
        if !number.isEmpty {
            canvas.draw(number, at: CGPoint(x: x, y: baseline), font: fontSceneNumber, color: colorText)
            x += canvas.width(of: number, font: fontSceneNumber) + 8
        }
        canvas.draw(slugline(scene), at: CGPoint(x: x, y: baseline), font: fontSceneTitle, color: colorText,
                    maxWidth: max(pageWidth - margin - metaWidth - 12 - x, 20))
    }

    private static func listText(_ items: [String]) -> String {
        items.joined(separator: ", ")
    }

    // MARK: - Frames on: three slots a page

    private static func drawSlots(_ sections: [Section], on page: inout Page) {
        let canvas = page.canvas
        var slotIndex = 0
        for section in sections {
            for (sceneIndex, block) in section.scenes.enumerated() {
                for (entryIndex, entry) in block.entries.enumerated() {
                    let position = slotIndex % slotsPerPage
                    if position == 0 { page.startPage() }
                    let top = contentTop - CGFloat(position) * slotHeight

                    // The band: the day bar where a section starts (or a page continues
                    // one), the scene line where a scene starts (or a page continues one).
                    let startsSection = sceneIndex == 0 && entryIndex == 0
                    if startsSection || position == 0 {
                        drawDayBar(section.title, continued: !startsSection, top: top, canvas: canvas)
                    }
                    if entryIndex == 0 || position == 0 {
                        drawSceneLine(block.scene, continued: entryIndex > 0, baseline: top - dayBarHeight - 17, canvas: canvas)
                    }
                    let bandBottom = top - bandHeight
                    canvas.line(from: CGPoint(x: margin, y: bandBottom + 4), to: CGPoint(x: pageWidth - margin, y: bandBottom + 4), color: colorRule, lineWidth: 0.5)

                    drawSlotBody(entry, top: bandBottom - 4, bottom: top - slotHeight + 8, canvas: canvas)
                    slotIndex += 1
                }
            }
        }
    }

    /// The frame box on the left, the shot's text on the right, between `top` and `bottom`.
    private static func drawSlotBody(_ entry: Entry, top: CGFloat, bottom: CGFloat, canvas: PDFCanvas) {
        let box = CGRect(x: margin, y: bottom, width: frameBoxWidth, height: top - bottom)
        canvas.stroke(box, color: colorFrameBox, lineWidth: 0.5)
        if let frame = entry.frame, let image = StoryboardFrame.decode(frame) {
            canvas.drawImage(image, aspectFitIn: box.insetBy(dx: 1, dy: 1))
        }

        let textX     = margin + frameBoxWidth + bodyGap
        let textWidth = pageWidth - margin - textX
        var y = top

        // The number, and the duration at the trailing edge of the same line.
        let numberBaseline = y - fontShotNumber.baselineOffset
        canvas.draw(entry.number.isEmpty ? "—" : entry.number, at: CGPoint(x: textX, y: numberBaseline), font: fontShotNumber, color: colorText)
        canvas.draw(formattedTime(entry.durationMinutes), at: CGPoint(x: pageWidth - margin, y: numberBaseline), font: fontDuration, color: colorText, anchor: .trailing)
        y -= fontShotNumber.lineHeight + 6

        // The lists sit at the foot of the text column, each a bold label with its items
        // wrapped beside it (three lines at most); the description takes what is left.
        let lists: [(String, String)] = [
            (L("Equipment"), listText(entry.equipment)),
            (L("Props"),     listText(entry.props)),
            (L("SFX"),       listText(entry.sfx)),
        ].filter { !$0.1.isEmpty }
        let labelWidth  = lists.map { canvas.width(of: "\($0.0):", font: fontListLabel) }.max().map { $0 + 6 } ?? 0
        let itemsWidth  = max(textWidth - labelWidth, 20)
        let listHeights = lists.map { min(canvas.height(of: $0.1, font: fontList, width: itemsWidth), fontList.lineHeight * 3) }
        let listsHeight = listHeights.reduce(0) { $0 + $1 + 3 }

        let details = entry.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty {
            let detailsRect = CGRect(x: textX, y: bottom + listsHeight + 4, width: textWidth, height: max(y - bottom - listsHeight - 4, 0))
            canvas.draw(details, in: detailsRect, font: fontDetails, color: colorText, lineSpacing: 1.5)
        }

        var listTop = bottom + listsHeight
        for ((label, items), height) in zip(lists, listHeights) {
            canvas.draw("\(label):", in: CGRect(x: textX, y: listTop - fontListLabel.lineHeight, width: labelWidth, height: fontListLabel.lineHeight),
                        font: fontListLabel, color: colorText, lineBreak: .truncateTail)
            canvas.draw(items, in: CGRect(x: textX + labelWidth, y: listTop - height, width: itemsWidth, height: height), font: fontList, color: colorText)
            listTop -= height + 3
        }
    }

    // MARK: - Frames off: the table

    private struct Column {
        let title: String
        let width: CGFloat
        let text:  (Entry) -> String
    }

    private static var columns: [Column] {
        let listWidth = (contentWidth - 42 - 170 - 56) / 3
        return [
            Column(title: L("Shot"),        width: 42,        text: { $0.number.isEmpty ? "—" : $0.number }),
            Column(title: L("Description"), width: 170,       text: { $0.details.trimmingCharacters(in: .whitespacesAndNewlines) }),
            Column(title: L("Duration"),    width: 56,        text: { formattedTime($0.durationMinutes) }),
            Column(title: L("Equipment"),   width: listWidth, text: { listText($0.equipment) }),
            Column(title: L("Props"),       width: listWidth, text: { listText($0.props) }),
            Column(title: L("SFX"),         width: listWidth, text: { listText($0.sfx) }),
        ]
    }

    private static let tableHeadHeight: CGFloat = 16
    private static let sceneLineHeight: CGFloat = 20
    private static let cellPadding:     CGFloat = 3
    /// Where the first thing under a page's column heads starts.
    private static let pageTopY:        CGFloat = contentTop - tableHeadHeight - 4

    private static func drawTable(_ sections: [Section], on page: inout Page) {
        let canvas  = page.canvas
        let columns = columns
        var y: CGFloat = 0

        func rowHeight(_ entry: Entry) -> CGFloat {
            let tallest = columns.map { column in
                canvas.height(of: column.text(entry), font: fontTable, width: column.width - 2 * cellPadding)
            }.max() ?? 0
            return max(tallest, fontTable.lineHeight) + 2 * cellPadding
        }

        func newPage() {
            page.startPage()
            y = contentTop
            var x = margin
            canvas.fill(CGRect(x: margin, y: y - tableHeadHeight, width: contentWidth, height: tableHeadHeight), color: colorTableBG)
            for column in columns {
                canvas.draw(column.title.uppercased(), at: CGPoint(x: x + cellPadding, y: y - tableHeadHeight + 5), font: fontTableHead, color: colorMeta,
                            maxWidth: column.width - 2 * cellPadding)
                x += column.width
            }
            y = pageTopY
        }

        func fits(_ height: CGFloat) -> Bool { y - height >= contentBottom }

        newPage()
        for section in sections {
            for (sceneIndex, block) in section.scenes.enumerated() {
                // A scene line is never left alone at the foot of a page: it moves over
                // with its first row, under the day bar (continued, mid-day).
                let firstRow = rowHeight(block.entries[0])
                if !fits(dayBarHeight + 4 + sceneLineHeight + firstRow) { newPage() }
                if sceneIndex == 0 || y == pageTopY {
                    drawDayBar(section.title, continued: sceneIndex > 0, top: y, canvas: canvas)
                    y -= dayBarHeight + 4
                }
                drawSceneLine(block.scene, continued: false, baseline: y - 13, canvas: canvas)
                y -= sceneLineHeight

                for (entryIndex, entry) in block.entries.enumerated() {
                    let height = rowHeight(entry)
                    if !fits(height) {
                        newPage()
                        drawDayBar(section.title, continued: true, top: y, canvas: canvas)
                        y -= dayBarHeight + 4
                        drawSceneLine(block.scene, continued: entryIndex > 0, baseline: y - 13, canvas: canvas)
                        y -= sceneLineHeight
                    }
                    var x = margin
                    for (index, column) in columns.enumerated() {
                        let rect = CGRect(x: x + cellPadding, y: y - height + cellPadding, width: column.width - 2 * cellPadding, height: height - 2 * cellPadding)
                        canvas.draw(column.text(entry), in: rect, font: index == 0 ? fontTableNumber : fontTable, color: colorText)
                        x += column.width
                    }
                    y -= height
                    canvas.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageWidth - margin, y: y), color: colorRule, lineWidth: 0.4)
                }
                y -= 6
            }
        }
    }
}

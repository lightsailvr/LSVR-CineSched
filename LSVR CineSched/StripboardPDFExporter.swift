// StripboardPDFExporter.swift
// A modernized, printed take on a Movie Magic Scheduling color strip
// schedule — a portrait, day-by-day stack of color-coded strips ending in a
// black "END OF DAY" bar, generated straight from the stripboard view.
// Deliberately not a reskin of PDFExporter's landscape calendar-grid layout;
// this is the "hand someone the stripboard" document, not the month view.
//
// Draws through PDFCanvas (CoreGraphics + CoreText), so it builds and runs on
// every platform. The rects handed to `canvas.draw(_:in:…)` are the ones the
// AppKit version handed to `NSAttributedString.draw(in:)`; PDFCanvas lays text
// out in them the way TextKit did, which is what keeps the output identical.

import SwiftUI

class StripboardPDFExporter {

    private static let pageWidth:  CGFloat = 612   // US Letter portrait
    private static let pageHeight: CGFloat = 792
    private static let margin:     CGFloat = 40
    private static let contentWidth: CGFloat = pageWidth - 2 * margin

    private static let fontTitle     = PDFFont.boldSystem(size: 18)
    private static let fontSubtitle  = PDFFont.system(size: 10)
    private static let fontDayHeader = PDFFont.boldSystem(size: 11)
    private static let fontDaySub    = PDFFont.system(size: 8.5)
    private static let fontStripNum  = PDFFont.boldSystem(size: 9)
    private static let fontStripTitle = PDFFont.boldSystem(size: 9.5)
    private static let fontStripMeta  = PDFFont.system(size: 8)
    private static let fontEOD        = PDFFont.boldSystem(size: 8.5)
    private static let fontFooter     = PDFFont.system(size: 7.5)

    private static let colorBlack  = CGColor.pdfBlack
    private static let colorDark   = CGColor.gray(0.15)
    private static let colorMid    = CGColor.gray(0.45)
    private static let dayHeaderBG = CGColor.gray(0.88)

    private static let dayHeaderHeight: CGFloat = 20
    private static let stripHeight:     CGFloat = 18
    private static let eodHeight:       CGFloat = 20
    private static let stripSpacing:    CGFloat = 1.5

    // MARK: - Entry point

    static func generatePDF(
        shootDays: [ShootDay],
        projectTitle: String,
        productionInfo: ProductionInfo,
        palette: ScenePalette
    ) -> Data? {
        // A printed schedule is a distributable document, not the live planning
        // board — skip days nobody's scheduled anything into yet.
        let scheduledDays = shootDays.filter { !$0.scenes.isEmpty }
        guard !scheduledDays.isEmpty else { return nil }

        let dayNumbers = productionDayNumbers(for: shootDays)

        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        var y: CGFloat = pageHeight - margin

        func beginPage() {
            canvas.beginPage()
            y = pageHeight - margin
        }
        func endPage() {
            drawFooter(on: canvas, pageNumber: canvas.pageCount)
            canvas.endPage()
        }
        /// Starts a new page if `height` won't fit in what's left above the
        /// bottom margin — used before every row so a strip or bar never gets
        /// sliced in half across a page break.
        func ensureRoom(_ height: CGFloat) {
            if y - height < margin {
                endPage()
                beginPage()
            }
        }

        beginPage()
        y = drawTitleHeader(on: canvas, y: y, projectTitle: projectTitle, productionInfo: productionInfo)

        for day in scheduledDays {
            let dayNumber = dayNumbers[day.id]

            ensureRoom(dayHeaderHeight + stripHeight)   // header alone with nothing under it reads as an error
            y = drawDayHeader(on: canvas, y: y, day: day, dayNumber: dayNumber)

            // Calendar events first, as slim tinted lines above the strips (they are not
            // part of the day's work or its time cascade), then the strips themselves.
            for event in day.scenes where event.isCalendarEvent {
                ensureRoom(eventHeight)
                y = drawEventLine(on: canvas, y: y, event: event)
            }
            for scene in day.scenes where !scene.isCalendarEvent {
                ensureRoom(stripHeight)
                y = drawSceneStrip(on: canvas, y: y, scene: scene, palette: palette)
            }

            if dayNumber != nil {
                ensureRoom(eodHeight)
                y = drawEndOfDayBar(on: canvas, y: y, day: day, dayNumber: dayNumber!)
            }

            y -= 8   // breathing room before the next day
        }

        endPage()
        return canvas.finish()
    }

    // MARK: - Title header (page 1 only)

    private static func drawTitleHeader(on canvas: PDFCanvas, y: CGFloat, projectTitle: String, productionInfo: ProductionInfo) -> CGFloat {
        var y = y
        y = drawText(on: canvas, projectTitle.isEmpty ? "Untitled Movie" : projectTitle,
                     font: fontTitle, color: colorBlack, x: margin, y: y, width: contentWidth)
        var subtitle = "Strip Schedule"
        if !productionInfo.companyName.isEmpty { subtitle += "   —   \(productionInfo.companyName)" }
        y = drawText(on: canvas, subtitle, font: fontSubtitle, color: colorMid, x: margin, y: y, width: contentWidth)
        y -= 8
        drawHRule(on: canvas, y: y)
        y -= 14
        return y
    }

    // MARK: - Day header band

    private static func drawDayHeader(on canvas: PDFCanvas, y: CGFloat, day: ShootDay, dayNumber: Int?) -> CGFloat {
        let rect = CGRect(x: margin, y: y - dayHeaderHeight, width: contentWidth, height: dayHeaderHeight)
        canvas.fill(rect, color: dayHeaderBG)

        // Left: "Day N" for counted production days, otherwise the day type (TRAVEL DAY,
        // HOLIDAY, …) in its tint so a non-shoot day reads as such on paper too.
        if let dayNumber {
            canvas.draw("Day \(dayNumber)", in: CGRect(x: rect.minX + 6, y: rect.midY - 6, width: 90, height: 13),
                        font: fontDayHeader, color: colorDark)
        } else if !day.dayType.isShootable {
            let tint = CGColor.hex(day.dayType.colorHex)
            canvas.draw(day.dayType.localizedName.uppercased(), in: CGRect(x: rect.minX + 6, y: rect.midY - 5, width: 120, height: 12),
                        font: fontDaySub, color: tint)
        }

        // Center: the full date — the page/time totals already live on the
        // END OF DAY bar below, so this header doesn't repeat them.
        canvas.draw(formattedFullDate(day.date), in: CGRect(x: rect.minX, y: rect.midY - 6, width: rect.width, height: 13),
                    font: fontDayHeader, color: colorDark, alignment: .center)

        // Right: scene count only. The "X/8 pgs" column below is left-anchored
        // at rect.maxX-56 but its values (e.g. "2/8 pgs") don't fill the full
        // 50pt box, so matching that left edge exactly still reads as too far
        // right relative to where those values visually sit. Starting a bit
        // further left — rather than center-aligning within the same box,
        // which only adds *more* left padding and pushes it right — lines the
        // two up.
        // Events are drawn above the strips but are not scenes; count only what has a strip.
        let stripCount = day.scenes.filter { !$0.isCalendarEvent }.count
        let sub = stripCount == 0 ? "" : "\(stripCount) scene\(stripCount == 1 ? "" : "s")"
        canvas.draw(sub, in: CGRect(x: rect.maxX - 61, y: rect.midY - 5, width: 50, height: 11),
                    font: fontDaySub, color: colorMid)

        return y - dayHeaderHeight - stripSpacing
    }

    // MARK: - Calendar event line

    private static let eventHeight: CGFloat = 12

    private static func drawEventLine(on canvas: PDFCanvas, y: CGFloat, event: Scene) -> CGFloat {
        let rect = CGRect(x: margin, y: y - eventHeight, width: contentWidth, height: eventHeight)
        let tint = CGColor.hex(event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex)
        canvas.fill(rect, color: tint.withAlpha(0.15))
        canvas.stroke(rect, color: tint.withAlpha(0.5), lineWidth: 0.5)

        let timePrefix = event.customStartTime.isEmpty ? "" : "\(event.customStartTime) · "
        let title = event.bannerTitle.isEmpty ? event.title : event.bannerTitle
        canvas.draw(timePrefix + title, in: CGRect(x: rect.minX + 6, y: rect.midY - 5, width: rect.width - 12, height: 11),
                    font: fontStripMeta, color: tint, lineBreak: .truncateTail)
        return y - eventHeight
    }

    // MARK: - Scene strip

    private static func drawSceneStrip(on canvas: PDFCanvas, y: CGFloat, scene: Scene, palette: ScenePalette) -> CGFloat {
        let rect = CGRect(x: margin, y: y - stripHeight, width: contentWidth, height: stripHeight)
        canvas.fill(rect, color: .of(scene.stripColor(in: palette)))
        canvas.stroke(rect, color: CGColor.pdfBlack.withAlpha(0.25), lineWidth: 0.5)

        let textColor = CGColor.of(scene.stripTextColor)
        var x = rect.minX + 6

        if !scene.sceneNumber.isEmpty {
            let numWidth: CGFloat = 26
            canvas.draw(scene.sceneNumber, in: CGRect(x: x, y: rect.midY - 5, width: numWidth, height: 11),
                        font: fontStripNum, color: textColor.withAlpha(0.7))
            x += numWidth
        }

        let metaColor = textColor.withAlpha(0.65)

        let pagesStr = "\(formattedEighths(scene.duration)) pgs"
        let pagesWidth: CGFloat = 50
        canvas.draw(pagesStr, in: CGRect(x: rect.maxX - pagesWidth - 6, y: rect.midY - 5, width: pagesWidth, height: 11),
                    font: fontStripMeta, color: metaColor, lineBreak: .truncateTail)

        let castStr = scene.cast.isEmpty ? "" : scene.cast.joined(separator: ", ")
        let castWidth: CGFloat = castStr.isEmpty ? 0 : 150
        if !castStr.isEmpty {
            canvas.draw(castStr, in: CGRect(x: rect.maxX - pagesWidth - castWidth - 12, y: rect.midY - 5, width: castWidth, height: 11),
                        font: fontStripMeta, color: metaColor, lineBreak: .truncateTail)
        }

        let titleWidth = rect.maxX - pagesWidth - castWidth - 18 - x
        canvas.draw(scene.title, in: CGRect(x: x, y: rect.midY - 5.5, width: max(titleWidth, 20), height: 12),
                    font: fontStripTitle, color: textColor, lineBreak: .truncateTail)

        return y - stripHeight - stripSpacing
    }

    // MARK: - End of day bar

    private static func drawEndOfDayBar(on canvas: PDFCanvas, y: CGFloat, day: ShootDay, dayNumber: Int) -> CGFloat {
        let rect = CGRect(x: margin, y: y - eodHeight, width: contentWidth, height: eodHeight)
        canvas.fill(rect, color: colorBlack)

        let text = "-- END OF DAY #\(dayNumber) -- \(formattedFullDate(day.date)) -- \(formattedEighths(day.totalDuration)) pgs. -- Estimated time: \(formattedTimeHM(day.totalEstimatedTime))"
        canvas.draw(text, in: CGRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 11),
                    font: fontEOD, color: .pdfWhite, alignment: .center)

        return y - eodHeight
    }

    // MARK: - Footer

    private static func drawFooter(on canvas: PDFCanvas, pageNumber: Int) {
        canvas.draw("Page \(pageNumber)", in: CGRect(x: margin, y: margin - 20, width: contentWidth, height: 10),
                    font: fontFooter, color: colorMid, alignment: .center)
    }

    // MARK: - Low-level drawing helpers

    /// Draws a wrapped block of text with its top at `y` and returns the y just under it.
    private static func drawText(on canvas: PDFCanvas, _ text: String, font: PDFFont, color: CGColor, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let height = canvas.height(of: text, font: font, width: width)
        canvas.draw(text, in: CGRect(x: x, y: y - height, width: width, height: height), font: font, color: color)
        return y - height - 2
    }

    private static func drawHRule(on canvas: PDFCanvas, y: CGFloat) {
        canvas.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageWidth - margin, y: y), color: .gray(0.7), lineWidth: 1)
    }
}

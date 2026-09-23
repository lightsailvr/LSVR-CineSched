// BreakdownExporter.swift
// Generates a portrait US Letter PDF with one bordered breakdown-sheet grid per scene —
// script order, every scene included — in the classic AD breakdown sheet layout.
// Enhanced with smart dynamic space allocation (shrinking unused categories to 24pt),
// bulleted list formatting, larger legible typography, and color-coded department titles.
//
// Draws through PDFCanvas (CoreGraphics + CoreText, no AppKit), so it builds on every
// platform. The rects handed to `canvas.draw(_:in:…)` are the ones the AppKit version
// handed to `NSAttributedString.draw(in:)`, and the auto-scaling loop compares
// `boundingHeight` (what `boundingRect` reported) against the cell exactly as before, so
// each sheet picks the same size and lands pixel for pixel where it did.

import CoreGraphics
import Foundation

struct BreakdownExporter {

    // MARK: - Department Title Colors (Matching User Reference)
    private static let castColor       = CGColor.srgb(0.88, 0.12, 0.12) // Red
    private static let wardrobeColor   = CGColor.srgb(0.58, 0.28, 0.08) // Brown
    private static let propsColor      = CGColor.srgb(0.55, 0.15, 0.75) // Purple
    private static let extrasColor     = CGColor.srgb(0.00, 0.65, 0.15) // Green
    private static let setDressColor   = CGColor.srgb(0.80, 0.55, 0.00) // Gold / Yellow
    private static let hairMakeupColor = CGColor.srgb(0.05, 0.40, 0.90) // Blue
    private static let vehiclesColor   = CGColor.srgb(0.48, 0.12, 0.52) // Dark Violet
    private static let sfxColor        = CGColor.srgb(0.00, 0.55, 0.65) // Cyan / Teal
    private static let vfxColor        = CGColor.srgb(0.00, 0.55, 0.65) // Cyan / Teal
    private static let specialEqColor  = CGColor.srgb(0.27, 0.35, 0.39) // Slate
    private static let stuntsColor     = CGColor.srgb(0.78, 0.16, 0.16) // Crimson
    private static let defaultColor    = CGColor.gray(0.10)             // Charcoal / Black

    static func generatePDF(shootDays: [ShootDay], allScenes: [Scene], projectTitle: String) -> Data? {
        var seen: Set<UUID> = []
        var scenes: [Scene] = []
        for s in allScenes where !seen.contains(s.id) { seen.insert(s.id); scenes.append(s) }
        for day in shootDays {
            for s in day.scenes where !seen.contains(s.id) { seen.insert(s.id); scenes.append(s) }
        }
        scenes.sort { $0.scriptOrderKey < $1.scriptOrderKey }
        guard !scenes.isEmpty else { return nil }

        let pageWidth:  CGFloat = 612   // US Letter portrait
        let pageHeight: CGFloat = 792
        let margin:     CGFloat = 36
        let contentWidth = pageWidth - 2 * margin

        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        let displayTitle = projectTitle.isEmpty ? "Untitled Movie" : projectTitle

        for (index, scene) in scenes.enumerated() {
            canvas.beginPage()

            // The number lives in `sceneNumber` for every imported and hand-entered scene,
            // and the title carries it only for projects saved before that field existed;
            // read the field first and fall back to the title's prefix, as the shooting
            // schedule does (#33). Banners and events have neither and print "—".
            let (headingNumber, intExt, setting) = parseSceneHeading(scene.title)
            let fieldNumber = scene.sceneNumber.trimmingCharacters(in: .whitespaces)
            let sceneNumber = fieldNumber.isEmpty ? headingNumber : fieldNumber

            // Masthead
            let mastheadTop = pageHeight - margin
            canvas.draw("BREAKDOWN SHEET", lineOrigin: CGPoint(x: margin, y: mastheadTop - 18),
                        font: .boldSystem(size: 18), color: .pdfBlack)

            let gridTop = mastheadTop - 26
            let footerBottom = margin + 12
            let totalAvailableGridHeight = gridTop - footerBottom

            // Calculate smart dynamic row heights for this specific scene
            let rowHeights = computeDynamicRowHeights(for: scene, totalHeight: totalAvailableGridHeight)
            var rowTops: [CGFloat] = []
            var rowY = gridTop
            for h in rowHeights { rowTops.append(rowY); rowY -= h }
            let gridBottom = rowY

            // Row 0: Breakdown Sheet # | Project Title | Scene #
            let narrowCol1: CGFloat = 115
            let wideCol1 = contentWidth - 2 * narrowCol1
            var x = margin
            // "BREAKDOWN SHEET #" at 9pt bold is 104pt wide on the Mac's SF, a point more
            // than the 103pt label area, so its "#" wrapped onto a second line that the
            // 14pt label box clipped to a sliver (#33). The masthead above already says
            // "BREAKDOWN SHEET"; the short label fits at the size every other label uses.
            drawCell(canvas, label: "SHEET #", value: "\(index + 1)",
                     rect: CGRect(x: x, y: rowTops[0] - rowHeights[0], width: narrowCol1, height: rowHeights[0]),
                     valueSize: 13, valueBold: true, centered: true, labelSize: 9.0)
            x += narrowCol1
            drawCell(canvas, label: "", value: displayTitle,
                     rect: CGRect(x: x, y: rowTops[0] - rowHeights[0], width: wideCol1, height: rowHeights[0]),
                     valueSize: 18, valueBold: true, centered: true)
            x += wideCol1
            drawCell(canvas, label: "SCENE #", value: sceneNumber.isEmpty ? "—" : sceneNumber,
                     rect: CGRect(x: x, y: rowTops[0] - rowHeights[0], width: narrowCol1, height: rowHeights[0]),
                     valueSize: 15, valueBold: true, centered: true, labelSize: 9.0)

            // Row 1: INT/EXT (narrow) | Setting (wide) | Location (medium)
            let intExtCol: CGFloat = 70
            let locationCol: CGFloat = 120
            let settingCol = contentWidth - intExtCol - locationCol
            x = margin
            drawCell(canvas, label: "INT / EXT", value: intExt,
                     rect: CGRect(x: x, y: rowTops[1] - rowHeights[1], width: intExtCol, height: rowHeights[1]),
                     valueSize: 11, valueBold: true, centered: true, labelSize: 9.0)
            x += intExtCol
            drawCell(canvas, label: "SETTING", value: setting,
                     rect: CGRect(x: x, y: rowTops[1] - rowHeights[1], width: settingCol, height: rowHeights[1]),
                     valueSize: 10.0, valueBold: false, labelSize: 9.0)
            x += settingCol
            drawCell(canvas, label: "LOCATION", value: "",
                     rect: CGRect(x: x, y: rowTops[1] - rowHeights[1], width: locationCol, height: rowHeights[1]),
                     valueSize: 10.0, labelSize: 9.0)

            // Row 2: Description (balanced) | Day/Night + Script Pages stacked in right column
            let rightCol2: CGFloat = 135
            let descCol = contentWidth - rightCol2
            let halfHeight2 = rowHeights[2] / 2
            x = margin
            drawCell(canvas, label: "DESCRIPTION", value: scene.summary,
                     rect: CGRect(x: x, y: rowTops[2] - rowHeights[2], width: descCol, height: rowHeights[2]),
                     valueSize: 9.5, labelSize: 9.0)
            x += descCol
            drawCell(canvas, label: "DAY / NIGHT", value: scene.dayNightType.displayName,
                     rect: CGRect(x: x, y: rowTops[2] - halfHeight2, width: rightCol2, height: halfHeight2),
                     valueSize: 11, valueBold: true, centered: true, labelSize: 9.0)
            drawCell(canvas, label: "SCRIPT PAGES", value: formattedEighths(scene.duration),
                     rect: CGRect(x: x, y: rowTops[2] - rowHeights[2], width: rightCol2, height: halfHeight2),
                     valueSize: 11, valueBold: true, centered: true, labelSize: 9.0)

            // Row 3: Cast | Extras / Background | Wardrobe (Prominent colored department titles: 11.5pt bold)
            drawThreeUp(canvas, row: 3, rowTops: rowTops, rowHeights: rowHeights, margin: margin, contentWidth: contentWidth,
                        a: ("CAST", formatBulletList(scene.cast), castColor),
                        b: ("EXTRAS / BACKGROUND", formatBulletList(scene.extras), extrasColor),
                        c: ("WARDROBE", formatBulletList(scene.wardrobe), wardrobeColor),
                        labelSize: 11.5)

            // Row 4: Hair & Makeup | Props | Set Dressing
            drawThreeUp(canvas, row: 4, rowTops: rowTops, rowHeights: rowHeights, margin: margin, contentWidth: contentWidth,
                        a: ("HAIR & MAKEUP", formatBulletList(scene.makeupHair), hairMakeupColor),
                        b: ("PROPS", formatBulletList(scene.allProps), propsColor),
                        c: ("SET DRESSING", formatBulletList(scene.setDressing), setDressColor),
                        labelSize: 11.5)

            // Row 5: Vehicles | Special Equipment | Stunts
            drawThreeUp(canvas, row: 5, rowTops: rowTops, rowHeights: rowHeights, margin: margin, contentWidth: contentWidth,
                        a: ("VEHICLES", formatBulletList(scene.vehicles), vehiclesColor),
                        b: ("SPECIAL EQUIPMENT", formatBulletList(scene.allSpecialEquipment), specialEqColor),
                        c: ("STUNTS", formatBulletList(scene.stunts), stuntsColor),
                        labelSize: 11.5)

            // Row 6: SFX | VFX
            drawTwoUp(canvas, row: 6, rowTops: rowTops, rowHeights: rowHeights, margin: margin, contentWidth: contentWidth,
                      a: ("SFX", formatBulletList(scene.allSFX), sfxColor),
                      b: ("VFX", formatBulletList(scene.vfx), vfxColor),
                      labelSize: 11.5)

            // Row 7: Notes (full width)
            drawCell(canvas, label: "NOTES", value: scene.breakdownNotes,
                     rect: CGRect(x: margin, y: rowTops[7] - rowHeights[7], width: contentWidth, height: rowHeights[7]),
                     valueSize: 9.5,
                     labelColor: defaultColor,
                     labelSize: 10.0)

            // Footer: est. time + scene counter
            canvas.draw("Est. Time: \(formattedTime(scene.estimatedTime))", lineOrigin: CGPoint(x: margin, y: gridBottom - 13),
                        font: .system(size: 8.5), color: .pdfGray)
            canvas.draw("Scene \(index + 1) of \(scenes.count)", lineOrigin: CGPoint(x: pageWidth - margin - 85, y: gridBottom - 13),
                        font: .system(size: 8.5), color: .pdfGray)

            canvas.endPage()
        }

        return canvas.finish()
    }

    // MARK: - Bullet List Formatter

    /// Formats an array of items into clean bullet points ("• Item")
    private static func formatBulletList(_ items: [String]) -> String {
        let clean = items
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !clean.isEmpty else { return "" }
        return clean.map { "• \($0)" }.joined(separator: "\n")
    }

    // MARK: - Dynamic Space Calculation

    /// Computes row heights dynamically:
    /// Description has a balanced, controlled height. Unused department rows collapse to 24pt,
    /// and active department rows receive the freed space proportionally for their bulleted lists.
    private static func computeDynamicRowHeights(for scene: Scene, totalHeight: CGFloat) -> [CGFloat] {
        let fixedRow0: CGFloat = 44 // Sheet # / Title / Scene #
        let fixedRow1: CGFloat = 48 // INT/EXT / Setting / Location
        
        // Controlled height for Description — ample space without ballooning
        let fixedRow2: CGFloat = scene.summary.count > 160 ? 90 : 76
        
        let availableForDepts = totalHeight - fixedRow0 - fixedRow1 - fixedRow2
        let compactHeight: CGFloat = 28 // Height for empty category rows
        
        let row3HasContent = !scene.cast.isEmpty || !scene.extras.isEmpty || !scene.wardrobe.isEmpty
        let row4HasContent = !scene.makeupHair.isEmpty || !scene.allProps.isEmpty || !scene.setDressing.isEmpty
        let row5HasContent = !scene.vehicles.isEmpty || !scene.allSpecialEquipment.isEmpty || !scene.stunts.isEmpty
        let row6HasContent = !scene.allSFX.isEmpty || !scene.vfx.isEmpty
        let row7HasContent = !scene.breakdownNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let w3: CGFloat = row3HasContent ? 100 : compactHeight
        let w4: CGFloat = row4HasContent ? 105 : compactHeight
        let w5: CGFloat = row5HasContent ? 90  : compactHeight
        let w6: CGFloat = row6HasContent ? 85  : compactHeight
        let w7: CGFloat = row7HasContent ? 80  : compactHeight

        let totalWeight = w3 + w4 + w5 + w6 + w7
        let scale = availableForDepts / totalWeight
        
        let r3 = w3 == compactHeight ? compactHeight : w3 * scale
        let r4 = w4 == compactHeight ? compactHeight : w4 * scale
        let r5 = w5 == compactHeight ? compactHeight : w5 * scale
        let r6 = w6 == compactHeight ? compactHeight : w6 * scale
        var r7 = w7 == compactHeight ? compactHeight : w7 * scale
        
        // Normalize any rounding difference on r7 (or largest active row)
        let currentTotal = fixedRow0 + fixedRow1 + fixedRow2 + r3 + r4 + r5 + r6 + r7
        let diff = totalHeight - currentTotal
        r7 += diff

        return [fixedRow0, fixedRow1, fixedRow2, r3, r4, r5, r6, r7]
    }

    // MARK: - Drawing Helpers

    private static func drawTwoUp(
        _ canvas: PDFCanvas,
        row: Int, rowTops: [CGFloat], rowHeights: [CGFloat], margin: CGFloat, contentWidth: CGFloat,
        a: (String, String, CGColor), b: (String, String, CGColor),
        labelSize: CGFloat = 10.0
    ) {
        let halfCol = contentWidth / 2
        var x = margin
        let h = rowHeights[row]
        let y = rowTops[row] - h
        drawCell(canvas, label: a.0, value: a.1, rect: CGRect(x: x, y: y, width: halfCol, height: h), labelColor: a.2, labelSize: labelSize)
        x += halfCol
        drawCell(canvas, label: b.0, value: b.1, rect: CGRect(x: x, y: y, width: contentWidth - halfCol, height: h), labelColor: b.2, labelSize: labelSize)
    }

    private static func drawThreeUp(
        _ canvas: PDFCanvas,
        row: Int, rowTops: [CGFloat], rowHeights: [CGFloat], margin: CGFloat, contentWidth: CGFloat,
        a: (String, String, CGColor), b: (String, String, CGColor), c: (String, String, CGColor),
        labelSize: CGFloat = 10.0
    ) {
        let thirdCol = contentWidth / 3
        var x = margin
        let h = rowHeights[row]
        let y = rowTops[row] - h
        drawCell(canvas, label: a.0, value: a.1, rect: CGRect(x: x, y: y, width: thirdCol, height: h), labelColor: a.2, labelSize: labelSize)
        x += thirdCol
        drawCell(canvas, label: b.0, value: b.1, rect: CGRect(x: x, y: y, width: thirdCol, height: h), labelColor: b.2, labelSize: labelSize)
        x += thirdCol
        drawCell(canvas, label: c.0, value: c.1, rect: CGRect(x: x, y: y, width: contentWidth - 2 * thirdCol, height: h), labelColor: c.2, labelSize: labelSize)
    }

    /// Draws one bordered cell with colored department header and dynamic auto-scaling text.
    private static func drawCell(
        _ canvas: PDFCanvas,
        label: String, value: String, rect: CGRect,
        valueSize: CGFloat = 9.0, valueBold: Bool = false, centered: Bool = false,
        labelColor: CGColor = defaultColor, labelSize: CGFloat = 10.0
    ) {
        canvas.stroke(rect, color: .pdfBlack, lineWidth: 1)

        canvas.clipped(to: rect) {
            let padH: CGFloat = 6
            let padV: CGFloat = 4
            let alignment: PDFCanvas.Alignment = centered ? .center : .leading
            var textTop = rect.maxY - padV

            if !label.isEmpty {
                let labelAvailWidth = max(rect.width - 2 * padH, 1)
                let labelHeight = labelSize + 5
                let labelRect = CGRect(x: rect.minX + padH, y: textTop - labelHeight, width: labelAvailWidth, height: labelHeight)
                canvas.draw(label, in: labelRect, font: .boldSystem(size: labelSize), color: labelColor, alignment: alignment)
                textTop -= (labelHeight + 3)
            }

            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanValue.isEmpty && textTop > rect.minY + padV {
                let availWidth  = max(rect.width - 2 * padH, 1)
                let availHeight = max(textTop - rect.minY - padV, 1)

                // Dynamic Font Auto-scaling to guarantee that text is large and never clipped.
                // The fit test is `boundingHeight`, the number `boundingRect` reported, which
                // runs a point short per line of what is then drawn at some sizes; keeping it
                // keeps every sheet at the size it always picked.
                func metrics(for size: CGFloat) -> (font: PDFFont, lineSpacing: CGFloat) {
                    (valueBold ? PDFFont.boldSystem(size: size) : PDFFont.system(size: size), max(1.5, size * 0.18))
                }
                let minSize: CGFloat = 7.0
                var currentSize = valueSize
                var (font, lineSpacing) = metrics(for: currentSize)

                while currentSize > minSize,
                      canvas.boundingHeight(of: cleanValue, font: font, width: availWidth, lineSpacing: lineSpacing) > availHeight {
                    currentSize -= 0.5
                    (font, lineSpacing) = metrics(for: currentSize)
                }

                let valueRect = CGRect(x: rect.minX + padH, y: rect.minY + padV,
                                       width: availWidth, height: availHeight)
                canvas.draw(cleanValue, in: valueRect, font: font, color: .pdfBlack, alignment: alignment, lineSpacing: lineSpacing)
            }
        }
    }

    /// Splits "12A. EXT. WOODS" into ("12A", "EXT", "WOODS")
    private static func parseSceneHeading(_ title: String) -> (number: String, intExt: String, setting: String) {
        var working = title.trimmingCharacters(in: .whitespaces)

        var number = ""
        if let regex = try? NSRegularExpression(pattern: #"^(\d+[A-Za-z]?)\.\s*"#),
           let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           let numRange = Range(match.range(at: 1), in: working) {
            number = String(working[numRange])
            if let fullRange = Range(match.range, in: working) {
                working.removeSubrange(fullRange)
            }
        }

        var intExt = ""
        let upper = working.uppercased()
        for prefix in ["INT./EXT.", "EXT./INT.", "INT.", "EXT."] {
            if upper.hasPrefix(prefix) {
                intExt = String(prefix.dropLast())
                working = String(working.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return (number, intExt, working)
    }
}

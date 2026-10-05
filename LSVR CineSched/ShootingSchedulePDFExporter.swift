// ShootingSchedulePDFExporter.swift
// Vector PDF exporter for the master Plan de Rodaje (Shooting Schedule / One-Line Schedule) directly from the Stripboard.
//
// Draws through PDFCanvas (CoreGraphics + CoreText), so it builds and runs on every
// platform. This exporter always placed its text by baseline with CTLineDraw; the
// `canvas.draw(_:at:…)` calls below are those same points, with the anchor and
// truncation options standing in for the old drawRightText / drawTextCentered /
// drawBoundedText helpers.

import SwiftUI

struct ShootingSchedulePDFExporter {

    private static func cleanSceneTitle(number: String, rawTitle: String) -> String {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespaces)
        if !number.isEmpty {
            let prefixes = ["\(number).", "\(number).-", "\(number) -", "\(number) ", "\(number))"]
            for p in prefixes {
                if cleaned.hasPrefix(p) {
                    cleaned = String(cleaned.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        if let match = cleaned.range(of: #"^\d+[\.\-\)\s]+\s*"#, options: .regularExpression) {
            let prefixStr = String(cleaned[match]).trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-) "))
            if prefixStr.isEmpty || prefixStr == number {
                cleaned = String(cleaned[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return cleaned
    }

    /// `shootDays` is the whole schedule, so the day numbers are the production's own;
    /// `printingDayIDs` narrows what prints (the Stripboard's per-day export), nil prints
    /// every day. Every strip's time comes from `dayTimeline`, the cascade the Stripboard
    /// and the phone show, so the printed times cannot drift from the board's: this file
    /// once had its own cascade that gave a zero-length banner 30 minutes, which put
    /// every slot after a synced day's General Call and Ready to Shoot strips an hour late.
    /// The rows are the board's strips and nothing else: the call sheet's times show in
    /// the day's header bar, never as rows the board does not have.
    static func generatePDF(
        shootDays: [ShootDay],
        printingDayIDs: Set<UUID>? = nil,
        projectTitle: String,
        productionInfo: ProductionInfo,
        palette: ScenePalette,
        options: ShootingSchedulePDFOptions = .default
    ) -> Data {
        let isSpanish = LocalizationManager.shared.currentLanguage == .spanish
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Standard US Letter Portrait (612 x 792 pt)
        guard let canvas = PDFCanvas(pageSize: pageRect.size) else {
            return Data()
        }

        let margin: CGFloat = 30
        let printableWidth = pageRect.width - (margin * 2) // 552pt

        var yPosition: CGFloat = pageRect.height - margin

        func startNewPage() {
            canvas.beginPage()
            yPosition = pageRect.height - margin

            drawTopHeader(
                canvas: canvas,
                margin: margin,
                width: printableWidth,
                projectTitle: projectTitle,
                productionInfo: productionInfo,
                pageNumber: canvas.pageCount,
                isSpanish: isSpanish,
                yPosition: &yPosition
            )
        }

        startNewPage()

        let productionNumbers = productionDayNumbers(for: shootDays)

        for dayIndex in 0..<shootDays.count {
            let day = shootDays[dayIndex]
            if let printingDayIDs, !printingDayIDs.contains(day.id) { continue }
            let dayNum = productionNumbers[day.id]

            if yPosition < margin + 90 {
                startNewPage()
            }

            // Calendar events are appointments, never work in the cascade (DayTimeline.swift).
            let strips   = day.scenes.filter { !$0.isCalendarEvent }
            let timeline = dayTimeline(for: day, scenes: strips)

            // The lunch: the call sheet's when typed, else where the board's lunch starts
            // (BoardTimes.swift).
            let calculatedLunchTime = day.effectiveLunchTime

            drawDayHeaderBar(
                canvas: canvas,
                margin: margin,
                width: printableWidth,
                day: day,
                dayNumber: dayNum ?? (dayIndex + 1),
                lunchTime: calculatedLunchTime,
                isSpanish: isSpanish,
                yPosition: &yPosition
            )

            for scene in strips {
                let rowH = scene.isBanner ? bannerRowHeight : SceneRowLines(scene: scene, options: options).height
                if yPosition - rowH < margin + 30 {
                    startNewPage()
                }

                let entry = timeline[scene.id]
                if scene.isBanner {
                    drawBannerRow(
                        canvas: canvas,
                        margin: margin,
                        width: printableWidth,
                        scene: scene,
                        timeRange: entry?.timeDisplay ?? "",
                        isSpanish: isSpanish,
                        yPosition: &yPosition
                    )
                } else {
                    drawSceneRow(
                        canvas: canvas,
                        margin: margin,
                        width: printableWidth,
                        scene: scene,
                        palette: palette,
                        timeRange: entry?.timeDisplay ?? "",
                        estimate: entry?.durStr ?? "",
                        options: options,
                        isSpanish: isSpanish,
                        yPosition: &yPosition
                    )
                }
            }

            if yPosition < margin + 30 {
                startNewPage()
            }

            let endTimeStr = strips.last.flatMap { timeline[$0.id]?.endStr } ?? formatMinutesToClock(dayStartMinutes(for: day))
            drawEndOfDayStrip(
                canvas: canvas,
                margin: margin,
                width: printableWidth,
                day: day,
                dayNumber: dayNum ?? (dayIndex + 1),
                endTimeStr: endTimeStr,
                isSpanish: isSpanish,
                yPosition: &yPosition
            )

            yPosition -= 12
        }

        return canvas.finish()
    }

    // MARK: - Top Header (Matching Screenshot Layout)

    private static func drawTopHeader(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        projectTitle: String,
        productionInfo: ProductionInfo,
        pageNumber: Int,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let titleStr = projectTitle.isEmpty ? "LA VIDA EDITADA" : projectTitle.uppercased()
        let companyStr = productionInfo.companyName.isEmpty ? "Promo 8" : productionInfo.companyName
        let schedLabel = isSpanish ? "PLAN DE RODAJE" : "SHOOTING SCHEDULE"
        let subStr = "\(schedLabel) — \(companyStr)"

        // Left Side Title
        let fontTitle = PDFFont.boldSystem(size: 16)
        let fontSub = PDFFont.system(size: 9.5)
        let textColor = CGColor.hex("1F2937")
        let subColor = CGColor.hex("6B7280")

        canvas.draw(titleStr, at: CGPoint(x: margin, y: yPosition - 16), font: fontTitle, color: textColor)
        canvas.draw(subStr, at: CGPoint(x: margin, y: yPosition - 30), font: fontSub, color: subColor)

        // Right Side Metadata (Page and Date)
        let df = DateFormatter()
        df.locale = appLocale()
        df.dateFormat = isSpanish ? "d 'de' MMMM, yyyy" : "MMMM d, yyyy"
        let dateStr = "\(isSpanish ? "EMISIÓN:" : "DATE:") \(df.string(from: Date()))"
        let pageStr = isSpanish ? "PÁGINA \(pageNumber)" : "PAGE \(pageNumber)"

        canvas.draw(pageStr, at: CGPoint(x: margin + width, y: yPosition - 16), font: fontSub, color: subColor, anchor: .trailing)
        canvas.draw(dateStr, at: CGPoint(x: margin + width, y: yPosition - 30), font: fontSub, color: subColor, anchor: .trailing)

        yPosition -= 36

        // Horizontal Line Separator
        canvas.line(from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: margin + width, y: yPosition),
                    color: .hex("374151"), lineWidth: 1.5)

        yPosition -= 14
    }

    // MARK: - Day Header Bar

    private static func drawDayHeaderBar(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        day: ShootDay,
        dayNumber: Int,
        lunchTime: String,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let rowH: CGFloat = 22
        let rect = CGRect(x: margin, y: yPosition - rowH, width: width, height: rowH)

        // Dark Slate Blue Background (#2E4057)
        canvas.fill(rect, color: CGColor(red: 0.18, green: 0.25, blue: 0.34, alpha: 1.0))

        let df = DateFormatter()
        df.locale = appLocale()
        df.dateFormat = isSpanish ? "EEEE, d 'de' MMMM 'de' yyyy" : "EEEE, MMMM d, yyyy"
        let dateStr = df.string(from: day.date).capitalized

        let shootDayPrefix = isSpanish ? "DÍA DE RODAJE" : "SHOOT DAY"
        let headerText = "\(shootDayPrefix) #\(dayNumber) — \(dateStr)"

        let font = PDFFont.boldSystem(size: 9.5)
        canvas.draw(headerText, at: CGPoint(x: margin + 8, y: yPosition - 15), font: font, color: .pdfWhite)

        // Crew Call, Set Call, Lunch Time on right side
        var milestones: [String] = []
        if !day.callSheet.generalCallTime.isEmpty {
            let label = isSpanish ? "LLEGADA:" : "CREW CALL:"
            milestones.append("🚌 \(label) \(day.callSheet.generalCallTime)")
        }
        if !day.callSheet.readyToShootTime.isEmpty {
            milestones.append("🎬 SET: \(day.callSheet.readyToShootTime)")
        }
        if !lunchTime.isEmpty {
            milestones.append("🍽️ \(lunchTime)")
        }

        let milesStr = milestones.joined(separator: "  |  ")
        if !milesStr.isEmpty {
            canvas.draw(milesStr, at: CGPoint(x: margin + width - 8, y: yPosition - 15), font: .boldSystem(size: 9), color: .pdfWhite, anchor: .trailing)
        }

        yPosition -= rowH
    }

    // MARK: - Scene Row Strip (Time, Scene Title, Estimate & Eighths; the Cast Underneath)

    private static let bannerRowHeight: CGFloat = 20

    /// What a scene row prints under its title: the cast, the shot count (right-aligned on
    /// the cast's line) and the description, each only when the scene has one and the
    /// options ask for it. Each extra line adds 10 pt to the row.
    private struct SceneRowLines {
        let cast:        String
        let shotCount:   String
        let description: String

        init(scene: Scene, options: ShootingSchedulePDFOptions) {
            cast = scene.cast
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            shotCount = options.includeShotCount ? StripboardField.shotCount(scene.shots.count) : ""
            // One line: the summary's line breaks would otherwise run off the row.
            description = options.includeDescription
                ? scene.summary.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                : ""
        }

        var hasCastLine: Bool { !cast.isEmpty || !shotCount.isEmpty }
        var lineCount:   Int  { 1 + (hasCastLine ? 1 : 0) + (description.isEmpty ? 0 : 1) }
        var height:      CGFloat { 22 + CGFloat(lineCount - 1) * 10 }
    }

    private static func drawSceneRow(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        scene: Scene,
        palette: ScenePalette,
        timeRange: String,
        estimate: String,
        options: ShootingSchedulePDFOptions,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let lines = SceneRowLines(scene: scene, options: options)
        let rowH = lines.height
        let rowY = yPosition - rowH
        let rect = CGRect(x: margin, y: rowY, width: width, height: rowH)

        // Background color matching strip color
        canvas.fill(rect, color: .of(scene.stripColor(in: palette)))

        let textColor = CGColor.hex("1F2937")

        let col1W: CGFloat = 112
        let xCol1 = margin + 4
        let xCol2 = xCol1 + col1W + 8
        let xEstimate = margin + width - 62   // right edge of the estimate
        let xCol4 = margin + width - 6        // right edge of the eighths

        // 1. Time Badge (centered on the row, across both lines)
        if !timeRange.isEmpty {
            let timeRect = CGRect(x: xCol1, y: rowY + (rowH - 16) / 2, width: col1W, height: 16)
            canvas.fill(timeRect, color: CGColor.pdfBlack.withAlpha(0.08))
            drawTextCentered(timeRange, in: timeRect, font: .boldSystem(size: 7.5), color: textColor.withAlpha(0.85), canvas: canvas)
        }

        // 2. Scene Number + Clean Full Title
        let rawNum = scene.sceneNumber.isEmpty ? scene.extractedSceneNumber : scene.sceneNumber
        let cleanTitle = cleanSceneTitle(number: rawNum, rawTitle: scene.title)
        let fullTitle = rawNum.isEmpty ? cleanTitle : "\(rawNum). \(cleanTitle)"
        let maxTitleW = (xEstimate - 58) - xCol2

        canvas.draw(fullTitle, at: CGPoint(x: xCol2, y: yPosition - 15), font: .boldSystem(size: 9), color: textColor, maxWidth: maxTitleW)

        // 3. The cascade's duration for the strip
        if !estimate.isEmpty {
            canvas.draw("Est: \(estimate)", at: CGPoint(x: xEstimate, y: yPosition - 15), font: .system(size: 8.5), color: textColor.withAlpha(0.8), anchor: .trailing)
        }

        // 4. Page Duration in Eighths (Right Aligned)
        let eighthsUnit = isSpanish ? "pág" : "pgs"
        let eighthsStr = "\(formattedEighths(scene.duration)) \(eighthsUnit)"
        canvas.draw(eighthsStr, at: CGPoint(x: xCol4, y: yPosition - 15), font: .boldSystem(size: 9), color: textColor, anchor: .trailing)

        // 5. The cast under the title, with the shot count at the estimate's edge
        var lineY = yPosition - 26
        if lines.hasCastLine {
            let castMaxW = (lines.shotCount.isEmpty ? xCol4 : xEstimate - 50) - xCol2
            if !lines.cast.isEmpty {
                canvas.draw(lines.cast, at: CGPoint(x: xCol2, y: lineY), font: .system(size: 8), color: textColor.withAlpha(0.8), maxWidth: castMaxW)
            }
            if !lines.shotCount.isEmpty {
                canvas.draw(lines.shotCount, at: CGPoint(x: xEstimate, y: lineY), font: .system(size: 8), color: textColor.withAlpha(0.8), anchor: .trailing)
            }
            lineY -= 10
        }

        // 6. The description, one line
        if !lines.description.isEmpty {
            canvas.draw(lines.description, at: CGPoint(x: xCol2, y: lineY), font: .italicSystem(size: 8), color: textColor.withAlpha(0.75), maxWidth: xCol4 - xCol2)
        }

        // Bottom border line
        drawRowBorder(canvas: canvas, margin: margin, width: width, y: rowY)

        yPosition -= rowH
    }

    // MARK: - Banner / Notice Row Strip

    private static func drawBannerRow(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        scene: Scene,
        timeRange: String,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let rowH = bannerRowHeight
        let rowY = yPosition - rowH
        let rect = CGRect(x: margin, y: rowY, width: width, height: rowH)

        // The strip the Stripboard draws: its fill and its label are `BannerAppearance.swift`'s,
        // white text on the banner's own color. This row once styled a banner by the words
        // in its title (a light amber, blue, green or grey of its own) and folded any title
        // containing "set call", "note", "lunch" or "crew call" to that word alone, so a
        // "HICCUP SET CALL" banner printed as "SET CALL" in a color the board never showed.
        let fillColor = CGColor.hex(scene.bannerFillHex)
        let textColor = CGColor.pdfWhite
        canvas.fill(rect, color: fillColor)

        let col1W: CGFloat = 112
        let xCol1 = margin + 6
        let xCol2 = xCol1 + col1W + 8

        if !timeRange.isEmpty {
            let timeRect = CGRect(x: xCol1, y: rowY + 3, width: col1W, height: rowH - 6)
            canvas.fill(timeRect, color: CGColor.pdfBlack.withAlpha(0.32))
            drawTextCentered(timeRange, in: timeRect, font: .boldSystem(size: 7.5), color: textColor, canvas: canvas)
        }

        let titleText = scene.bannerDisplayLabel.uppercased()
        let maxTitleW = width - (col1W + 90)
        canvas.draw(titleText, at: CGPoint(x: xCol2, y: yPosition - 14), font: .boldSystem(size: 8.5), color: textColor, maxWidth: maxTitleW)

        // Right side estimated duration
        if scene.estimatedTime > 0 {
            let timeHM = formattedTimeHM(scene.estimatedTime)
            canvas.draw("Est: \(timeHM)", at: CGPoint(x: margin + width - 8, y: yPosition - 14), font: .boldSystem(size: 8.5), color: textColor, anchor: .trailing)
        }

        // Bottom border line
        drawRowBorder(canvas: canvas, margin: margin, width: width, y: rowY)

        yPosition -= rowH
    }

    // MARK: - End of Day Strip

    private static func drawEndOfDayStrip(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        day: ShootDay,
        dayNumber: Int,
        endTimeStr: String,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let rowH: CGFloat = 20
        let rowY = yPosition - rowH
        let rect = CGRect(x: margin, y: rowY, width: width, height: rowH)

        canvas.fill(rect, color: .hex("E5E7EB"))

        let df = DateFormatter()
        df.locale = appLocale()
        df.dateFormat = isSpanish ? "EEEE, d 'de' MMMM" : "EEEE, MMMM d"
        let fullDate = df.string(from: day.date).capitalized

        let wrapLabel = isSpanish ? "FIN DE JORNADA:" : "WRAP:"
        let totalPagesLabel = isSpanish ? "TOTAL PÁGINAS:" : "TOTAL PAGES:"
        let totalTimeLabel = isSpanish ? "TIEMPO EST.:" : "EST. TIME:"
        let endDayPrefix = isSpanish ? "FIN DEL DÍA" : "END OF DAY"

        let wrapText = day.effectiveWrapTime.isEmpty ? endTimeStr : day.effectiveWrapTime
        let footerText = "-- \(endDayPrefix) #\(dayNumber) \(fullDate) -- \(wrapLabel) \(wrapText) -- \(totalPagesLabel) \(formattedEighths(day.totalDuration)) -- \(totalTimeLabel) \(formattedTimeHM(day.totalEstimatedTime)) --"
        drawTextCentered(footerText, in: rect, font: .boldSystem(size: 8.5), color: .hex("374151"), canvas: canvas)

        yPosition -= rowH
    }

    // MARK: - Drawing Helpers

    /// Centers a single line in `rect`, with the baseline a third of the point size
    /// below the vertical middle (a cheap optical centering for all-caps labels).
    private static func drawTextCentered(_ text: String, in rect: CGRect, font: PDFFont, color: CGColor, canvas: PDFCanvas) {
        canvas.draw(text, at: CGPoint(x: rect.midX, y: rect.midY - (font.pointSize / 3)), font: font, color: color, anchor: .center)
    }

    private static func drawRowBorder(canvas: PDFCanvas, margin: CGFloat, width: CGFloat, y: CGFloat) {
        canvas.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y),
                    color: CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0), lineWidth: 0.5)
    }
}

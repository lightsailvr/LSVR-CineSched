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

    private static func cleanBannerTitle(_ rawTitle: String) -> String {
        let isSpanish = LocalizationManager.shared.currentLanguage == .spanish
        // Strip any hardcoded parenthesized times like "(01:30 PM)" or "(07:30 AM)"
        var clean = rawTitle.replacingOccurrences(of: #"\s*\(\s*\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?\s*\)"#, with: "", options: .regularExpression)
        // Strip any existing leading emojis like 🍽️, 🍽, 🍴, 🚌, 🎬
        clean = clean.replacingOccurrences(of: #"^[🍽🍴🚌🎬\s]+"#, with: "", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespaces)

        // Translate typical bilingual or default banner titles
        let lower = clean.lowercased()
        if lower.contains("almuerzo") || lower.contains("lunch") {
            return isSpanish ? "ALMUERZO" : "LUNCH"
        }
        if lower.contains("llegada") || lower.contains("crew call") {
            return isSpanish ? "LLEGADA DEL EQUIPO" : "CREW CALL"
        }
        if lower.contains("inicio") || lower.contains("set call") {
            return isSpanish ? "INICIO DE RODAJE" : "SET CALL"
        }
        if lower.contains("merienda") || lower.contains("snack") {
            return isSpanish ? "MERIENDA" : "SNACK"
        }
        if lower.contains("cena") || lower.contains("dinner") {
            return isSpanish ? "CENA" : "DINNER"
        }
        if lower.contains("aviso") || lower.contains("notice") || lower.contains("note") {
            return isSpanish ? "AVISO" : "NOTICE"
        }
        return clean
    }

    static func generatePDF(
        shootDays: [ShootDay],
        projectTitle: String,
        productionInfo: ProductionInfo,
        palette: ScenePalette
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
        var cumulativeEighths = 0

        for dayIndex in 0..<shootDays.count {
            let day = shootDays[dayIndex]
            let dayNum = productionNumbers[day.id]

            if yPosition < margin + 90 {
                startNewPage()
            }

            // Find actual calculated lunch time from scheduled scenes if available
            var calculatedLunchTime: String = day.callSheet.lunchTime
            var currentTimeMinutes: Int = parseTimeToMinutes(day.callSheet.readyToShootTime.isEmpty ? (day.callSheet.generalCallTime.isEmpty ? "07:30 AM" : day.callSheet.generalCallTime) : day.callSheet.readyToShootTime) ?? (7 * 60 + 30)

            var runningMin = currentTimeMinutes
            for s in day.scenes.filter({ !$0.isCalendarEvent }) {
                if !s.customStartTime.isEmpty, let customMin = parseTimeToMinutes(s.customStartTime) {
                    runningMin = customMin
                }
                let isMeal = s.title.lowercased().contains("almuerzo") || s.title.lowercased().contains("lunch") || s.isAutoMeal
                if isMeal {
                    calculatedLunchTime = formatMinutesToClock(runningMin)
                }
                let dur = s.estimatedTime > 0 ? s.estimatedTime : (s.isBanner ? 30 : 15)
                runningMin += dur
            }

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

            // Render CallSheet Milestones if present
            if !day.callSheet.generalCallTime.isEmpty {
                let callTime = day.callSheet.generalCallTime
                let title = isSpanish ? "LLEGADA DEL EQUIPO" : "CREW CALL"
                let crewCallScene = Scene.createBanner(type: .notice, title: title, note: callTime, estimatedTime: "0:15", colorHex: "3B82F6")
                drawBannerRow(
                    canvas: canvas,
                    margin: margin,
                    width: printableWidth,
                    scene: crewCallScene,
                    timeRange: callTime,
                    isSpanish: isSpanish,
                    yPosition: &yPosition
                )
            }
            if !day.callSheet.readyToShootTime.isEmpty {
                let setTime = day.callSheet.readyToShootTime
                let title = isSpanish ? "INICIO DE RODAJE" : "SET CALL"
                let readyScene = Scene.createBanner(type: .notice, title: title, note: setTime, estimatedTime: "0:15", colorHex: "10B981")
                drawBannerRow(
                    canvas: canvas,
                    margin: margin,
                    width: printableWidth,
                    scene: readyScene,
                    timeRange: setTime,
                    isSpanish: isSpanish,
                    yPosition: &yPosition
                )
            }

            for scene in day.scenes.filter({ !$0.isCalendarEvent }) {
                let rowH: CGFloat = 24
                if yPosition - rowH < margin + 30 {
                    startNewPage()
                }

                if !scene.customStartTime.isEmpty, let customMin = parseTimeToMinutes(scene.customStartTime) {
                    currentTimeMinutes = customMin
                }

                let startClock = formatMinutesToClock(currentTimeMinutes)
                let durMinutes = scene.estimatedTime > 0 ? scene.estimatedTime : (scene.isBanner ? 30 : 15)
                let endClock = formatMinutesToClock(currentTimeMinutes + durMinutes)
                let timeRange = "\(startClock) – \(endClock)"

                // Estimated script page calculation
                let scriptPageNum = max(1, (cumulativeEighths / 8) + 1)
                cumulativeEighths += scene.duration

                if scene.isBanner {
                    drawBannerRow(
                        canvas: canvas,
                        margin: margin,
                        width: printableWidth,
                        scene: scene,
                        timeRange: timeRange,
                        isSpanish: isSpanish,
                        yPosition: &yPosition
                    )
                    currentTimeMinutes += durMinutes
                } else {
                    drawSceneRow(
                        canvas: canvas,
                        margin: margin,
                        width: printableWidth,
                        scene: scene,
                        palette: palette,
                        timeRange: timeRange,
                        scriptPageNumber: scriptPageNum,
                        isSpanish: isSpanish,
                        yPosition: &yPosition
                    )
                    currentTimeMinutes += durMinutes
                }
            }

            if yPosition < margin + 30 {
                startNewPage()
            }

            let endTimeStr = formatMinutesToClock(currentTimeMinutes)
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

    // MARK: - Scene Row Strip (Full Width for Scene Title / Description, Script Page & Eighths)

    private static func drawSceneRow(
        canvas: PDFCanvas,
        margin: CGFloat,
        width: CGFloat,
        scene: Scene,
        palette: ScenePalette,
        timeRange: String,
        scriptPageNumber: Int,
        isSpanish: Bool,
        yPosition: inout CGFloat
    ) {
        let rowH: CGFloat = 22
        let rowY = yPosition - rowH
        let rect = CGRect(x: margin, y: rowY, width: width, height: rowH)

        // Background color matching strip color
        canvas.fill(rect, color: .of(scene.stripColor(in: palette)))

        let textColor = CGColor.hex("1F2937")

        let col1W: CGFloat = 112
        let xCol1 = margin + 4
        let xCol2 = xCol1 + col1W + 8
        let xCol3 = margin + width - 114
        let xCol4 = margin + width - 6

        // 1. Time Badge
        if !timeRange.isEmpty {
            let timeRect = CGRect(x: xCol1, y: rowY + 3, width: col1W, height: rowH - 6)
            canvas.fill(timeRect, color: CGColor.pdfBlack.withAlpha(0.08))
            drawTextCentered(timeRange, in: timeRect, font: .boldSystem(size: 7.5), color: textColor.withAlpha(0.85), canvas: canvas)
        }

        // 2. Scene Number + Clean Full Title
        let rawNum = scene.sceneNumber.isEmpty ? scene.extractedSceneNumber : scene.sceneNumber
        let cleanTitle = cleanSceneTitle(number: rawNum, rawTitle: scene.title)
        let fullTitle = rawNum.isEmpty ? cleanTitle : "\(rawNum). \(cleanTitle)"
        let maxTitleW = (xCol3 - 10) - xCol2

        canvas.draw(fullTitle, at: CGPoint(x: xCol2, y: yPosition - 15), font: .boldSystem(size: 9), color: textColor, maxWidth: maxTitleW)

        // 3. Script Page (Fixed Column)
        let pageStr = isSpanish ? "Pág. \(scriptPageNumber)" : "Pg. \(scriptPageNumber)"
        canvas.draw(pageStr, at: CGPoint(x: xCol3, y: yPosition - 15), font: .system(size: 8.5), color: textColor.withAlpha(0.8))

        // 4. Page Duration in Eighths (Right Aligned)
        let eighthsUnit = isSpanish ? "pág" : "pgs"
        let eighthsStr = "\(formattedEighths(scene.duration)) \(eighthsUnit)"
        canvas.draw(eighthsStr, at: CGPoint(x: xCol4, y: yPosition - 15), font: .boldSystem(size: 9), color: textColor, anchor: .trailing)

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
        let rowH: CGFloat = 20
        let rowY = yPosition - rowH
        let rect = CGRect(x: margin, y: rowY, width: width, height: rowH)

        let isMeal = scene.title.lowercased().contains("almuerzo") || scene.title.lowercased().contains("lunch") || scene.isAutoMeal
        let isCrewCall = scene.title.lowercased().contains("llegada") || scene.title.lowercased().contains("crew call")
        let isSetCall = scene.title.lowercased().contains("inicio") || scene.title.lowercased().contains("set call")

        let bannerBgColor: CGColor
        let accentColor: CGColor
        let textColor: CGColor

        if isMeal {
            bannerBgColor = .hex("FEF3C7")
            accentColor = .hex("D97706")
            textColor = .hex("B45309")
        } else if isCrewCall {
            bannerBgColor = .hex("EFF6FF")
            accentColor = .hex("3B82F6")
            textColor = .hex("1D4ED8")
        } else if isSetCall {
            bannerBgColor = .hex("ECFDF5")
            accentColor = .hex("10B981")
            textColor = .hex("047857")
        } else {
            bannerBgColor = .hex("E5E7EB")
            accentColor = .hex("4B5563")
            textColor = .hex("374151")
        }

        // Tinted background
        canvas.fill(rect, color: bannerBgColor)

        // 4pt left accent bar
        canvas.fill(CGRect(x: margin, y: rowY, width: 4, height: rowH), color: accentColor)

        let col1W: CGFloat = 112
        let xCol1 = margin + 6
        let xCol2 = xCol1 + col1W + 8

        if !timeRange.isEmpty {
            let timeRect = CGRect(x: xCol1, y: rowY + 3, width: col1W, height: rowH - 6)
            canvas.fill(timeRect, color: accentColor.withAlpha(0.14))
            drawTextCentered(timeRange, in: timeRect, font: .boldSystem(size: 7.5), color: textColor, canvas: canvas)
        }

        // Cleaned and localized title
        let cleanedTitle = cleanBannerTitle(scene.title)
        let icon = isMeal ? "🍽️ " : (isCrewCall ? "🚌 " : (isSetCall ? "🎬 " : ""))
        let titleText = "\(icon)\(cleanedTitle.uppercased())"
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

        let wrapText = day.callSheet.wrapTime.isEmpty ? endTimeStr : day.callSheet.wrapTime
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

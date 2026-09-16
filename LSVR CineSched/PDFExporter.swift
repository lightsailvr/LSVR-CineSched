// PDFExporter.swift
// Generates a landscape US Letter PDF calendar from shoot data
//
// Draws through PDFCanvas (CoreGraphics + CoreText), so it builds and runs on every
// platform. The rects handed to `canvas.draw(_:in:…)` are the ones the AppKit version
// handed to `NSAttributedString.draw(in:)`, and `draw(_:lineOrigin:…)` takes the points
// `draw(at:)` took; PDFCanvas lays text out in them the way TextKit did, which is what
// keeps the output identical — pixel for pixel, apart from lines cut with "…", which
// TextKit tracked tighter (verified by pixel-diffing the fixture exports, #5).

import SwiftUI

// MARK: - PDFExporter

class PDFExporter {

    static func generatePDF(
        shootDays: [ShootDay],
        projectTitle: String,
        allScenes: [Scene],
        startDate: Date,
        endDate: Date
    ) -> Data? {

        let pageWidth:  CGFloat = 792   // US Letter landscape
        let pageHeight: CGFloat = 612
        let margin:     CGFloat = 40

        let contentRect = CGRect(
            x: margin, y: margin,
            width:  pageWidth  - 2 * margin,
            height: pageHeight - 2 * margin
        )

        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        let weeks      = groupDaysIntoWeeks(shootDays)
        let rowHeights = calculateIdealRowHeights(weeks: weeks)
        let cellWidth  = contentRect.width / 7
        let dayNumbers = productionDayNumbers(for: shootDays)

        var pageNumber = 0
        var weekIndex  = 0
        var currentY   = contentRect.maxY

        while weekIndex < weeks.count {
            pageNumber += 1
            canvas.beginPage()

            // Header on first page only
            if pageNumber == 1 {
                let headerHeight: CGFloat = 50
                let headerRect = CGRect(
                    x: contentRect.minX,
                    y: contentRect.maxY - headerHeight,
                    width: contentRect.width,
                    height: headerHeight
                )
                drawHeader(
                    on: canvas,
                    in: headerRect,
                    projectTitle: projectTitle,
                    startDate: startDate,
                    endDate: endDate,
                    allScenes: allScenes,
                    shootDays: shootDays
                )
                currentY = contentRect.maxY - headerHeight - 10
            } else {
                currentY = contentRect.maxY
            }

            var horizontalLines: [CGFloat] = [currentY]

            while weekIndex < weeks.count {
                let rowHeight = rowHeights[weekIndex]
                guard currentY - rowHeight >= contentRect.minY + 10 else { break }

                let rowRect = CGRect(
                    x: contentRect.minX,
                    y: currentY - rowHeight,
                    width: contentRect.width,
                    height: rowHeight
                )
                drawWeekRow(on: canvas, week: weeks[weekIndex], in: rowRect, cellWidth: cellWidth, dayNumbers: dayNumbers)
                currentY -= rowHeight
                horizontalLines.append(currentY)
                weekIndex += 1
            }

            drawGridLines(
                on: canvas,
                horizontalLines: horizontalLines,
                minX: contentRect.minX, maxX: contentRect.maxX,
                minY: contentRect.minY, maxY: contentRect.maxY
            )

            canvas.endPage()
        }

        return canvas.finish()
    }

    // MARK: - Private Drawing Helpers

    private static func drawHeader(
        on canvas: PDFCanvas,
        in rect: CGRect,
        projectTitle: String,
        startDate: Date,
        endDate: Date,
        allScenes: [Scene],
        shootDays: [ShootDay]
    ) {
        let displayTitle = projectTitle.isEmpty ? "Untitled Movie" : projectTitle
        canvas.draw(displayTitle, in: CGRect(x: rect.minX, y: rect.maxY - 25, width: rect.width, height: 25),
                    font: .boldSystem(size: 14), color: .pdfBlack)

        let scheduled = shootDays.filter { !$0.scenes.isEmpty }.count
        canvas.draw("Shoot Days: \(scheduled)", in: CGRect(x: rect.minX, y: rect.maxY - 50, width: rect.width, height: 20),
                    font: .system(size: 10), color: .pdfGray)
    }

    private static func calculateIdealRowHeights(weeks: [[ShootDay?]]) -> [CGFloat] {
        let minHeight: CGFloat = 50
        let maxHeight: CGFloat = 160

        return weeks.map { week in
            let maxScenes     = week.compactMap { $0 }.map(\.scenes.count).max() ?? 0
            let contentHeight = 40 + CGFloat(maxScenes) * 11
            return min(max(contentHeight + 20, minHeight), maxHeight)
        }
    }

    private static func drawWeekRow(on canvas: PDFCanvas, week: [ShootDay?], in rowRect: CGRect, cellWidth: CGFloat, dayNumbers: [UUID: Int]) {
        for (col, day) in week.enumerated() {
            let cellRect = CGRect(
                x: rowRect.minX + CGFloat(col) * cellWidth,
                y: rowRect.minY,
                width: cellWidth,
                height: rowRect.height
            )
            if let day = day { drawDay(on: canvas, day: day, in: cellRect, dayNumber: dayNumbers[day.id]) }
        }
    }

    private static func drawGridLines(
        on canvas: PDFCanvas,
        horizontalLines: [CGFloat],
        minX: CGFloat, maxX: CGFloat,
        minY: CGFloat, maxY: CGFloat
    ) {
        guard !horizontalLines.isEmpty else { return }

        let top    = horizontalLines.first ?? maxY
        let bottom = horizontalLines.last  ?? minY

        // Vertical lines spanning actual calendar content only
        for i in 0...7 {
            let x = minX + CGFloat(i) * ((maxX - minX) / 7)
            canvas.line(from: CGPoint(x: x, y: bottom), to: CGPoint(x: x, y: top), color: .pdfLightGray, lineWidth: 0.5)
        }

        // Horizontal row separators
        for y in horizontalLines {
            canvas.line(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y), color: .pdfLightGray, lineWidth: 0.5)
        }
    }

    private static func drawDay(on canvas: PDFCanvas, day: ShootDay, in rect: CGRect, dayNumber: Int?) {
        let padding = CGFloat(8)
        let content = CGRect(
            x: rect.minX + padding, y: rect.minY + padding,
            width:  rect.width  - 2 * padding,
            height: rect.height - 2 * padding
        )

        // Date header (top of cell)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E MMM d"
        canvas.draw(dateFormatter.string(from: day.date), in: CGRect(x: content.minX, y: content.maxY - 12, width: content.width, height: 12),
                    font: .boldSystem(size: 10), color: .pdfBlack)

        // Production day number, right-justified — matches the on-screen calendar
        if let dayNumber {
            canvas.draw("Day \(dayNumber)", in: CGRect(x: content.minX, y: content.maxY - 12, width: content.width, height: 12),
                        font: .system(size: 8), color: .gray(0.4), alignment: .trailing)
        }

        // Scene strips
        let boxHeight: CGFloat = 11
        let sceneFont          = PDFFont.system(size: 8)

        var yOffset: CGFloat = 16
        for scene in day.scenes {
            let boxRect = CGRect(
                x: content.minX,
                y: content.maxY - yOffset - boxHeight,
                width: content.width,
                height: boxHeight
            )

            canvas.fill(boxRect, cornerRadius: 2, color: scene.dayNightType == .night ? .gray(0.9) : .pdfWhite)
            canvas.stroke(boxRect, cornerRadius: 2, color: .pdfLightGray, lineWidth: 0.5)

            let textHeight = sceneFont.lineHeight
            let textRect   = CGRect(
                x: content.minX + 3,
                y: content.maxY - yOffset - boxHeight + (boxHeight - textHeight) / 2,
                width: content.width - 6,
                height: textHeight
            )
            canvas.draw(scene.displayTitle, in: textRect, font: sceneFont, color: .pdfBlack, lineBreak: .truncateTail)
            yOffset += boxHeight
        }

        // Totals at bottom
        if !day.scenes.isEmpty {
            let totalText = "Total: \(formattedEighths(day.totalDuration))\nEst: \(formattedTime(day.totalEstimatedTime))"
            canvas.draw(totalText, in: CGRect(x: content.minX, y: content.minY, width: content.width, height: 20),
                        font: .system(size: 7), color: .pdfGray)
        }
    }

    private static func groupDaysIntoWeeks(_ shootDays: [ShootDay]) -> [[ShootDay?]] {
        guard !shootDays.isEmpty else { return [] }

        let cal  = Calendar.current
        var weeks: [[ShootDay?]] = []
        var week = Array(repeating: ShootDay?.none, count: 7)

        var date = cal.startOfDay(for: shootDays.first!.date)
        let end  = cal.startOfDay(for: shootDays.last!.date)
        var idx  = 0

        while date <= end {
            let weekday = cal.component(.weekday, from: date) - 1 // 0 = Sun

            let match = (idx < shootDays.count && cal.isDate(shootDays[idx].date, inSameDayAs: date))
                ? shootDays[idx] : nil
            if match != nil { idx += 1 }

            week[weekday] = match ?? ShootDay(date: date)

            if weekday == 6 || date == end {
                weeks.append(week)
                week = Array(repeating: nil, count: 7)
            }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return weeks
    }

    // MARK: - Monthly Calendar PDF Generator

    static func generateMonthPDF(
        month: Date,
        shootDays: [ShootDay],
        projectTitle: String,
        productionInfo: ProductionInfo,
        options: MonthPDFOptions = .default
    ) -> Data? {
        let pageWidth:  CGFloat = 792   // US Letter landscape
        let pageHeight: CGFloat = 612
        let margin:     CGFloat = 36

        let contentRect = CGRect(
            x: margin, y: margin,
            width:  pageWidth  - 2 * margin,
            height: pageHeight - 2 * margin
        )

        let cal = Calendar.current
        let monthComps = cal.dateComponents([.year, .month], from: month)
        guard let startOfMonth = cal.date(from: monthComps),
              let dayRange = cal.range(of: .day, in: .month, for: startOfMonth) else { return nil }

        let dayNumbers = productionDayNumbers(for: shootDays)

        // Build month weeks (Sunday-based: 0=Sun, 6=Sat)
        var monthWeeks: [[(date: Date, shootDay: ShootDay?)]] = []
        var currentWeek: [(date: Date, shootDay: ShootDay?)] = []

        let firstWeekday = cal.component(.weekday, from: startOfMonth) // 1=Sun, 2=Mon...
        let leadingEmpty = firstWeekday - 1 // Sunday=0

        // Fill leading empty days from previous month
        for i in (0..<leadingEmpty).reversed() {
            if let prevDate = cal.date(byAdding: .day, value: -(i + 1), to: startOfMonth) {
                let match = shootDays.first(where: { cal.isDate($0.date, inSameDayAs: prevDate) })
                currentWeek.append((date: prevDate, shootDay: match))
            }
        }

        // Fill month days
        for d in dayRange {
            if let date = cal.date(byAdding: .day, value: d - 1, to: startOfMonth) {
                let match = shootDays.first(where: { cal.isDate($0.date, inSameDayAs: date) })
                currentWeek.append((date: date, shootDay: match))
                if currentWeek.count == 7 {
                    monthWeeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }

        // Fill trailing empty days
        if !currentWeek.isEmpty {
            var nextD = 1
            while currentWeek.count < 7 {
                let lastDate = startOfMonth
                if let nextDate = cal.date(byAdding: .month, value: 1, to: lastDate),
                   let trailDate = cal.date(byAdding: .day, value: nextD - 1, to: nextDate) {
                    let match = shootDays.first(where: { cal.isDate($0.date, inSameDayAs: trailDate) })
                    currentWeek.append((date: trailDate, shootDay: match))
                }
                nextD += 1
            }
            monthWeeks.append(currentWeek)
        }

        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        canvas.beginPage()

        // Header (Month & Year + Project info)
        let headerHeight: CGFloat = 46
        let headerRect = CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - headerHeight,
            width: contentRect.width,
            height: headerHeight
        )

        let isSpanish = LocalizationManager.shared.currentLanguage == .spanish
        let df = DateFormatter()
        df.locale = isSpanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateFormat = "MMMM yyyy"
        let monthTitle = df.string(from: month).uppercased()

        let displayTitle = (projectTitle.isEmpty ? "CineSched" : projectTitle) + " — " + monthTitle
        canvas.draw(displayTitle, in: CGRect(x: headerRect.minX, y: headerRect.maxY - 20, width: headerRect.width, height: 20),
                    font: .boldSystem(size: 16), color: .pdfBlack)

        let scheduledCount = shootDays.filter { !$0.scenes.isEmpty && cal.isDate($0.date, equalTo: month, toGranularity: .month) }.count
        let metaText = isSpanish
            ? "Días de Rodaje en el Mes: \(scheduledCount)  ·  Director: \(productionInfo.directorName.isEmpty ? "—" : productionInfo.directorName)  ·  Productor: \(productionInfo.producerName.isEmpty ? "—" : productionInfo.producerName)"
            : "Month Shoot Days: \(scheduledCount)  ·  Director: \(productionInfo.directorName.isEmpty ? "—" : productionInfo.directorName)  ·  Producer: \(productionInfo.producerName.isEmpty ? "—" : productionInfo.producerName)"
        canvas.draw(metaText, in: CGRect(x: headerRect.minX, y: headerRect.maxY - 36, width: headerRect.width, height: 16),
                    font: .system(size: 9), color: .pdfDarkGray)

        // Weekday header bar
        let weekdayBarHeight: CGFloat = 16
        let weekdayBarRect = CGRect(
            x: contentRect.minX,
            y: headerRect.minY - weekdayBarHeight - 4,
            width: contentRect.width,
            height: weekdayBarHeight
        )

        canvas.fill(weekdayBarRect, cornerRadius: 3, color: .gray(0.92))

        let weekdaySymbols = isSpanish
            ? ["DOMINGO", "LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO"]
            : ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]

        let cellWidth = contentRect.width / 7
        for (col, symbol) in weekdaySymbols.enumerated() {
            let colRect = CGRect(x: weekdayBarRect.minX + CGFloat(col) * cellWidth, y: weekdayBarRect.minY + 2, width: cellWidth, height: 12)
            canvas.draw(symbol, in: colRect, font: .boldSystem(size: 8.5), color: .gray(0.3), alignment: .center)
        }

        // Draw Weeks Grid (Page 1 gets 100% full height for maximum cell room)
        let gridTop = weekdayBarRect.minY - 4
        let gridHeight = gridTop - contentRect.minY
        let numWeeks = max(CGFloat(monthWeeks.count), 1)
        let rowHeight = gridHeight / numWeeks

        for (wIdx, week) in monthWeeks.enumerated() {
            let rowY = gridTop - CGFloat(wIdx + 1) * rowHeight
            let rowRect = CGRect(x: contentRect.minX, y: rowY, width: contentRect.width, height: rowHeight)

            for (cIdx, cell) in week.enumerated() {
                let cellRect = CGRect(x: rowRect.minX + CGFloat(cIdx) * cellWidth, y: rowRect.minY, width: cellWidth, height: rowHeight)
                let isCurrentMonth = cal.isDate(cell.date, equalTo: month, toGranularity: .month)
                let dayNum = cell.shootDay != nil ? dayNumbers[cell.shootDay!.id] : nil

                drawMonthGridCell(
                    on: canvas,
                    date: cell.date,
                    shootDay: cell.shootDay,
                    dayNumber: dayNum,
                    in: cellRect,
                    isCurrentMonth: isCurrentMonth
                )
            }
        }

        canvas.endPage()

        // Pages 2+: Detailed Activity & Shoot Schedule Breakdown (if month has scheduled content)
        // Days with something to say: scenes, events, or a day note. A typed day with no note
        // (a plain Day Off) is already labelled in the grid, so it doesn't earn a card of its own.
        let activeDays = shootDays.filter { day in
            cal.isDate(day.date, equalTo: month, toGranularity: .month)
                && (!day.scenes.isEmpty || !day.dayNote.isEmpty)
        }.sorted { $0.date < $1.date }

        if !activeDays.isEmpty {
            drawMonthBreakdownPages(
                on: canvas,
                contentRect: contentRect,
                monthTitle: monthTitle,
                projectTitle: projectTitle,
                activeDays: activeDays,
                dayNumbers: dayNumbers,
                isSpanish: isSpanish,
                options: options
            )
        }

        return canvas.finish()
    }

    private static func drawMonthGridCell(
        on canvas: PDFCanvas,
        date: Date,
        shootDay: ShootDay?,
        dayNumber: Int?,
        in rect: CGRect,
        isCurrentMonth: Bool
    ) {
        let isShoot = shootDay != nil && shootDay!.dayType.isShootable && (dayNumber != nil || !shootDay!.scenes.filter { !$0.isCalendarEvent }.isEmpty)

        let cellFill: CGColor
        if isShoot {
            cellFill = .srgb(0.94, 0.97, 1.0)
        } else if let sd = shootDay, !sd.dayType.isShootable {
            // Same tint the calendar cell uses for this day type, washed out for print.
            cellFill = tint(sd.dayType.colorHex).withAlpha(0.12)
        } else if !isCurrentMonth {
            cellFill = .gray(0.97)
        } else {
            cellFill = .pdfWhite
        }
        canvas.fill(rect, color: cellFill)
        canvas.stroke(rect, color: .gray(0.82), lineWidth: 0.5)

        let cal = Calendar.current
        let dayDigit = cal.component(.day, from: date)
        let padding: CGFloat = 4
        let inner = rect.insetBy(dx: padding, dy: padding)

        // Day Number Header
        canvas.draw("\(dayDigit)", lineOrigin: CGPoint(x: inner.minX, y: inner.maxY - 13),
                    font: .boldSystem(size: 9.5), color: isCurrentMonth ? .pdfBlack : .pdfLightGray)

        // Shoot Day Badge
        if let dayNumber = dayNumber, isShoot {
            let badgeText = LocalizationManager.shared.currentLanguage == .spanish ? "DÍA #\(dayNumber)" : "DAY #\(dayNumber)"
            canvas.draw(badgeText, in: CGRect(x: inner.minX, y: inner.maxY - 13, width: inner.width, height: 13),
                        font: .boldSystem(size: 8.5), color: badgeBlue, alignment: .trailing)
        } else if let sd = shootDay, !sd.dayType.isShootable {
            // Day type badge in the same slot the DAY # badge uses on shoot days.
            canvas.draw(sd.dayType.localizedName.uppercased(), in: CGRect(x: inner.minX + 14, y: inner.maxY - 13, width: inner.width - 14, height: 13),
                        font: .boldSystem(size: 7.5), color: tint(sd.dayType.colorHex), alignment: .trailing, lineBreak: .truncateTail)
        }

        // Scenes and Calendar Events list
        if let day = shootDay {
            let boxHeight: CGFloat = 12
            var yOff: CGFloat = 16

            if !day.dayNote.isEmpty {
                canvas.draw(day.dayNote, in: CGRect(x: inner.minX, y: inner.maxY - yOff - 10, width: inner.width, height: 10),
                            font: .system(size: 7), color: .gray(0.3), lineBreak: .truncateTail)
                yOff += 12
            }

            for scene in day.scenes {
                guard inner.maxY - yOff - boxHeight >= inner.minY + 4 else { break }

                let bRect = CGRect(x: inner.minX, y: inner.maxY - yOff - boxHeight, width: inner.width, height: boxHeight)

                if scene.isCalendarEvent {
                    let evColor = tint(scene.bannerColorHex)
                    canvas.fill(bRect, cornerRadius: 2.5, color: evColor.withAlpha(0.18))
                    canvas.stroke(bRect, cornerRadius: 2.5, color: evColor.withAlpha(0.6), lineWidth: 0.5)

                    let timePrefix = scene.customStartTime.isEmpty ? "" : "\(scene.customStartTime) · "
                    canvas.draw("\(timePrefix)\(scene.title)", in: bRect.insetBy(dx: 3, dy: 1),
                                font: .boldSystem(size: 6.8), color: evColor, lineBreak: .truncateTail)
                } else if !scene.isBanner {
                    canvas.fill(bRect, cornerRadius: 2.5, color: scene.dayNightType == .night ? .srgb(0.88, 0.92, 0.98) : .pdfWhite)
                    canvas.stroke(bRect, cornerRadius: 2.5, color: .gray(0.72), lineWidth: 0.5)

                    // Scene number + shooting location, not the slugline — the cell is tiny
                    // and the full breakdown follows on the next pages. Scenes without a
                    // Real Location fall back to the slugline so the line is never bare.
                    let numPrefix = scene.sceneNumber.isEmpty ? "" : "\(scene.sceneNumber) · "
                    let loc = scene.realLocation.trimmingCharacters(in: .whitespaces)
                    let body = loc.isEmpty ? scene.title : loc
                    let durStr = scene.duration > 0 ? " (\(formattedEighths(scene.duration)))" : ""
                    canvas.draw("\(numPrefix)\(body)\(durStr)", in: bRect.insetBy(dx: 3, dy: 1),
                                font: .system(size: 6.8), color: .pdfBlack, lineBreak: .truncateTail)
                }
                yOff += boxHeight + 2
            }
        }
    }

    // MARK: - Breakdown pages (pages 2+)

    /// One measured slice of a breakdown card. `draw` receives the slot rect the
    /// pagination loop reserved for it (its `height` tall); everything the item renders
    /// stays inside that rect, so card heights are exact and nothing can overflow.
    private struct BreakdownItem {
        let height: CGFloat
        let draw: (CGRect) -> Void
    }

    /// Wrapping-aware text item: measured at `width`, capped at `maxLines` whole lines,
    /// so a long note wraps instead of clipping mid-word but can never swallow the card.
    private static func makeBreakdownLine(
        on canvas: PDFCanvas,
        _ string: String,
        font: PDFFont,
        color: CGColor,
        width: CGFloat,
        maxLines: Int
    ) -> BreakdownItem {
        // One TextKit line in this font per wrapped line; an emoji prefix draws from the
        // fallback face but does not make the line taller.
        let lineCount = max(1, min(maxLines, canvas.lineCount(of: string, font: font, width: width)))
        let height = font.lineHeight * CGFloat(lineCount)
        return BreakdownItem(height: height, draw: { rect in canvas.draw(string, in: rect, font: font, color: color) })
    }

    // MARK: Scene pills

    private struct PDFPill {
        let text:   String
        let font:   PDFFont
        let color:  CGColor
        let size:   CGSize
        let fill:   CGColor
        let stroke: CGColor
    }

    /// A rounded pill ("📍 HOLLYWOOD"). One that can't fit a single row becomes a
    /// full-width pill with wrapped text (≤3 lines) so a long cast list keeps every
    /// name instead of truncating.
    private static func makePill(on canvas: PDFCanvas, _ string: String, tint: CGColor?, maxWidth: CGFloat) -> PDFPill {
        let font   = PDFFont.system(size: 6.8)
        let color  = tint ?? .gray(0.25)
        let fill   = tint?.withAlpha(0.07) ?? .pdfWhite
        let stroke = tint?.withAlpha(0.4)  ?? .gray(0.78)
        // Box height comes from the line height: a rect shorter than one line clips the
        // text.
        let lineHeight = font.lineHeight
        let lineWidth  = ceil(canvas.width(of: string, font: font))
        if lineWidth + 10 <= maxWidth {
            return PDFPill(text: string, font: font, color: color, size: CGSize(width: lineWidth + 10, height: lineHeight + 4), fill: fill, stroke: stroke)
        }
        let lines = max(1, min(3, canvas.lineCount(of: string, font: font, width: maxWidth - 10)))
        return PDFPill(text: string, font: font, color: color, size: CGSize(width: maxWidth, height: lineHeight * CGFloat(lines) + 4), fill: fill, stroke: stroke)
    }

    /// Lays pills into left-aligned rows (3pt gaps), one BreakdownItem per row.
    private static func pillRowItems(on canvas: PDFCanvas, _ pills: [PDFPill], width: CGFloat, indent: CGFloat) -> [BreakdownItem] {
        var items: [BreakdownItem] = []
        var row: [PDFPill] = []
        var rowWidth: CGFloat = 0

        func flushRow() {
            guard !row.isEmpty else { return }
            let rowPills = row
            let rowHeight = rowPills.map(\.size.height).max()! + 1
            items.append(BreakdownItem(height: rowHeight, draw: { rect in
                var x = rect.minX + indent
                for pill in rowPills {
                    let pRect = CGRect(x: x, y: rect.maxY - pill.size.height, width: pill.size.width, height: pill.size.height)
                    let radius = min(pill.size.height / 2, 6)
                    canvas.fill(pRect, cornerRadius: radius, color: pill.fill)
                    canvas.stroke(pRect, cornerRadius: radius, color: pill.stroke, lineWidth: 0.5)
                    canvas.draw(pill.text, in: pRect.insetBy(dx: 5, dy: 2), font: pill.font, color: pill.color)
                    x += pill.size.width + 3
                }
            }))
            row = []; rowWidth = 0
        }

        for pill in pills {
            if rowWidth > 0 && rowWidth + pill.size.width > width { flushRow() }
            row.append(pill)
            rowWidth += pill.size.width + 3
        }
        flushRow()
        return items
    }

    /// One scene's block: heading line (strip-color swatch, slugline, right-aligned
    /// pgs/time), the synopsis on its own italic line, then a row of tinted pills for
    /// the fields chosen in the export dialog — built to be read at a glance.
    private static func sceneItems(
        on canvas: PDFCanvas,
        for scene: Scene,
        options: MonthPDFOptions,
        width: CGFloat
    ) -> [BreakdownItem] {
        var items: [BreakdownItem] = []
        let indent: CGFloat = 11          // heading text starts after the color swatch;
        let contentWidth = width - indent // synopsis and pills align with it

        // Heading
        var metaParts: [String] = []
        if options.includePageCount, scene.duration > 0 { metaParts.append("\(formattedEighths(scene.duration)) \(L("pgs"))") }
        if options.includeEstimatedTime, scene.estimatedTime > 0 { metaParts.append(formattedTime(scene.estimatedTime)) }
        let metaFont = PDFFont.system(size: 7)
        let metaStr: String? = metaParts.isEmpty ? nil : metaParts.joined(separator: " · ")
        let metaWidth = metaStr.map { ceil(canvas.width(of: $0, font: metaFont)) } ?? 0

        let numStr = scene.sceneNumber.isEmpty ? "" : "\(L("Sc")) \(scene.sceneNumber): "
        let headingFont = PDFFont.semiboldSystem(size: 8)
        let headingStr = "\(numStr)\(scene.title) [\(scene.intExtString) \(scene.dayNightType.rawValue.uppercased())]"
        let headingTextWidth = contentWidth - (metaWidth > 0 ? metaWidth + 8 : 0)
        let headingLineHeight = headingFont.lineHeight
        let headingLines = max(1, min(2, canvas.lineCount(of: headingStr, font: headingFont, width: headingTextWidth)))
        let headingHeight = headingLineHeight * CGFloat(headingLines)
        let swatchColor = CGColor.of(scene.stripColor)   // convention: colors only via stripColor
        items.append(BreakdownItem(height: headingHeight, draw: { rect in
            let swatch = CGRect(x: rect.minX, y: rect.maxY - 8.5, width: 7, height: 7)
            canvas.fill(swatch, cornerRadius: 2, color: swatchColor)
            canvas.stroke(swatch, cornerRadius: 2, color: .gray(0, alpha: 0.15), lineWidth: 0.5)
            canvas.draw(headingStr, in: CGRect(x: rect.minX + indent, y: rect.minY, width: headingTextWidth, height: rect.height),
                        font: headingFont, color: .pdfBlack)
            if let metaStr {
                canvas.draw(metaStr, in: CGRect(x: rect.maxX - metaWidth, y: rect.maxY - headingLineHeight, width: metaWidth, height: headingLineHeight),
                            font: metaFont, color: .gray(0.4))
            }
        }))

        // Synopsis on its own line, italic so it reads as prose, not another data field.
        if options.fields.contains(.summary) {
            let synopsis = StripboardField.summary.displayValue(for: scene)
            if !synopsis.isEmpty {
                let line = makeBreakdownLine(on: canvas, synopsis, font: .italicSystem(size: 7.5), color: .gray(0.32),
                                             width: contentWidth, maxLines: 3)
                items.append(BreakdownItem(height: line.height, draw: { rect in
                    line.draw(CGRect(x: rect.minX + indent, y: rect.minY, width: contentWidth, height: rect.height))
                }))
            }
        }

        // Pills, in declaration order so every scene reads the same. Location and
        // equipment get a color of their own; the rest stay neutral.
        var pills: [PDFPill] = []
        for field in StripboardField.allCases where field != .summary && options.fields.contains(field) {
            let value = field.displayValue(for: scene)
            guard !value.isEmpty else { continue }
            let tint: CGColor?
            switch field {
            case .realLocation:     tint = badgeBlue
            case .specialEquipment: tint = .srgb(0.72, 0.42, 0.03)
            default:                tint = nil
            }
            pills.append(makePill(on: canvas, "\(field.pdfEmoji) \(value)", tint: tint, maxWidth: contentWidth))
        }
        items.append(contentsOf: pillRowItems(on: canvas, pills, width: contentWidth, indent: indent))

        return items
    }

    /// Everything a day's card prints under its date header. Fixed items (call times,
    /// day note, events) come first; each scene is its own group so an oversized card
    /// can be trimmed at scene granularity. The call-times line is measured like
    /// everything else — the old fixed-height estimate forgot it and pushed scene
    /// lines past the card border.
    private static func breakdownContent(
        on canvas: PDFCanvas,
        for day: ShootDay,
        isShoot: Bool,
        isSpanish: Bool,
        options: MonthPDFOptions,
        width: CGFloat
    ) -> (fixed: [BreakdownItem], sceneGroups: [[BreakdownItem]]) {
        var fixed: [BreakdownItem] = []

        // Call sheet times summary if shoot day
        if isShoot && (!day.callSheet.generalCallTime.isEmpty || !day.callSheet.lunchTime.isEmpty || !day.callSheet.dinnerTime.isEmpty) {
            var callParts: [String] = []
            if !day.callSheet.generalCallTime.isEmpty { callParts.append("\(isSpanish ? "Llamado" : "Call"): \(day.callSheet.generalCallTime)") }
            if !day.callSheet.lunchTime.isEmpty { callParts.append("\(isSpanish ? "Almuerzo" : "Lunch"): \(day.callSheet.lunchTime)") }
            if !day.callSheet.dinnerTime.isEmpty { callParts.append("Wrap: \(day.callSheet.dinnerTime)") }
            if !day.callSheet.basecampLocation.isEmpty { callParts.append("\(isSpanish ? "Loc" : "Base"): \(day.callSheet.basecampLocation)") }
            fixed.append(makeBreakdownLine(on: canvas, "⏰ " + callParts.joined(separator: "  ·  "),
                                           font: .system(size: 7.8),
                                           color: .gray(0.35),
                                           width: width, maxLines: 2))
        }

        // Day note (travel details, hold reason, …)
        if !day.dayNote.isEmpty {
            fixed.append(makeBreakdownLine(on: canvas, "📝 " + day.dayNote,
                                           font: .system(size: 7.8),
                                           color: .gray(0.3),
                                           width: width, maxLines: 2))
        }

        // Events list
        for ev in day.scenes where ev.isCalendarEvent {
            let evTime = ev.customStartTime.isEmpty ? "" : "[\(ev.customStartTime)] "
            fixed.append(makeBreakdownLine(on: canvas, "🗓️  \(evTime)\(ev.title)",
                                           font: .boldSystem(size: 7.8),
                                           color: tint(ev.bannerColorHex),
                                           width: width, maxLines: 2))
        }

        var sceneGroups: [[BreakdownItem]] = []
        for scene in day.scenes where !scene.isCalendarEvent && !scene.isBanner {
            var group = sceneItems(on: canvas, for: scene, options: options, width: width)
            group.append(BreakdownItem(height: 2, draw: { _ in }))   // breathing room between scenes
            sceneGroups.append(group)
        }

        return (fixed, sceneGroups)
    }

    /// Header + divider for a breakdown page. Returns the Y where the first card starts.
    private static func drawBreakdownHeader(
        on canvas: PDFCanvas,
        contentRect: CGRect,
        monthTitle: String,
        projectTitle: String,
        isSpanish: Bool,
        isContinuation: Bool
    ) -> CGFloat {
        var headerTitle = (projectTitle.isEmpty ? "CineSched" : projectTitle) + " — " + monthTitle + (isSpanish ? " — Desglose y Actividades" : " — Schedule & Breakdown")
        if isContinuation { headerTitle += " (cont.)" }
        canvas.draw(headerTitle, lineOrigin: CGPoint(x: contentRect.minX, y: contentRect.maxY - 20),
                    font: .boldSystem(size: 15), color: .pdfBlack)

        let subTitle = isSpanish
            ? "Detalle completo de escenas, llamados, personajes y eventos programados para este mes."
            : "Complete detail of scheduled scenes, call times, cast and calendar events for this month."
        canvas.draw(subTitle, lineOrigin: CGPoint(x: contentRect.minX, y: contentRect.maxY - 34),
                    font: .system(size: 8.5), color: .pdfDarkGray)

        canvas.line(from: CGPoint(x: contentRect.minX, y: contentRect.maxY - 40), to: CGPoint(x: contentRect.maxX, y: contentRect.maxY - 40),
                    color: .gray(0.8), lineWidth: 0.75)

        return contentRect.maxY - 52
    }

    /// Draws the per-day breakdown cards, starting a new PDF page whenever the next card
    /// won't fit — the old single-page version silently dropped every remaining day once
    /// the page filled. Owns its page lifecycle because the page count depends on content;
    /// the caller only closes the document.
    private static func drawMonthBreakdownPages(
        on canvas: PDFCanvas,
        contentRect: CGRect,
        monthTitle: String,
        projectTitle: String,
        activeDays: [ShootDay],
        dayNumbers: [UUID: Int],
        isSpanish: Bool,
        options: MonthPDFOptions
    ) {
        let df = DateFormatter()
        df.locale = isSpanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateStyle = .full

        let cardWidth = contentRect.width
        let lineWidth = cardWidth - 16
        // What a card can use on a fresh page, for trimming one that could never fit.
        let fullPageRoom = (contentRect.maxY - 52) - contentRect.minY

        var pageNumber = 0
        var curY: CGFloat = 0

        func beginPage() {
            pageNumber += 1
            canvas.beginPage()
            curY = drawBreakdownHeader(
                on: canvas,
                contentRect: contentRect,
                monthTitle: monthTitle,
                projectTitle: projectTitle,
                isSpanish: isSpanish,
                isContinuation: pageNumber > 1
            )
        }
        func endPage() {
            canvas.draw("\(isSpanish ? "Página" : "Page") \(pageNumber)",
                        in: CGRect(x: contentRect.minX, y: contentRect.minY - 18, width: contentRect.width, height: 10),
                        font: .system(size: 7), color: .pdfGray, alignment: .trailing)
            canvas.endPage()
        }

        beginPage()

        for day in activeDays {
            let isShoot = dayNumbers[day.id] != nil
            let scriptScenes = day.scenes.filter { !$0.isCalendarEvent && !$0.isBanner }
            let totalEighths = scriptScenes.reduce(0) { $0 + $1.duration }
            let totalMins = scriptScenes.reduce(0) { $0 + $1.estimatedTime }

            let content = breakdownContent(on: canvas, for: day, isShoot: isShoot, isSpanish: isSpanish, options: options, width: lineWidth)
            var sceneGroups = content.sceneGroups

            // 22pt header row + measured items + bottom padding; 44 keeps a bare
            // note-only card from collapsing, same minimum as before.
            func cardHeight(for items: [BreakdownItem]) -> CGFloat {
                max(22 + items.reduce(0) { $0 + $1.height + 2 } + 6, 44)
            }
            func assembled() -> [BreakdownItem] { content.fixed + sceneGroups.flatMap { $0 } }

            // A card taller than a whole page gets trailing scenes trimmed with an
            // explicit count instead of overflowing the media box.
            var items = assembled()
            if cardHeight(for: items) > fullPageRoom {
                var dropped = 0
                while cardHeight(for: assembled()) + 14 > fullPageRoom && !sceneGroups.isEmpty {
                    sceneGroups.removeLast()
                    dropped += 1
                }
                items = assembled()
                items.append(makeBreakdownLine(on: canvas, isSpanish ? "… y \(dropped) escenas más" : "… and \(dropped) more scenes",
                                               font: .system(size: 7.8),
                                               color: .pdfGray,
                                               width: lineWidth, maxLines: 1))
            }
            let height = cardHeight(for: items)

            if curY - height < contentRect.minY {
                endPage()
                beginPage()
            }

            let cardRect = CGRect(x: contentRect.minX, y: curY - height, width: cardWidth, height: height)

            if isShoot {
                canvas.fill(cardRect, cornerRadius: 4, color: .srgb(0.96, 0.98, 1.0))
                canvas.stroke(cardRect, cornerRadius: 4, color: .srgb(0.7, 0.82, 0.96), lineWidth: 0.5)
            } else {
                canvas.fill(cardRect, cornerRadius: 4, color: .gray(0.97))
                canvas.stroke(cardRect, cornerRadius: 4, color: .gray(0.85), lineWidth: 0.5)
            }

            // Card Header: Date + Day Badge
            let dateString = df.string(from: day.date).capitalized
            canvas.draw(dateString, lineOrigin: CGPoint(x: cardRect.minX + 8, y: cardRect.maxY - 15),
                        font: .boldSystem(size: 9.5), color: .pdfBlack)

            let badgeFont   = PDFFont.boldSystem(size: 8.5)
            let badgeOrigin = CGPoint(x: cardRect.minX + 220, y: cardRect.maxY - 15)
            if let dayNum = dayNumbers[day.id] {
                let badgeText = isSpanish
                    ? "DÍA #\(dayNum) DE RODAJE (\(scriptScenes.count) esc · \(formattedEighths(totalEighths)) págs · \(formattedTime(totalMins)))"
                    : "SHOOT DAY #\(dayNum) (\(scriptScenes.count) sc · \(formattedEighths(totalEighths)) pgs · \(formattedTime(totalMins)))"
                canvas.draw(badgeText, lineOrigin: badgeOrigin, font: badgeFont, color: badgeBlue)
            } else if !day.dayType.isShootable {
                canvas.draw(day.dayType.localizedName.uppercased(), lineOrigin: badgeOrigin, font: badgeFont, color: tint(day.dayType.colorHex))
            } else {
                let eventBadgeText = isSpanish ? "📅 DÍA DE AGENDA" : "📅 AGENDA / PREP DAY"
                canvas.draw(eventBadgeText, lineOrigin: badgeOrigin, font: badgeFont, color: eventIndigo)
            }

            // Measured items, top-down under the header row.
            var lineTop = cardRect.maxY - 22
            for item in items {
                item.draw(CGRect(x: cardRect.minX + 8, y: lineTop - item.height, width: lineWidth, height: item.height))
                lineTop -= item.height + 2
            }

            curY -= (height + 8)
        }

        endPage()
    }
}

// MARK: - Tints

extension PDFExporter {
    /// The blue of the "DAY #" badges and the location pill, and the indigo of calendar
    /// events with no colour of their own.
    fileprivate static let badgeBlue   = CGColor.srgb(0.1, 0.35, 0.85)
    fileprivate static let eventIndigo = CGColor.hex("6366F1")

    /// The colour behind an event's or day type's hex string. An empty or malformed string
    /// gives `eventIndigo`, as the AppKit version's `NSColor(hexString:)` did (where
    /// `Color(hex:)` would give black).
    fileprivate static func tint(_ hex: String) -> CGColor {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return [3, 6, 8].contains(digits.count) ? .hex(digits) : eventIndigo
    }
}

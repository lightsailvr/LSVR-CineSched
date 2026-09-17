// DaysOutOfDaysExporter.swift
// Generates a landscape US Letter "Days Out of Days" (DOOD) PDF — one row per cast
// member, one column per shoot day, showing when each character starts, works,
// holds, and finishes across the schedule.
//
// Draws through PDFCanvas (CoreGraphics + CoreText, no AppKit), so it builds on every
// platform. The rects handed to `canvas.draw(_:in:…)` are the ones the AppKit version
// handed to `NSAttributedString.draw(in:)`, and the points handed to `draw(_:lineOrigin:…)`
// are the ones it handed to `draw(at:)`, so the grid lands pixel for pixel where it did.
// The status colors used to be `NSColor.systemBlue` / `.systemYellow` / `.systemRed`,
// which followed the app's appearance (the PDF came out a shade different in dark mode);
// they are pinned to the light-appearance values now.

import CoreGraphics
import Foundation

enum DOODStatus: Equatable {
    case startWork, work, hold, finish, startFinish, unavailable, none

    var code: String {
        switch self {
        case .startWork:   return "SW"
        case .work:        return "W"
        case .hold:        return "H"
        case .finish:      return "WF"
        case .startFinish: return "SWF"
        case .unavailable: return "X"
        case .none:        return ""
        }
    }

    var isWorkDay: Bool {
        switch self {
        case .startWork, .work, .finish, .startFinish: return true
        case .hold, .unavailable, .none: return false
        }
    }

    /// Light-appearance `systemBlue`, `systemYellow` and `systemRed` (sRGB 0/136/255,
    /// 255/204/0 and 255/56/60).
    private static let blue   = CGColor.srgb(0, 136.0 / 255, 1)
    private static let yellow = CGColor.srgb(1, 0.8, 0)
    private static let red    = CGColor.srgb(1, 56.0 / 255, 60.0 / 255)

    var textColor: CGColor {
        switch self {
        case .startWork, .finish, .startFinish: return .pdfWhite
        case .work:  return .pdfBlack
        case .hold:  return .calibratedGray(0.35)
        case .unavailable: return .pdfWhite
        case .none:  return .pdfBlack   // never drawn: `code` is empty
        }
    }

    /// The cell background; `nil` leaves the cell unfilled.
    var fillColor: CGColor? {
        switch self {
        case .startWork, .finish, .startFinish: return Self.blue
        case .work:  return .calibratedGray(0.94)
        case .hold:  return Self.yellow.withAlpha(0.35)
        case .unavailable: return Self.red.withAlpha(0.55)
        case .none:  return nil
        }
    }
}

struct DOODRow {
    let displayName: String
    let statuses: [DOODStatus]     // one entry per shoot day, aligned by index
    let workDayCount: Int
    let holdDayCount: Int
    let totalSpan: Int             // finish day minus start day, inclusive; 0 if never scheduled
}

struct DaysOutOfDaysExporter {

    /// Builds one row per character that's actually scheduled anywhere in the project.
    /// Characters from Production Setup's cast list come first (in that order), followed
    /// by any character names found only in scene cast lists (e.g. background/unlisted).
    static func buildRows(shootDays: [ShootDay], productionInfo: ProductionInfo, includeHold: Bool = true) -> (days: [ShootDay], rows: [DOODRow]) {
        let sortedDays = shootDays.sorted { $0.date < $1.date }

        var seen: Set<String> = []
        var orderedCharacters: [String] = []
        for member in productionInfo.castList {
            let name = member.characterName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())
            orderedCharacters.append(name)
        }
        let sceneCharacters = Set(sortedDays.flatMap { $0.scenes.flatMap { $0.cast } })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for name in sceneCharacters.sorted() where !seen.contains(name.lowercased()) {
            seen.insert(name.lowercased())
            orderedCharacters.append(name)
        }

        var rows: [DOODRow] = []
        for character in orderedCharacters {
            var workDayIndices: [Int] = []
            for (idx, day) in sortedDays.enumerated() {
                let works = day.scenes.contains { scene in
                    scene.cast.contains { $0.caseInsensitiveCompare(character) == .orderedSame }
                }
                if works { workDayIndices.append(idx) }
            }
            guard !workDayIndices.isEmpty else { continue }

            let firstIdx = workDayIndices.first!
            let lastIdx  = workDayIndices.last!
            var statuses = Array(repeating: DOODStatus.none, count: sortedDays.count)

            if firstIdx == lastIdx {
                statuses[firstIdx] = .startFinish
            } else {
                statuses[firstIdx] = .startWork
                statuses[lastIdx]  = .finish
                if lastIdx - firstIdx > 1 {
                    for idx in (firstIdx + 1)..<lastIdx {
                        if workDayIndices.contains(idx) {
                            statuses[idx] = .work
                        } else if includeHold && !sortedDays[idx].scenes.isEmpty {
                            // A shoot day where *other* people are working, but not this
                            // character — a true hold. A production-wide day off (no
                            // scenes scheduled for anyone) is left blank instead, since
                            // that's not specific to this cast member. Left blank entirely
                            // when includeHold is off — some productions only pay actors
                            // for days actually on set, so Hold isn't meaningful to them.
                            statuses[idx] = .hold
                        }
                    }
                }
            }

            let matchedMember = productionInfo.castList.first {
                $0.characterName.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(character) == .orderedSame
            }

            // Mark actor-specific unavailable dates — overriding Hold (an unavailable date
            // almost always falls within an actor's existing Hold span, which is exactly
            // why this needs to override it rather than only filling blank cells) but
            // never overriding an actual work day: if they're scheduled to work despite
            // being marked unavailable, that's a genuine conflict already flagged via the
            // calendar's red strips and Scan for Conflicts — the DOOD should keep showing
            // they're actually working that day, not hide it behind an availability flag.
            if let ranges = matchedMember?.unavailableRanges, !ranges.isEmpty {
                for idx in statuses.indices where statuses[idx] == .none || statuses[idx] == .hold {
                    if ranges.contains(where: { $0.contains(sortedDays[idx].date) }) {
                        statuses[idx] = .unavailable
                    }
                }
            }

            let displayName = matchedMember?.displayString ?? character

            rows.append(DOODRow(
                displayName: displayName,
                statuses: statuses,
                workDayCount: statuses.filter { $0.isWorkDay }.count,
                holdDayCount: statuses.filter { $0 == .hold }.count,
                totalSpan: lastIdx - firstIdx + 1
            ))
        }
        return (sortedDays, rows)
    }

    static func generatePDF(shootDays: [ShootDay], projectTitle: String, productionInfo: ProductionInfo, includeHold: Bool = true) -> Data? {
        let (days, rows) = buildRows(shootDays: shootDays, productionInfo: productionInfo, includeHold: includeHold)
        guard !days.isEmpty, !rows.isEmpty else { return nil }

        let pageWidth:  CGFloat = 792   // US Letter landscape
        let pageHeight: CGFloat = 612
        let margin:     CGFloat = 36

        let nameColWidth:    CGFloat = 150
        let summaryColWidth: CGFloat = 30
        let dayColWidth:     CGFloat = 22
        let rowHeight:       CGFloat = 18
        let headerHeight:    CGFloat = 30
        let titleHeight:     CGFloat = 34
        let legendHeight:    CGFloat = 20
        let summaryLabels = includeHold ? ["TOT", "WRK", "HLD"] : ["TOT", "WRK"]

        let contentWidth  = pageWidth - 2 * margin
        let fixedColsWidth = nameColWidth + summaryColWidth * CGFloat(summaryLabels.count)
        let daysAvailableWidth = contentWidth - fixedColsWidth
        let daysPerPage = max(1, Int(daysAvailableWidth / dayColWidth))
        let rowsPerPage = max(1, Int((pageHeight - 2 * margin - titleHeight - headerHeight - legendHeight) / rowHeight))

        let dayChunkStarts = stride(from: 0, to: days.count, by: daysPerPage).map { $0 }
        let rowChunkStarts = stride(from: 0, to: rows.count, by: rowsPerPage).map { $0 }
        let totalPages = dayChunkStarts.count * rowChunkStarts.count

        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        let dayNumFormatter = DateFormatter(); dayNumFormatter.dateFormat = "d"
        let weekdayFormatter = DateFormatter(); weekdayFormatter.dateFormat = "EEEEE"
        let monthFormatter = DateFormatter(); monthFormatter.dateFormat = "MMM"

        var pageNum = 0
        for dayStart in dayChunkStarts {
            let dayChunk = Array(days[dayStart..<min(dayStart + daysPerPage, days.count)])

            for rowStart in rowChunkStarts {
                let rowChunk = Array(rows[rowStart..<min(rowStart + rowsPerPage, rows.count)])
                pageNum += 1

                canvas.beginPage()

                var y = pageHeight - margin

                // Title
                let titleText = "\(projectTitle.isEmpty ? "Untitled Movie" : projectTitle) — Days Out of Days"
                canvas.draw(titleText, lineOrigin: CGPoint(x: margin, y: y - 16), font: .boldSystem(size: 14), color: .pdfBlack)
                canvas.draw("Page \(pageNum) of \(totalPages)", lineOrigin: CGPoint(x: pageWidth - margin - 70, y: y - 14),
                            font: .system(size: 9), color: .pdfGray)

                y -= titleHeight

                let gridTop = y
                var x = margin

                // Column headers
                drawCell(canvas, "", rect: CGRect(x: x, y: y - headerHeight, width: nameColWidth, height: headerHeight),
                         font: .boldSystem(size: 9), align: .leading, textColor: .pdfBlack, fill: nil)
                x += nameColWidth
                for label in summaryLabels {
                    drawCell(canvas, label, rect: CGRect(x: x, y: y - headerHeight, width: summaryColWidth, height: headerHeight),
                             font: .boldSystem(size: 8), align: .center, textColor: .pdfBlack, fill: nil)
                    x += summaryColWidth
                }

                var lastMonth = ""
                for day in dayChunk {
                    let month = monthFormatter.string(from: day.date)
                    let monthLabel = month != lastMonth ? month : ""
                    lastMonth = month
                    let headerText = "\(monthLabel)\n\(weekdayFormatter.string(from: day.date))\n\(dayNumFormatter.string(from: day.date))"
                    drawMultilineHeader(canvas, headerText, rect: CGRect(x: x, y: y - headerHeight, width: dayColWidth, height: headerHeight),
                                        isOff: !day.dayType.isShootable)
                    x += dayColWidth
                }
                y -= headerHeight
                let gridBottom0 = y

                // Rows
                for row in rowChunk {
                    var rx = margin
                    drawCell(canvas, row.displayName, rect: CGRect(x: rx, y: y - rowHeight, width: nameColWidth, height: rowHeight),
                             font: .system(size: 9), align: .leading, textColor: .pdfBlack, fill: nil)
                    rx += nameColWidth

                    drawCell(canvas, "\(row.totalSpan)", rect: CGRect(x: rx, y: y - rowHeight, width: summaryColWidth, height: rowHeight),
                             font: .boldSystem(size: 9), align: .center, textColor: .pdfBlack, fill: nil)
                    rx += summaryColWidth
                    drawCell(canvas, "\(row.workDayCount)", rect: CGRect(x: rx, y: y - rowHeight, width: summaryColWidth, height: rowHeight),
                             font: .system(size: 9), align: .center, textColor: .pdfBlack, fill: nil)
                    rx += summaryColWidth
                    if includeHold {
                        drawCell(canvas, "\(row.holdDayCount)", rect: CGRect(x: rx, y: y - rowHeight, width: summaryColWidth, height: rowHeight),
                                 font: .system(size: 9), align: .center, textColor: .pdfBlack, fill: nil)
                        rx += summaryColWidth
                    }

                    for i in dayStart..<(dayStart + dayChunk.count) {
                        let status = row.statuses[i]
                        drawCell(canvas, status.code, rect: CGRect(x: rx, y: y - rowHeight, width: dayColWidth, height: rowHeight),
                                 font: .boldSystem(size: 7), align: .center, textColor: status.textColor, fill: status.fillColor)
                        rx += dayColWidth
                    }
                    y -= rowHeight
                }
                let gridBottom = y

                // Grid lines
                drawGrid(canvas, top: gridTop, headerBottom: gridBottom0, bottom: gridBottom,
                         left: margin, nameColWidth: nameColWidth, summaryColWidth: summaryColWidth, summaryColCount: summaryLabels.count,
                         dayColWidth: dayColWidth, dayCount: dayChunk.count, rowCount: rowChunk.count, rowHeight: rowHeight)

                // Legend (every page, since pages can be viewed independently)
                let legendY = margin - 4
                let legendText = includeHold
                    ? "SW = Start Work    W = Work    H = Hold    WF = Work Finish    SWF = Start/Work/Finish    X = Unavailable    TOT = Total Days    WRK = Work Days    HLD = Hold Days"
                    : "SW = Start Work    W = Work    WF = Work Finish    SWF = Start/Work/Finish    X = Unavailable    TOT = Total Days    WRK = Work Days"
                canvas.draw(legendText, lineOrigin: CGPoint(x: margin, y: legendY), font: .system(size: 8), color: .pdfGray)

                canvas.endPage()
            }
        }

        return canvas.finish()
    }

    // MARK: - Drawing helpers

    /// One line, vertically centered in `rect` (the text box is exactly one TextKit line
    /// tall, so a name that would wrap loses its second line, as it always did).
    private static func drawCell(_ canvas: PDFCanvas, _ text: String, rect: CGRect, font: PDFFont, align: PDFCanvas.Alignment, textColor: CGColor, fill: CGColor?) {
        if let fill = fill {
            canvas.fill(rect, color: fill)
        }
        guard !text.isEmpty else { return }
        let textHeight = font.lineHeight
        let textRect = CGRect(x: rect.minX + 2, y: rect.minY + (rect.height - textHeight) / 2,
                               width: rect.width - 4, height: textHeight)
        canvas.draw(text, in: textRect, font: font, color: textColor, alignment: align)
    }

    private static func drawMultilineHeader(_ canvas: PDFCanvas, _ text: String, rect: CGRect, isOff: Bool) {
        if isOff {
            canvas.fill(rect, color: .calibratedGray(0.9))
        }
        canvas.draw(text, in: rect.insetBy(dx: 0, dy: 2), font: .system(size: 7), color: .pdfBlack, alignment: .center)
    }

    private static func drawGrid(
        _ canvas: PDFCanvas,
        top: CGFloat, headerBottom: CGFloat, bottom: CGFloat,
        left: CGFloat, nameColWidth: CGFloat, summaryColWidth: CGFloat, summaryColCount: Int,
        dayColWidth: CGFloat, dayCount: Int, rowCount: Int, rowHeight: CGFloat
    ) {
        var lines: [(CGPoint, CGPoint)] = []

        let right = left + nameColWidth + summaryColWidth * CGFloat(summaryColCount) + dayColWidth * CGFloat(dayCount)

        // Header underline + outer box
        lines.append((CGPoint(x: left, y: headerBottom), CGPoint(x: right, y: headerBottom)))
        lines.append((CGPoint(x: left, y: top),          CGPoint(x: right, y: top)))
        lines.append((CGPoint(x: left, y: bottom),       CGPoint(x: right, y: bottom)))
        lines.append((CGPoint(x: left, y: top),          CGPoint(x: left, y: bottom)))
        lines.append((CGPoint(x: right, y: top),         CGPoint(x: right, y: bottom)))

        // Row separators
        for i in 0...rowCount {
            let y = headerBottom - CGFloat(i) * rowHeight
            lines.append((CGPoint(x: left, y: y), CGPoint(x: right, y: y)))
        }

        // Column separators: name | summary columns... | day, day, day...
        var x = left + nameColWidth
        lines.append((CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)))
        for _ in 0..<summaryColCount {
            x += summaryColWidth
            lines.append((CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)))
        }
        for _ in 0..<dayCount {
            x += dayColWidth
            lines.append((CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)))
        }
        canvas.stroke(lines: lines, color: .pdfLightGray, lineWidth: 0.4)
    }
}

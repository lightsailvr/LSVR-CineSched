// CallSheetExporter.swift
// Generates a professional Call Sheet PDF matching standard film industry layout with Basecamp and Actor Scenes.
//
// Draws through PDFCanvas (CoreGraphics + CoreText), so it builds and runs on every
// platform. The rects handed to `canvas.draw(_:in:…)` are the ones the AppKit version
// handed to `NSAttributedString.draw(in:)`; PDFCanvas lays text out in them the way
// TextKit did, which is what keeps the output identical — pixel for pixel, apart from
// lines cut with "…", which TextKit tracked tighter (verified by pixel-diffing the fixture
// exports, #5). The two italic faces are the ones `NSFontManager` resolved: the schedule
// line is the system italic (a descriptor trait), the quote is Helvetica Oblique by name,
// because asking for the system italic there would have changed the face.

import SwiftUI

// MARK: - CallSheetExporter

class CallSheetExporter {

    private static let pageWidth:    CGFloat = 612   // US Letter portrait
    private static let pageHeight:   CGFloat = 792
    private static let margin:       CGFloat = 28
    private static let contentWidth: CGFloat = pageWidth - 2 * margin

    // Fonts
    private static let fontBannerTitle = PDFFont.boldSystem(size: 13)
    private static let fontCallBig     = PDFFont.boldSystem(size: 26)
    private static let fontSchedule    = PDFFont.italicSystem(size: 8.5)
    private static let fontQuote       = PDFFont.named("Helvetica-Oblique", size: 8.5)
    private static let fontSectionHdr  = PDFFont.boldSystem(size: 9.5)
    private static let fontTableHdr    = PDFFont.boldSystem(size: 8.5)
    private static let fontBoldBody    = PDFFont.boldSystem(size: 8.5)
    private static let fontRegularBody = PDFFont.system(size: 8)
    private static let fontSmall       = PDFFont.system(size: 7.5)
    private static let fontTiny        = PDFFont.system(size: 7)

    // Colors (Clean modern monochrome & subtle grays, NO orange)
    private static let colorHeaderBar   = CGColor.gray(0.88)
    private static let colorGrayHeader  = CGColor.gray(0.93)
    private static let colorBorder      = CGColor.gray(0.25)
    private static let colorBlack       = CGColor.pdfBlack
    private static let colorDark        = CGColor.gray(0.15)

    // MARK: - Entry point

    static func generatePDF(
        shootDay: ShootDay,
        productionInfo: ProductionInfo,
        projectTitle: String,
        dayNumber: Int? = nil,
        totalProductionDays: Int = 0,
        language: AppLanguage = LocalizationManager.shared.currentLanguage
    ) -> Data? {
        guard let canvas = PDFCanvas(pageSize: CGSize(width: pageWidth, height: pageHeight)) else { return nil }

        var y: CGFloat = pageHeight - margin

        func beginPage() {
            canvas.beginPage()
            y = pageHeight - margin
        }

        func endPage() {
            canvas.endPage()
        }

        func ensureRoom(_ height: CGFloat) {
            if y - height < margin + 10 {
                endPage()
                beginPage()
            }
        }

        beginPage()

        // 1. Top Header Banner
        y = drawTopBanner(on: canvas, y: y, shootDay: shootDay, dayNumber: dayNumber, lang: language)

        // 2. General Call Banner (with Quote of the day if exists)
        y = drawGeneralCallBanner(on: canvas, y: y, callSheet: shootDay.callSheet, lang: language)

        // 3. Three-Block Info Row (Shooting Contacts, Milestones, Weather)
        y = drawThreeBlockInfoRow(on: canvas, y: y, shootDay: shootDay, productionInfo: productionInfo, lang: language)

        // 4. Basecamp Bar (Above Nearest Hospital)
        y = drawBasecampBar(on: canvas, y: y, callSheet: shootDay.callSheet, lang: language)

        // 5. Nearest Hospital
        y = drawHospitalBar(on: canvas, y: y, callSheet: shootDay.callSheet, lang: language)

        // 6. Scenes Breakdown Table
        y = drawScenesTable(on: canvas, y: y, shootDay: shootDay, lang: language, ensureRoom: ensureRoom)

        // 7. Cast Call Table (with SCENES column)
        y = drawCastTable(on: canvas, y: y, shootDay: shootDay, productionInfo: productionInfo, lang: language, ensureRoom: ensureRoom)

        // 8. Crew Call Times (Role: Name + Call Time)
        y = drawCrewTable(on: canvas, y: y, shootDay: shootDay, productionInfo: productionInfo, lang: language, ensureRoom: ensureRoom)

        // 9. General Notes (Unified in one single block)
        y = drawProductionNotes(on: canvas, y: y, callSheet: shootDay.callSheet, lang: language, ensureRoom: ensureRoom)

        endPage()
        return canvas.finish()
    }

    // MARK: - 1. Top Banner

    private static func drawTopBanner(on canvas: PDFCanvas, y: CGFloat, shootDay: ShootDay, dayNumber: Int?, lang: AppLanguage) -> CGFloat {
        let height: CGFloat = 22
        let rect = CGRect(x: margin, y: y - height, width: contentWidth, height: height)

        canvas.fill(rect, color: colorHeaderBar)
        canvas.stroke(rect, color: colorBorder, lineWidth: 1)

        let numStr = dayNumber.map { String(format: "%02d", $0) } ?? "01"
        let titleLabel = lang == .spanish ? "ORDEN DE RODAJE Nº" : "CALL SHEET #"
        let fullText = "\(titleLabel) \(numStr) — \(formattedFullDate(shootDay.date))"

        canvas.draw(fullText, in: CGRect(x: rect.minX, y: rect.midY - 7.5, width: rect.width, height: 16),
                    font: fontBannerTitle, color: colorBlack, alignment: .center)

        return y - height
    }

    // MARK: - 2. General Call Banner

    private static func drawGeneralCallBanner(on canvas: PDFCanvas, y: CGFloat, callSheet: CallSheetData, lang: AppLanguage) -> CGFloat {
        let hasQuote = !callSheet.quoteOfTheDay.trimmingCharacters(in: .whitespaces).isEmpty
        let height: CGFloat = hasQuote ? 72 : 62
        let rect = CGRect(x: margin, y: y - height, width: contentWidth, height: height)

        canvas.fill(rect, color: colorGrayHeader)
        canvas.stroke(rect, color: colorBorder, lineWidth: 1)

        // Subtitle
        let callTitle = lang == .spanish ? "CITACIÓN GENERAL" : "GENERAL CALL"
        canvas.draw(callTitle, in: CGRect(x: rect.minX, y: rect.maxY - 14, width: rect.width, height: 12),
                    font: fontSectionHdr, color: colorDark, alignment: .center)

        // Big Call Time (12h)
        let callTime = callSheet.generalCallTime.isEmpty ? "07:30 AM" : callSheet.generalCallTime
        canvas.draw(callTime, in: CGRect(x: rect.minX, y: rect.midY - (hasQuote ? 18 : 14), width: rect.width, height: 28),
                    font: fontCallBig, color: colorBlack, alignment: .center)

        // Schedule range & Quote
        var bottomY = rect.minY + 4
        if hasQuote {
            let quotePrefix = lang == .spanish ? "Frase del día" : "Quote of the day"
            let quoteStr = "“\(quotePrefix): \(callSheet.quoteOfTheDay)”"
            canvas.draw(quoteStr, in: CGRect(x: rect.minX + 8, y: bottomY, width: rect.width - 16, height: 11),
                        font: fontQuote, color: colorBlack, alignment: .center)
            bottomY += 12
        }

        if !callSheet.workDaySchedule.isEmpty {
            let rawSched = callSheet.workDaySchedule
                .replacingOccurrences(of: "Jornada de ", with: "")
                .replacingOccurrences(of: "Jornada ", with: "")
                .replacingOccurrences(of: "Schedule: ", with: "")
            let prefix = lang == .spanish ? "Jornada: " : "Schedule: "
            let schedText = "\(prefix)\(rawSched)"
            canvas.draw(schedText, in: CGRect(x: rect.minX, y: bottomY, width: rect.width, height: 11),
                        font: fontSchedule, color: colorDark, alignment: .center)
        }

        return y - height
    }

    // MARK: - 3. Three-Block Info Row

    private static func drawThreeBlockInfoRow(on canvas: PDFCanvas, y: CGFloat, shootDay: ShootDay, productionInfo: ProductionInfo, lang: AppLanguage) -> CGFloat {
        let height: CGFloat = 68
        let w1: CGFloat = contentWidth * 0.33
        let w2: CGFloat = contentWidth * 0.33
        let w3: CGFloat = contentWidth - w1 - w2

        let r1 = CGRect(x: margin,           y: y - height, width: w1, height: height)
        let r2 = CGRect(x: margin + w1,      y: y - height, width: w2, height: height)
        let r3 = CGRect(x: margin + w1 + w2, y: y - height, width: w3, height: height)

        for r in [r1, r2, r3] {
            canvas.stroke(r, color: colorBorder, lineWidth: 0.75)
        }

        let cs = shootDay.callSheet

        // --- Box 1: SHOOTING CONTACTS ---
        let contactsTitle = lang == .spanish ? "☎ CONTACTOS EN RODAJE" : "☎ SHOOTING CONTACTS"
        canvas.draw(contactsTitle, in: CGRect(x: r1.minX + 4, y: r1.maxY - 13, width: r1.width - 8, height: 12),
                    font: fontSectionHdr, color: colorBlack, alignment: .center)

        /// A centered contact line: the role in bold, the name and phone under it.
        func drawContactLine(_ text: String, bold: Bool, y: CGFloat) {
            canvas.draw(text, in: CGRect(x: r1.minX + 4, y: y, width: r1.width - 8, height: 10),
                        font: bold ? fontBoldBody : fontRegularBody, color: bold ? colorBlack : colorDark, alignment: .center)
        }

        var cY = r1.maxY - 25

        // 1. Producer
        var prodContact = ""
        if !productionInfo.producerName.isEmpty {
            let phone = productionInfo.producerPhone.isEmpty ? "" : " - Tel: \(productionInfo.producerPhone)"
            prodContact = "\(productionInfo.producerName)\(phone)"
        } else if !cs.prodManagerContact.isEmpty {
            prodContact = cs.prodManagerContact
        }

        if !prodContact.isEmpty {
            let prodLabel = lang == .spanish ? "PRODUCTOR" : "PRODUCER"
            drawContactLine(prodLabel, bold: true, y: cY)
            cY -= 10
            drawContactLine(prodContact, bold: false, y: cY)
            cY -= 10
        }

        // 2. 1st AD or Director
        var secondRole = ""
        var secondContact = ""
        if !productionInfo.adName.isEmpty {
            secondRole = lang == .spanish ? "AYUDANTE DE DIRECCIÓN" : "1ST AD"
            let phone = productionInfo.adPhone.isEmpty ? "" : " - Tel: \(productionInfo.adPhone)"
            secondContact = "\(productionInfo.adName)\(phone)"
        } else if !productionInfo.directorName.isEmpty {
            secondRole = "DIRECTOR"
            let phone = productionInfo.directorPhone.isEmpty ? "" : " - Tel: \(productionInfo.directorPhone)"
            secondContact = "\(productionInfo.directorName)\(phone)"
        } else if !cs.adContact.isEmpty {
            secondRole = lang == .spanish ? "AYUDANTE DE DIRECCIÓN" : "1ST AD"
            secondContact = cs.adContact
        }

        if !secondContact.isEmpty {
            drawContactLine(secondRole, bold: true, y: cY)
            cY -= 10
            drawContactLine(secondContact, bold: false, y: cY)
        }

        // --- Box 2: MILESTONES & MEAL TIMES ---
        let readyLabel = lang == .spanish ? "LISTOS" : "READY TO SHOOT"
        let lunchLabel = lang == .spanish ? "ALMUERZO" : "LUNCH"
        let snackLabel = lang == .spanish ? "MERIENDA" : "SNACK"
        let wrapLabel  = lang == .spanish ? "FIN / CENA" : "WRAP"

        var milestones: [(String, String)] = []
        if !cs.readyToShootTime.isEmpty { milestones.append((readyLabel, cs.readyToShootTime)) }
        if !cs.lunchTime.isEmpty        { milestones.append((lunchLabel, cs.lunchTime)) }
        if !cs.snackTime.isEmpty        { milestones.append((snackLabel, cs.snackTime)) }
        if !cs.dinnerTime.isEmpty       { milestones.append((wrapLabel, cs.dinnerTime)) }

        if milestones.isEmpty {
            milestones = [(readyLabel, ""), (lunchLabel, ""), (snackLabel, ""), (wrapLabel, "")]
        }

        let rowH = height / CGFloat(milestones.count)
        for (i, m) in milestones.enumerated() {
            let mRect = CGRect(x: r2.minX, y: r2.maxY - CGFloat(i + 1) * rowH, width: r2.width, height: rowH)
            canvas.stroke(mRect, color: colorBorder, lineWidth: 0.5)

            let mLabel = "\(m.0)................................."
            canvas.draw(mLabel, in: CGRect(x: mRect.minX + 6, y: mRect.midY - 5, width: mRect.width - 52, height: 11),
                        font: fontBoldBody, color: colorBlack)

            canvas.draw(m.1, in: CGRect(x: mRect.maxX - 50, y: mRect.midY - 5, width: 46, height: 11),
                        font: fontBoldBody, color: colorBlack, alignment: .center)
        }

        // --- Box 3: WEATHER FORECAST ---
        let weatherTitle = lang == .spanish ? "☁ PREVISIÓN METEOROLÓGICA" : "☁ WEATHER FORECAST"
        canvas.draw(weatherTitle, in: CGRect(x: r3.minX + 4, y: r3.maxY - 13, width: r3.width - 8, height: 12),
                    font: fontSectionHdr, color: colorBlack, alignment: .center)

        var wY = r3.maxY - 25
        var weatherLines: [String] = []
        if !cs.weatherTemp.isEmpty       { weatherLines.append("Temp: \(cs.weatherTemp)") }
        if !cs.weatherCondition.isEmpty  { weatherLines.append(cs.weatherCondition) }
        if !cs.weatherPrecipWind.isEmpty { weatherLines.append(cs.weatherPrecipWind) }
        if !cs.sunTimes.isEmpty          { weatherLines.append(cs.sunTimes) }

        for line in weatherLines {
            let bold = line.uppercased().contains("SUNRISE") || line.uppercased().contains("AMANECE")
            canvas.draw(line, in: CGRect(x: r3.minX + 4, y: wY, width: r3.width - 8, height: 10),
                        font: bold ? fontBoldBody : fontRegularBody, color: colorBlack, alignment: .center)
            wY -= 10
        }

        return y - height
    }

    // MARK: - 4. Basecamp Bar (Above Hospital)

    private static func drawBasecampBar(on canvas: PDFCanvas, y: CGFloat, callSheet: CallSheetData, lang: AppLanguage) -> CGFloat {
        let height: CGFloat = 18
        let rect = CGRect(x: margin, y: y - height, width: contentWidth, height: height)

        canvas.stroke(rect, color: colorBorder, lineWidth: 0.75)

        let basecampTitle = lang == .spanish ? "⛺ BASECAMP / BASE DE RODAJE:" : "⛺ BASECAMP:"
        let basecampText = callSheet.basecampLocation.trimmingCharacters(in: .whitespaces)
        let full = basecampText.isEmpty ? basecampTitle : "\(basecampTitle) \(basecampText)"
        canvas.draw(full, in: CGRect(x: rect.minX + 6, y: rect.midY - 5, width: rect.width - 12, height: 11),
                    font: fontBoldBody, color: colorBlack)

        return y - height
    }

    // MARK: - 5. Nearest Hospital

    private static func drawHospitalBar(on canvas: PDFCanvas, y: CGFloat, callSheet: CallSheetData, lang: AppLanguage) -> CGFloat {
        let height: CGFloat = 18
        let rect = CGRect(x: margin, y: y - height, width: contentWidth, height: height)

        canvas.stroke(rect, color: colorBorder, lineWidth: 1)

        let hospTitle = lang == .spanish ? "✚ HOSPITAL MÁS CERCANO:" : "✚ NEAREST HOSPITAL:"
        let hospText = callSheet.nearestHospital.trimmingCharacters(in: .whitespaces)
        let full = hospText.isEmpty ? hospTitle : "\(hospTitle) \(hospText)"
        canvas.draw(full, in: CGRect(x: rect.minX + 6, y: rect.midY - 5, width: rect.width - 12, height: 11),
                    font: fontBoldBody, color: colorBlack)

        return y - height - 4
    }

    // MARK: - 6. Scenes Table

    private static func drawScenesTable(on canvas: PDFCanvas, y: CGFloat, shootDay: ShootDay, lang: AppLanguage, ensureRoom: (CGFloat) -> Void) -> CGFloat {
        var y = y
        let headerH: CGFloat = 16
        let cols: [(title: String, width: CGFloat)] = [
            (lang == .spanish ? "ESCENA" : "SCENE",       65),
            (lang == .spanish ? "DECORADO" : "SET / DESCRIPTION", 180),
            (lang == .spanish ? "PERSONAJES" : "CAST",        95),
            (lang == .spanish ? "PÁGINAS" : "PAGES",       55),
            ("LOC",         35),
            (lang == .spanish ? "DIRECCIÓN" : "ADDRESS",     contentWidth - 65 - 180 - 95 - 55 - 35)
        ]

        ensureRoom(headerH + 30)

        // Draw Table Header
        drawTableHeader(on: canvas, cols: cols, y: y, height: headerH)
        y -= headerH

        let dayLocations = shootDay.callSheet.locations

        // Draw Scenes
        for scene in shootDay.scenes {
            let rowH: CGFloat = 34
            ensureRoom(rowH)

            var x = margin

            // Col 1: SCENE (# + INT/EXT/DAY)
            let c1 = CGRect(x: x, y: y - rowH, width: cols[0].width, height: rowH)
            drawCellBorder(on: canvas, c1)
            let numStr = scene.extractedSceneNumber
            let typeStr = "\(scene.intExtString) / \(scene.dayNightType.rawValue.uppercased())"
            drawCenteredText(on: canvas, numStr, font: fontBannerTitle, in: CGRect(x: c1.minX, y: c1.midY - 2, width: c1.width, height: 14))
            drawCenteredText(on: canvas, typeStr, font: fontSmall, in: CGRect(x: c1.minX, y: c1.minY + 3, width: c1.width, height: 10))
            x += cols[0].width

            // Col 2: SET / DESCRIPTION (Clean decorado name without INT/EXT or time suffix!)
            let c2 = CGRect(x: x, y: y - rowH, width: cols[1].width, height: rowH)
            drawCellBorder(on: canvas, c2)
            let decoradoStr = scene.decoradoOnly
            let synStr = scene.summary.isEmpty ? "" : scene.summary
            drawCenteredText(on: canvas, decoradoStr, font: fontBoldBody, in: CGRect(x: c2.minX + 4, y: c2.midY - 2, width: c2.width - 8, height: 12))
            if !synStr.isEmpty {
                drawCenteredText(on: canvas, synStr, font: fontSmall, in: CGRect(x: c2.minX + 4, y: c2.minY + 3, width: c2.width - 8, height: 10))
            }
            x += cols[1].width

            // Col 3: CAST
            let c3 = CGRect(x: x, y: y - rowH, width: cols[2].width, height: rowH)
            drawCellBorder(on: canvas, c3)
            let castStr = scene.cast.joined(separator: ", ")
            drawCenteredText(on: canvas, castStr, font: fontRegularBody, in: CGRect(x: c3.minX + 4, y: c3.midY - 6, width: c3.width - 8, height: 12))
            x += cols[2].width

            // Col 4: PAGES
            let c4 = CGRect(x: x, y: y - rowH, width: cols[3].width, height: rowH)
            drawCellBorder(on: canvas, c4)
            let pgs = formattedEighths(scene.duration)
            drawCenteredText(on: canvas, pgs, font: fontRegularBody, in: CGRect(x: c4.minX, y: c4.midY - 6, width: c4.width, height: 12))
            x += cols[3].width

            // Determine LOC index and Address
            var locIndexStr = "1"
            var addrStr = ""
            if let matchedIdx = dayLocations.firstIndex(where: {
                (!scene.realLocation.isEmpty && $0.name.caseInsensitiveCompare(scene.realLocation) == .orderedSame) ||
                (!scene.decoradoOnly.isEmpty && $0.name.caseInsensitiveCompare(scene.decoradoOnly) == .orderedSame)
            }) {
                locIndexStr = "\(matchedIdx + 1)"
                addrStr = dayLocations[matchedIdx].address
            } else if !dayLocations.isEmpty {
                locIndexStr = "1"
                addrStr = dayLocations[0].address
            }

            // Col 5: LOC
            let c5 = CGRect(x: x, y: y - rowH, width: cols[4].width, height: rowH)
            drawCellBorder(on: canvas, c5)
            drawCenteredText(on: canvas, locIndexStr, font: fontRegularBody, in: CGRect(x: c5.minX, y: c5.midY - 6, width: c5.width, height: 12))
            x += cols[4].width

            // Col 6: ADDRESS
            let c6 = CGRect(x: x, y: y - rowH, width: cols[5].width, height: rowH)
            drawCellBorder(on: canvas, c6)
            drawCenteredText(on: canvas, addrStr, font: fontTiny, in: CGRect(x: c6.minX + 4, y: c6.midY - 10, width: c6.width - 8, height: 20))

            y -= rowH
        }

        return y - 6
    }

    // MARK: - 7. Cast Table (with SCENES column)

    private static func drawCastTable(on canvas: PDFCanvas, y: CGFloat, shootDay: ShootDay, productionInfo: ProductionInfo, lang: AppLanguage, ensureRoom: (CGFloat) -> Void) -> CGFloat {
        var y = y
        let headerH: CGFloat = 16
        let cols: [(title: String, width: CGFloat)] = [
            (lang == .spanish ? "PERSONAJE" : "CHARACTER",       75),
            (lang == .spanish ? "ACTOR/ACTRIZ" : "ACTOR/ACTRESS",  105),
            (lang == .spanish ? "ESCENAS" : "SCENES",            55),
            (lang == .spanish ? "ECDT" : "STATUS",               32),
            (lang == .spanish ? "RECOGIDA" : "PICK UP",          48),
            (lang == .spanish ? "VEST. Y MAQ." : "H/MU & WARD.", 62),
            (lang == .spanish ? "LISTOS" : "ON SET",             48),
            (lang == .spanish ? "FIN" : "WRAP",                 48),
            ("LOC",             contentWidth - 75 - 105 - 55 - 32 - 48 - 62 - 48 - 48)
        ]

        ensureRoom(headerH + 20)

        // Draw Table Header
        drawTableHeader(on: canvas, cols: cols, y: y, height: headerH)
        y -= headerH

        let entries = shootDay.callSheet.castCallEntries
        for entry in entries {
            let rowH: CGFloat = 16
            ensureRoom(rowH)

            var x = margin

            // Determine scenes for this character if entry.sceneNumbers is empty
            var scenesStr = entry.sceneNumbers.trimmingCharacters(in: .whitespaces)
            if scenesStr.isEmpty {
                let matchedScenes = shootDay.scenes.filter { scene in
                    scene.cast.contains(where: { $0.caseInsensitiveCompare(entry.characterName) == .orderedSame })
                }.map { $0.extractedSceneNumber }
                scenesStr = matchedScenes.joined(separator: ", ")
            }

            let vals = [
                entry.characterName,
                entry.actorName,
                scenesStr,
                entry.ecdt,
                entry.pickupTime,
                entry.hmuWardrobeTime,
                entry.onSetTime,
                entry.wrapTime,
                entry.locationIndex
            ]

            for (i, val) in vals.enumerated() {
                let cell = CGRect(x: x, y: y - rowH, width: cols[i].width, height: rowH)
                drawCellBorder(on: canvas, cell)
                let isLeft = (i == 0 || i == 1)
                let textX = isLeft ? cell.minX + 4 : cell.minX
                let textW = isLeft ? cell.width - 8 : cell.width
                canvas.draw(val, in: CGRect(x: textX, y: cell.midY - 5, width: textW, height: 11),
                            font: isLeft ? fontBoldBody : fontRegularBody, color: colorBlack, alignment: isLeft ? .leading : .center)
                x += cols[i].width
            }
            y -= rowH
        }

        return y - 6
    }

    // MARK: - 8. Crew Call Table

    private static func drawCrewTable(on canvas: PDFCanvas, y: CGFloat, shootDay: ShootDay, productionInfo: ProductionInfo, lang: AppLanguage, ensureRoom: (CGFloat) -> Void) -> CGFloat {
        var y = y
        let bannerH: CGFloat = 16
        ensureRoom(bannerH + 30)

        // Banner Header
        let crewTitle = lang == .spanish ? "CITACIÓN ESPECÍFICA DEL EQUIPO TÉCNICO" : "CREW CALL TIMES"
        drawSectionBanner(on: canvas, crewTitle, y: y, height: bannerH)
        y -= bannerH

        let entries = shootDay.callSheet.crewCallEntries.isEmpty
            ? productionInfo.crew.map { CrewCallEntry(role: $0.role, name: $0.name, callTime: "07:30 AM", phone: $0.phone) }
            : shootDay.callSheet.crewCallEntries

        let colWidth3 = contentWidth / 3
        let rowH: CGFloat = 14

        let chunks = stride(from: 0, to: entries.count, by: 3).map {
            Array(entries[$0..<min($0 + 3, entries.count)])
        }

        for chunk in chunks {
            ensureRoom(rowH)
            for (cIdx, member) in chunk.enumerated() {
                let cRect = CGRect(x: margin + CGFloat(cIdx) * colWidth3, y: y - rowH, width: colWidth3, height: rowH)
                drawCellBorder(on: canvas, cRect)

                let roleWidth: CGFloat = colWidth3 - 52

                var memberName = member.name.trimmingCharacters(in: .whitespaces)
                let memberRole = member.role.trimmingCharacters(in: .whitespaces)
                if memberName.isEmpty, !memberRole.isEmpty {
                    if let matched = productionInfo.crew.first(where: { $0.role.caseInsensitiveCompare(memberRole) == .orderedSame }) {
                        memberName = matched.name.trimmingCharacters(in: .whitespaces)
                    }
                }

                let label: String
                if !memberRole.isEmpty && !memberName.isEmpty {
                    label = "\(memberRole): \(memberName)"
                } else if !memberRole.isEmpty {
                    label = memberRole
                } else if !memberName.isEmpty {
                    label = memberName
                } else {
                    label = "—"
                }

                canvas.draw(label, in: CGRect(x: cRect.minX + 4, y: cRect.midY - 5, width: roleWidth - 6, height: 11),
                            font: fontRegularBody, color: colorBlack)

                let timeStr = member.callTime.isEmpty ? "07:30 AM" : member.callTime
                canvas.draw(timeStr, in: CGRect(x: cRect.maxX - 48, y: cRect.midY - 5, width: 46, height: 11),
                            font: fontBoldBody, color: colorBlack, alignment: .center)
            }
            y -= rowH
        }

        return y - 6
    }

    // MARK: - 9. General Notes

    private static func drawProductionNotes(on canvas: PDFCanvas, y: CGFloat, callSheet: CallSheetData, lang: AppLanguage, ensureRoom: (CGFloat) -> Void) -> CGFloat {
        var y = y
        let bannerH: CGFloat = 16
        ensureRoom(bannerH + 30)

        let notesTitle = lang == .spanish ? "OBSERVACIONES GENERALES" : "GENERAL NOTES"
        drawSectionBanner(on: canvas, notesTitle, y: y, height: bannerH)
        y -= bannerH

        let notesText = callSheet.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? callSheet.productionNotes.joined(separator: "\n")
            : callSheet.notes

        if !notesText.isEmpty {
            // Wrapped with 3pt between lines, the paragraph style the notes always had.
            let textHeight = canvas.height(of: notesText, font: fontBoldBody, width: contentWidth - 16, lineSpacing: 3)
            let boxHeight = max(30, textHeight + 14)

            ensureRoom(boxHeight)
            let rRect = CGRect(x: margin, y: y - boxHeight, width: contentWidth, height: boxHeight)
            drawCellBorder(on: canvas, rRect)

            canvas.draw(notesText, in: CGRect(x: rRect.minX + 8, y: rRect.minY + 7, width: rRect.width - 16, height: boxHeight - 14),
                        font: fontBoldBody, color: colorDark, lineSpacing: 3)
            y -= boxHeight
        } else {
            let emptyH: CGFloat = 30
            ensureRoom(emptyH)
            let rRect = CGRect(x: margin, y: y - emptyH, width: contentWidth, height: emptyH)
            drawCellBorder(on: canvas, rRect)
            y -= emptyH
        }

        return y
    }

    // MARK: - Drawing Helpers

    private static func drawCellBorder(on canvas: PDFCanvas, _ rect: CGRect) {
        canvas.stroke(rect, color: colorBorder, lineWidth: 0.5)
    }

    private static func drawCenteredText(on canvas: PDFCanvas, _ text: String, font: PDFFont, in rect: CGRect) {
        canvas.draw(text, in: rect, font: font, color: colorBlack, alignment: .center, lineBreak: .truncateTail)
    }

    /// A gray header row of centered column titles, each cell bordered.
    private static func drawTableHeader(on canvas: PDFCanvas, cols: [(title: String, width: CGFloat)], y: CGFloat, height headerH: CGFloat) {
        let hRect = CGRect(x: margin, y: y - headerH, width: contentWidth, height: headerH)
        canvas.fill(hRect, color: colorGrayHeader)

        var curX = margin
        for c in cols {
            let cell = CGRect(x: curX, y: y - headerH, width: c.width, height: headerH)
            canvas.stroke(cell, color: colorBorder, lineWidth: 0.5)
            canvas.draw(c.title, in: CGRect(x: cell.minX, y: cell.midY - 5, width: cell.width, height: 11),
                        font: fontTableHdr, color: colorBlack, alignment: .center)
            curX += c.width
        }
    }

    /// A full-width gray banner with a centered section title (crew calls, notes).
    private static func drawSectionBanner(on canvas: PDFCanvas, _ title: String, y: CGFloat, height bannerH: CGFloat) {
        let bRect = CGRect(x: margin, y: y - bannerH, width: contentWidth, height: bannerH)
        canvas.fill(bRect, color: colorGrayHeader)
        canvas.stroke(bRect, color: colorBorder, lineWidth: 0.5)
        canvas.draw(title, in: CGRect(x: bRect.minX, y: bRect.midY - 5, width: bRect.width, height: 11),
                    font: fontSectionHdr, color: colorBlack, alignment: .center)
    }
}

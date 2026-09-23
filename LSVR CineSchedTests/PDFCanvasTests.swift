//
//  PDFCanvasTests.swift
//  LSVR CineSchedTests
//
//  The shared PDF drawing helper: TextKit-compatible line metrics (the numbers here were
//  measured from `NSAttributedString.draw(in:)` on the Mac before the exporters moved
//  off AppKit, so a change breaks the pixel match), wrapping, truncation, and a PDF that
//  PDFKit can read back on every platform.
//

import CoreText
import Foundation
import Testing
import PDFKit
@testable import LSVR_CineSched

@MainActor
struct PDFCanvasTests {

    // The TextKit numbers below were measured against the Mac's system face. iOS and
    // visionOS ship a differently-hinted SF (`PDFFixture.hasMacSystemFace`), so there the
    // literal tables have nothing to compare against and the rounding rules are checked on
    // their own.

    @Test(.enabled(if: PDFFixture.hasMacSystemFace, "TextKit reference values are from the Mac's SF face"))
    func lineMetricsMatchTextKit() {
        // (size, TextKit line height, TextKit baseline offset from the top of the line)
        let expected: [(CGFloat, CGFloat, CGFloat)] = [
            (18, 21, 17), (11, 14, 11), (10, 13, 10), (9.5, 12, 9),
            (9, 11, 9), (8.5, 10, 8), (8, 10, 8), (7.5, 9, 7),
        ]
        for (size, lineHeight, baseline) in expected {
            let regular = PDFFont.system(size: size)
            let bold    = PDFFont.boldSystem(size: size)
            #expect(regular.lineHeight == lineHeight, "\(size)pt line height")
            #expect(regular.baselineOffset == baseline, "\(size)pt baseline")
            #expect(bold.lineHeight == lineHeight, "\(size)pt bold line height")
            #expect(bold.baselineOffset == baseline, "\(size)pt bold baseline")
        }
    }

    /// The rounding rule itself, on whatever SF face the platform has: whole-point baseline
    /// and line height, the baseline never more than half a point above the true ascent
    /// (it is rounded, not floored) and the line never more than a point short of, or two
    /// points over, the font's own ascent + descent + leading.
    @Test func lineMetricsAreWholePointsCloseToTheFontsOwn() {
        for size: CGFloat in [7.5, 8, 8.5, 9, 9.5, 10, 11, 16, 18] {
            for font in [PDFFont.system(size: size), PDFFont.boldSystem(size: size), PDFFont.italicSystem(size: size)] {
                let natural = font.ascent + font.descent + font.leading
                #expect(font.baselineOffset == font.baselineOffset.rounded())
                #expect(font.lineHeight == font.lineHeight.rounded())
                #expect(abs(font.baselineOffset - font.ascent) <= 0.5)
                #expect(font.lineHeight > natural - 1 && font.lineHeight < natural + 2, "\(size)pt")
            }
        }
    }

    /// `NSAttributedString.boundingRect` measured a line as `round(ascent) + round(descent)`
    /// (what `NSLayoutManager.defaultLineHeight` gives), one point shorter than the line
    /// `draw(in:)` then advanced by wherever SF's descent rounds down: 11pt measured 13
    /// but drew 14 to the line. The breakdown sheet's auto-scaling loop compares the
    /// measured number against its cell, so both numbers are kept.
    @Test(.enabled(if: PDFFixture.hasMacSystemFace, "TextKit reference values are from the Mac's SF face"))
    func boundingLineHeightMatchesTextKitBoundingRect() {
        // (size, boundingRect line height, draw(in:) line height)
        let expected: [(CGFloat, CGFloat, CGFloat)] = [
            (7, 8, 9), (8, 10, 10), (9, 11, 11), (9.5, 11, 12), (10, 12, 13), (11, 13, 14),
            (11.5, 13, 14), (13, 16, 16), (15, 18, 19), (18, 21, 21),
        ]
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        for (size, bounding, drawn) in expected {
            let font = PDFFont.system(size: size)
            #expect(font.boundingLineHeight == bounding, "\(size)pt bounding line height")
            #expect(font.lineHeight == drawn, "\(size)pt drawn line height")
            #expect(PDFFont.boldSystem(size: size).boundingLineHeight == bounding, "\(size)pt bold")
            // Three lines with the breakdown sheet's spacing: boundingRect measured
            // 3 × line + 2 × spacing (36.42 at 9.5pt, 42.96 at 11pt).
            let spacing = max(1.5, size * 0.18)
            #expect(canvas.boundingHeight(of: "One\nTwo\nThree", font: font, width: 500, lineSpacing: spacing) == 3 * bounding + 2 * spacing, "\(size)pt")
        }
        #expect(canvas.boundingHeight(of: "", font: .system(size: 11), width: 500) == 0)
    }

    /// A named face measured the same either way (its rounded descent is what the line
    /// carries), so the two heights agree.
    @Test func namedFaceBoundingLineHeightIsItsLineHeight() {
        for size: CGFloat in [7, 8.5, 12] {
            let font = PDFFont.named("Helvetica-Oblique", size: size)
            #expect(font.boundingLineHeight == font.lineHeight)
        }
    }

    /// TextKit laid a line out only if its top edge was above the rect's bottom, and it
    /// drew every line it laid out whole (clipped to the rect when the text overran it):
    /// three 9pt lines (11pt each) in an 11pt rect gave one line, in a 12pt rect two,
    /// with 1.62pt of spacing the second needed 12.62.
    @Test func linesWhoseTopIsBelowTheRectAreNotDrawn() {
        let font = PDFFont.system(size: 9)
        func drawnLines(height: CGFloat, spacing: CGFloat = 0) -> [String] {
            let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
            canvas.beginPage()
            canvas.draw("One\nTwo\nThree", in: CGRect(x: 100, y: 700 - height, width: 200, height: height), font: font, color: .pdfBlack, lineSpacing: spacing)
            let text = PDFDocument(data: canvas.finish())?.page(at: 0)?.string ?? ""
            return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }
        let line = font.lineHeight
        #expect(drawnLines(height: line) == ["One"])
        #expect(drawnLines(height: line + 0.25) == ["One", "Two"])
        #expect(drawnLines(height: 2 * line) == ["One", "Two"])
        #expect(drawnLines(height: 2 * line + 0.25) == ["One", "Two", "Three"])
        #expect(drawnLines(height: 100) == ["One", "Two", "Three"])
        #expect(drawnLines(height: line + 1.62, spacing: 1.62) == ["One"])
        #expect(drawnLines(height: line + 1.62 + 0.25, spacing: 1.62) == ["One", "Two"])
    }

    /// `NSColor(calibratedWhite:)` was the generic gamma-1.8 gray, a visibly different
    /// shade from `NSColor(white:)`'s gamma-2.2 space at the same number.
    @Test func calibratedGrayIsTheGenericGraySpace() {
        let calibrated = CGColor.calibratedGray(0.35)
        #expect(calibrated.colorSpace?.name == "kCGColorSpaceGenericGray" as CFString)
        #expect(calibrated.components == [0.35, 1])
        #expect(CGColor.gray(0.35).colorSpace?.name == CGColorSpace.genericGrayGamma2_2)
        #expect(CGColor.calibratedGray(0.9, alpha: 0.5).alpha == 0.5)
    }

    @Test func wrappedHeightIsWholeLines() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        let font = PDFFont.boldSystem(size: 18)
        let text = "A quite long project title that wraps onto a second line for sure yes"
        let narrow = canvas.height(of: text, font: font, width: 300)
        #expect(narrow.truncatingRemainder(dividingBy: font.lineHeight) == 0)
        #expect(narrow >= 2 * font.lineHeight)
        #expect(canvas.height(of: text, font: font, width: 2000) == font.lineHeight)
        #expect(canvas.height(of: "", font: font, width: 300) == 0)
    }

    @Test(.enabled(if: PDFFixture.hasMacSystemFace, "TextKit reference values are from the Mac's SF face"))
    func wrappedHeightMatchesTextKitBoundingRect() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        let font = PDFFont.boldSystem(size: 18)
        let text = "A quite long project title that wraps onto a second line for sure yes"
        // Measured with NSAttributedString.boundingRect at 300pt: three 21pt lines.
        #expect(canvas.height(of: text, font: font, width: 300) == 63)
    }

    @Test func namedFaceResolvesByPostScriptName() {
        #expect(PDFFont.named("Helvetica-Oblique", size: 8.5).postScriptName == "Helvetica-Oblique")
        #expect(PDFFont.named("Helvetica-Oblique", size: 8.5).pointSize == 8.5)
    }

    /// TextKit gives a named face without leading a synthetic gap above its ascent (a fifth
    /// of the size, rounded) and rounds its descent, so Helvetica sits lower in its line than
    /// SF does. Measured with `NSLayoutManager.defaultBaselineOffset(for:)` / `defaultLineHeight(for:)`
    /// and `NSAttributedString.size()` on the Mac (all three agree for these faces).
    @Test(.enabled(if: PDFFixture.hasMacSystemFace, "TextKit reference values are from the Mac"))
    func namedFaceMetricsMatchTextKit() {
        // (size, TextKit line height, TextKit baseline offset)
        let expected: [(CGFloat, CGFloat, CGFloat)] = [
            (7, 8, 6), (7.5, 10, 8), (8.5, 11, 9), (10, 12, 10), (12, 14, 11), (20, 24, 19),
        ]
        for (size, lineHeight, baseline) in expected {
            let font = PDFFont.named("Helvetica-Oblique", size: size)
            #expect(font.lineHeight == lineHeight, "\(size)pt line height")
            #expect(font.baselineOffset == baseline, "\(size)pt baseline")
        }
    }

    /// The semibold weight is the same SF face as the regular one (same metrics, same
    /// tracking), just heavier — what `NSFont.systemFont(ofSize:weight: .semibold)` gave.
    @Test func semiboldSystemIsTheSystemFaceAtASemiboldWeight() {
        let regular  = PDFFont.system(size: 8)
        let semibold = PDFFont.semiboldSystem(size: 8)
        #expect(semibold.postScriptName.localizedCaseInsensitiveContains("semibold"))
        #expect(semibold.postScriptName != regular.postScriptName)
        #expect(semibold.ascent == regular.ascent)
        #expect(semibold.descent == regular.descent)
        #expect(semibold.lineHeight == regular.lineHeight)
        #expect(semibold.baselineOffset == regular.baselineOffset)
    }

    /// A paragraph style's `lineSpacing` went between lines, never after the last one, so
    /// two 8.5pt bold lines with 3pt spacing measured 23pt, not 26.
    @Test func lineSpacingIsAddedBetweenLinesOnly() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        let font = PDFFont.boldSystem(size: 8.5)
        let one = canvas.height(of: "One line", font: font, width: 500, lineSpacing: 3)
        let two = canvas.height(of: "One line\nTwo lines", font: font, width: 500, lineSpacing: 3)
        let three = canvas.height(of: "One line\nTwo lines\nThree", font: font, width: 500, lineSpacing: 3)
        #expect(one == font.lineHeight)
        #expect(two == 2 * font.lineHeight + 3)
        #expect(three == 3 * font.lineHeight + 6)
        #expect(canvas.height(of: "", font: font, width: 500, lineSpacing: 3) == 0)
        if PDFFixture.hasMacSystemFace {
            #expect(two == 23)
        }
    }

    @Test func truncationKeepsWhatFitsAndEndsWithAnEllipsis() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        let font = PDFFont.boldSystem(size: 9.5)
        let text = "A very long title that must be truncated with an ellipsis somewhere"
        canvas.beginPage()
        canvas.draw(text, in: CGRect(x: 100, y: 700, width: 120, height: 12), font: font, color: .pdfBlack, lineBreak: .truncateTail)
        canvas.draw("Untouched", at: CGPoint(x: 100, y: 600), font: font, color: .pdfBlack)
        let doc = PDFDocument(data: canvas.finish())
        let drawn = doc?.page(at: 0)?.string ?? ""

        #expect(drawn.contains("Untouched"))
        let truncated = drawn.components(separatedBy: .newlines).first { $0.hasSuffix("\u{2026}") } ?? ""
        #expect(truncated.hasPrefix("A very long title"))
        #expect(!truncated.contains("somewhere"))
        // The kept prefix plus the ellipsis fits the width, and one more character would not.
        #expect(canvas.width(of: truncated, font: font) <= 120)
        let keptCount = truncated.dropLast().count
        let oneMore = String(text.prefix(keptCount + 1)) + "\u{2026}"
        #expect(canvas.width(of: oneMore, font: font) > 120)
    }

    // MARK: - Images (#40)

    /// A `width` × `height` image of one opaque sRGB color.
    private func solidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The RGB of page 0's pixel at PDF point (`x`, `y`), rasterized at 1 pt a pixel on white.
    private func pixel(_ data: Data, x: Int, y: Int) -> [Int]? {
        guard let page = PDFDocument(data: data)?.page(at: 0)?.pageRef else { return nil }
        let (width, height) = (612, 792)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let i = ((height - 1 - y) * width + x) * 4   // rows run top-down in memory
        return [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
    }

    @Test func aspectFitLeavesMarginsOnTheShortSideOnly() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        // Landscape 2:1 in a square: full width, centred vertically.
        #expect(PDFCanvas.aspectFitRect(for: CGSize(width: 200, height: 100), in: box) == CGRect(x: 100, y: 125, width: 100, height: 50))
        // Portrait 1:4: full height, centred horizontally.
        #expect(PDFCanvas.aspectFitRect(for: CGSize(width: 50, height: 200), in: box) == CGRect(x: 137.5, y: 100, width: 25, height: 100))
        // A small image grows to fit: aspect-fit, not "at most its own size".
        #expect(PDFCanvas.aspectFitRect(for: CGSize(width: 10, height: 10), in: box) == box)
        #expect(PDFCanvas.aspectFitRect(for: .zero, in: box) == .zero)
    }

    @Test func anImageDrawnIntoARectChangesThePageAndLandsAspectFit() throws {
        func page(drawing image: CGImage?) -> (Data, CGRect?) {
            let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
            canvas.beginPage()
            canvas.stroke(CGRect(x: 100, y: 100, width: 200, height: 200), color: .pdfBlack, lineWidth: 0.5)
            let drawn = image.map { canvas.drawImage($0, aspectFitIn: CGRect(x: 100, y: 100, width: 200, height: 200)) }
            return (canvas.finish(), drawn)
        }
        let (blank, _) = page(drawing: nil)
        let (framed, drawn) = page(drawing: solidImage(width: 400, height: 200, red: 1, green: 0, blue: 0))
        #expect(framed.count > blank.count)
        #expect(drawn == CGRect(x: 100, y: 150, width: 200, height: 100))

        // Inside the fitted rect, red; above and below it (the short side), the white page.
        let center = try #require(pixel(framed, x: 200, y: 200))
        #expect(center[0] > 240 && center[1] < 15 && center[2] < 15)
        let above = try #require(pixel(framed, x: 200, y: 280))
        #expect(above == [255, 255, 255])
        let below = try #require(pixel(framed, x: 200, y: 120))
        #expect(below == [255, 255, 255])
        // Upright, not flipped: a band drawn at the image's top lands at the rect's top.
        let banded = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        banded.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        banded.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        banded.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        banded.fill(CGRect(x: 0, y: 75, width: 100, height: 25))   // the top quarter, in CG's y-up space
        let (bandedPage, _) = page(drawing: banded.makeImage()!)
        let top = try #require(pixel(bandedPage, x: 200, y: 280))
        #expect(top[0] > 240 && top[2] < 15)
        let bottom = try #require(pixel(bandedPage, x: 200, y: 120))
        #expect(bottom[2] > 240 && bottom[0] < 15)
    }

    @Test func producesAReadablePDFWithOnePageEachBeginPage() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        for n in 1...3 {
            canvas.beginPage()
            canvas.fill(CGRect(x: 40, y: 40, width: 100, height: 20), color: .hex("FEF3C7"))
            canvas.stroke(CGRect(x: 40, y: 40, width: 100, height: 20), cornerRadius: 3, color: .gray(0.5), lineWidth: 0.5)
            canvas.line(from: CGPoint(x: 40, y: 700), to: CGPoint(x: 572, y: 700), color: .pdfBlack)
            canvas.stroke(lines: [(CGPoint(x: 40, y: 690), CGPoint(x: 572, y: 690)), (CGPoint(x: 40, y: 680), CGPoint(x: 40, y: 700))], color: .pdfLightGray, lineWidth: 0.4)
            canvas.draw("Page \(n)", in: CGRect(x: 40, y: 720, width: 532, height: 14), font: .system(size: 11), color: .pdfBlack, alignment: .center)
        }
        let doc = PDFDocument(data: canvas.finish())
        #expect(doc?.pageCount == 3)
        #expect(canvas.pageCount == 3)
        #expect(doc?.page(at: 2)?.string?.contains("Page 3") == true)
    }
}

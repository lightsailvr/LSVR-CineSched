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

    /// The TextKit numbers below were measured against the Mac's system face (18pt ascent
    /// 17.40234375). iOS and visionOS ship a differently-hinted SF, so there the literal
    /// table has nothing to compare against and the rounding rule is checked on its own.
    nonisolated private static var hasMacSystemFace: Bool {
        CTFontCreateUIFontForLanguage(.system, 18, nil).map { CTFontGetAscent($0) == 17.40234375 } ?? false
    }

    @Test(.enabled(if: hasMacSystemFace, "TextKit reference values are from the Mac's SF face"))
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

    @Test(.enabled(if: hasMacSystemFace, "TextKit reference values are from the Mac's SF face"))
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
    @Test(.enabled(if: hasMacSystemFace, "TextKit reference values are from the Mac"))
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
        if Self.hasMacSystemFace {
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

    @Test func producesAReadablePDFWithOnePageEachBeginPage() {
        let canvas = PDFCanvas(pageSize: CGSize(width: 612, height: 792))!
        for n in 1...3 {
            canvas.beginPage()
            canvas.fill(CGRect(x: 40, y: 40, width: 100, height: 20), color: .hex("FEF3C7"))
            canvas.stroke(CGRect(x: 40, y: 40, width: 100, height: 20), cornerRadius: 3, color: .gray(0.5), lineWidth: 0.5)
            canvas.line(from: CGPoint(x: 40, y: 700), to: CGPoint(x: 572, y: 700), color: .pdfBlack)
            canvas.draw("Page \(n)", in: CGRect(x: 40, y: 720, width: 532, height: 14), font: .system(size: 11), color: .pdfBlack, alignment: .center)
        }
        let doc = PDFDocument(data: canvas.finish())
        #expect(doc?.pageCount == 3)
        #expect(canvas.pageCount == 3)
        #expect(doc?.page(at: 2)?.string?.contains("Page 3") == true)
    }
}

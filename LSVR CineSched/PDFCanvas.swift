// PDFCanvas.swift
// The shared PDF drawing helper (ADR 0002's "shared in-repo helper", ADR 0003's exporter
// seam remover): one PDF context, page lifecycle, rectangles, lines and text, all on
// CoreGraphics + CoreText so an exporter compiles and runs on every platform. Nothing in
// this file, or in an exporter built on it, may import AppKit or UIKit.
//
// Adopting it in an exporter that still draws through AppKit (`PDFExporter`,
// `CallSheetExporter`, `BreakdownExporter`, `DaysOutOfDaysExporter`):
//
// 1. Replace the `CGDataConsumer` / `CGContext` / `NSGraphicsContext` boilerplate with a
//    `PDFCanvas(pageSize:)`, `beginPage()` / `endPage()` per page and `finish()` at the end.
//    `canvas.context` is still there for anything the helper does not cover.
// 2. `NSFont.systemFont(ofSize:)` becomes `PDFFont.system(size:)`, `boldSystemFont` becomes
//    `PDFFont.boldSystem(size:)`, an italic system descriptor becomes `PDFFont.italicSystem(size:)`.
//    These are the same SF faces AppKit hands out, with the same metrics and tracking. A named
//    face (`CallSheetExporter`'s Helvetica italic via `NSFontManager`) becomes
//    `PDFFont.named("Helvetica-Oblique", size:)`, which falls back to the system face.
// 3. `NSColor` becomes `CGColor`: `CGColor.gray(0.15)` for `NSColor(white:alpha:)`,
//    `CGColor.hex("1F2937")` for `NSColor(Color(hex:))` / `NSColor(hexString:)`,
//    `CGColor.of(scene.stripColor)` for `NSColor(someSwiftUIColor)`, and `.withAlpha(_:)`
//    for `withAlphaComponent`. Strip colors still come only from `Scene.stripColor`.
// 4. `NSBezierPath(rect:).fill()` / `.stroke()` become `fill(_:color:)` / `stroke(_:color:lineWidth:)`
//    (both take a `cornerRadius:` for `NSBezierPath(roundedRect:)`), a two-point path becomes
//    `line(from:to:color:lineWidth:)`, and `NSBezierPath.addClip()` becomes `clipped(to:) { }`.
// 5. `NSAttributedString.draw(in:)` becomes `draw(_:in:font:color:alignment:lineBreak:)`. It
//    lays text out the way TextKit did — first baseline `round(ascent)` below the top of the
//    rect, `lineHeight` per line, tail truncation or word wrapping, clipped only when the
//    lines are taller than the rect — so migrated output stays pixel-for-pixel where it was.
//    `boundingRect(with:options:)` becomes `height(of:font:width:)`.
//    Exporters that already used `CTLineDraw` at a baseline keep doing so through
//    `draw(_:at:font:color:anchor:maxWidth:)`, which also right-aligns, centers and truncates.
//
// Coordinates are PDF coordinates: the origin is the bottom-left corner of the page and y
// grows upward, exactly as the exporters have always worked. Every measurement is in points.

import CoreGraphics
import CoreText
import Foundation
import SwiftUI

// MARK: - Fonts

/// A CoreText font with the line metrics TextKit used when the exporters drew through
/// `NSAttributedString.draw(in:)`. The system faces cover almost every PDF; `named` is for
/// the odd Helvetica.
struct PDFFont {
    let ctFont: CTFont

    static func system(size: CGFloat) -> PDFFont {
        PDFFont(ctFont: CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil))
    }

    static func boldSystem(size: CGFloat) -> PDFFont {
        PDFFont(ctFont: CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil))
    }

    static func italicSystem(size: CGFloat) -> PDFFont {
        let base = system(size: size).ctFont
        return PDFFont(ctFont: CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitItalic, .traitItalic) ?? base)
    }

    /// A face by PostScript name (`"Helvetica-Oblique"`). CoreText substitutes a fallback for an
    /// unknown name rather than failing, so check `postScriptName` if the exact face matters.
    static func named(_ postScriptName: String, size: CGFloat) -> PDFFont {
        PDFFont(ctFont: CTFontCreateWithName(postScriptName as CFString, size, nil))
    }

    var postScriptName: String { CTFontCopyPostScriptName(ctFont) as String }

    var pointSize: CGFloat { CTFontGetSize(ctFont) }
    var ascent:    CGFloat { CTFontGetAscent(ctFont) }
    var descent:   CGFloat { CTFontGetDescent(ctFont) }
    var leading:   CGFloat { CTFontGetLeading(ctFont) }

    /// Distance from the top of a line to its baseline, as TextKit lays it out: the ascent
    /// rounded to a whole point (SF's 17.4pt ascent at 18pt sits the baseline 17pt down).
    var baselineOffset: CGFloat { ascent.rounded() }

    /// TextKit's line height for this face: rounded ascent plus the descent and leading
    /// rounded *up*, so an 11pt system line is 14pt tall (11 + 3), not 12.95.
    var lineHeight: CGFloat { baselineOffset + descent.rounded(.up) + leading.rounded(.up) }
}

// MARK: - Colors

extension CGColor {
    /// A neutral gray, in the same generic gamma-2.2 space `NSColor(white:alpha:)` used.
    static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(genericGrayGamma2_2Gray: white, alpha: alpha)
    }

    static let pdfBlack = CGColor.gray(0)
    static let pdfWhite = CGColor.gray(1)

    /// The sRGB color behind a SwiftUI `Color`, through `Color.Resolved` rather than
    /// NSColor / UIColor. Exporters only pass static hex or palette colors, never an
    /// appearance-dependent system color, so resolving in a default environment is exact.
    static func of(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }

    /// `"1F2937"`, `"#1F2937"`, or the other forms `Color(hex:)` accepts.
    static func hex(_ hex: String) -> CGColor {
        of(Color(hex: hex))
    }

    func withAlpha(_ alpha: CGFloat) -> CGColor {
        copy(alpha: alpha) ?? self
    }
}

// MARK: - Canvas

final class PDFCanvas {

    enum Alignment {
        case leading, center, trailing

        /// CoreText's flush factor: 0 sets the line against the left edge, 1 the right.
        fileprivate var flush: CGFloat {
            switch self {
            case .leading:  return 0
            case .center:   return 0.5
            case .trailing: return 1
            }
        }
    }

    enum LineBreak {
        /// Word-wrap onto as many lines as the text needs (`NSLineBreakMode.byWordWrapping`).
        case wrap
        /// One line, cut with an ellipsis when it would overflow (`.byTruncatingTail`).
        case truncateTail
    }

    let pageSize: CGSize
    let context:  CGContext
    private let data = NSMutableData()
    private var pageIsOpen = false
    private(set) var pageCount = 0

    /// Fails only if CoreGraphics cannot open a PDF context, which in practice it always can.
    init?(pageSize: CGSize) {
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        self.pageSize = pageSize
        self.context  = context
    }

    // MARK: Pages

    /// Ends any page still open first, so a caller that draws something on `endPage()` (a
    /// footer, say) must call its own wrapper rather than this directly.
    func beginPage() {
        if pageIsOpen { endPage() }
        context.beginPDFPage(nil)
        pageIsOpen = true
        pageCount += 1
    }

    func endPage() {
        guard pageIsOpen else { return }
        context.endPDFPage()
        pageIsOpen = false
    }

    /// Closes the document (and any open page) and returns the PDF bytes. The canvas is
    /// done after this; make a new one for another document.
    func finish() -> Data {
        endPage()
        context.closePDF()
        return data as Data
    }

    // MARK: Shapes

    func fill(_ rect: CGRect, cornerRadius: CGFloat = 0, color: CGColor) {
        context.setFillColor(color)
        if cornerRadius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    func stroke(_ rect: CGRect, cornerRadius: CGFloat = 0, color: CGColor, lineWidth: CGFloat = 1) {
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        if cornerRadius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.strokePath()
        } else {
            context.stroke(rect)
        }
    }

    func line(from start: CGPoint, to end: CGPoint, color: CGColor, lineWidth: CGFloat = 1) {
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    /// Runs `body` with drawing clipped to `rect`, restoring the graphics state afterwards.
    func clipped(to rect: CGRect, _ body: () -> Void) {
        context.saveGState()
        context.clip(to: rect)
        body()
        context.restoreGState()
    }

    // MARK: Text measurement

    func width(of text: String, font: PDFFont) -> CGFloat {
        Self.width(of: Self.line(text, font: font, color: .pdfBlack))
    }

    /// The height `text` occupies when word-wrapped into `width`: whole TextKit line heights,
    /// so it matches what `NSAttributedString.boundingRect(with:options:)` reported.
    func height(of text: String, font: PDFFont, width: CGFloat) -> CGFloat {
        CGFloat(Self.wrappedLines(text, font: font, color: .pdfBlack, width: width).count) * font.lineHeight
    }

    // MARK: Text drawing

    /// Draws a single line with its baseline origin at `point`. `anchor` says which part of the
    /// line sits on `point.x`: its left edge, its center, or its right edge. `maxWidth` truncates
    /// with an ellipsis (and applies before the anchor, so a centered line stays centered).
    func draw(_ text: String, at point: CGPoint, font: PDFFont, color: CGColor, anchor: Alignment = .leading, maxWidth: CGFloat? = nil) {
        var line = Self.line(text, font: font, color: color)
        if let maxWidth {
            line = Self.truncated(line, text: text, font: font, color: color, maxWidth: maxWidth)
        }
        let width = Self.width(of: line)
        context.textPosition = CGPoint(x: point.x - width * anchor.flush, y: point.y)
        CTLineDraw(line, context)
    }

    /// Draws `text` inside `rect` the way `NSAttributedString.draw(in:)` did: top-aligned, the
    /// first baseline `font.baselineOffset` below `rect.maxY`, one `font.lineHeight` per further
    /// line, aligned within the rect's width. Text taller than the rect is clipped to it, as
    /// TextKit clipped; text that fits is not (so nothing an overhanging glyph does changes).
    /// Returns the laid-out height.
    @discardableResult
    func draw(_ text: String, in rect: CGRect, font: PDFFont, color: CGColor, alignment: Alignment = .leading, lineBreak: LineBreak = .wrap) -> CGFloat {
        let lines: [CTLine]
        switch lineBreak {
        case .wrap:
            lines = Self.wrappedLines(text, font: font, color: color, width: rect.width)
        case .truncateTail:
            lines = [Self.truncated(Self.line(text, font: font, color: color), text: text, font: font, color: color, maxWidth: rect.width)]
        }
        let height = CGFloat(lines.count) * font.lineHeight

        let drawLines = {
            var baseline = rect.maxY - font.baselineOffset
            for line in lines {
                let x = rect.minX + CGFloat(CTLineGetPenOffsetForFlush(line, alignment.flush, Double(rect.width)))
                self.context.textPosition = CGPoint(x: x, y: baseline)
                CTLineDraw(line, self.context)
                baseline -= font.lineHeight
            }
        }
        if height > rect.height {
            clipped(to: rect, drawLines)
        } else {
            drawLines()
        }
        return height
    }

    // MARK: - CoreText plumbing

    private static func attributed(_ text: String, font: PDFFont, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String):            font.ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    private static func line(_ text: String, font: PDFFont, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(attributed(text, font: font, color: color))
    }

    private static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Word-wraps with CoreText's typesetter (the same one TextKit uses for line breaking).
    private static func wrappedLines(_ text: String, font: PDFFont, color: CGColor, width: CGFloat) -> [CTLine] {
        let attributed = attributed(text, font: font, color: color)
        guard attributed.length > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [CTLine] = []
        var start = 0
        while start < attributed.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    /// Tail truncation that keeps as much of the text as fits, then an ellipsis.
    /// `CTLineCreateTruncatedLine` would do, but it gives up a character early now and then
    /// (it measures the prefix and the token separately, so the pair never kerns), so the
    /// fit is found here: a binary search over character prefixes, each measured *with*
    /// the ellipsis so kerning and tracking between the two count. Note that TextKit drew
    /// its truncated lines with noticeably tighter tracking than the untruncated text next
    /// to them (see learnings.md, 2026-09-16); this helper does not reproduce that, so a
    /// migrated truncated line may end one character sooner than it used to.
    private static func truncated(_ line: CTLine, text: String, font: PDFFont, color: CGColor, maxWidth: CGFloat) -> CTLine {
        guard width(of: line) > maxWidth else { return line }
        let ellipsis = "\u{2026}"
        let characters = Array(text)
        var low = 0, high = characters.count - 1   // the full string is known not to fit
        var best = self.line(ellipsis, font: font, color: color)
        while low <= high {
            let mid = (low + high) / 2
            let candidate = self.line(String(characters[0..<mid]) + ellipsis, font: font, color: color)
            if width(of: candidate) <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}

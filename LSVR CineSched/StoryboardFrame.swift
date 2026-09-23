//
//  StoryboardFrame.swift
//  LSVR CineSched
//
//  The one way a storyboard frame becomes stored bytes, and the one way stored bytes become
//  an image again (#38, spec #36). Every frame source on every platform (paste, drop,
//  Photos, the camera, a file) hands its bytes or its decoded image to `encode`; the board,
//  the editor's thumbnails and the Shot List export read them back through `decode`.
//
//  Frames live inside the project's JSON as base64 JPEG (the ADR #37 adds), so their size is
//  the file's size: the long edge is capped at 1200 px (never upscaled) and the JPEG quality
//  is one fixed 0.8, which keeps a sketched or photographed board at roughly 80–150 KB (a
//  hundred of them near 13 MB of base64) while a 3.3-inch slot in the export, about 330 pt,
//  still gets well over 300 dpi. Lower qualities ring visibly around pencil lines.
//
//  CoreGraphics and ImageIO only: no AppKit, no UIKit, no `#if os`. The result is
//  deterministic (same pixels in, equal bytes out) because the image is redrawn into a fresh
//  sRGB context and written with no properties but the quality: ImageIO embeds no timestamp,
//  no EXIF and no source metadata then, and a flattened alpha channel always lands on white
//  (a transparent PNG from a drawing app reads as ink on paper, not ink on black).
//
//  `decode` keeps its results in a bounded `NSCache` keyed by the bytes, because a board, an
//  editor row and an export all decode the same frame, and a view redraws far more often
//  than a frame changes.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum StoryboardFrame {

    // MARK: - The rule

    /// The longest edge a stored frame may have, in pixels. Smaller images keep their size.
    static let maxLongEdge = 1200

    /// The one JPEG quality every frame is written at (see the header for why 0.8).
    static let jpegQuality: CGFloat = 0.8

    /// The stored size of an image of `width` × `height` pixels: the long edge capped at
    /// `maxLongEdge`, the short edge scaled by the same factor and rounded to the nearest
    /// pixel (never below 1). An image already within the cap keeps its size exactly.
    static func storedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let width     = max(width, 1)
        let height    = max(height, 1)
        let longEdge  = max(width, height)
        guard longEdge > maxLongEdge else { return (width, height) }
        let scale     = Double(maxLongEdge) / Double(longEdge)
        let scaled    = { (edge: Int) in max(1, Int((Double(edge) * scale).rounded())) }
        return width >= height ? (maxLongEdge, scaled(height)) : (scaled(width), maxLongEdge)
    }

    // MARK: - Encoding

    /// The stored bytes for a decoded image: downscaled to `storedSize`, flattened onto white,
    /// in sRGB, as JPEG at `jpegQuality`. Nil only if CoreGraphics or ImageIO fail.
    static func encode(_ image: CGImage) -> Data? {
        let size = storedSize(width: image.width, height: image.height)
        return encode(image, width: size.width, height: size.height)
    }

    /// The stored bytes for any ImageIO-readable bytes (JPEG, PNG, HEIC, TIFF, …), upright
    /// by the source's EXIF orientation, then by the same rule as `encode(_:)`. Nil for
    /// bytes ImageIO cannot read.
    static func encode(data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let upright = uprightSize(of: source) else { return nil }
        let size = storedSize(width: upright.width, height: upright.height)
        // The thumbnail call decodes at (about) the target size straight from the file, which
        // is what keeps a 48-megapixel camera photo from being decoded whole, and it applies
        // the EXIF orientation. Its own rounding of the short edge is not ours, so the result
        // is redrawn at exactly `storedSize` by the one encoder below.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceThumbnailMaxPixelSize:          max(size.width, size.height),
            kCGImageSourceShouldCacheImmediately:         true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encode(image, width: size.width, height: size.height)
    }

    private static func encode(_ image: CGImage, width: Int, height: Int) -> Data? {
        guard let space   = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, flattened, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The source's first image size as displayed: width and height swapped for the EXIF
    /// orientations that turn the image on its side (5–8).
    private static func uprightSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width      = (properties[kCGImagePropertyPixelWidth]  as? NSNumber)?.intValue,
              let height     = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    // MARK: - Decoding

    /// The image stored bytes hold, decoded now (not lazily at the first draw), from the
    /// cache when these bytes were decoded before. Stored frames carry no orientation, so
    /// the image is as stored. Nil for empty or unreadable bytes.
    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty else { return nil }
        if let cached = cachedImage(for: data) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(DecodedFrame(image), forKey: data as NSData, cost: image.bytesPerRow * image.height)
        return image
    }

    /// The image for bytes `decode` has already decoded, without decoding: what a view body
    /// may call on every redraw.
    static func cachedImage(for data: Data) -> CGImage? {
        guard !data.isEmpty else { return nil }
        return cache.object(forKey: data as NSData)?.image
    }

    /// The pixel size of stored bytes, read from the image's properties without decoding the
    /// pixels. The size `decode` returns (stored frames carry no orientation).
    static func pixelSize(of data: Data) -> CGSize? {
        guard !data.isEmpty,
              let source     = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width      = (properties[kCGImagePropertyPixelWidth]  as? NSNumber)?.intValue,
              let height     = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - The decode cache

    /// Decoded frames by their bytes (`NSData` hashes and compares by content), bounded at
    /// about 64 MB of pixels: some fifteen full-size frames, or every thumbnail of a long
    /// shot list. `NSCache` is thread-safe and drops entries under memory pressure.
    private static let cache: NSCache<NSData, DecodedFrame> = {
        let cache = NSCache<NSData, DecodedFrame>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private final class DecodedFrame {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}

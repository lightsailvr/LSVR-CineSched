//
//  StoryboardFrameTests.swift
//  LSVR CineSchedTests
//
//  The frame bytes rule (#38): every image is stored as JPEG with its long edge at most
//  1200 px, never upscaled, opaque, and the same pixels always give the same bytes. The
//  images are synthesized with a `CGContext`, so the suite needs no fixtures on disk and
//  runs the same on macOS, iOS and visionOS.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LSVR_CineSched

@MainActor
struct StoryboardFrameTests {

    // MARK: - Fixtures

    /// A `width` × `height` sRGB image: red on the top half, blue on the bottom half, and a
    /// transparent band down the left tenth when `withAlpha`.
    private func image(_ width: Int, _ height: Int, withAlpha: Bool = false) -> CGImage {
        let space   = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CoreGraphics' origin is the bottom left: the top half is y ≥ height / 2.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        if withAlpha { context.clear(CGRect(x: 0, y: 0, width: width / 10, height: height)) }
        return context.makeImage()!
    }

    /// `image` written by ImageIO as `type`, with an EXIF orientation when given.
    private func bytes(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data {
        let output      = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func decodedSize(_ data: Data?) -> (Int, Int)? {
        guard let data, let image = StoryboardFrame.decode(data) else { return nil }
        return (image.width, image.height)
    }

    /// The red, green and blue of the pixel at (`x`, `y`) from the top left of `image`.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int) {
        var rgba    = [UInt8](repeating: 0, count: 4)
        let space   = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(rgba[0]), Int(rgba[1]), Int(rgba[2]))
    }

    // MARK: - The size rule

    @Test(arguments: [
        (3000, 1500, 1200, 600),
        (1500, 3000, 600, 1200),
        (800, 400, 800, 400),
        (1200, 1200, 1200, 1200),
        (1201, 1, 1200, 1),
        (4032, 3024, 1200, 900),
        (2000, 1001, 1200, 601),   // 600.6 rounds to the nearest pixel
    ])
    func storedSizeCapsTheLongEdgeAndKeepsTheAspect(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int) {
        let size = StoryboardFrame.storedSize(width: width, height: height)
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test func aLandscapeImageDownscalesToTheCap() {
        #expect(decodedSize(StoryboardFrame.encode(image(3000, 1500))) ?? (0, 0) == (1200, 600))
    }

    @Test func aPortraitImageDownscalesToTheCap() {
        #expect(decodedSize(StoryboardFrame.encode(image(1500, 3000))) ?? (0, 0) == (600, 1200))
    }

    @Test func aSmallImageIsNotUpscaled() {
        #expect(decodedSize(StoryboardFrame.encode(image(800, 400))) ?? (0, 0) == (800, 400))
    }

    // MARK: - The bytes

    @Test func theResultIsJPEG() throws {
        let data   = try #require(StoryboardFrame.encode(image(3000, 1500)))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func encodingTheSameImageTwiceGivesEqualBytes() throws {
        let frame  = image(3000, 1500)
        let first  = try #require(StoryboardFrame.encode(frame))
        let second = try #require(StoryboardFrame.encode(frame))
        #expect(first == second)
        // A second image with the same pixels, not just the same object.
        #expect(StoryboardFrame.encode(image(3000, 1500)) == first)
        let fromPNG = bytes(image(3000, 1500), as: .png)
        #expect(StoryboardFrame.encode(data: fromPNG) == StoryboardFrame.encode(data: fromPNG))
    }

    @Test func theBytesCarryNoSourceMetadata() throws {
        let data       = try #require(StoryboardFrame.encode(data: bytes(image(400, 200), as: .jpeg, orientation: 6)))
        let source     = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        // ImageIO always writes a minimal Exif block for a JPEG (color space and pixel
        // dimensions); nothing of the source and nothing time-derived rides along.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(Set(exif.keys.map { $0 as String })
                    .isSubset(of: [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension,
                                   kCGImagePropertyExifPixelYDimension].map { $0 as String }))
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 == 1)
    }

    @Test func anImageWithAlphaFlattensOntoWhite() throws {
        let data    = try #require(StoryboardFrame.encode(image(800, 400, withAlpha: true)))
        let decoded = try #require(StoryboardFrame.decode(data))
        let alpha   = decoded.alphaInfo
        #expect(alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst)
        let (r, g, b) = pixel(decoded, x: 20, y: 100)   // inside the transparent band
        #expect(r > 240 && g > 240 && b > 240)
    }

    // MARK: - From encoded bytes

    @Test func pngBytesFollowTheSameRule() {
        #expect(decodedSize(StoryboardFrame.encode(data: bytes(image(3000, 1500), as: .png))) ?? (0, 0) == (1200, 600))
        #expect(decodedSize(StoryboardFrame.encode(data: bytes(image(1500, 3000), as: .png))) ?? (0, 0) == (600, 1200))
        #expect(decodedSize(StoryboardFrame.encode(data: bytes(image(800, 400), as: .png))) ?? (0, 0) == (800, 400))
    }

    @Test func anEXIFRotatedJPEGComesOutUpright() throws {
        // Stored 400 × 200 with red on top; orientation 6 is "rotate 90° clockwise to
        // display", so it displays 200 × 400 with red on the right.
        let data    = try #require(StoryboardFrame.encode(data: bytes(image(400, 200), as: .jpeg, orientation: 6)))
        let decoded = try #require(StoryboardFrame.decode(data))
        #expect((decoded.width, decoded.height) == (200, 400))
        let right = pixel(decoded, x: 150, y: 200)
        let left  = pixel(decoded, x: 50, y: 200)
        #expect(right.0 > 200 && right.2 < 60)
        #expect(left.2 > 200 && left.0 < 60)
    }

    @Test func aLargeRotatedPhotoDownscalesByItsUprightSize() {
        let data = bytes(image(3000, 1500), as: .jpeg, orientation: 8)
        #expect(decodedSize(StoryboardFrame.encode(data: data)) ?? (0, 0) == (600, 1200))
    }

    @Test func unreadableBytesEncodeToNothing() {
        #expect(StoryboardFrame.encode(data: Data()) == nil)
        #expect(StoryboardFrame.encode(data: Data("not an image".utf8)) == nil)
    }

    // MARK: - Decoding and size

    @Test func pixelSizeReadsTheStoredSize() throws {
        let data = try #require(StoryboardFrame.encode(image(1500, 3000)))
        #expect(StoryboardFrame.pixelSize(of: data) == CGSize(width: 600, height: 1200))
        #expect(StoryboardFrame.pixelSize(of: Data()) == nil)
        #expect(StoryboardFrame.pixelSize(of: Data("garbage".utf8)) == nil)
    }

    @Test func decodeRefusesEmptyAndUnreadableBytes() {
        #expect(StoryboardFrame.decode(Data()) == nil)
        #expect(StoryboardFrame.decode(Data("garbage".utf8)) == nil)
    }

    @Test func aDecodedFrameIsCachedByItsBytes() throws {
        let data = try #require(StoryboardFrame.encode(image(640, 480)))
        let copy = Data(Array(data))   // equal bytes in a different buffer
        #expect(StoryboardFrame.cachedImage(for: copy) == nil)
        let decoded = try #require(StoryboardFrame.decode(data))
        #expect(StoryboardFrame.cachedImage(for: copy) === decoded)
        #expect(StoryboardFrame.decode(copy) === decoded)
    }
}

//
//  StoryboardFrameImportTests.swift
//  LSVR CineSchedTests
//
//  What a paste or a drop onto the frame slot reads (#41, StoryboardFrameSlot.swift):
//  `StoryboardFrameImport` loaded from item providers shaped like the real sources — a PNG
//  file (a drag from Finder or Files), TIFF bytes (Preview's Copy), JPEG bytes (a photo
//  dragged from Photos) — carries the picture's bytes, which the one encoder turns into a
//  stored frame; a scene drag (`ScheduleDragPayload`) is not an image and never imports.
//  The views themselves have no unit seam (learnings.md 2026-09-23 #41).
//

import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LSVR_CineSched

@MainActor
struct StoryboardFrameImportTests {

    // MARK: - Fixtures

    /// A 2400 × 1600 sRGB image, red, written by ImageIO as `type`.
    private func imageBytes(_ type: UTType, width: Int = 2400, height: Int = 1600) -> Data {
        let space   = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output      = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// A provider offering `data` as `type`, the way a pasteboard or an app's drag does.
    private func provider(_ data: Data, as type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: type) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Loads a `StoryboardFrameImport` from `provider`, nil when nothing in it matches.
    private func load(_ provider: NSItemProvider) async -> StoryboardFrameImport? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: StoryboardFrameImport.self) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    // MARK: - The sources

    @Test func aPNGFileImportsItsBytes() async throws {
        let png = imageBytes(.png)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frame-\(UUID().uuidString).png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file     = try #require(NSItemProvider(contentsOf: url))
        let imported = try #require(await load(file))
        #expect(imported.data == png)
    }

    @Test(arguments: [UTType.tiff, .jpeg, .png])
    func imageBytesImport(type: UTType) async throws {
        let bytes    = imageBytes(type)
        let imported = try #require(await load(provider(bytes, as: type)))
        #expect(imported.data == bytes)
    }

    @Test func anImportedPictureBecomesAStoredFrame() async throws {
        let imported = try #require(await load(provider(imageBytes(.tiff), as: .tiff)))
        let stored   = try #require(StoryboardFrame.encode(data: imported.data))
        #expect(StoryboardFrame.pixelSize(of: stored) == CGSize(width: 1200, height: 800))
        let source   = try #require(CGImageSourceCreateWithData(stored as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func aSceneDragIsNotAnImage() async throws {
        let data     = try ScheduleDragPayload.scenes([UUID()], from: nil).pasteboardData()
        #expect(await load(provider(data, as: .cineschedDragPayload)) == nil)
    }
}

//
//  StoryboardFrameView.swift
//  LSVR CineSched
//
//  A storyboard frame's stored bytes, shown whole (#38): aspect-fit inside whatever frame the
//  container proposes, never cropped, centred on a subtle background so a 2:1 board in a
//  square slot reads as letterboxed and a fisheye reads as drawn. Nil, empty or unreadable
//  bytes show a placeholder. The view is greedy: it fills the proposal, so the container
//  gives it its box (`.frame(width:height:)`, `.aspectRatio(_:contentMode:)` or a row's
//  height).
//
//  Decoding stays off the body's hot path, because the shot rows (#39) hold a thumbnail each
//  and a list redraws far more often than a frame changes: the body only asks the decode
//  cache (`StoryboardFrame.cachedImage(for:)`, a lookup), and `.task(id:)` decodes bytes it
//  has not seen off the main actor, once per change of the bytes. Until then the box shows
//  its background alone, so a frame that is on its way never flashes "No Frame".
//
//  Platform-free: SwiftUI's `Image` from a `CGImage`, no AppKit or UIKit.
//

import CoreGraphics
import SwiftUI

struct StoryboardFrameView: View {

    /// The frame's stored bytes (`StoryboardFrame.encode`), or nil for no frame.
    let data: Data?

    /// The caption under the placeholder's symbol; nil for the symbol alone (a small thumbnail).
    var placeholderCaption: String? = L("No Frame")

    /// The bytes the task last decoded and what they gave (nil image: unreadable).
    @State private var loaded: LoadedFrame?

    var body: some View {
        let state = displayState
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
            content(for: state)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isNoFrame ? L("No Frame") : L("Storyboard Frame"))
        .accessibilityAddTraits(.isImage)
        .task(id: data) {
            // Held here as well as in the cache, so an eviction never leaves the box empty.
            guard let data, !data.isEmpty else { loaded = nil; return }
            if let cached = StoryboardFrame.cachedImage(for: data) {
                loaded = LoadedFrame(data: data, image: cached)
            } else {
                loaded = LoadedFrame(data: data, image: await Self.decoded(data))
            }
        }
    }

    // MARK: - What to draw

    private enum DisplayState {
        case image(CGImage)
        case decoding
        case noFrame

        var isNoFrame: Bool {
            if case .noFrame = self { return true }
            return false
        }
    }

    /// Read once per body: a cache lookup, never a decode.
    private var displayState: DisplayState {
        guard let data, !data.isEmpty else { return .noFrame }
        if let image = StoryboardFrame.cachedImage(for: data) { return .image(image) }
        if let loaded, loaded.data == data {
            return loaded.image.map(DisplayState.image) ?? .noFrame
        }
        return .decoding
    }

    @ViewBuilder
    private func content(for state: DisplayState) -> some View {
        switch state {
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        case .decoding:
            EmptyView()
        case .noFrame:
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.title2)
                if let placeholderCaption {
                    Text(placeholderCaption)
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            .padding(4)
        }
    }

    // MARK: - Decoding

    private struct LoadedFrame {
        let data:  Data
        let image: CGImage?
    }

    /// `StoryboardFrame.decode` off the main actor (it fills the cache the body reads).
    @concurrent
    private nonisolated static func decoded(_ data: Data) async -> CGImage? {
        StoryboardFrame.decode(data)
    }
}

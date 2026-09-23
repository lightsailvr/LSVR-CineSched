// StoryboardFrameSlot.swift
// A storyboard frame in a bounded box, shown whole (#38's view), with the ways to put one
// there (#41, spec #36). The scene's frame row (a shotless scene) and the shot page both
// show it (#39), bound to the draft's frame: every change here is part of the editor's one
// Save, and Cancel drops it.
//
// The sources: an Add Frame menu (Replace once there is a frame) with Choose File… on every
// platform and whatever `PlatformFrameSources` adds (Photo Library…, Take Photo…); a drop
// onto the box; and, where the seam offers paste (the Mac, iPhone, iPad), a Paste button
// and ⌘V while the box has keyboard focus (a click on the Mac gives it that). Every one
// delivers the picture's bytes to `accept`, which runs them through
// `StoryboardFrame.encode(data:)` off the main actor: nothing else writes frame bytes, so
// every platform stores the same bytes for the same picture. Bytes ImageIO cannot read
// raise the slot's alert and leave the frame as it was.
//
// Paste is SwiftUI's `PasteButton` and `pasteDestination` (through the seam, since
// visionOS has neither), not the pasteboard responder behind the board
// (PlatformPasteboardResponder.swift): on the Mac the editor is a sheet, another window,
// so ⌘V there never reaches the board's responder and scenes still paste on the board;
// the image only reaches a focused slot. The `PasteButton` reads the pasteboard without
// iOS's paste permission prompt. Platform-free.

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The slot

struct StoryboardFrameSlot: View {
    @Binding var frame: Data?

    @State private var choosingFile  = false
    @State private var choosingPhoto = false
    @State private var takingPhoto   = false
    @State private var encoding      = false
    @State private var dropTargeted  = false
    @State private var unreadable    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            frameBox
            sourceControls
        }
        .padding(.vertical, 4)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image],
                      allowsMultipleSelection: false, onCompletion: fileChosen)
        .storyboardFramePhotosPicker(isPresented: $choosingPhoto, onPick: accept)
        .storyboardFrameCamera(isPresented: $takingPhoto, onPick: accept)
        .alert(L("The image could not be read."), isPresented: $unreadable) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Choose a JPEG, PNG, HEIC or TIFF image."))
        }
    }

    // MARK: The box

    /// The frame aspect-fit, a drop target and, focused, a paste target.
    private var frameBox: some View {
        StoryboardFrameView(data: frame)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay {
                if encoding { ProgressView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .opacity(dropTargeted ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .storyboardFramePasteTarget(onPaste: accept)
            .dropDestination(for: StoryboardFrameImport.self) { items, _ in
                guard let item = items.first else { return false }
                accept(item.data)
                return true
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active:                      dropTargeted = true
                case .exiting, .ended, .dataTransferCompleted: dropTargeted = false
                @unknown default:                              dropTargeted = false
                }
            }
            .accessibilityLabel(frame == nil ? L("No storyboard frame") : L("Storyboard frame"))
    }

    // MARK: The controls

    /// Add Frame (or Replace), Paste and Remove in one row: with their words where they
    /// fit, as icons where they do not (the iPad's 340 pt inspector column).
    private var sourceControls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow(compact: false)
            controlRow(compact: true)
        }
        // Several buttons in one form row: borderless, or a tap on the row fires them all.
        .buttonStyle(.borderless)
        // The paste control proposes no height of its own and would take the row's.
        .fixedSize(horizontal: false, vertical: true)
        .disabled(encoding)
    }

    private func controlRow(compact: Bool) -> some View {
        HStack(spacing: 16) {
            Menu {
                sourceItems
            } label: {
                Label(frame == nil ? L("Add Frame") : L("Replace"),
                      systemImage: frame == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath")
            }
            .fixedSize()

            StoryboardFramePasteButton(compact: compact, onPaste: accept)

            Spacer(minLength: 0)

            if frame != nil {
                Button(role: .destructive) {
                    frame = nil
                } label: {
                    Label(L("Remove"), systemImage: "trash")
                }
                .fixedSize()
            }
        }
        // A form row shows a menu's and a button's label as the icon alone unless told;
        // the words say which source is which wherever they fit.
        .modifier(FrameControlLabels(compact: compact))
    }

    /// The menu's items: the platform's pickers (the seam decides) and a file.
    @ViewBuilder
    private var sourceItems: some View {
        if PlatformFrameSources.offersPhotos {
            Button {
                choosingPhoto = true
            } label: {
                Label(L("Photo Library…"), systemImage: "photo.on.rectangle")
            }
        }
        if PlatformFrameSources.offersCamera {
            Button {
                takingPhoto = true
            } label: {
                Label(L("Take Photo…"), systemImage: "camera")
            }
            .disabled(!PlatformFrameSources.cameraAvailable)
        }
        Button {
            choosingFile = true
        } label: {
            Label(L("Choose File…"), systemImage: "folder")
        }
    }

    // MARK: Accepting a picture

    private func fileChosen(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        accept(try? Data(contentsOf: url))
    }

    /// The one way a picture becomes the frame: the stored bytes from the one encoder,
    /// computed off the main actor (a 48-megapixel photo takes a moment), or the alert.
    private func accept(_ data: Data?) {
        guard let data else {
            unreadable = true
            return
        }
        encoding = true
        Task {
            let stored = await Task.detached(priority: .userInitiated) {
                StoryboardFrame.encode(data: data)
            }.value
            encoding = false
            if let stored { frame = stored } else { unreadable = true }
        }
    }
}

/// Title and icon, or the icon alone for the compact row (VoiceOver still reads the title).
private struct FrameControlLabels: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.labelStyle(.iconOnly)
        } else {
            content.labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - What a paste or a drop carries

/// A picture as pasted or dropped: a file (a PNG from Finder or Files, a photo from the
/// Photos app) or image bytes (Preview's copy). Any image type, since the encoder reads
/// whatever ImageIO does; a scene drag (`ScheduleDragPayload`) is not an image and never
/// matches. Import only.
nonisolated struct StoryboardFrameImport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            StoryboardFrameImport(data: try Data(contentsOf: received.file))
        }
        DataRepresentation(importedContentType: .image) { data in
            StoryboardFrameImport(data: data)
        }
    }
}

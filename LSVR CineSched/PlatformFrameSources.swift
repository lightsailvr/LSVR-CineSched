// PlatformFrameSources.swift
// Platform seam (ADR 0003): where a storyboard frame can come from (#41, spec #36). The
// frame slot (`StoryboardFrameSlot`) offers one Add Frame / Replace menu and never names a
// platform; this file says which of its items exist and presents the two pickers that are
// not SwiftUI's own everywhere. Every source hands the slot the picture's bytes as the
// source gave them, and the slot hands those to `StoryboardFrame.encode(data:)`, so every
// platform stores the same bytes for the same picture.
//
// What each platform offers, and why:
// - Choose File… (`fileImporter`) and drop are SwiftUI's on every platform and live in the
//   slot itself.
// - Paste: the Mac, iPhone and iPad, as SwiftUI's `PasteButton` (no iOS paste prompt) and
//   `pasteDestination` on the focusable frame box (⌘V with the box focused). visionOS has
//   neither API, and the spec gives Vision Pro the Photos picker and Files only.
// - The Photos picker: iPhone, iPad and Vision Pro. PhotosUI exists on the Mac too, but
//   the Mac's sources are the ones a Mac user reaches for (the spec's list: paste, a drag
//   from Finder or Photos, the open panel), and the Photos app drags onto the slot.
// - The camera: iPhone and iPad, through `UIImagePickerController`, the one camera UI
//   that returns a still without an AVFoundation session of our own. It is offered but
//   disabled where the device reports no camera, so the menu reads the same on every
//   iPhone and iPad (the iOS 27 simulator reports one: a simulated feed). Vision Pro's
//   cameras are not open to apps for stills, and the Mac has none a storyboard would
//   want, so neither offers it.
//   The permission prompt's text is the iOS-only `INFOPLIST_KEY_NSCameraUsageDescription`
//   build setting (never a plist in the source folder; CLAUDE.md Working agreements).

import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - What the platform offers

enum PlatformFrameSources {
    /// Whether the slot's menu has Photo Library…: iPhone, iPad and Vision Pro.
    static var offersPhotos: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    /// Whether the slot's menu has Take Photo…: iPhone and iPad.
    static var offersCamera: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Whether Take Photo… can run here: false on a device without a camera, where the
    /// item stays in the menu, disabled.
    static var cameraAvailable: Bool {
        #if os(iOS)
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        false
        #endif
    }
}

// MARK: - Paste

/// The slot's Paste button: SwiftUI's `PasteButton` for any image, small and capsule-shaped
/// beside the Add Frame menu, its icon alone when `compact`; nothing on visionOS.
struct StoryboardFramePasteButton: View {
    var compact: Bool = false
    let onPaste: (Data?) -> Void

    var body: some View {
        #if os(visionOS)
        EmptyView()
        #else
        Group {
            if compact {
                button.labelStyle(.iconOnly)
            } else {
                button.labelStyle(.titleAndIcon)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize()
        #endif
    }

    #if !os(visionOS)
    private var button: some View {
        PasteButton(payloadType: StoryboardFrameImport.self) { items in
            let data = items.first?.data
            Task { @MainActor in onPaste(data) }
        }
    }
    #endif
}

extension View {
    /// Makes the frame box focusable and a paste target for an image while focused (⌘V on
    /// the Mac, a hardware keyboard's on the iPad); nothing on visionOS.
    func storyboardFramePasteTarget(onPaste: @escaping (Data?) -> Void) -> some View {
        #if os(visionOS)
        self
        #else
        focusable()
            .pasteDestination(for: StoryboardFrameImport.self) { items in
                onPaste(items.first?.data)
            }
        #endif
    }
}

// MARK: - The pickers

extension View {
    /// The Photos picker for one image while `isPresented`. `onPick` receives the image's
    /// bytes (JPEG where the library holds HEIC, `.compatible`), or nil when the library
    /// could not deliver them; Cancel calls nothing. Applied everywhere, reached only where
    /// `offersPhotos`.
    func storyboardFramePhotosPicker(isPresented: Binding<Bool>, onPick: @escaping (Data?) -> Void) -> some View {
        modifier(PhotosFramePicker(isPresented: isPresented, onPick: onPick))
    }

    /// The camera, full screen, while `isPresented` (iPhone and iPad; nothing elsewhere).
    /// `onPick` receives the photo's bytes; Cancel, or a photo with no image, calls nothing.
    func storyboardFrameCamera(isPresented: Binding<Bool>, onPick: @escaping (Data?) -> Void) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            CameraFramePicker { data in
                isPresented.wrappedValue = false
                if let data { onPick(data) }
            }
            .ignoresSafeArea()
        }
        #else
        self
        #endif
    }
}

private struct PhotosFramePicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (Data?) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images,
                          preferredItemEncoding: .compatible)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task {
                    let data = try? await picked.loadTransferable(type: Data.self)
                    onPick(data)
                }
            }
    }
}

#if os(iOS)
/// `UIImagePickerController` on the camera. The photo comes back as a `UIImage` with its
/// orientation beside the pixels; `jpegData` writes that orientation into the bytes, which
/// `StoryboardFrame.encode(data:)` applies. Quality 1 here: the one lossy step is the encoder's.
private struct CameraFramePicker: UIViewControllerRepresentable {
    /// The photo's bytes, nil for Cancel or a photo with no image.
    let onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker        = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 1))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif

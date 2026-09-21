// EditorChrome.swift
// What every adaptive editor (#19) wraps its `Form` in: a header (the title, or the
// scene editor's Previous / title / Next row, or the day detail's date and badge), the
// grouped form, and a footer row of buttons (Cancel and the primary action, a
// destructive one at the leading edge). The same chrome in every container, so an
// editor looks the same in the iPad's inspector column, in a form-sized sheet on iPad
// and Vision Pro, in a detented sheet on iPhone and in the Mac's fixed-frame sheet; only
// the size around it changes (`editorContainer`). Platform-free: the grouped form's
// backdrop is the seam's `Color.windowBackground` (the grouped background on iOS, the
// window's on the Mac), which the header and footer share so the editor reads as one
// surface.
//
// Not a navigation bar: the inspector column sits inside a `NavigationSplitView` whose
// bars the infrastructure mirrors (learnings, 2026-09-20), and the Mac's sheets have no
// bar, so the buttons live in the view where every container shows them the same way.

import SwiftUI

struct EditorChrome<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder let header:  () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer:  () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header()
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
            content()
            Divider()
            footer()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color.windowBackground)
    }
}

// MARK: - Title

/// The header most editors use: a title with an optional line under it.
struct EditorTitle: View {
    let title:    String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Color swatches

/// The banner and event inputs' color choice: one tappable circle per option, the
/// selected one ringed. Reads as a row in a form section.
struct ColorSwatchRow: View {
    let options: [(name: String, hex: String)]
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.hex) { option in
                Button {
                    selectedHex = option.hex
                } label: {
                    Circle()
                        .fill(Color(hex: option.hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.primary, lineWidth: selectedHex == option.hex ? 2.5 : 0)
                        )
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help(L(option.name))
                .accessibilityLabel(L(option.name))
                .accessibilityAddTraits(selectedHex == option.hex ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Multi-line text

/// A `TextEditor` as a form row: a minimum height so there is something to tap, and a
/// prompt while empty, which the editor itself has no way to show.
struct FormTextEditor: View {
    let prompt: String
    @Binding var text: String
    var minHeight: CGFloat = 80

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }
}

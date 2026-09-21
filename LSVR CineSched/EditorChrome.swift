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

// MARK: - Stacked title

/// The header of an editor whose lists push detail pages (#20): the editor's title and
/// subtitle at the root; on a page, a Back button, the page's title and the editor's
/// title under it. Every container gets the same Back this way: the Mac draws no
/// navigation bar inside a sheet, and on iOS the stack's bar is hidden
/// (`editorStackPage`) so the document infrastructure cannot mirror its own Back
/// button into it (learnings, 2026-09-20 #23).
struct EditorStackTitle: View {
    let title:    String
    var subtitle: String? = nil
    /// The pushed page's title; nil at the root.
    var page:     String? = nil
    let onBack:   () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let page {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .help(L("Back"))
                .accessibilityLabel(L("Back"))
                .accessibilityIdentifier("EditorStackBack")
                EditorTitle(title: page, subtitle: title)
            } else {
                EditorTitle(title: title, subtitle: subtitle)
            }
        }
    }
}

extension View {
    /// A page inside an editor's navigation stack: no system Back (the chrome's header
    /// has one) and no system bar where there is one.
    func editorStackPage() -> some View {
        navigationBarBackButtonHidden(true)
            .editorNavigationBarHidden()
    }
}

// MARK: - Row summaries

/// A list row that opens a detail page: a title, an optional detail beside it in the
/// secondary style, a badge at the trailing edge and a caption under them. The rosters
/// and the call sheet's cast and crew calls use it so their rows read alike.
struct EditorRowSummary: View {
    let title:   String
    var detail:  String? = nil
    var caption: String? = nil
    var badge:   String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
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

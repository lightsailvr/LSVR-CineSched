// ShotPage.swift
// The scene editor's shot list (#39), the parts that are not the editor itself: the page
// a shot row pushes (`ShotPage`) and the row (`ShotRow`). The frame slot the page and the
// scene's shotless frame row show is `StoryboardFrameSlot` (#41, its own file).
//
// The page is the call sheet editor's detail page pattern (#20): a grouped `Form` pushed
// inside the scene editor's own `NavigationStack`, bound by id through a `ShotDraft` the
// editor holds per shot, while the editor's chrome shows Back and the shot number in its
// header and Remove / Duplicate Shot / Add Another / Done in its footer. Every change the
// page makes is written into the scene draft at once through `SceneDraft.updateShot`, so
// the rows behind it, the letters and the summed estimate are current whenever the page
// is left, by any route (Back, Done, Add Another, a swipe); the scene's one Save writes
// it all back. Platform-free.

import SwiftUI

// MARK: - Page

struct ShotPage: View {
    @Binding var draft: ShotDraft
    let suggestions: BreakdownSuggestions
    /// The project's frame total past 20 MB (#41), under the frame; nil below it.
    var framesCaption: String? = nil
    @Environment(\.editorPresentation) private var presentation
    @FocusState private var detailsFocused: Bool

    var body: some View {
        Form {
            Section(L("Shot")) {
                TextField(L("Description"), text: $draft.details,
                          prompt: Text(L("e.g. Dolly in towards Astrid")), axis: .vertical)
                    .lineLimit(1...6)
                    .focused($detailsFocused)
                    .accessibilityLabel(L("Description"))
            }

            Section {
                LabeledContent(L("Duration")) {
                    TextField(TimeParser.placeholderText, text: $draft.duration)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if let hint = durationHint {
                    Text(hint.text).foregroundStyle(hint.isError ? Color.red : Color.secondary)
                }
            }

            // One section per list: an iOS form row shows a text field's prompt but not
            // its label, so three unlabelled lists would read alike once filled in.
            Section(L("Equipment")) {
                listField(L("Equipment"), placeholder: L("e.g. Dolly, Ronin"), icon: "wrench.and.screwdriver",
                          text: $draft.equipment, suggestions: suggestions.equipment)
            }
            Section(L("Props")) {
                listField(L("Props"), placeholder: L("e.g. Umbrella, Letter"), icon: "shippingbox",
                          text: $draft.props, suggestions: suggestions.props)
            }
            Section {
                listField(L("SFX"), placeholder: L("e.g. Rain, Smoke"), icon: "sparkles",
                          text: $draft.sfx, suggestions: suggestions.sfx)
            } header: {
                Text(L("SFX"))
            } footer: {
                Text(L("Separate items with commas"))
            }

            Section {
                StoryboardFrameSlot(frame: $draft.frame)
            } header: {
                Text(L("Storyboard Frame"))
            } footer: {
                if let framesCaption {
                    Text(framesCaption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: focusDescription)
    }

    /// A new page starts with its description focused (a shot is often one line of
    /// typing), except in the inspector, where raising the keyboard would squeeze the
    /// board; the scene editor's own duration focus follows the same rule.
    private func focusDescription() {
        guard presentation != .inspector else { return }
        DispatchQueue.main.async { detailsFocused = true }
    }

    private func listField(_ title: String, placeholder: String, icon: String,
                           text: Binding<String>, suggestions: [String]) -> some View {
        LocationAutocompleteField(
            title:              title,
            placeholder:        placeholder,
            text:               text,
            suggestions:        suggestions,
            style:              .formRow,
            icon:               icon,
            completesListItems: true
        )
    }

    private struct Hint { let text: String; let isError: Bool }

    /// The estimate field's hint: the parsed length, or the format when it does not parse.
    private var durationHint: Hint? {
        if let hint = TimeParser.getInputHint(draft.duration) {
            return Hint(text: hint, isError: false)
        }
        return Hint(text: L("Invalid format. Use: 4 (4 hours), 15 (15 minutes), or 2:30 (2hr 30min)"), isError: true)
    }
}

// MARK: - Row

/// A shot in the Shots section: the number (bold), the description, the duration, and a
/// small thumbnail when the shot has a frame.
struct ShotRow: View {
    let number: String
    let shot:   Shot

    var body: some View {
        HStack(spacing: 10) {
            if shot.frame != nil {
                StoryboardFrameView(data: shot.frame, placeholderCaption: nil)
                    .frame(width: 56, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(number)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text(TimeParser.formatMinutes(shot.durationMinutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(shot.details.isEmpty ? L("No description") : shot.details)
                    .font(.subheadline)
                    .foregroundStyle(shot.details.isEmpty ? .tertiary : .secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

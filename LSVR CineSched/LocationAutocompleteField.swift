// LocationAutocompleteField.swift
// Reusable text field with live dropdown suggestions for film locations. Standalone
// (its own headline and rounded field, for a free-standing layout) or as a form row
// (#19: the enclosing `Form` supplies the field style and the label is the prompt).
// The shot page (#39) uses it for Equipment, Props and SFX: a suggestion row's `icon` is
// the category's rather than the location pin, and `completesListItems` makes it a
// comma list's field, where the suggestions match and replace only the item being typed
// (the text after the last comma) and never repeat an item the list already has.

import SwiftUI

struct LocationAutocompleteField: View {
    enum Style {
        /// A headline over a rounded-border field.
        case standalone
        /// A row of a `Form`: the plain field the form styles, the title as its prompt.
        case formRow
    }

    let title: String
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    var style: Style = .standalone
    /// The SF Symbol on each suggestion row.
    var icon: String = "mappin.and.ellipse"
    /// A comma-separated list (#39): suggest and complete the last item only.
    var completesListItems: Bool = false
    @State private var isShowingSuggestions: Bool = false

    var filteredSuggestions: [String] {
        Self.filtered(suggestions, for: text, asList: completesListItems)
    }

    // MARK: - Matching (pure)

    /// The suggestions for `text`: those containing what is typed (case-insensitively)
    /// that are not exactly it. In a list, what is typed is the last item, and an item the
    /// list already names is never suggested again.
    nonisolated static func filtered(_ suggestions: [String], for text: String, asList: Bool) -> [String] {
        let items   = asList ? text.components(separatedBy: ",") : [text]
        let current = (items.last ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !current.isEmpty else { return [] }
        let listed  = Set(items.dropLast().map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return suggestions.filter {
            let candidate = $0.lowercased()
            return candidate.contains(current) && candidate != current && !listed.contains(candidate)
        }
    }

    /// `text` with `suggestion` chosen: the whole text, or in a list the last item.
    nonisolated static func completing(_ text: String, with suggestion: String, asList: Bool) -> String {
        guard asList, let comma = text.lastIndex(of: ",") else { return suggestion }
        return text[...comma] + " " + suggestion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if style == .standalone {
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 0) {
                switch style {
                case .standalone:
                    TextField(placeholder, text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                case .formRow:
                    TextField(title, text: $text, prompt: Text(placeholder))
                }

                if isShowingSuggestions && !filteredSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredSuggestions.prefix(6), id: \.self) { suggestion in
                            Button {
                                text = Self.completing(text, with: suggestion, asList: completesListItems)
                                isShowingSuggestions = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(suggestion)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.windowBackground)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .padding(.top, 2)
                }
            }
        }
        .onChange(of: text) { _, _ in
            isShowingSuggestions = !filteredSuggestions.isEmpty
        }
    }
}

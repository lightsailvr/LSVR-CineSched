// LocationAutocompleteField.swift
// Reusable text field with live dropdown suggestions for film locations. Standalone
// (its own headline and rounded field, for a free-standing layout) or as a form row
// (#19: the enclosing `Form` supplies the field style and the label is the prompt).

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
    @State private var isShowingSuggestions: Bool = false

    var filteredSuggestions: [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return suggestions.filter {
            $0.lowercased().contains(trimmed) && $0.caseInsensitiveCompare(trimmed) != .orderedSame
        }
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
                                text = suggestion
                                isShowingSuggestions = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.and.ellipse")
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

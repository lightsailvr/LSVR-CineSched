// BannerInputSheet.swift
// The banner input (#19): one adaptive `Form` to create a custom banner strip (Company
// Move, Meal Break, Notice, Custom Text) for the Stripboard, or (#26, the iPhone's Day
// screen) to edit one (`initialBanner`). The fields are a `BannerDraft`; Add Banner hands
// `draft.makeBanner()` to `onSave` once, Save Changes `draft.applied(to:)`, which keeps
// the banner's id and its fixed start. Only the size around the form changes per
// container (`editorContainer`). The Mac's call site adds only.

import SwiftUI

struct BannerInputSheet: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var isPresented: Bool
    /// The banner being edited; nil to add one.
    var initialBanner: Scene? = nil
    let onSave: (Scene) -> Void

    @State private var draft: BannerDraft

    static let sheetSize = EditorSheetSize(width: 480, height: 620, compactDetents: [.medium, .large], fitsHeight: true)

    init(isPresented: Binding<Bool>, initialBanner: Scene? = nil, onSave: @escaping (Scene) -> Void) {
        _isPresented       = isPresented
        self.initialBanner = initialBanner
        self.onSave        = onSave
        _draft             = State(initialValue: initialBanner.map { BannerDraft(banner: $0) } ?? BannerDraft())
    }

    var body: some View {
        EditorChrome {
            EditorTitle(
                title:    draft.isEditing ? L("Edit Banner Strip") : L("Add Notice / Banner Strip"),
                subtitle: L("Insert custom move, notice, or note into the stripboard schedule")
            )
        } content: {
            form
        } footer: {
            HStack {
                Button(L("Cancel")) { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(draft.isEditing ? L("Save Changes") : L("Add Banner")) {
                    if let initialBanner {
                        onSave(draft.applied(to: initialBanner))
                    } else {
                        onSave(draft.makeBanner())
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
            }
        }
        .editorContainer(Self.sheetSize)
    }

    private var form: some View {
        Form {
            Section {
                Picker(L("Banner Type"), selection: Binding(get: { draft.type }, set: { draft.setType($0) })) {
                    ForEach(BannerType.allCases, id: \.self) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
                .pickerStyle(.menu)

                TextField(L("Title / Message"), text: $draft.title, prompt: Text(BannerDraft.defaultTitle(for: draft.type)))
            }

            Section {
                LabeledContent(L("Start Time")) {
                    TextField(L("e.g. 12:00 PM"), text: $draft.startTime)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L("Duration (h:mm)")) {
                    TextField(L("e.g. 0:30 or 1:00"), text: $draft.estimatedTime)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section(L("Additional Notes")) {
                TextField(L("Additional Notes"), text: $draft.note, prompt: Text(L("e.g. Equipment trucks depart at 01:00 PM")))
            }

            Section(L("Banner Color")) {
                ColorSwatchRow(options: BannerDraft.colorOptions, selectedHex: $draft.colorHex)
            }
        }
        .formStyle(.grouped)
    }
}

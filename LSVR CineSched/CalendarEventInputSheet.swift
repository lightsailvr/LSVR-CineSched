// CalendarEventInputSheet.swift
// The calendar event input (#19): one adaptive `Form` to add an agenda event to a day
// or edit one (`initialEvent`), from the calendar, the Stripboard and the day detail.
// The fields are a `CalendarEventDraft`; Add Event / Save Changes hands
// `draft.makeEvent()` (which keeps an edited event's id) to `onSave` once. Only the size
// around the form changes per container (`editorContainer`).

import SwiftUI

struct CalendarEventInputSheet: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var isPresented: Bool
    var initialEvent: Scene? = nil
    let onSave: (Scene) -> Void

    @State private var draft: CalendarEventDraft

    static let sheetSize = EditorSheetSize(width: 420, height: 380, compactDetents: [.medium, .large], fitsHeight: true)

    init(isPresented: Binding<Bool>, initialEvent: Scene? = nil, onSave: @escaping (Scene) -> Void) {
        _isPresented      = isPresented
        self.initialEvent = initialEvent
        self.onSave       = onSave
        _draft            = State(initialValue: CalendarEventDraft(event: initialEvent))
    }

    var body: some View {
        EditorChrome {
            HStack {
                Label(draft.isEditing ? L("Edit Calendar Event") : L("Add Calendar Event"), systemImage: "calendar.badge.clock")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
        } content: {
            form
        } footer: {
            HStack {
                Button(L("Cancel")) { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(draft.isEditing ? L("Save Changes") : L("Add Event")) {
                    guard let event = draft.makeEvent() else { return }
                    onSave(event)
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
                TextField(L("Event Title / Subject"), text: $draft.title, prompt: Text(L("e.g. Cast Table Read, Fitting, Scout")))
                LabeledContent(L("Time (Optional)")) {
                    TextField(L("e.g. 10:00 AM, 02:30 PM"), text: $draft.time)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section(L("Event Badge Color")) {
                ColorSwatchRow(options: CalendarEventDraft.colorOptions, selectedHex: $draft.colorHex)
            }
        }
        .formStyle(.grouped)
    }
}

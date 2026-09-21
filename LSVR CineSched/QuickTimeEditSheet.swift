// QuickTimeEditSheet.swift
// Set Time (#26): the Stripboard's "Set Time…" on a strip, rebuilt as one adaptive
// `Form` in the #19 chrome so the Mac's sheet, the iPad's and the iPhone's are the same
// view sized by `editorContainer`. A strip either takes its start from the cascade or
// starts at a fixed time (`customStartTime`), and carries its own estimate; the fields
// are a `QuickTimeDraft` (seeded as the old sheet seeded them, previewed the same way)
// and Save hands `draft.applied(to:)` to `onSave` once. The Mac's call site
// (`StripboardView`, `.sheet(item:)` with `onSave` and `onCancel` both dismissing) is
// unchanged; the Day screen and the strip actions present it on the phone.

import SwiftUI

struct QuickTimeEditSheet: View {
    let scene: Scene
    let onSave: (Scene) -> Void
    let onCancel: () -> Void

    @State private var draft: QuickTimeDraft

    static let sheetSize = EditorSheetSize(width: 420, height: 560, compactDetents: [.medium, .large], fitsHeight: true)

    init(scene: Scene, onSave: @escaping (Scene) -> Void, onCancel: @escaping () -> Void) {
        self.scene    = scene
        self.onSave   = onSave
        self.onCancel = onCancel
        // Populated here rather than on appear so the first frame shows the strip's time.
        _draft = State(initialValue: QuickTimeDraft(scene: scene))
    }

    var body: some View {
        EditorChrome {
            EditorTitle(title: L("Set Shooting Time"), subtitle: scene.displayTitle)
        } content: {
            form
        } footer: {
            HStack {
                Button(L("Cancel")) { onCancel() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("Save Schedule")) {
                    onSave(draft.applied(to: scene))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
        }
        .editorContainer(Self.sheetSize)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section(L("Time Mode")) {
                Picker(L("Time Mode"), selection: $draft.isCustomTime) {
                    Text(L("Automatic Cascade (by order)")).tag(false)
                    Text(L("Fixed Time (e.g. 11:00 AM)")).tag(true)
                }
                .radioGroupPickerStyle()
                .labelsHidden()

                if draft.isCustomTime {
                    LabeledContent(L("Start Time")) {
                        TextField("11:00 AM", text: $draft.customTimeText)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section(L("Estimated Duration")) {
                Stepper("\(draft.hours) h", value: $draft.hours, in: 0...12)
                Stepper("\(draft.minutes) min", value: $draft.minutes, in: 0...59, step: 5)
            }

            Section {
                Label {
                    Text(draft.previewText)
                        .font(.callout.weight(draft.isCustomTime ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(draft.isValid ? Color.primary : Color.red)
                } icon: {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Text(L("Schedule Preview"))
            } footer: {
                if !draft.isValid {
                    Text(L("Enter a time like 11:00 AM or 13:30."))
                        .foregroundStyle(Color.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

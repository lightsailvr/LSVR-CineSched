// DayDetailSheet.swift
// The day detail (#19): one adaptive `Form` for a shoot day, as the Mac's sheet (a
// double-click on a day) and as the iPad's inspector column for the selected day (#17).
// The date, the day badge and the statistics head it; the form holds the day type and
// note, the day's actions (Add Calendar Event, Edit Call Sheet, Export Call Sheet), the
// call schedule, the calendar events and the scenes. Every edit is a callback the
// presenter writes through the funnel; the note is a draft committed on submit, on Done
// and when the view goes away, and only when it changed, so an untouched day registers
// nothing. Only the size around the form changes per container (`editorContainer`).

import SwiftUI

struct DayDetailSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePalette) private var palette
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue
    @ObservedObject private var l10n = LocalizationManager.shared

    let day: ShootDay
    let dayNumber: Int?
    let productionInfo: ProductionInfo
    @Binding var isPresented: Bool

    let onEditScene: (Scene) -> Void
    let onRemoveScene: (Scene) -> Void
    let onAddCalendarEvent: () -> Void
    let onSetDayType: (DayType) -> Void
    /// Called with the trimmed note on submit and when the sheet closes; the parent skips
    /// the write (and the undo snapshot) when nothing changed.
    let onSetDayNote: (String) -> Void
    let onClearDayType: () -> Void
    let onOpenCallSheet: () -> Void
    let onExportCallSheetPDF: () -> Void

    @State private var noteDraft: String = ""

    // MARK: - Derived

    private var scriptScenes:   [Scene] { day.scenes.filter { !$0.isBanner && !$0.isCalendarEvent } }
    private var calendarEvents: [Scene] { day.scenes.filter { $0.isCalendarEvent } }

    private var totalEighths: Int { scriptScenes.reduce(0) { $0 + $1.duration } }
    private var totalEstTime: String { formattedTime(scriptScenes.reduce(0) { $0 + $1.estimatedTime }) }

    private var isShootDay: Bool { dayNumber != nil && day.dayType.isShootable }

    private var dayTypeColor: Color { Color(hex: day.dayType.colorHex) }
    private var eventColor:   Color { Color(hex: "6366F1") }

    /// The Mac sheet's frame: the shoot-day sheet is the roomier of the two, as before.
    private var sheetSize: EditorSheetSize {
        isShootDay
            ? EditorSheetSize(width: 700, height: 640, compactDetents: [.large])
            : EditorSheetSize(width: 540, height: 460, compactDetents: [.medium, .large])
    }

    private func commitNote() {
        let clean = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != day.dayNote { onSetDayNote(clean) }
    }

    // MARK: - Body

    var body: some View {
        EditorChrome {
            header
        } content: {
            form
        } footer: {
            HStack {
                Spacer()
                Button(L("Done")) {
                    commitNote()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .editorContainer(sheetSize)
        .onAppear { noteDraft = day.dayNote }
        .onChange(of: day.dayNote) { _, newNote in noteDraft = newNote }
        .onDisappear { commitNote() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formattedFullDate(day.date))
                .font(.title2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                dayBadge
                if isShootDay {
                    Text("\(scriptScenes.count) \(L("scenes")) · \(formattedEighths(totalEighths)) \(L("pgs")) · \(totalEstTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("\(calendarEvents.count) \(L("calendar event(s)"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dayBadge: some View {
        if let num = dayNumber, isShootDay {
            let accent = currentTheme.primaryAccent(isDarkMode: colorScheme == .dark)
            badge(Text("\(L("Shoot Day")) #\(num)"), color: accent)
        } else if !day.dayType.isShootable {
            badge(Label(day.dayType.localizedName, systemImage: day.dayType.icon), color: dayTypeColor)
        } else {
            badge(Label(L("Calendar Event"), systemImage: "calendar"), color: eventColor)
        }
    }

    private func badge<Content: View>(_ content: Content, color: Color) -> some View {
        content
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(6)
            .lineLimit(1)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            // Day type + note first: it answers "what is this day?" before the detail.
            dayTypeSection
            actionsSection

            if isShootDay {
                callScheduleSection
                if !calendarEvents.isEmpty {
                    calendarEventsSection
                }
                scenesSection
            } else {
                // Off-day / non-shoot day: only the calendar events.
                calendarEventsSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Day type and note

    private var dayTypeSection: some View {
        Section {
            Picker(selection: Binding(get: { day.dayType }, set: { onSetDayType($0) })) {
                ForEach(DayType.allCases, id: \.self) { type in
                    Label(type.localizedName, systemImage: type.icon).tag(type)
                }
            } label: {
                Label(L("Day Type"), systemImage: "calendar.badge.exclamationmark")
            }
            .pickerStyle(.menu)

            TextField(L("Day Note"), text: $noteDraft, prompt: Text(L("Day note (travel details, hold reason, …)")))
                .onSubmit { commitNote() }

            if !day.dayType.isShootable || !day.dayNote.isEmpty {
                Button {
                    noteDraft = ""
                    onClearDayType()
                } label: {
                    Label(L("Clear Day Type"), systemImage: "xmark.circle")
                }
                .help(L("Clear Day Type"))
            }
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        Section {
            Button {
                onAddCalendarEvent()
            } label: {
                Label(L("Add Calendar Event"), systemImage: "plus.circle.fill")
            }
            if isShootDay {
                Button {
                    onOpenCallSheet()
                } label: {
                    Label(L("Edit Call Sheet"), systemImage: "doc.plaintext")
                }
                Button {
                    onExportCallSheetPDF()
                } label: {
                    Label(L("Export Call Sheet (PDF)"), systemImage: "arrow.down.doc.fill")
                }
            }
        }
    }

    // MARK: Call schedule

    private var callScheduleSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 10) {
                timeBadge(label: L("General Call"), time: day.callSheet.generalCallTime, icon: "megaphone.fill",      color: .blue)
                timeBadge(label: L("Lunch"),        time: day.callSheet.lunchTime,       icon: "fork.knife",         color: .orange)
                timeBadge(label: L("Snack"),        time: day.callSheet.snackTime,       icon: "cup.and.saucer.fill", color: .brown)
                timeBadge(label: L("Wrap"),         time: day.callSheet.dinnerTime,      icon: "flag.checkered",     color: .red)
            }
            .padding(.vertical, 2)

            if !day.callSheet.basecampLocation.isEmpty {
                Label {
                    Text(day.callSheet.basecampLocation).font(.caption)
                } icon: {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                }
            }
        } header: {
            Label(L("Call Schedule"), systemImage: "clock.badge.checkmark")
        }
    }

    private func timeBadge(label: String, time: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(time.isEmpty ? "—" : time)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Calendar events

    private var calendarEventsSection: some View {
        Section {
            if calendarEvents.isEmpty {
                Text(L("No calendar events on this day."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(calendarEvents) { event in
                let color = Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex)
                HStack(spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.bold())
                        if !event.customStartTime.isEmpty {
                            Text(event.customStartTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        onEditScene(event)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Edit Event"))
                    .accessibilityLabel(L("Edit Event"))

                    Button(role: .destructive) {
                        onRemoveScene(event)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Delete Event"))
                    .accessibilityLabel(L("Delete Event"))
                }
                .listRowBackground(color.opacity(0.12))
            }
        } header: {
            Label(L("Calendar Events"), systemImage: "calendar.badge.clock")
        }
    }

    // MARK: Scenes

    private var scenesSection: some View {
        Section {
            if scriptScenes.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(L("No scenes scheduled on this day."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(Array(scriptScenes.enumerated()), id: \.element.id) { index, scene in
                    sceneRow(scene: scene, index: index)
                        .listRowBackground(scene.stripColor(in: palette))
                }
            }
        } header: {
            HStack {
                Label(L("Day Scenes"), systemImage: "list.bullet.rectangle")
                Spacer()
                Text("\(scriptScenes.count) \(L("scenes"))")
            }
        }
    }

    /// The whole row opens the scene's editor; the pencil says so. The badges sit on
    /// their own line so the title keeps its width in a narrow column.
    private func sceneRow(scene: Scene, index: Int) -> some View {
        let intExtLabel = scene.intExtString
        let textColor   = scene.stripTextColor

        return Button {
            onEditScene(scene)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Scene number badge
                    Text(scene.sceneNumber.isEmpty ? "\(index + 1)" : scene.sceneNumber)
                        .font(.subheadline.bold())
                        .foregroundStyle(textColor)
                        .frame(minWidth: 26)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)

                    Text(scene.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(textColor)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.7))
                }

                HStack(spacing: 8) {
                    // INT/EXT & DAY/NIGHT
                    Text(intExtLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(intExtLabel.contains("INT") ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundStyle(intExtLabel.contains("INT") ? Color.blue : Color.orange)
                        .cornerRadius(4)

                    Text(scene.dayNightType.rawValue.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(scene.dayNightType == .night ? Color.purple.opacity(0.15) : Color.yellow.opacity(0.2))
                        .foregroundStyle(scene.dayNightType == .night ? Color.purple : Color.brown)
                        .cornerRadius(4)

                    Text("\(formattedEighths(scene.duration)) | \(formattedTime(scene.estimatedTime))")
                        .font(.caption.bold())
                        .foregroundStyle(textColor.opacity(0.8))
                        .lineLimit(1)
                }

                // Location and cast
                if !scene.realLocation.isEmpty || !scene.cast.isEmpty {
                    HStack(spacing: 16) {
                        if !scene.realLocation.isEmpty {
                            Label(scene.realLocation, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(textColor.opacity(0.85))
                                .lineLimit(1)
                        }
                        if !scene.cast.isEmpty {
                            Label(scene.cast.joined(separator: ", "), systemImage: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(textColor.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }

                // Synopsis / notes
                if !scene.summary.isEmpty {
                    Text(scene.summary)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.75))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Edit Scene"))
    }
}

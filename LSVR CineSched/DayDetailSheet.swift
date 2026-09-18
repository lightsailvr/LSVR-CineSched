// DayDetailSheet.swift
// Detailed modal inspector for a Shoot Day, displaying full breakdown scenes, cast, call sheet and calendar events.

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

    private var isSpanish: Bool {
        LocalizationManager.shared.currentLanguage == .spanish
    }

    private var formattedFullDate: String {
        let df = DateFormatter()
        df.locale = isSpanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        df.dateStyle = .full
        return df.string(from: day.date).capitalized
    }

    private var scriptScenes: [Scene] {
        day.scenes.filter { !$0.isBanner && !$0.isCalendarEvent }
    }

    private var calendarEvents: [Scene] {
        day.scenes.filter { $0.isCalendarEvent }
    }

    private var bannerScenes: [Scene] {
        day.scenes.filter { $0.isBanner && !$0.isCalendarEvent }
    }

    private var totalEighths: Int {
        scriptScenes.reduce(0) { $0 + $1.duration }
    }

    private var totalEstTime: String {
        let totalMins = scriptScenes.reduce(0) { $0 + $1.estimatedTime }
        return formattedTime(totalMins)
    }

    private var isShootDay: Bool {
        dayNumber != nil && day.dayType.isShootable
    }

    private var dayTypeColor: Color { Color(hex: day.dayType.colorHex) }

    private func commitNote() {
        let clean = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != day.dayNote { onSetDayNote(clean) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formattedFullDate)
                            .font(.title2.bold())
                            .foregroundColor(.primary)

                        if let num = dayNumber, isShootDay {
                            Text(isSpanish ? "Día #\(num) de Rodaje" : "Shoot Day #\(num)")
                                .font(.caption.bold())
                                .foregroundColor(currentTheme.primaryAccent(isDarkMode: colorScheme == .dark))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(currentTheme.primaryAccent(isDarkMode: colorScheme == .dark).opacity(0.18))
                                .cornerRadius(6)
                        } else if !day.dayType.isShootable {
                            Label(day.dayType.localizedName, systemImage: day.dayType.icon)
                                .font(.caption.bold())
                                .foregroundColor(dayTypeColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(dayTypeColor.opacity(0.15))
                                .cornerRadius(6)
                        } else {
                            Text(isSpanish ? "📅 Agenda / Eventos" : "📅 Calendar Event")
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "6366F1"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "6366F1").opacity(0.15))
                                .cornerRadius(6)
                        }
                    }

                    if isShootDay {
                        HStack(spacing: 16) {
                            Label("\(scriptScenes.count) \(isSpanish ? "escenas" : "scenes")", systemImage: "film")
                            Label("\(formattedEighths(totalEighths)) \(isSpanish ? "págs" : "pgs")", systemImage: "doc.text")
                            Label("\(totalEstTime) \(isSpanish ? "tiempo est." : "est. time")", systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text("\(calendarEvents.count) \(isSpanish ? "evento(s) de agenda" : "calendar event(s)")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    commitNote()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(currentTheme.panelBackground(isDarkMode: colorScheme == .dark))

            Divider()

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Day type + note first: it answers "what is this day?" before the detail.
                    dayTypeCard

                    if isShootDay {
                        // Call Sheet & Horarios
                        callSheetSummaryCard

                        // Eventos de Agenda (si hay)
                        if !calendarEvents.isEmpty {
                            calendarEventsSection
                        }

                        // Escenas Programadas
                        scenesSection
                    } else {
                        // Off-day / Non-shoot day: Only show Calendar Events
                        calendarEventsSection
                    }
                }
                .padding(20)
            }
            .onAppear { noteDraft = day.dayNote }
            .onChange(of: day.dayNote) { _, newNote in noteDraft = newNote }
            .onDisappear { commitNote() }

            Divider()

            // Footer action buttons
            HStack {
                if isShootDay {
                    Button {
                        onAddCalendarEvent()
                    } label: {
                        Label(L("Add Calendar Event"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        onAddCalendarEvent()
                    } label: {
                        Label(L("Add Calendar Event"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                if isShootDay {
                    Button {
                        onOpenCallSheet()
                    } label: {
                        Label(isSpanish ? "Editar Call Sheet" : "Edit Call Sheet", systemImage: "doc.plaintext")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onExportCallSheetPDF()
                    } label: {
                        Label(isSpanish ? "Exportar Call Sheet (PDF)" : "Export Call Sheet (PDF)", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(currentTheme.panelBackground(isDarkMode: colorScheme == .dark))
        }
        .frame(minWidth: isShootDay ? 620 : 480, idealWidth: isShootDay ? 700 : 540, minHeight: isShootDay ? 520 : 380, idealHeight: isShootDay ? 640 : 440)
    }

    // MARK: - Day Type & Note

    private var dayTypeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("Day Type"), systemImage: "calendar.badge.exclamationmark")
                    .font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { day.dayType }, set: { onSetDayType($0) })) {
                    ForEach(DayType.allCases, id: \.self) { type in
                        Label(type.localizedName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)

                if !day.dayType.isShootable || !day.dayNote.isEmpty {
                    Button {
                        noteDraft = ""
                        onClearDayType()
                    } label: {
                        Label(L("Clear"), systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help(L("Clear Day Type"))
                }
            }

            TextField(L("Day note (travel details, hold reason, …)"), text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitNote() }
        }
        .padding(14)
        .background(Color.controlBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Call Sheet Summary Card

    private var callSheetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isSpanish ? "Horarios y Citación" : "Call Schedule", systemImage: "clock.badge.checkmark")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 20) {
                timeBadge(label: isSpanish ? "Llamado General" : "General Call", time: day.callSheet.generalCallTime.isEmpty ? "—" : day.callSheet.generalCallTime, icon: "megaphone.fill", color: .blue)
                timeBadge(label: isSpanish ? "Almuerzo" : "Lunch", time: day.callSheet.lunchTime.isEmpty ? "—" : day.callSheet.lunchTime, icon: "fork.knife", color: .orange)
                timeBadge(label: isSpanish ? "Merienda / Snack" : "Snack", time: day.callSheet.snackTime.isEmpty ? "—" : day.callSheet.snackTime, icon: "cup.and.saucer.fill", color: .brown)
                timeBadge(label: isSpanish ? "Wrap / Fin" : "Wrap", time: day.callSheet.dinnerTime.isEmpty ? "—" : day.callSheet.dinnerTime, icon: "flag.checkered", color: .red)
            }

            if !day.callSheet.basecampLocation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text(day.callSheet.basecampLocation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.controlBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func timeBadge(label: String, time: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(time)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calendar Events Section

    private var calendarEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isSpanish ? "Eventos de Agenda" : "Calendar Events", systemImage: "calendar.badge.clock")
                .font(.headline)

            ForEach(calendarEvents) { event in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        if !event.customStartTime.isEmpty {
                            Text(event.customStartTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        onEditScene(event)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isSpanish ? "Editar Evento" : "Edit Event")

                    Button {
                        onRemoveScene(event)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help(isSpanish ? "Eliminar Evento" : "Delete Event")
                }
                .padding(10)
                .background(Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex).opacity(0.12))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Scenes Section

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isSpanish ? "Escenas del Día" : "Day Scenes", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(scriptScenes.count) \(isSpanish ? "escenas" : "scenes")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if scriptScenes.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(isSpanish ? "No hay escenas programadas en este día." : "No scenes scheduled on this day.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(30)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(scriptScenes.enumerated()), id: \.element.id) { index, scene in
                        sceneRow(scene: scene, index: index)
                    }
                }
            }
        }
    }

    private func sceneRow(scene: Scene, index: Int) -> some View {
        let intExtLabel = scene.intExtString

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Scene number badge
                Text(scene.sceneNumber.isEmpty ? "\(index + 1)" : scene.sceneNumber)
                    .font(.subheadline.bold())
                    .frame(minWidth: 26)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)

                // Title
                Text(scene.title)
                    .font(.subheadline.bold())
                    .foregroundColor(scene.stripTextColor)
                    .lineLimit(1)

                Spacer()

                // INT/EXT & DAY/NIGHT
                Text(intExtLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(intExtLabel.contains("INT") ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(intExtLabel.contains("INT") ? .blue : .orange)
                    .cornerRadius(4)

                Text(scene.dayNightType.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scene.dayNightType == .night ? Color.purple.opacity(0.15) : Color.yellow.opacity(0.2))
                    .foregroundColor(scene.dayNightType == .night ? .purple : .brown)
                    .cornerRadius(4)

                // Duration & Est
                Text("\(formattedEighths(scene.duration)) | \(formattedTime(scene.estimatedTime))")
                    .font(.caption.bold())
                    .foregroundColor(scene.stripTextColor.opacity(0.8))

                Button {
                    onEditScene(scene)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(scene.stripTextColor.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Location and Cast
            HStack(spacing: 16) {
                if !scene.realLocation.isEmpty {
                    Label(scene.realLocation, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(scene.stripTextColor.opacity(0.85))
                }

                if !scene.cast.isEmpty {
                    Label(scene.cast.joined(separator: ", "), systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(scene.stripTextColor.opacity(0.85))
                        .lineLimit(1)
                }
            }

            // Synopsis / Notes
            if !scene.summary.isEmpty {
                Text(scene.summary)
                    .font(.caption)
                    .foregroundColor(scene.stripTextColor.opacity(0.75))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(scene.stripColor(in: palette))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

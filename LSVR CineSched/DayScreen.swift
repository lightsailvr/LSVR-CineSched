// DayScreen.swift
// The iPhone's Day screen (#24): everything about one shoot day, pushed from the Days
// list as a navigation destination (not a sheet). Bound to the day by id and read from
// the document on every body, so it follows an edit, an undo or a sync under it, and
// shows an empty state if a range change removes the day. Read-only here: the header
// (`DaySummary`), the day type and note, the call sheet card (the call sheet's times and
// basecamp, named as the day detail names them), the calendar events and the strips with
// the time cascade, each its own `Section` with a `MARK`, because #25 adds moves to the
// strips section and #26 makes the type, the note, the call sheet and the events
// editable. The strips are the same `PhoneStripRow` the list draws, with the same
// `PhoneStripActions` (no Open Day here; this is the day).
//
// Platform-free SwiftUI; the Mac compiles it and never shows it.

import SwiftUI

struct DayScreen: View {
    let dayID: UUID
    let document: ProjectDocument
    let conflictSceneIDs: Set<UUID>
    let edit: ProjectEdit
    @Environment(\.scenePalette) private var palette

    private var day: ShootDay? { document.project.shootDays.first { $0.id == dayID } }

    var body: some View {
        if let day {
            content(for: day)
        } else {
            ContentUnavailableView(
                L("Day Removed"),
                systemImage: "calendar.badge.exclamationmark",
                description: Text(L("This date is no longer in the production range."))
            )
        }
    }

    private func content(for day: ShootDay) -> some View {
        let dayNumbers = productionDayNumbers(for: document.project.shootDays)
        let summary    = DaySummary(day: day, dayNumbers: dayNumbers)
        let strips     = day.scenes.filter { !$0.isCalendarEvent }
        let events     = day.scenes.filter { $0.isCalendarEvent }
        let timeline   = dayTimeline(for: day, scenes: strips)
        let actions    = PhoneStripActions(day: day, edit: edit, openDay: nil)

        return List {
            headerSection(summary)
            dayTypeSection(day)
            callSheetSection(day)
            eventsSection(events)
            stripsSection(strips, timeline: timeline, actions: actions)
        }
        .insetGroupedListStyle()
        .navigationTitle(summary.productionDayNumber.map { "\(L("Day")) \($0)" } ?? formattedDate(day.date))
        .toolbarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    /// The day as the list's header reads it, at full size: the date, the day number or
    /// the type, and the counts.
    private func headerSection(_ summary: DaySummary) -> some View {
        let typeColor = Color(hex: summary.dayType.colorHex)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(formattedFullDate(summary.date))
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    if let number = summary.productionDayNumber {
                        Text("\(L("Day")) \(number)")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    if !summary.dayType.isShootable {
                        Label(summary.dayType.localizedName, systemImage: summary.dayType.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(typeColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(typeColor.opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 14) {
                    stat(icon: "film",       text: summary.sceneCount == 1 ? L("1 scene") : String(format: L("%d scenes"), summary.sceneCount))
                    stat(icon: "doc.text",   text: "\(summary.pagesText) \(L("pgs"))")
                    if summary.eventCount > 0 {
                        stat(icon: "calendar.badge.clock", text: summary.eventCount == 1 ? L("1 event") : String(format: L("%d events"), summary.eventCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(summary.dayType.isShootable ? nil : typeColor.opacity(0.10))
    }

    private func stat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .lineLimit(1)
    }

    // MARK: - Day type and note (#26 makes these editable)

    private func dayTypeSection(_ day: ShootDay) -> some View {
        Section {
            HStack {
                Text(L("Day Type"))
                Spacer()
                Label(day.dayType.localizedName, systemImage: day.dayType.icon)
                    .foregroundStyle(day.dayType.isShootable ? Color.primary : Color(hex: day.dayType.colorHex))
            }
            if !day.dayNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(day.dayNote)
                }
            }
        }
    }

    // MARK: - Call sheet card (#26 opens the call sheet editor from here)

    private func callSheetSection(_ day: ShootDay) -> some View {
        let sheet = day.callSheet
        return Section {
            if !day.hasCallSheetData && sheet.readyToShootTime.isEmpty && sheet.wrapTime.isEmpty {
                Text(L("No call sheet yet"))
                    .foregroundStyle(.secondary)
            } else {
                callTime(L("General Call"),   sheet.generalCallTime,  icon: "megaphone.fill",       color: .blue)
                if !sheet.readyToShootTime.isEmpty {
                    callTime(L("Ready to Shoot"), sheet.readyToShootTime, icon: "film.fill",        color: .green)
                }
                callTime(L("Lunch"),          sheet.lunchTime,        icon: "fork.knife",           color: .orange)
                if !sheet.snackTime.isEmpty {
                    callTime(L("Snack"),      sheet.snackTime,        icon: "cup.and.saucer.fill",  color: .brown)
                }
                if !sheet.dinnerTime.isEmpty {
                    callTime(L("Dinner"),     sheet.dinnerTime,       icon: "fork.knife.circle",    color: .orange)
                }
                callTime(L("Wrap"),           sheet.wrapTime,         icon: "flag.checkered",       color: .red)
                if !sheet.basecampLocation.isEmpty {
                    LabeledContent {
                        Text(sheet.basecampLocation)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label(L("Basecamp"), systemImage: "mappin.circle.fill")
                    }
                }
            }
        } header: {
            Label(L("Call Sheet"), systemImage: "doc.text")
        }
    }

    private func callTime(_ label: String, _ time: String, icon: String, color: Color) -> some View {
        LabeledContent {
            Text(time.isEmpty ? "—" : time)
                .font(.body.weight(time.isEmpty ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(time.isEmpty ? .secondary : .primary)
        } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
        }
    }

    // MARK: - Calendar events (#26 adds and edits them)

    private func eventsSection(_ events: [Scene]) -> some View {
        Section {
            if events.isEmpty {
                Text(L("No calendar events on this day."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                let color = Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex)
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(event.bannerTitle.isEmpty ? event.title : event.bannerTitle)
                    Spacer()
                    if !event.customStartTime.isEmpty {
                        Text(event.customStartTime)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label(L("Calendar Events"), systemImage: "calendar.badge.clock")
        }
    }

    // MARK: - Strips (#25 adds moves, #26 the editor)

    private func stripsSection(_ strips: [Scene], timeline: [UUID: DayTimelineEntry], actions: PhoneStripActions) -> some View {
        Section {
            if strips.isEmpty {
                Text(L("No scenes scheduled"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(strips) { scene in
                PhoneStripRow(scene: scene, timeText: timeline[scene.id]?.timeDisplay ?? "", hasConflict: conflictSceneIDs.contains(scene.id))
                    .stripListRow(color: PhoneStripRow.rowColor(for: scene, palette: palette))
                    .stripInteractions(actions, scene: scene)
            }
        } header: {
            Label(L("Strips"), systemImage: "rectangle.stack")
        }
    }
}

// PhoneStripRow.swift
// The strip as the iPhone draws it (#24), in the Days list and on the Day screen alike:
// a script scene (number, slugline, the time cascade's range, estimate and pages, on the
// strip color the palette gives it, and one chip per field the app-wide Stripboard
// Fields setting turns on, the same chips the Mac's `SceneStripRow` prints, #26), a
// banner or auto-meal (its own dark color and label), and the calendar event chip the
// lists show above the strips. Two lines instead of the Mac's one, semantic text styles
// and no fixed heights, so Dynamic Type and a narrow window both get a readable strip.
// Colors come from `Scene.stripColor(in:)` with the `scenePalette` environment, as
// everywhere.
//
// `PhoneStripActions` is where the strip's tap, long-press menu and swipe actions are
// built, one function each, so the tickets that add moves (#25) and edits (#26) have one
// place to add to for both lists. Here: the long-press preview (`StripPreview`: number,
// slugline, cast, summary), Open Day; the moves (#25): Send to Day…, Move to Next Day
// and Move to Previous Day (the M4 review: the one-gesture slip to the adjacent day, the
// next entry of the schedule whatever is on it, absent at the first and last day) and
// Return to Boneyard in the menu and as the trailing swipe (Previous Day in the menu
// only, #35); and the edits (#26): a tap
// opens the strip's editor (the scene editor, the banner input, Set Time for an
// auto-meal), the menu adds Edit, Set Time…, Duplicate Scene and Delete Banner, the
// leading swipe is Edit and Set Time, the trailing swipe gains Duplicate for a script
// scene and Delete for a banner (never a full swipe: a mis-swipe on a small screen must
// be harmless).

import SwiftUI

// MARK: - Strip row

struct PhoneStripRow: View {
    let scene: Scene
    /// The cascade's range for this strip ("07:30 AM – 08:15 AM"), or empty.
    let timeText: String
    var hasConflict: Bool = false
    /// The fields the strip prints as chips (the Stripboard Fields setting, decoded once
    /// per list body by the caller); a fresh install shows the cast, as the Mac does.
    var visibleFields: Set<StripboardField> = StripboardField.defaultSelection
    @Environment(\.scenePalette) private var palette

    var body: some View {
        if scene.isBanner {
            bannerRow
        } else {
            sceneRow
        }
    }

    // MARK: Script scene

    private var textColor: Color { scene.stripTextColor }

    private struct FieldChip: Identifiable {
        let field: StripboardField
        let value: String
        var id: StripboardField { field }
    }

    /// The enabled fields this scene has a value for, in `StripboardField` order (the
    /// Mac row's rule: a blank field leaves no dangling icon).
    private var fieldChips: [FieldChip] {
        StripboardField.allCases.compactMap { field in
            guard visibleFields.contains(field) else { return nil }
            let value = field.displayValue(for: scene)
            return value.isEmpty ? nil : FieldChip(field: field, value: value)
        }
    }

    private var sceneRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !scene.sceneNumber.isEmpty {
                    Text(scene.sceneNumber)
                        .font(.subheadline.weight(.bold).monospaced())
                        .foregroundStyle(textColor.opacity(0.75))
                }
                Text(scene.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .accessibilityLabel(L("Cast conflict"))
                }
                Text(FractionParser.formatEighths(scene.duration))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(textColor.opacity(0.8))
            }
            HStack(spacing: 8) {
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                if scene.estimatedTime > 0 {
                    Text(formattedTimeHM(scene.estimatedTime))
                        .font(.caption.monospaced())
                        .foregroundStyle(textColor.opacity(0.7))
                }
            }
            // One chip per enabled field with a value, on their own line so the time
            // range never gives way to them; each truncates on its own.
            let chips = fieldChips
            if !chips.isEmpty {
                HStack(spacing: 10) {
                    ForEach(chips) { chip in
                        HStack(spacing: 3) {
                            Image(systemName: chip.field.icon)
                                .font(.caption2.weight(.semibold))
                            Text(chip.value)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(textColor.opacity(0.7))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(chip.field.label): \(chip.value)"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.stripColor(in: palette))
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.15)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Banner and auto-meal

    private var bannerRow: some View {
        HStack(spacing: 10) {
            if !timeText.isEmpty {
                Text(timeText)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
            }
            if !scene.isAutoMeal {
                Image(systemName: scene.bannerType?.defaultIcon ?? "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(Self.bannerLabel(for: scene))
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if scene.estimatedTime > 0 {
                Text(formattedTimeHM(scene.estimatedTime))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.bannerColor(for: scene))
        .accessibilityElement(children: .combine)
    }

    /// The strip's fill, for the list row behind it too (a short banner would otherwise
    /// leave the row's minimum height showing above and below it).
    static func rowColor(for scene: Scene, palette: ScenePalette) -> Color {
        scene.isBanner ? bannerColor(for: scene) : scene.stripColor(in: palette)
    }

    /// The banner's fill and label are the Mac Stripboard's rules (`BannerAppearance.swift`:
    /// an auto-meal by its kind, a meal banner near black, the legacy amber too, else its
    /// own color or slate; the label without the "(01:00 PM)" suffix), so the same banner
    /// draws the same here and on the Mac.
    static func bannerColor(for scene: Scene) -> Color {
        Color(hex: scene.bannerFillHex)
    }

    static func bannerLabel(for scene: Scene) -> String {
        scene.bannerDisplayLabel
    }
}

// MARK: - Event chip

/// A calendar event as the chip the calendar cell and the Stripboard show: its color,
/// its time and its title.
struct PhoneEventChip: View {
    let event: Scene

    private var color: Color { Color(hex: event.bannerColorHex.isEmpty ? "6366F1" : event.bannerColorHex) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption2.weight(.bold))
            if !event.customStartTime.isEmpty {
                Text(event.customStartTime)
                    .font(.caption2.weight(.bold))
                Text("·").opacity(0.6)
            }
            Text(event.bannerTitle.isEmpty ? event.title : event.bannerTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Long-press preview

/// What a long press on a strip shows before the menu: the scene's number and slugline,
/// its cast and its summary, on its strip color.
struct StripPreview: View {
    let scene: Scene
    @Environment(\.scenePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !scene.sceneNumber.isEmpty {
                    Text(scene.sceneNumber)
                        .font(.title3.weight(.bold).monospaced())
                }
                Text(scene.title)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Label("\(FractionParser.formatEighths(scene.duration)) \(L("pgs"))", systemImage: "doc.text")
                if scene.estimatedTime > 0 {
                    Label(formattedTimeHM(scene.estimatedTime), systemImage: "clock")
                }
                if !scene.realLocation.isEmpty {
                    Label(scene.realLocation, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .opacity(0.8)
            if !scene.cast.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Cast"))
                        .font(.caption.weight(.semibold))
                        .opacity(0.7)
                    Text(scene.cast.joined(separator: ", "))
                        .font(.subheadline)
                }
            }
            let summary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Summary"))
                        .font(.caption.weight(.semibold))
                        .opacity(0.7)
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(8)
                }
            }
        }
        .foregroundStyle(scene.stripTextColor)
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(scene.stripColor(in: palette))
    }
}

// MARK: - Strip actions (the hooks for #25 and #26)

/// The actions a strip row offers, built in one place for the Days list and the Day
/// screen. `stripContextMenu(for:)` is the long-press menu's items,
/// `stripSwipeActions(for:)` the trailing swipe and `stripLeadingSwipeActions(for:)`
/// the leading one; `open(_:)` is the tap. #25 put the moves here (Send to Day… for a
/// script scene or a banner, Move to Next Day / Move to Previous Day for the same when
/// the day has a neighbour — `hasPreviousDay` and `hasNextDay`, which the caller reads
/// off the day's place in `shootDays` once per redraw — Return to Boneyard for a script
/// scene; auto-meals follow the call sheet and calendar events are never strips, so
/// none of them gets a move) and #26
/// the edits (`PhoneDayEdits`: Edit, Set Time…, Duplicate Scene, Delete Banner; an
/// auto-meal has Set Time only, because its call sheet's time would bring a deleted one
/// back at the next sync). Every item writes through `moves` (`PhoneMoves`, the move
/// funnel and its pickers) or `dayEdits` (`PhoneDayEdits`, the edit funnel and its
/// editors); nothing here holds the raw `edit` closure.
struct PhoneStripActions {
    let day:      ShootDay
    let moves:    PhoneMoves
    let dayEdits: PhoneDayEdits
    /// Opens the Day screen for `day`; nil on the Day screen itself.
    let openDay: (() -> Void)?
    /// Whether the schedule has a day before / after this one (Move to Previous Day and
    /// Move to Next Day are absent otherwise).
    var hasPreviousDay: Bool = false
    var hasNextDay:     Bool = false

    /// Send to Day applies to what a drag would carry: a script scene or a banner.
    private func canSendToDay(_ scene: Scene) -> Bool { !scene.isCalendarEvent && !scene.isAutoMeal }
    /// Move to Next / Previous Day is a Send to Day to the neighbour: the same strips.
    private func canMoveToAdjacentDay(_ scene: Scene, _ direction: DayDirection) -> Bool {
        canSendToDay(scene) && (direction == .next ? hasNextDay : hasPreviousDay)
    }
    /// Only a script scene has a place in the Boneyard.
    private func canReturnToBoneyard(_ scene: Scene) -> Bool { !scene.isBanner && !scene.isCalendarEvent }
    /// Duplicate Scene copies a script scene.
    private func canDuplicate(_ scene: Scene) -> Bool { !scene.isBanner && !scene.isCalendarEvent }
    /// Delete Banner: a custom banner goes; an auto-meal is the call sheet's to remove.
    private func canDeleteBanner(_ scene: Scene) -> Bool { scene.isBanner && !scene.isAutoMeal && !scene.isCalendarEvent }

    /// The tap: the strip's editor (the scene editor, the banner input, or Set Time for
    /// an auto-meal).
    func open(_ scene: Scene) {
        dayEdits.presentEditor(for: scene, dayID: day.id)
    }

    private func editLabel(_ scene: Scene) -> String {
        scene.isAutoMeal ? L("Set Time…") : (scene.isBanner ? L("Edit Banner") : L("Edit Scene"))
    }

    @ViewBuilder
    func stripContextMenu(for scene: Scene) -> some View {
        if let openDay {
            Button {
                openDay()
            } label: {
                Label(L("Open Day"), systemImage: "calendar")
            }
        }
        // The edits (#26).
        Button {
            open(scene)
        } label: {
            Label(editLabel(scene), systemImage: scene.isAutoMeal ? "clock" : "pencil")
        }
        if !scene.isAutoMeal {
            Button {
                dayEdits.presentSetTime(sceneID: scene.id, dayID: day.id)
            } label: {
                Label(L("Set Time…"), systemImage: "clock")
            }
        }
        if canDuplicate(scene) {
            Button {
                dayEdits.duplicateScene(id: scene.id)
            } label: {
                Label(L("Duplicate Scene"), systemImage: "doc.on.doc")
            }
        }
        Divider()
        // The moves (#25).
        if canMoveToAdjacentDay(scene, .next) {
            Button {
                moves.moveToAdjacentDay([scene.id], from: day.id, .next)
            } label: {
                Label(L("Move to Next Day"), systemImage: "arrow.down.to.line")
            }
        }
        if canMoveToAdjacentDay(scene, .previous) {
            Button {
                moves.moveToAdjacentDay([scene.id], from: day.id, .previous)
            } label: {
                Label(L("Move to Previous Day"), systemImage: "arrow.up.to.line")
            }
        }
        if canSendToDay(scene) {
            Button {
                moves.presentSendToDay(sceneIDs: [scene.id])
            } label: {
                Label(L("Send to Day…"), systemImage: "arrow.turn.down.right")
            }
        }
        if canReturnToBoneyard(scene) {
            Button {
                moves.returnToBoneyard([scene.id])
            } label: {
                Label(L("Return to Boneyard"), systemImage: "tray.and.arrow.down")
            }
        }
        if canDeleteBanner(scene) {
            Divider()
            Button(role: .destructive) {
                dayEdits.deleteNoticeStrip(scene)
            } label: {
                Label(L("Delete Banner"), systemImage: "trash")
            }
        }
    }

    /// The trailing swipe: Boneyard, Next Day and Send to Day for a script scene (#25),
    /// then Duplicate; Delete and the moves for a custom banner; nothing for an auto-meal.
    /// The first button is the one a short swipe reveals, so the adjacent day comes before
    /// the picker. Move to Previous Day is in the long-press menu only (#35): five
    /// buttons left each one too narrow to read on a phone row, and the slip back a day is
    /// the rarer one.
    @ViewBuilder
    func stripSwipeActions(for scene: Scene) -> some View {
        if canDeleteBanner(scene) {
            Button(role: .destructive) {
                dayEdits.deleteNoticeStrip(scene)
            } label: {
                Label(L("Delete"), systemImage: "trash")
            }
        }
        if canReturnToBoneyard(scene) {
            Button {
                moves.returnToBoneyard([scene.id])
            } label: {
                Label(L("Boneyard"), systemImage: "tray.and.arrow.down")
            }
            .tint(.orange)
        }
        if canMoveToAdjacentDay(scene, .next) {
            Button {
                moves.moveToAdjacentDay([scene.id], from: day.id, .next)
            } label: {
                Label(L("Next Day"), systemImage: "arrow.down.to.line")
            }
            .tint(.green)
        }
        if canSendToDay(scene) {
            Button {
                moves.presentSendToDay(sceneIDs: [scene.id])
            } label: {
                Label(L("Send to Day"), systemImage: "arrow.turn.down.right")
            }
            .tint(.blue)
        }
        if canDuplicate(scene) {
            Button {
                dayEdits.duplicateScene(id: scene.id)
            } label: {
                Label(L("Duplicate"), systemImage: "doc.on.doc")
            }
            .tint(.indigo)
        }
    }

    /// The leading swipe (#26): Edit (the strip's editor) and Set Time.
    @ViewBuilder
    func stripLeadingSwipeActions(for scene: Scene) -> some View {
        Button {
            open(scene)
        } label: {
            Label(scene.isAutoMeal ? L("Set Time") : L("Edit"), systemImage: scene.isAutoMeal ? "clock" : "pencil")
        }
        .tint(.accentColor)
        if !scene.isAutoMeal {
            Button {
                dayEdits.presentSetTime(sceneID: scene.id, dayID: day.id)
            } label: {
                Label(L("Set Time"), systemImage: "clock")
            }
            .tint(.teal)
        }
    }
}

extension View {
    /// The list row a strip sits in: no insets, no separator, and the strip's own color
    /// behind it so the row is the strip edge to edge.
    func stripListRow(color: Color) -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(color)
    }

    /// The strip's tap (its editor, #26), its long press (the preview for a script scene,
    /// the menu items from `stripContextMenu`) and its swipe actions on both edges
    /// (`stripSwipeActions`, `stripLeadingSwipeActions`), never a full swipe.
    func stripInteractions(_ actions: PhoneStripActions, scene: Scene) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture { actions.open(scene) }
            .contextMenu {
                actions.stripContextMenu(for: scene)
            } preview: {
                if scene.isBanner {
                    PhoneStripRow(scene: scene, timeText: "")
                } else {
                    StripPreview(scene: scene)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                actions.stripLeadingSwipeActions(for: scene)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                actions.stripSwipeActions(for: scene)
            }
    }
}


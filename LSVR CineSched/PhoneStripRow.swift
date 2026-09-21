// PhoneStripRow.swift
// The strip as the iPhone draws it (#24), in the Days list and on the Day screen alike:
// a script scene (number, slugline, the time cascade's range, cast count, estimate and
// pages, on the strip color the palette gives it), a banner or auto-meal (its own dark
// color and label), and the calendar event chip the lists show above the strips. Two
// lines instead of the Mac's one, semantic text styles and no fixed heights, so Dynamic
// Type and a narrow window both get a readable strip. Colors come from
// `Scene.stripColor(in:)` with the `scenePalette` environment, as everywhere.
//
// `PhoneStripActions` is where the strip's long-press menu and swipe actions are built,
// one function each, so the tickets that add moves (#25) and edits (#26) have one place
// to add to for both lists. Here they hold the preview-only baseline: the long-press
// preview (`StripPreview`: number, slugline, cast, summary) and Open Day.

import SwiftUI

// MARK: - Edit funnel type

/// The edit funnel `PhoneEditor` hands down: `edit(name) { data in … }`, the same call
/// shape as `ContentView.edit(_:_:)`, so a subview writes the project without holding
/// the document or the undo manager.
typealias ProjectEdit = (_ actionName: String?, _ change: (inout ProjectData) -> Void) -> Void

// MARK: - Strip row

struct PhoneStripRow: View {
    let scene: Scene
    /// The cascade's range for this strip ("07:30 AM – 08:15 AM"), or empty.
    let timeText: String
    var hasConflict: Bool = false
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
                }
                if !scene.cast.isEmpty {
                    Label(scene.cast.count == 1 ? L("1 cast") : String(format: L("%d cast"), scene.cast.count), systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if scene.estimatedTime > 0 {
                    Text(formattedTimeHM(scene.estimatedTime))
                        .font(.caption.monospaced())
                        .foregroundStyle(textColor.opacity(0.7))
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

    /// The banner's dark fill: meals and auto-meals near black, the general call navy,
    /// ready-to-shoot green, wrap red; a banner with its own color keeps it (the same
    /// rules the Stripboard's `BannerStripRow` applies).
    static func bannerColor(for scene: Scene) -> Color {
        if scene.isAutoMeal {
            switch scene.mealKind {
            case .generalCall:  return Color(hex: "1E3A8A")
            case .readyToShoot: return Color(hex: "064E3B")
            case .wrap:         return Color(hex: "991B1B")
            default:            return Color(hex: "18181B")
            }
        }
        if scene.bannerType == .mealBreak || scene.bannerColorHex == "F59E0B" {
            return Color(hex: "18181B")
        }
        return Color(hex: scene.bannerColorHex.isEmpty ? "334155" : scene.bannerColorHex)
    }

    /// The banner's label: an auto-meal by its kind, otherwise its title without the
    /// "(01:00 PM)" time the auto-generated titles carry.
    static func bannerLabel(for scene: Scene) -> String {
        if let kind = scene.mealKind {
            return "\(kind.icon) \(kind.defaultTitle)"
        }
        let raw = scene.bannerTitle.isEmpty ? scene.title : scene.bannerTitle
        return raw
            .replacingOccurrences(of: #"\s*\(\s*\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?\s*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
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
/// screen. `stripContextMenu(for:)` is the long-press menu's items and
/// `stripSwipeActions(for:)` the row's swipe actions; both are the baseline here (the
/// menu opens the day, the swipe does nothing), and #25 (moves) and #26 (edits) add
/// their items to these two functions. `edit` is the funnel every item writes through.
struct PhoneStripActions {
    let day:  ShootDay
    let edit: ProjectEdit
    /// Opens the Day screen for `day`; nil on the Day screen itself.
    let openDay: (() -> Void)?

    @ViewBuilder
    func stripContextMenu(for scene: Scene) -> some View {
        if let openDay {
            Button {
                openDay()
            } label: {
                Label(L("Open Day"), systemImage: "calendar")
            }
        }
    }

    @ViewBuilder
    func stripSwipeActions(for scene: Scene) -> some View {
        EmptyView()
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

    /// The strip's long press (the preview for a script scene, the menu items from
    /// `stripContextMenu`) and its swipe actions (`stripSwipeActions`).
    func stripInteractions(_ actions: PhoneStripActions, scene: Scene) -> some View {
        self
            .contextMenu {
                actions.stripContextMenu(for: scene)
            } preview: {
                if scene.isBanner {
                    PhoneStripRow(scene: scene, timeText: "")
                } else {
                    StripPreview(scene: scene)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                actions.stripSwipeActions(for: scene)
            }
    }
}

// EditorDrafts.swift
// The drafts the adaptive editors edit (#19): the plain values a scene editor, the
// banner input, the calendar event input, the iPhone's new-scene form (#27) and the Set
// Time sheet (#26) hold between opening and Save, with what each reads from the model and
// the one value it writes back. Pure and view-free, so every conversion (eighths to
// "1 7/8" and back, minutes to "2:30", comma lists, the Custom type's blank-means-none
// rule, the time of day read off a slugline) is pinned in `EditorDraftsTests`. A view
// keeps one draft in `@State`, repopulates it when its subject changes, and on Save
// assigns `draft.applied(to:)` (or `makeBanner()` / `makeEvent()` / `makeScene()`) to its
// binding **once**, so a Save is one `perform` and one undo step by construction
// (learnings, 2026-09-17 #9).

import Foundation

// MARK: - Scene

struct SceneDraft: Equatable {
    var sceneNumber:      String
    var title:            String
    var realLocation:     String
    var duration:         String
    var estimatedTime:    String
    var dayNightType:     DayNightType
    var castText:         String   // comma-separated editing surface
    var summary:          String

    var extras:           String
    var props:            String
    var setDressing:      String
    var wardrobe:         String
    var makeupHair:       String
    var vehicles:         String
    var specialEquipment: String
    var stunts:           String
    var sfx:              String
    var vfx:              String
    var breakdownNotes:   String

    /// The fields as the scene holds them. A number still at the front of the title (the
    /// shape projects had before the scene-number field) is split out for editing.
    init(scene: Scene) {
        var numbered = scene
        numbered.autoExtractSceneNumberIfNeeded()
        sceneNumber      = numbered.sceneNumber
        title            = numbered.title
        realLocation     = scene.realLocation
        duration         = scene.duration      > 0 ? FractionParser.formatEighths(scene.duration) : ""
        estimatedTime    = scene.estimatedTime > 0 ? Self.minutesForEditing(scene.estimatedTime) : ""
        dayNightType     = scene.dayNightType
        castText         = scene.cast.joined(separator: ", ")
        summary          = scene.summary
        extras           = scene.extras.joined(separator: ", ")
        props            = scene.props.joined(separator: ", ")
        setDressing      = scene.setDressing.joined(separator: ", ")
        wardrobe         = scene.wardrobe.joined(separator: ", ")
        makeupHair       = scene.makeupHair.joined(separator: ", ")
        vehicles         = scene.vehicles.joined(separator: ", ")
        specialEquipment = scene.specialEquipment.joined(separator: ", ")
        stunts           = scene.stunts.joined(separator: ", ")
        sfx              = scene.sfx.joined(separator: ", ")
        vfx              = scene.vfx.joined(separator: ", ")
        breakdownNotes   = scene.breakdownNotes
    }

    // MARK: Validation

    var parsedEighths: Int? { FractionParser.parseToEighths(duration) }
    var parsedMinutes: Int? { TimeParser.parseToMinutes(estimatedTime) }

    /// Blank is valid (the stored value stays, see `applied`); only a malformed entry is not.
    var durationIsValid:      Bool { parsedEighths != nil || duration.isEmpty }
    var estimatedTimeIsValid: Bool { parsedMinutes != nil || estimatedTime.isEmpty }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && durationIsValid && estimatedTimeIsValid
    }

    // MARK: Writing back

    /// `scene` with the draft's fields applied; everything the form does not edit (the id,
    /// the address, the custom start time, the completion flag, the banner fields) is
    /// carried through. A blank length keeps the stored value, except on a Custom scene,
    /// where blank means none.
    func applied(to scene: Scene) -> Scene {
        var saved = scene
        saved.sceneNumber  = sceneNumber.trimmingCharacters(in: .whitespaces)
        saved.title        = title
        saved.realLocation = realLocation.trimmingCharacters(in: .whitespaces)
        saved.dayNightType = dayNightType
        saved.cast         = Self.commaList(castText)
        saved.summary      = summary
        if let eighths = parsedEighths      { saved.duration      = eighths }
        else if dayNightType == .custom     { saved.duration      = 0 }
        if let minutes = parsedMinutes      { saved.estimatedTime = minutes }
        else if dayNightType == .custom     { saved.estimatedTime = 0 }

        saved.extras           = Self.commaList(extras)
        saved.props            = Self.commaList(props)
        saved.setDressing      = Self.commaList(setDressing)
        saved.wardrobe         = Self.commaList(wardrobe)
        saved.makeupHair       = Self.commaList(makeupHair)
        saved.vehicles         = Self.commaList(vehicles)
        saved.specialEquipment = Self.commaList(specialEquipment)
        saved.stunts           = Self.commaList(stunts)
        saved.sfx              = Self.commaList(sfx)
        saved.vfx              = Self.commaList(vfx)
        saved.breakdownNotes   = breakdownNotes
        return saved
    }

    // MARK: Conversions

    /// A stored minute count as the editor shows it (no units): "45", "2", "2:05".
    static func minutesForEditing(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours):\(String(format: "%02d", mins))" }
        if hours > 0              { return "\(hours)" }
        return "\(mins)"
    }

    static func commaList(_ text: String) -> [String] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Banner

struct BannerDraft: Equatable {
    var type:          BannerType = .notice
    var title:         String     = BannerDraft.defaultTitle(for: .notice)
    var startTime:     String     = "12:00 PM"
    var note:          String     = ""
    var estimatedTime: String     = "0:30"
    var colorHex:      String     = "8B5CF6"   // violet
    /// The banner being edited (#26), whose id and fixed start `applied(to:)` keeps;
    /// nil when adding, the only case the Mac's Stripboard has.
    private(set) var existingID: UUID?

    static let defaultColorHex = "8B5CF6"

    /// A new banner: the defaults the old sheet started with.
    init() {}

    /// An existing banner's fields, read back the way `makeBanner` wrote them: the
    /// start time from `bannerNote`, the note from `summary` only when there is no
    /// start time (with one, the old sheet kept no note), the estimate as "h:mm".
    init(banner: Scene) {
        type          = banner.bannerType ?? .notice
        title         = banner.bannerTitle.isEmpty ? banner.title : banner.bannerTitle
        startTime     = banner.bannerNote
        note          = banner.bannerNote.isEmpty ? banner.summary : ""
        estimatedTime = "\(banner.estimatedTime / 60):" + String(format: "%02d", banner.estimatedTime % 60)
        colorHex      = banner.bannerColorHex.isEmpty ? Self.defaultColorHex : banner.bannerColorHex
        existingID    = banner.id
    }

    var isEditing: Bool { existingID != nil }

    static let colorOptions: [(name: String, hex: String)] = [
        ("Indigo",   "6366F1"),
        ("Crimson",  "EF4444"),
        ("Teal",     "14B8A6"),
        ("Amber",    "D97706"),
        ("Violet",   "8B5CF6"),
        ("Charcoal", "374151")
    ]

    static func defaultTitle(for type: BannerType) -> String { type.localizedName }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Switches the type; a title still at the old type's default (or blank) follows it,
    /// a typed one stays.
    mutating func setType(_ newType: BannerType) {
        let wasDefault = title.isEmpty || title == Self.defaultTitle(for: type)
        type = newType
        if wasDefault { title = Self.defaultTitle(for: newType) }
    }

    /// The strip the old sheet built: a blank title falls back to the type's default; the
    /// trimmed start time rides in `bannerNote` and, when present, in `summary` (the
    /// strip's second line), with the note as the summary otherwise.
    func makeBanner() -> Scene {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanTime  = startTime.trimmingCharacters(in: .whitespaces)
        var banner = Scene.createBanner(
            type:          type,
            title:         cleanTitle.isEmpty ? Self.defaultTitle(for: type) : cleanTitle,
            note:          note,
            estimatedTime: estimatedTime,
            colorHex:      colorHex
        )
        banner.summary    = cleanTime.isEmpty ? note : cleanTime
        banner.bannerNote = cleanTime
        return banner
    }

    /// The edit's write (#26): `makeBanner()` in the place of `banner`, keeping its id and
    /// the fixed start time Set Time may have given it (the form does not edit that).
    func applied(to banner: Scene) -> Scene {
        var saved = makeBanner()
        saved.id              = banner.id
        saved.customStartTime = banner.customStartTime
        return saved
    }
}

// MARK: - Calendar event

struct CalendarEventDraft: Equatable {
    var title:    String
    var time:     String
    var colorHex: String
    /// The event being edited, whose id the saved event keeps; nil when adding.
    private(set) var existingID: UUID?

    static let defaultColorHex = "6366F1"   // indigo

    static let colorOptions: [(name: String, hex: String)] = [
        ("Indigo",  "6366F1"),
        ("Teal",    "14B8A6"),
        ("Amber",   "D97706"),
        ("Rose",    "F43F5E"),
        ("Violet",  "8B5CF6"),
        ("Emerald", "10B981")
    ]

    /// Blank for a new event; an existing one's title (its banner title, or the plain
    /// title for events that predate it), time and color otherwise.
    init(event: Scene?) {
        if let event {
            title      = event.bannerTitle.isEmpty ? event.title : event.bannerTitle
            time       = event.summary
            colorHex   = event.bannerColorHex.isEmpty ? Self.defaultColorHex : event.bannerColorHex
            existingID = event.id
        } else {
            title      = ""
            time       = "10:00 AM"
            colorHex   = Self.defaultColorHex
            existingID = nil
        }
    }

    var isEditing: Bool { existingID != nil }
    var canSave:   Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The event to write, or nil while the title is blank. An edit keeps the event's id
    /// so the day's list replaces it in place.
    func makeEvent() -> Scene? {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        guard !cleanTitle.isEmpty else { return nil }
        var event = Scene.createCalendarEvent(
            title:    cleanTitle,
            time:     time.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex
        )
        if let existingID { event.id = existingID }
        return event
    }
}

// MARK: - New scene (#27)

/// What the iPhone's New Scene form holds (`NewSceneSheet`): the fields the Mac's
/// `NewSceneInputView` has, as strings, validated its way (a title is required, the
/// number may be blank, a length may be blank but not malformed), and one `makeScene()`
/// that builds the Boneyard scene the Mac's form builds: an estimate typed is taken as
/// typed, else it is derived from the pages (fifteen minutes an eighth), else none.
/// One thing the Mac's form does not do: with the type picker at its default (nil) the
/// time of day is read off the slugline, as the script importers read it
/// (`FinalDraftParser.TimeOfDay`), so "INT. KITCHEN - NIGHT" is a night scene without a
/// second tap; a slugline naming none is a day scene, and a picked type wins.
struct NewSceneDraft: Equatable {
    var sceneNumber:   String = ""
    var title:         String = ""
    var realLocation:  String = ""
    var duration:      String = ""
    var estimatedTime: String = ""
    /// The picker's choice; nil is the default, the type read off the slugline.
    var dayNightType:  DayNightType? = nil

    // MARK: Validation

    var parsedEighths: Int? { FractionParser.parseToEighths(duration) }
    var parsedMinutes: Int? { TimeParser.parseToMinutes(estimatedTime) }

    var durationIsValid:      Bool { parsedEighths != nil || duration.isEmpty }
    var estimatedTimeIsValid: Bool { parsedMinutes != nil || estimatedTime.isEmpty }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && durationIsValid && estimatedTimeIsValid
    }

    // MARK: The type

    /// The scene's time of day: the picker's choice, else the slugline's.
    var resolvedDayNightType: DayNightType {
        dayNightType ?? Self.dayNightType(inSlugline: title)
    }

    /// The time of day a slugline names, folded onto `DayNightType` the way the Final
    /// Draft mapping folds it (unknown reads as day).
    static func dayNightType(inSlugline slugline: String) -> DayNightType {
        switch FinalDraftParser.TimeOfDay(from: slugline) {
        case .night:         return .night
        case .dawn:          return .dawn
        case .dusk:          return .dusk
        case .afternoon:     return .afternoon
        case .day, .unknown: return .day
        }
    }

    // MARK: Writing

    /// The new Boneyard scene, a fresh id each call.
    func makeScene() -> Scene {
        let eighths = parsedEighths ?? 0
        let minutes: Int
        if let typed = parsedMinutes { minutes = typed }
        else if eighths > 0          { minutes = TimeParser.estimatedMinutes(forEighths: eighths) }
        else                         { minutes = 0 }
        return Scene(
            title:         title,
            sceneNumber:   sceneNumber.trimmingCharacters(in: .whitespaces),
            duration:      eighths,
            estimatedTime: minutes,
            dayNightType:  resolvedDayNightType,
            realLocation:  realLocation.trimmingCharacters(in: .whitespaces)
        )
    }
}

// MARK: - Quick time (Set Time)

/// The Set Time sheet's fields (#26; the Stripboard's `QuickTimeEditSheet` seeded them on
/// appear): whether the strip starts at a fixed time or where the cascade puts it, that
/// time, and the estimate as hours and minutes.
struct QuickTimeDraft: Equatable {
    var isCustomTime:   Bool
    var customTimeText: String
    var hours:          Int
    var minutes:        Int

    /// The old sheet's seeding: a fixed time as set, else automatic with "08:00 AM" ready
    /// to switch to; the estimate as stored, else the cascade's 15 minutes for a script
    /// scene and 30 for a banner.
    init(scene: Scene) {
        let start      = scene.customStartTime.trimmingCharacters(in: .whitespaces)
        isCustomTime   = !start.isEmpty
        customTimeText = start.isEmpty ? "08:00 AM" : start
        let duration   = scene.estimatedTime > 0 ? scene.estimatedTime : (scene.isBanner ? 30 : 15)
        hours          = duration / 60
        minutes        = duration % 60
    }

    var durationMinutes: Int { hours * 60 + minutes }

    /// A fixed time must parse ("11:00 AM", "13:30"); the text is ignored when automatic.
    var isValid: Bool { !isCustomTime || parseTimeToMinutes(customTimeText) != nil }

    /// The old sheet's preview line: the fixed range with the duration, or the duration
    /// with a reminder that the cascade places it.
    var previewText: String {
        if isCustomTime, let start = parseTimeToMinutes(customTimeText) {
            return "\(formatMinutesToClock(start)) ➔ \(formatMinutesToClock(start + durationMinutes)) (\(formattedTimeHM(durationMinutes)))"
        }
        return "\(L("Duration")): \(formattedTimeHM(durationMinutes)) (\(L("cascades by day order")))"
    }

    /// The one write: the fixed start (trimmed, or cleared when automatic) and the
    /// estimate; everything else is carried.
    func applied(to scene: Scene) -> Scene {
        var saved = scene
        saved.customStartTime = isCustomTime ? customTimeText.trimmingCharacters(in: .whitespaces) : ""
        saved.estimatedTime   = durationMinutes
        return saved
    }
}

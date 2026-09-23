// EditorDrafts.swift
// The drafts the adaptive editors edit (#19): the plain values a scene editor, the
// banner input, the calendar event input, the iPhone's new-scene form (#27) and the Set
// Time sheet (#26) hold between opening and Save, with what each reads from the model and
// the one value it writes back. Pure and view-free, so every conversion (eighths to
// "1 7/8" and back, minutes to "2:30", comma lists, the Custom type's blank-means-none
// rule, the time of day read off a slugline, a shot's fields, #39) is pinned in
// `EditorDraftsTests`. A view
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

    /// The shot list and the scene's own frame (#39), carried whole and edited only
    /// through the shot edits below, which run ShotEdits.swift's rules on a scene value so
    /// the estimate is the sum and the frame moves onto shot A exactly as a project edit
    /// would. Save writes both back with the rest, in the one assignment.
    var shots:            [Shot]
    var frame:            Data?

    /// The pages as seeded and the eighths they stand for: a whole number of pages
    /// shows as "1" or "2", which the parser would read as eighths (a bare integer is
    /// eighths, the New Scene rule), so an untouched field writes the stored length back.
    private let seededDuration: String
    private let seededEighths:  Int

    /// The fields as the scene holds them. A number still at the front of the title (the
    /// shape projects had before the scene-number field) is split out for editing.
    init(scene: Scene) {
        var numbered = scene
        numbered.autoExtractSceneNumberIfNeeded()
        sceneNumber      = numbered.sceneNumber
        title            = numbered.title
        realLocation     = scene.realLocation
        duration         = scene.duration      > 0 ? FractionParser.formatEighths(scene.duration) : ""
        seededDuration   = duration
        seededEighths    = scene.duration
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
        shots            = scene.shots
        frame            = scene.frame
    }

    // MARK: Validation

    /// The pages as typed; the seeded text untouched is the seeded length (see above).
    var parsedEighths: Int? {
        duration == seededDuration && seededEighths > 0 ? seededEighths : FractionParser.parseToEighths(duration)
    }
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
        saved.shots            = shots
        saved.frame            = frame
        // The estimate rule once more, so a Save with shots writes the sum whatever the
        // estimate text says (the field is read-only then, and shows that sum).
        saved.applyShotEstimate()
        return saved
    }

    // MARK: Conversions

    /// A stored minute count as the editor shows it (no units): "45", "2", "2:05", in a
    /// form `TimeParser` reads back as the same count. A bare number up to 14 is hours
    /// there and 15 or more is minutes, so 10 minutes is "0:10" (never "10", ten hours)
    /// and 15 hours is "15:00" (never "15", fifteen minutes): a shot's 10 minutes, or an
    /// estimate left by removing the last shot, must survive an untouched Save (#39).
    static func minutesForEditing(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        if mins == 0 && (1...10).contains(hours) { return "\(hours)" }
        if hours == 0 && mins > 14               { return "\(mins)" }
        return "\(hours):\(String(format: "%02d", mins))"
    }

    static func commaList(_ text: String) -> [String] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Scene draft: the shot list (#39)

extension SceneDraft {
    var hasShots: Bool { !shots.isEmpty }

    /// The shot `id` as the editor holds it; nil once it is gone.
    func shot(withID id: UUID) -> Shot? {
        shots.first { $0.id == id }
    }

    /// The displayed number of the shot with `id` for the number as typed ("12A"), by
    /// #37's letter rule; nil when the draft has no such shot.
    func shotNumber(forShotID id: UUID) -> String? {
        shotScene.shotNumber(forShotID: id)
    }

    /// Appends `shot`, or inserts it right after `previousID` (Add Another, #37's
    /// add-after); the first shot takes the scene's frame. The new shot's id, or nil when
    /// the edit was refused.
    @discardableResult
    mutating func addShot(_ shot: Shot = Shot(), after previousID: UUID? = nil) -> UUID? {
        editShots { $0.addShot(shot, after: previousID) } ? shot.id : nil
    }

    /// Replaces the shot with `shot.id` in place (a page's commit).
    @discardableResult
    mutating func updateShot(_ shot: Shot) -> Bool {
        editShots { $0.updateShot(shot) }
    }

    /// Removes the shot with `id`; the last one leaves its sum as the estimate, editable.
    @discardableResult
    mutating func removeShot(withID id: UUID) -> Bool {
        editShots { $0.removeShot(withID: id) }
    }

    /// A list's `onMove` over the shot rows.
    @discardableResult
    mutating func moveShots(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        editShots { $0.moveShots(fromOffsets: source, toOffset: destination) }
    }

    /// A copy of the shot with `id` right after it; the copy's id.
    @discardableResult
    mutating func duplicateShot(withID id: UUID) -> UUID? {
        editShots { $0.duplicateShot(withID: id) }
    }

    /// The Props the shots add to the breakdown: what the union (#37) lists after the
    /// scene's own items, i.e. every shot item the Props field does not already name,
    /// compared case-insensitively. Empty when the shots add nothing.
    var propsFromShots: [String] {
        Self.itemsFromShots(Self.commaList(props), shots.map { $0.props })
    }

    /// The same for Special Equipment, which a shot's equipment feeds.
    var equipmentFromShots: [String] {
        Self.itemsFromShots(Self.commaList(specialEquipment), shots.map { $0.equipment })
    }

    /// The same for SFX.
    var sfxFromShots: [String] {
        Self.itemsFromShots(Self.commaList(sfx), shots.map { $0.sfx })
    }

    // MARK: Helpers

    /// The union starts with the scene's items de-duplicated, so what follows them is
    /// exactly what the shots contribute.
    private static func itemsFromShots(_ sceneItems: [String], _ shotItems: [[String]]) -> [String] {
        let own   = Scene.breakdownUnion(sceneItems, [])
        let union = Scene.breakdownUnion(sceneItems, shotItems)
        return Array(union.dropFirst(own.count))
    }

    /// The draft's shot list as a scene value, for #37's rules: the number and title as
    /// typed (the letters' prefix), the estimate as it parses, the shots and the frame.
    private var shotScene: Scene {
        Scene(
            title:         title,
            sceneNumber:   sceneNumber,
            estimatedTime: parsedMinutes ?? 0,
            shots:         shots,
            frame:         frame
        )
    }

    /// Runs one of #37's `Scene` edits on the draft's shot list and reads back what it
    /// wrote: the shots, the frame, and, while the scene has or had shots, the estimate
    /// (the sum, or the last sum after the last shot goes) as the field shows it.
    private mutating func editShots<Result>(_ change: (inout Scene) -> Result) -> Result {
        var scene   = shotScene
        let hadShots = !scene.shots.isEmpty
        let result  = change(&scene)
        shots = scene.shots
        frame = scene.frame
        if hadShots || !scene.shots.isEmpty {
            estimatedTime = Self.minutesForEditing(scene.estimatedTime)
        }
        return result
    }
}

// MARK: - Shot (#39)

/// A shot's page in the scene editor: the description, the duration as `TimeParser`
/// reads it, the three breakdown lists as comma-separated text and the frame. The page
/// edits one in `@State`, and each change is written into the scene draft through
/// `SceneDraft.updateShot(draft.applied(to:))`, so the rules run and the list behind the
/// page is always current; the scene's one Save writes it all back.
struct ShotDraft: Equatable {
    /// The shot this page edits.
    let shotID:    UUID
    var details:   String
    var duration:  String
    var equipment: String
    var props:     String
    var sfx:       String
    var frame:     Data?

    init(shot: Shot) {
        shotID    = shot.id
        details   = shot.details
        duration  = SceneDraft.minutesForEditing(shot.durationMinutes)
        equipment = shot.equipment.joined(separator: ", ")
        props     = shot.props.joined(separator: ", ")
        sfx       = shot.sfx.joined(separator: ", ")
        frame     = shot.frame
    }

    var parsedMinutes: Int? { TimeParser.parseToMinutes(duration) }

    /// A shot always has a duration: blank or malformed is not valid.
    var isValid: Bool { parsedMinutes != nil }

    /// `shot` with the page's fields: the description trimmed, the duration in minutes
    /// (the shot's own kept while the text does not parse), the lists split and trimmed
    /// with blanks dropped, the frame as the page holds it. The id is `shot`'s.
    func applied(to shot: Shot) -> Shot {
        var saved = shot
        saved.details   = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if let minutes = parsedMinutes { saved.durationMinutes = minutes }
        saved.equipment = SceneDraft.commaList(equipment)
        saved.props     = SceneDraft.commaList(props)
        saved.sfx       = SceneDraft.commaList(sfx)
        saved.frame     = frame
        return saved
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

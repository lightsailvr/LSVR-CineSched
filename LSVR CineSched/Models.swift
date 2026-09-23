// Models.swift
// Core data models for CineSched

import SwiftUI

// MARK: - Color blending

extension Color {
    /// Blends this color toward white by `amount` (0...1) — e.g. 0.1 mixes in
    /// 10% white, keeping 90% of the original. Computed from this color's
    /// actual RGB components rather than a guessed replacement value, so it
    /// tracks whatever the base color really is. Resolved through SwiftUI's own
    /// `Color.Resolved` (sRGB) rather than NSColor/UIColor so the same code
    /// runs on every platform; see ColorHelperTests. Resolving in a default
    /// `EnvironmentValues()` is fine because every caller passes a static hex or
    /// picker color, never a dynamic system color that depends on appearance.
    func lightened(by amount: Double) -> Color {
        let c = resolve(in: EnvironmentValues())
        let r = Double(c.red), g = Double(c.green), b = Double(c.blue)
        return Color(
            .sRGB,
            red:   r + (1 - r) * amount,
            green: g + (1 - g) * amount,
            blue:  b + (1 - b) * amount,
            opacity: Double(c.opacity)
        )
    }
}

// MARK: - DayNightType

enum DayNightType: String, nonisolated Codable, CaseIterable {
    case day       = "DAY"
    case night     = "NIGHT"
    case dawn      = "DAWN"
    case dusk      = "DUSK"
    case afternoon = "AFTERNOON"
    case custom    = "CUSTOM"

    var color: Color {
        color(isInterior: true)
    }

    func color(isInterior: Bool) -> Color {
        switch self {
        case .day:
            return isInterior ? Color(hex: "F3F4F6") : Color(hex: "FEF08A") // INT. DAY (Off-white) vs EXT. DAY (Yellow)
        case .night:
            return isInterior ? Color(hex: "86EFAC") : Color(hex: "93C5FD") // INT. NIGHT (Green) vs EXT. NIGHT (Blue)
        case .dawn:
            return Color(hex: "FDE68A") // DAWN / Amanecer (Gold)
        case .dusk:
            return Color(hex: "E9D5FF") // DUSK / Atardecer (Soft Lavender/Purple)
        case .afternoon:
            return isInterior ? Color(hex: "FFE4C4") : Color(hex: "FDBA74") // INT. TARDE vs EXT. TARDE (Warm Coral/Peach)
        case .custom:
            return Color(hex: "D1D5DB") // Custom / Notice (Gray)
        }
    }

    var displayName: String { rawValue }

    var shortCode: String {
        switch self {
        case .day:       return "D"
        case .night:     return "N"
        case .dawn:      return "DW"
        case .dusk:      return "DK"
        case .afternoon: return "AFT"
        case .custom:    return "C"
        }
    }

    var sortOrder: Int {
        switch self {
        case .day:       return 0
        case .dawn:      return 1
        case .afternoon: return 2
        case .dusk:      return 3
        case .night:     return 4
        case .custom:    return 5
        }
    }
}

// MARK: - Banner & Meal Types

enum BannerType: String, CaseIterable, nonisolated Codable {
    case companyMove = "Company Move"
    case mealBreak   = "Meal Break"
    case notice      = "Notice"
    case custom      = "Custom Banner"

    var localizedName: String {
        switch self {
        case .companyMove: return L("Company Move")
        case .mealBreak:   return L("Meal Break")
        case .notice:      return L("Notice")
        case .custom:      return L("Custom Banner")
        }
    }

    var defaultIcon: String {
        switch self {
        case .companyMove: return "truck.box.fill"
        case .mealBreak:   return "fork.knife"
        case .notice:      return "note.text"
        case .custom:      return "flag.fill"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        switch raw {
        case "Company Move", "Traslado", "Traslado de Equipo":
            self = .companyMove
        case "Meal Break", "Comida", "Pausa de Comida":
            self = .mealBreak
        case "Notice / Note", "Notice", "Note", "Aviso / Nota", "Aviso", "Nota":
            self = .notice
        case "Custom Banner", "Tira Personalizada", "Banner Personalizado":
            self = .custom
        default:
            self = BannerType(rawValue: raw) ?? .notice
        }
    }
}

enum MealKind: String, CaseIterable, nonisolated Codable {
    case generalCall  = "General Call"
    case readyToShoot = "Ready to Shoot"
    case lunch        = "Lunch"
    case snack        = "Snack"
    case dinner       = "Dinner"
    case wrap         = "Wrap"

    var icon: String {
        switch self {
        case .generalCall:  return "⏰"
        case .readyToShoot: return "🎬"
        case .lunch:        return "🍽️"
        case .snack:        return "☕"
        case .dinner:       return "🍕"
        case .wrap:         return "🎬"
        }
    }

    var defaultTitle: String {
        switch self {
        case .generalCall:  return L("GENERAL CALL")
        case .readyToShoot: return L("READY TO SHOOT")
        case .lunch:        return L("LUNCH")
        case .snack:        return L("SNACK")
        case .dinner:       return L("DINNER")
        case .wrap:         return L("WRAP")
        }
    }
}

// MARK: - Scene

struct Scene: Identifiable, nonisolated Codable, nonisolated Hashable {
    var id: UUID
    var title: String
    var sceneNumber: String
    var duration: Int
    var estimatedTime: Int
    var dayNightType: DayNightType
    var cast: [String]
    var summary: String
    // Breakdown tagging — set via SceneEditSheet's Breakdown section or the Breakdown
    // Browser, printed one page per scene via BreakdownExporter.
    var realLocation: String
    var locationAddress: String
    var extras: [String]
    var props: [String]
    var setDressing: [String]
    var wardrobe: [String]
    var makeupHair: [String]
    var vehicles: [String]
    var specialEquipment: [String]
    var stunts: [String]
    var sfx: [String]
    var vfx: [String]
    var breakdownNotes: String

    // Banner & Auto-Meal Strip Extensions
    var isBanner: Bool
    var bannerType: BannerType?
    var bannerTitle: String
    var bannerNote: String
    var bannerColorHex: String
    var isAutoMeal: Bool
    var mealKind: MealKind?
    var isCalendarEvent: Bool
    var customStartTime: String
    /// Marks a scene as shot/done. Independent of dayNightType — previously the only way
    /// to flag a scene as complete was hijacking the Custom type, which meant losing the
    /// scene's real Day/Night/Dawn/Dusk/Afternoon classification to do it.
    var isCompleted: Bool

    // Shot list (#37): the scene's shots in shooting order, lettered by position
    // (ShotEdits.swift), and the storyboard frame of a scene that has none — JPEG bytes,
    // base64 in the file (ADR 0007). Every change to `shots` goes through ShotEdits so the
    // estimate and frame rules run; a scene with shots never carries a frame of its own.
    var shots: [Shot]
    var frame: Data?

    init(
        title: String,
        sceneNumber: String = "",
        duration: Int = 0,
        estimatedTime: Int = 0,
        dayNightType: DayNightType = .day,
        cast: [String] = [],
        summary: String = "",
        realLocation: String = "",
        locationAddress: String = "",
        extras: [String] = [],
        props: [String] = [],
        setDressing: [String] = [],
        wardrobe: [String] = [],
        makeupHair: [String] = [],
        vehicles: [String] = [],
        specialEquipment: [String] = [],
        stunts: [String] = [],
        sfx: [String] = [],
        vfx: [String] = [],
        breakdownNotes: String = "",
        isBanner: Bool = false,
        bannerType: BannerType? = nil,
        bannerTitle: String = "",
        bannerNote: String = "",
        bannerColorHex: String = "",
        isAutoMeal: Bool = false,
        mealKind: MealKind? = nil,
        isCalendarEvent: Bool = false,
        customStartTime: String = "",
        isCompleted: Bool = false,
        shots: [Shot] = [],
        frame: Data? = nil
    ) {
        self.id               = UUID()
        self.title            = title
        self.sceneNumber      = sceneNumber
        self.duration         = duration
        self.estimatedTime    = estimatedTime
        self.dayNightType     = dayNightType
        self.cast             = cast
        self.summary          = summary
        self.realLocation     = realLocation
        self.locationAddress  = locationAddress
        self.extras           = extras
        self.props            = props
        self.setDressing      = setDressing
        self.wardrobe         = wardrobe
        self.makeupHair       = makeupHair
        self.vehicles         = vehicles
        self.specialEquipment = specialEquipment
        self.stunts           = stunts
        self.sfx              = sfx
        self.vfx              = vfx
        self.breakdownNotes   = breakdownNotes
        self.isBanner         = isBanner
        self.bannerType       = bannerType
        self.bannerTitle      = bannerTitle
        self.bannerNote       = bannerNote
        self.bannerColorHex   = bannerColorHex
        self.isAutoMeal       = isAutoMeal
        self.mealKind         = mealKind
        self.isCalendarEvent  = isCalendarEvent
        self.customStartTime  = customStartTime
        self.isCompleted      = isCompleted
        self.shots            = shots
        self.frame            = frame
    }

    static func createBanner(type: BannerType, title: String, note: String = "", estimatedTime: String = "0:30", colorHex: String = "8B5CF6") -> Scene {
        let estMin = parseMinutes(estimatedTime)
        return Scene(
            title: title,
            sceneNumber: "",
            duration: 0,
            estimatedTime: estMin,
            dayNightType: .custom,
            summary: note,
            isBanner: true,
            bannerType: type,
            bannerTitle: title,
            bannerNote: note,
            bannerColorHex: colorHex,
            isAutoMeal: false,
            mealKind: nil
        )
    }

    static func createAutoMeal(kind: MealKind, timeString: String) -> Scene {
        let cleanTime = timeString.trimmingCharacters(in: .whitespaces)
        let title = "\(kind.icon) \(kind.defaultTitle) \(cleanTime.isEmpty ? "" : "(\(cleanTime))")"
        let colorHex: String
        let estTime: Int
        let bType: BannerType

        switch kind {
        case .generalCall:
            colorHex = "1E3A8A" // Midnight Navy
            estTime  = 0
            bType    = .notice
        case .readyToShoot:
            colorHex = "064E3B" // Deep Forest Green
            estTime  = 0
            bType    = .notice
        case .lunch:
            colorHex = "18181B" // Black / Dark Charcoal
            estTime  = 60
            bType    = .mealBreak
        case .snack:
            colorHex = "18181B" // Black / Dark Charcoal
            estTime  = 15
            bType    = .mealBreak
        case .dinner:
            colorHex = "18181B" // Black / Dark Charcoal
            estTime  = 60
            bType    = .mealBreak
        case .wrap:
            colorHex = "991B1B" // Deep Crimson Red
            estTime  = 0
            bType    = .notice
        }

        return Scene(
            title: title,
            sceneNumber: "",
            duration: 0,
            estimatedTime: estTime,
            dayNightType: .custom,
            summary: cleanTime,
            isBanner: true,
            bannerType: bType,
            bannerTitle: title,
            bannerNote: cleanTime,
            bannerColorHex: colorHex,
            isAutoMeal: true,
            mealKind: kind,
            customStartTime: cleanTime
        )
    }

    static func createCalendarEvent(title: String, time: String, colorHex: String = "6366F1") -> Scene {
        let cleanTime = time.trimmingCharacters(in: .whitespaces)
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        return Scene(
            title: cleanTitle,
            sceneNumber: "",
            duration: 0,
            estimatedTime: 0,
            dayNightType: .custom,
            summary: cleanTime,
            isBanner: true,
            bannerType: .notice,
            bannerTitle: cleanTitle,
            bannerNote: cleanTime,
            bannerColorHex: colorHex,
            isAutoMeal: false,
            mealKind: nil,
            isCalendarEvent: true,
            customStartTime: cleanTime
        )
    }

    private static func parseMinutes(_ raw: String) -> Int {
        let parts = raw.components(separatedBy: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            return h * 60 + m
        } else if let mins = Int(raw) {
            return mins
        }
        return 30
    }

    enum CodingKeys: String, CodingKey {
        case id, title, sceneNumber, duration, estimatedTime, dayNightType, cast, summary
        case realLocation, locationAddress
        case extras, props, setDressing, wardrobe, makeupHair, vehicles, specialEquipment, stunts, sfx, vfx, breakdownNotes
        case isBanner, bannerType, bannerTitle, bannerNote, bannerColorHex, isAutoMeal, mealKind, isCalendarEvent, customStartTime
        case isCompleted
        case shots, frame
    }

    nonisolated init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,         forKey: .id)
        title         = try c.decode(String.self,       forKey: .title)
        sceneNumber   = try c.decodeIfPresent(String.self, forKey: .sceneNumber) ?? ""
        duration      = try c.decode(Int.self,          forKey: .duration)
        estimatedTime = try c.decode(Int.self,          forKey: .estimatedTime)
        dayNightType  = try c.decode(DayNightType.self, forKey: .dayNightType)
        summary       = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        realLocation  = try c.decodeIfPresent(String.self, forKey: .realLocation) ?? ""
        locationAddress = try c.decodeIfPresent(String.self, forKey: .locationAddress) ?? ""
        if let array = try? c.decode([String].self, forKey: .cast) {
            cast = array
        } else if let legacy = try? c.decode(String.self, forKey: .cast) {
            cast = legacy.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            cast = []
        }
        extras           = try c.decodeIfPresent([String].self, forKey: .extras) ?? []
        props            = try c.decodeIfPresent([String].self, forKey: .props) ?? []
        setDressing      = try c.decodeIfPresent([String].self, forKey: .setDressing) ?? []
        wardrobe         = try c.decodeIfPresent([String].self, forKey: .wardrobe) ?? []
        makeupHair       = try c.decodeIfPresent([String].self, forKey: .makeupHair) ?? []
        vehicles         = try c.decodeIfPresent([String].self, forKey: .vehicles) ?? []
        specialEquipment = try c.decodeIfPresent([String].self, forKey: .specialEquipment) ?? []
        stunts           = try c.decodeIfPresent([String].self, forKey: .stunts) ?? []
        sfx              = try c.decodeIfPresent([String].self, forKey: .sfx) ?? []
        vfx              = try c.decodeIfPresent([String].self, forKey: .vfx) ?? []
        breakdownNotes   = try c.decodeIfPresent(String.self, forKey: .breakdownNotes) ?? ""
        isBanner         = try c.decodeIfPresent(Bool.self, forKey: .isBanner) ?? false
        bannerType       = (try? c.decodeIfPresent(BannerType.self, forKey: .bannerType)) ?? nil
        bannerTitle      = try c.decodeIfPresent(String.self, forKey: .bannerTitle) ?? ""
        bannerNote       = try c.decodeIfPresent(String.self, forKey: .bannerNote) ?? ""
        bannerColorHex   = try c.decodeIfPresent(String.self, forKey: .bannerColorHex) ?? ""
        isAutoMeal       = try c.decodeIfPresent(Bool.self, forKey: .isAutoMeal) ?? false
        mealKind         = (try? c.decodeIfPresent(MealKind.self, forKey: .mealKind)) ?? nil
        isCalendarEvent  = try c.decodeIfPresent(Bool.self, forKey: .isCalendarEvent) ?? false
        customStartTime  = try c.decodeIfPresent(String.self, forKey: .customStartTime) ?? ""
        isCompleted      = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        shots            = try c.decodeIfPresent([Shot].self, forKey: .shots) ?? []
        frame            = try c.decodeIfPresent(Data.self, forKey: .frame)
    }

    /// Written by hand only so a scene with no shots and no frame writes neither key, and a
    /// project saved from before shot lists keeps the same content on its next save. Every
    /// other field is written exactly as the synthesized encoder did (optionals only when
    /// set), so older builds read the file as before and ignore the two new keys.
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                        forKey: .id)
        try c.encode(title,                     forKey: .title)
        try c.encode(sceneNumber,               forKey: .sceneNumber)
        try c.encode(duration,                  forKey: .duration)
        try c.encode(estimatedTime,             forKey: .estimatedTime)
        try c.encode(dayNightType,              forKey: .dayNightType)
        try c.encode(cast,                      forKey: .cast)
        try c.encode(summary,                   forKey: .summary)
        try c.encode(realLocation,              forKey: .realLocation)
        try c.encode(locationAddress,           forKey: .locationAddress)
        try c.encode(extras,                    forKey: .extras)
        try c.encode(props,                     forKey: .props)
        try c.encode(setDressing,               forKey: .setDressing)
        try c.encode(wardrobe,                  forKey: .wardrobe)
        try c.encode(makeupHair,                forKey: .makeupHair)
        try c.encode(vehicles,                  forKey: .vehicles)
        try c.encode(specialEquipment,          forKey: .specialEquipment)
        try c.encode(stunts,                    forKey: .stunts)
        try c.encode(sfx,                       forKey: .sfx)
        try c.encode(vfx,                       forKey: .vfx)
        try c.encode(breakdownNotes,            forKey: .breakdownNotes)
        try c.encode(isBanner,                  forKey: .isBanner)
        try c.encodeIfPresent(bannerType,       forKey: .bannerType)
        try c.encode(bannerTitle,               forKey: .bannerTitle)
        try c.encode(bannerNote,                forKey: .bannerNote)
        try c.encode(bannerColorHex,            forKey: .bannerColorHex)
        try c.encode(isAutoMeal,                forKey: .isAutoMeal)
        try c.encodeIfPresent(mealKind,         forKey: .mealKind)
        try c.encode(isCalendarEvent,           forKey: .isCalendarEvent)
        try c.encode(customStartTime,           forKey: .customStartTime)
        try c.encode(isCompleted,               forKey: .isCompleted)
        if !shots.isEmpty { try c.encode(shots, forKey: .shots) }
        try c.encodeIfPresent(frame,            forKey: .frame)
    }

    /// "12A. INT. HOUSE - DAY" for display — combines the dedicated number field
    /// with the title. Falls back to the bare title when there's no number, which
    /// also covers scenes saved before this field existed (their number, if any,
    /// is already part of `title` from that era).
    var displayTitle: String {
        if isBanner { return title }
        let trimmedNum = sceneNumber.trimmingCharacters(in: .whitespaces)
        return trimmedNum.isEmpty ? title : "\(trimmedNum). \(title)"
    }

    /// Auto-parses leading scene number from title if `sceneNumber` is currently empty.
    /// E.g., title "2. EXT. PLAYA. DIA" -> sceneNumber = "2", cleanTitle = "EXT. PLAYA. DIA"
    mutating func autoExtractSceneNumberIfNeeded() {
        guard sceneNumber.trimmingCharacters(in: .whitespaces).isEmpty, !isBanner else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let pattern = #"^#?(\d+[A-Za-z]?)\.?\s*[-–—.]?\s*(.*)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let numRange = Range(match.range(at: 1), in: trimmed) {
            let extractedNum = String(trimmed[numRange])
            self.sceneNumber = extractedNum
            if let restRange = Range(match.range(at: 2), in: trimmed) {
                let rest = String(trimmed[restRange]).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty {
                    self.title = rest
                }
            }
        }
    }

    /// Extracted scene number: uses dedicated sceneNumber or parses leading digits from title (e.g. "2. EXT..." -> "2")
    var extractedSceneNumber: String {
        let trimmed = sceneNumber.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let titleTrimmed = title.trimmingCharacters(in: .whitespaces)
        if let match = titleTrimmed.range(of: "^#?(\\d+[A-Za-z]?)", options: .regularExpression) {
            return String(titleTrimmed[match]).replacingOccurrences(of: "#", with: "")
        }
        return "1"
    }

    /// Extracted decorado/set name: removes leading scene number, INT/EXT, and trailing time of day
    var decoradoOnly: String {
        if !realLocation.trimmingCharacters(in: .whitespaces).isEmpty {
            return realLocation.trimmingCharacters(in: .whitespaces).uppercased()
        }
        var s = title.trimmingCharacters(in: .whitespaces)
        // Strip leading number like "1. ", "12A - ", "#2. "
        s = s.replacingOccurrences(of: "^#?\\d+[A-Za-z]?\\.?\\s*[-–—.]?\\s*", with: "", options: .regularExpression)
        // Strip INT./EXT., INT., EXT., I/E., I/E
        s = s.replacingOccurrences(of: "^(INT\\.?/EXT\\.?|INT\\.?|EXT\\.?|I/E\\.?|INT\\s+/\\s+EXT)\\s*[-–—.]?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        // Strip trailing time of day: " - DAY", ". DIA", " - NIGHT", " - NOCHE", etc.
        s = s.replacingOccurrences(of: "\\s*[-–—.]+\\s*(DAY|NIGHT|DAWN|DUSK|AFTERNOON|DIA|NOCHE|TARDE|ATARDECER|AMANECER|CONTINUOUS|SAME)\\.?\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-–—"))
        return s.isEmpty ? title.uppercased() : s.uppercased()
    }

    // MARK: - Interior / Exterior + Movie Magic strip color

    enum IntExt { case interior, exterior, unknown }

    /// Interior/exterior, sniffed from title even when preceded by scene number
    var intExt: IntExt {
        var upper = title.trimmingCharacters(in: .whitespaces).uppercased()
        upper = upper.replacingOccurrences(of: "^#?\\d+[A-Za-z]?\\.?\\s*", with: "", options: .regularExpression)
        if upper.hasPrefix("EXT.") || upper.hasPrefix("EXT ") || upper.hasPrefix("EXT") {
            return .exterior
        }
        return .interior
    }

    var intExtString: String {
        var upper = title.trimmingCharacters(in: .whitespaces).uppercased()
        upper = upper.replacingOccurrences(of: "^#?\\d+[A-Za-z]?\\.?\\s*", with: "", options: .regularExpression)
        if upper.hasPrefix("INT/EXT") || upper.hasPrefix("INT./EXT") || upper.hasPrefix("I/E") || upper.hasPrefix("INT / EXT") {
            return "INT/EXT"
        }
        if upper.hasPrefix("EXT.") || upper.hasPrefix("EXT ") || upper.hasPrefix("EXT") {
            return "EXT"
        }
        return "INT"
    }

    /// Movie Magic Scheduling's own strip color code:
    /// white = day interior, yellow = day exterior, green = night interior,
    /// blue = night exterior, rose/gold for dawn/afternoon/dusk.
    var isNoticeStrip: Bool {
        let hasNoNum = sceneNumber.trimmingCharacters(in: .whitespaces).isEmpty
        let titleHasNoHeading = !title.uppercased().contains("INT") && !title.uppercased().contains("EXT") && extractedSceneNumber == "1" && sceneNumber.isEmpty && duration == 0
        return hasNoNum && titleHasNoHeading && dayNightType == .custom
    }

    /// The strip's color under `palette`, the project's (`ProjectData.resolvedPalette`).
    /// The only place a strip color is resolved; views read the palette from the
    /// `scenePalette` environment and exporters take it with the project (#11).
    func stripColor(in palette: ScenePalette) -> Color {
        if isCompleted {
            return Color(hex: "9CA3AF")
        }
        if isNoticeStrip {
            return Color(hex: "374151")
        }
        return palette.color(for: colorSlot)
    }

    /// Which palette slot this scene's INT/EXT and time of day select.
    var colorSlot: SceneColorSlot {
        if dayNightType == .custom {
            return .custom
        }
        switch (intExt, dayNightType) {
        case (.interior, .day):       return .intDay
        case (.exterior, .day):       return .extDay
        case (.interior, .night):     return .intNight
        case (.exterior, .night):     return .extNight
        case (.interior, .dawn):      return .intDawn
        case (.exterior, .dawn):      return .extDawn
        case (.interior, .dusk):      return .intDusk
        case (.exterior, .dusk):      return .extDusk
        case (.interior, .afternoon): return .intAfternoon
        case (.exterior, .afternoon): return .extAfternoon
        case (.unknown, .day):        return .intDay
        case (.unknown, .night):      return .extNight
        case (.unknown, .dawn):       return .intDawn
        case (.unknown, .dusk):       return .intDusk
        case (.unknown, .afternoon):  return .extAfternoon
        case (_, .custom):            return .custom
        }
    }

    var stripTextColor: Color {
        if isCompleted { return Color(hex: "4B5563") }
        return isNoticeStrip ? .white : .black
    }

    /// Splits a raw scene number like "12A" into its numeric and letter parts.
    static func parseSceneNumber(_ raw: String) -> (number: Int, letter: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits  = trimmed.prefix { $0.isNumber }
        let letter  = trimmed.dropFirst(digits.count).prefix { $0.isLetter }
        guard let number = Int(digits) else { return nil }
        return (number, String(letter).uppercased())
    }
}

// MARK: - Shot

/// One shot of a scene's shot list (#37): what it is, how long it takes including its
/// relight, what it needs, and one optional storyboard frame (JPEG bytes, ADR 0007). A
/// shot has no stored letter: its letter is its position in `Scene.shots`
/// (`Shot.letter(forIndex:)`, `Scene.shotNumber(at:)`). Edited only through ShotEdits.swift.
struct Shot: Identifiable, nonisolated Codable, nonisolated Hashable {
    /// What a new shot lasts: the cascade's 15 minutes for an unestimated strip, so a shot
    /// typed as one line of description counts as the scene did before it had any.
    nonisolated static let defaultDurationMinutes = 15

    var id:              UUID
    /// The free-text description ("Dolly in towards Astrid"). Not `description`, which
    /// would read as `CustomStringConvertible` in the debugger and in string interpolation.
    var details:         String
    var durationMinutes: Int
    /// Feeds the scene's Special Equipment in the breakdown union.
    var equipment:       [String]
    var props:           [String]
    var sfx:             [String]
    var frame:           Data?

    nonisolated init(
        id:              UUID     = UUID(),
        details:         String   = "",
        durationMinutes: Int      = Shot.defaultDurationMinutes,
        equipment:       [String] = [],
        props:           [String] = [],
        sfx:             [String] = [],
        frame:           Data?    = nil
    ) {
        self.id              = id
        self.details         = details
        self.durationMinutes = durationMinutes
        self.equipment       = equipment
        self.props           = props
        self.sfx             = sfx
        self.frame           = frame
    }

    enum CodingKeys: String, CodingKey {
        case id, details, durationMinutes, equipment, props, sfx, frame
    }

    /// Every field is optional in the file, so a hand-edited shot with only a description
    /// opens (with a fresh id and the default duration).
    nonisolated init(from decoder: Decoder) throws {
        let c           = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self,     forKey: .id) ?? UUID()
        details         = try c.decodeIfPresent(String.self,   forKey: .details) ?? ""
        durationMinutes = try c.decodeIfPresent(Int.self,      forKey: .durationMinutes) ?? Shot.defaultDurationMinutes
        equipment       = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        props           = try c.decodeIfPresent([String].self, forKey: .props) ?? []
        sfx             = try c.decodeIfPresent([String].self, forKey: .sfx) ?? []
        frame           = try c.decodeIfPresent(Data.self,     forKey: .frame)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(details,         forKey: .details)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(equipment,       forKey: .equipment)
        try c.encode(props,           forKey: .props)
        try c.encode(sfx,             forKey: .sfx)
        try c.encodeIfPresent(frame,  forKey: .frame)
    }
}

// MARK: - Location

struct Location: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var name:    String
    var address: String

    init(name: String = "", address: String = "") {
        self.id      = UUID()
        self.name    = name
        self.address = address
    }
}

// MARK: - CastCallEntry

struct CastCallEntry: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var characterName: String
    var actorName: String
    var sceneNumbers: String     // e.g. "1, 4, 7"
    var ecdt: String             // "E", "ET", "W", etc.
    var pickupTime: String       // e.g. "07:00 AM"
    var hmuWardrobeTime: String  // e.g. "07:30 AM"
    var onSetTime: String        // e.g. "08:00 AM"
    var wrapTime: String         // e.g. "09:30 PM"
    var locationIndex: String    // e.g. "1", "2"

    init(
        id: UUID = UUID(),
        characterName: String = "",
        actorName: String = "",
        sceneNumbers: String = "",
        ecdt: String = "E",
        pickupTime: String = "",
        hmuWardrobeTime: String = "",
        onSetTime: String = "",
        wrapTime: String = "",
        locationIndex: String = "1"
    ) {
        self.id = id
        self.characterName = characterName
        self.actorName = actorName
        self.sceneNumbers = sceneNumbers
        self.ecdt = ecdt
        self.pickupTime = pickupTime
        self.hmuWardrobeTime = hmuWardrobeTime
        self.onSetTime = onSetTime
        self.wrapTime = wrapTime
        self.locationIndex = locationIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, characterName, actorName, sceneNumbers, ecdt, pickupTime, hmuWardrobeTime, onSetTime, wrapTime, locationIndex
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        characterName   = try c.decodeIfPresent(String.self, forKey: .characterName) ?? ""
        actorName       = try c.decodeIfPresent(String.self, forKey: .actorName) ?? ""
        sceneNumbers    = try c.decodeIfPresent(String.self, forKey: .sceneNumbers) ?? ""
        ecdt            = try c.decodeIfPresent(String.self, forKey: .ecdt) ?? "E"
        pickupTime      = try c.decodeIfPresent(String.self, forKey: .pickupTime) ?? ""
        hmuWardrobeTime = try c.decodeIfPresent(String.self, forKey: .hmuWardrobeTime) ?? ""
        onSetTime       = try c.decodeIfPresent(String.self, forKey: .onSetTime) ?? ""
        wrapTime        = try c.decodeIfPresent(String.self, forKey: .wrapTime) ?? ""
        locationIndex   = try c.decodeIfPresent(String.self, forKey: .locationIndex) ?? "1"
    }
}

// MARK: - CrewCallEntry

struct CrewCallEntry: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var role: String
    var name: String
    var callTime: String
    var phone: String

    init(
        id: UUID = UUID(),
        role: String = "",
        name: String = "",
        callTime: String = "",
        phone: String = ""
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.callTime = callTime
        self.phone = phone
    }
}

// MARK: - CallSheetData

struct CallSheetData: nonisolated Codable, Equatable {
    var generalCallTime: String
    var workDaySchedule: String       // e.g. "Schedule: 07:30 AM to 09:30 PM"
    var readyToShootTime: String      // e.g. "08:00 AM"
    var lunchTime: String             // e.g. "01:30 PM"
    var snackTime: String             // Merienda, e.g. "05:00 PM"
    var dinnerTime: String            // Cena, e.g. "08:30 PM"
    var wrapTime: String              // Fin de Rodaje / Wrap, e.g. "09:30 PM"
    var quoteOfTheDay: String         // "Quote of the day"
    var prodManagerContact: String    // Producer contact override if needed
    var adContact: String             // AD contact
    var weatherTemp: String
    var weatherCondition: String
    var weatherPrecipWind: String
    var sunTimes: String
    var basecampLocation: String      // Basecamp location / address
    var nearestHospital: String
    var castCallEntries: [CastCallEntry]
    var crewCallEntries: [CrewCallEntry]
    var productionNotes: [String]
    var locations:       [Location]
    var castOverride:    [String]?
    var crewOverride:    [String]?
    var crewIDOverride:  [UUID]?
    var crewOneOffs:     [String]?
    var notes:           String

    init(
        generalCallTime: String     = "",
        workDaySchedule: String     = "",
        readyToShootTime: String    = "",
        lunchTime: String           = "",
        snackTime: String           = "",
        dinnerTime: String          = "",
        wrapTime: String            = "",
        quoteOfTheDay: String       = "",
        prodManagerContact: String  = "",
        adContact: String           = "",
        weatherTemp: String         = "",
        weatherCondition: String    = "",
        weatherPrecipWind: String   = "",
        sunTimes: String            = "",
        basecampLocation: String    = "",
        nearestHospital: String     = "",
        castCallEntries: [CastCallEntry] = [],
        crewCallEntries: [CrewCallEntry] = [],
        productionNotes: [String]   = [],
        locations:       [Location] = [],
        castOverride:    [String]?  = nil,
        crewOverride:    [String]?  = nil,
        crewIDOverride:  [UUID]?    = nil,
        crewOneOffs:     [String]?  = nil,
        notes:           String     = ""
    ) {
        self.generalCallTime    = generalCallTime
        self.workDaySchedule    = workDaySchedule
        self.readyToShootTime   = readyToShootTime
        self.lunchTime          = lunchTime
        self.snackTime          = snackTime
        self.dinnerTime         = dinnerTime
        self.wrapTime           = wrapTime
        self.quoteOfTheDay      = quoteOfTheDay
        self.prodManagerContact = prodManagerContact
        self.adContact          = adContact
        self.weatherTemp        = weatherTemp
        self.weatherCondition   = weatherCondition
        self.weatherPrecipWind  = weatherPrecipWind
        self.sunTimes           = sunTimes
        self.basecampLocation   = basecampLocation
        self.nearestHospital    = nearestHospital
        self.castCallEntries    = castCallEntries
        self.crewCallEntries    = crewCallEntries
        self.productionNotes    = productionNotes
        self.locations          = locations
        self.castOverride       = castOverride
        self.crewOverride       = crewOverride
        self.crewIDOverride     = crewIDOverride
        self.crewOneOffs        = crewOneOffs
        self.notes              = notes
    }

    enum CodingKeys: String, CodingKey {
        case generalCallTime, workDaySchedule, readyToShootTime, lunchTime, snackTime, dinnerTime, wrapTime
        case quoteOfTheDay, prodManagerContact, adContact, weatherTemp, weatherCondition, weatherPrecipWind, sunTimes, basecampLocation, nearestHospital
        case castCallEntries, crewCallEntries, productionNotes, locations, castOverride, crewOverride, crewIDOverride, crewOneOffs, notes
    }

    nonisolated init(from decoder: Decoder) throws {
        let c              = try decoder.container(keyedBy: CodingKeys.self)
        generalCallTime    = try c.decodeIfPresent(String.self, forKey: .generalCallTime) ?? ""
        workDaySchedule    = try c.decodeIfPresent(String.self, forKey: .workDaySchedule) ?? ""
        readyToShootTime   = try c.decodeIfPresent(String.self, forKey: .readyToShootTime) ?? ""
        lunchTime          = try c.decodeIfPresent(String.self, forKey: .lunchTime) ?? ""
        snackTime          = try c.decodeIfPresent(String.self, forKey: .snackTime) ?? ""
        dinnerTime         = try c.decodeIfPresent(String.self, forKey: .dinnerTime) ?? ""
        wrapTime           = try c.decodeIfPresent(String.self, forKey: .wrapTime) ?? ""
        quoteOfTheDay      = try c.decodeIfPresent(String.self, forKey: .quoteOfTheDay) ?? ""
        prodManagerContact = try c.decodeIfPresent(String.self, forKey: .prodManagerContact) ?? ""
        adContact          = try c.decodeIfPresent(String.self, forKey: .adContact) ?? ""
        weatherTemp        = try c.decodeIfPresent(String.self, forKey: .weatherTemp) ?? ""
        weatherCondition   = try c.decodeIfPresent(String.self, forKey: .weatherCondition) ?? ""
        weatherPrecipWind  = try c.decodeIfPresent(String.self, forKey: .weatherPrecipWind) ?? ""
        sunTimes           = try c.decodeIfPresent(String.self, forKey: .sunTimes) ?? ""
        basecampLocation   = try c.decodeIfPresent(String.self, forKey: .basecampLocation) ?? ""
        nearestHospital    = try c.decodeIfPresent(String.self, forKey: .nearestHospital) ?? ""
        castCallEntries    = try c.decodeIfPresent([CastCallEntry].self, forKey: .castCallEntries) ?? []
        crewCallEntries    = try c.decodeIfPresent([CrewCallEntry].self, forKey: .crewCallEntries) ?? []
        productionNotes    = try c.decodeIfPresent([String].self, forKey: .productionNotes) ?? []
        locations          = try c.decodeIfPresent([Location].self, forKey: .locations) ?? []
        castOverride       = try c.decodeIfPresent([String].self, forKey: .castOverride)
        crewOverride       = try c.decodeIfPresent([String].self, forKey: .crewOverride)
        crewIDOverride     = try c.decodeIfPresent([UUID].self, forKey: .crewIDOverride)
        crewOneOffs        = try c.decodeIfPresent([String].self, forKey: .crewOneOffs)
        notes              = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// Resolves the raw character names (auto-pulled from scenes, or the manually-edited
    /// override) to "Actor — Character" using the *current* cast list.
    func resolvedCast(from scenes: [Scene], productionInfo: ProductionInfo? = nil) -> [String] {
        if !castCallEntries.isEmpty {
            return castCallEntries.map { entry in
                entry.actorName.isEmpty ? entry.characterName : "\(entry.actorName) — \(entry.characterName)"
            }
        }
        let characters = castOverride ?? Array(Set(scenes.flatMap { $0.cast })).sorted()
        guard let production = productionInfo, !production.castList.isEmpty else {
            return characters
        }
        return characters.map { character in
            if let match = production.castList.first(where: {
                $0.characterName.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(character.trimmingCharacters(in: .whitespaces)) == .orderedSame
            }) {
                return match.displayString
            }
            return character
        }
    }

    /// Resolves selected crew to "Name — Role" using the *current* roster for anyone selected
    /// by ID.
    func resolvedCrew(productionInfo: ProductionInfo) -> [String] {
        if !crewCallEntries.isEmpty {
            return crewCallEntries.map { "\($0.name) — \($0.role)" }
        }
        if crewIDOverride != nil || crewOneOffs != nil {
            let roster = productionInfo.crew
            let selected = (crewIDOverride ?? []).compactMap { id in
                roster.first(where: { $0.id == id })?.displayString
            }
            return selected + (crewOneOffs ?? [])
        }
        if let legacy = crewOverride { return legacy }
        return productionInfo.crew
            .filter { $0.isDailyDefault }
            .map    { $0.displayString }
    }
}

// MARK: - CrewMember

struct CrewMember: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var name:           String
    var role:           String
    var phone:          String
    var isDailyDefault: Bool

    init(name: String = "", role: String = "", phone: String = "", isDailyDefault: Bool = false) {
        self.id             = UUID()
        self.name           = name
        self.role           = role
        self.phone          = phone
        self.isDailyDefault = isDailyDefault
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role, phone, isDailyDefault
    }

    nonisolated init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        role           = try c.decode(String.self, forKey: .role)
        phone          = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isDailyDefault = try c.decodeIfPresent(Bool.self, forKey: .isDailyDefault) ?? false
    }

    var displayString: String {
        role.isEmpty ? name : "\(name) — \(role)"
    }
}

// MARK: - DateRange (actor unavailability)

struct DateRange: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var start: Date
    var end: Date

    init(start: Date, end: Date) {
        self.id    = UUID()
        self.start = start
        self.end   = max(start, end)
    }

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        return d >= cal.startOfDay(for: start) && d <= cal.startOfDay(for: end)
    }
}

// MARK: - CastMember

struct CastMember: Identifiable, nonisolated Codable, Hashable {
    let id: UUID
    var actorName:     String
    var characterName: String
    var unavailableRanges: [DateRange]

    init(actorName: String = "", characterName: String = "", unavailableRanges: [DateRange] = []) {
        self.id                = UUID()
        self.actorName         = actorName
        self.characterName     = characterName
        self.unavailableRanges = unavailableRanges
    }

    enum CodingKeys: String, CodingKey {
        case id, actorName, characterName, unavailableRanges
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        actorName         = try c.decode(String.self, forKey: .actorName)
        characterName     = try c.decode(String.self, forKey: .characterName)
        unavailableRanges = try c.decodeIfPresent([DateRange].self, forKey: .unavailableRanges) ?? []
    }

    var displayString: String {
        actorName.isEmpty ? characterName : "\(actorName) — \(characterName)"
    }
}

// MARK: - Scene script order

extension Scene {
    /// A numeric-aware sort key. If `sceneNumber` is populated, uses `parseSceneNumber`
    /// so scenes sort in true script order — 12, 12A, 12B, 13.
    /// Falls back to parsing a leading scene number in the title for legacy scenes.
    var scriptOrderKey: (Int, String) {
        if let parsed = Scene.parseSceneNumber(sceneNumber) {
            return (parsed.number, parsed.letter)
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(\d+)([A-Za-z]*)\."#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let numRange = Range(match.range(at: 1), in: trimmed) {
            let num = Int(trimmed[numRange]) ?? Int.max
            let letterRange = Range(match.range(at: 2), in: trimmed)
            let letter = letterRange.map { String(trimmed[$0]) } ?? ""
            return (num, letter)
        }
        return (Int.max, trimmed)
    }
}

// MARK: - Scene tooltip

extension Scene {
    var tooltipText: String {
        var lines: [String] = [displayTitle]
        if !cast.isEmpty {
            lines.append("Cast: " + cast.joined(separator: ", "))
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            lines.append(trimmedSummary)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ProductionInfo

struct ProductionInfo: nonisolated Codable, Equatable {
    var companyName:   String
    var directorName:  String
    var directorPhone: String
    var producerName:  String
    var producerPhone: String
    var adName:        String
    var adPhone:       String
    var contactNumber: String
    var defaultLunchTime: String
    var crew:          [CrewMember]
    var castList:      [CastMember]
    var locationRoster: [Location]
    var scheduleLock: ScheduleLock?

    init(
        companyName:   String = "",
        directorName:  String = "",
        directorPhone: String = "",
        producerName:  String = "",
        producerPhone: String = "",
        adName:        String = "",
        adPhone:       String = "",
        contactNumber: String = "",
        defaultLunchTime: String = "01:30 PM",
        crew:          [CrewMember] = [],
        castList:      [CastMember] = [],
        locationRoster: [Location] = [],
        scheduleLock:  ScheduleLock? = nil
    ) {
        self.companyName      = companyName
        self.directorName     = directorName
        self.directorPhone    = directorPhone
        self.producerName     = producerName
        self.producerPhone    = producerPhone
        self.adName           = adName
        self.adPhone          = adPhone
        self.contactNumber    = contactNumber
        self.defaultLunchTime = defaultLunchTime
        self.crew             = crew
        self.castList         = castList
        self.locationRoster   = locationRoster
        self.scheduleLock     = scheduleLock
    }

    enum CodingKeys: String, CodingKey {
        case companyName, directorName, directorPhone, producerName, producerPhone, adName, adPhone, contactNumber, defaultLunchTime, crew, castList, locationRoster, scheduleLock
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        companyName      = try c.decode(String.self, forKey: .companyName)
        directorName     = try c.decode(String.self, forKey: .directorName)
        directorPhone    = try c.decodeIfPresent(String.self, forKey: .directorPhone) ?? ""
        producerName     = try c.decodeIfPresent(String.self, forKey: .producerName) ?? ""
        producerPhone    = try c.decodeIfPresent(String.self, forKey: .producerPhone) ?? ""
        adName           = try c.decodeIfPresent(String.self, forKey: .adName) ?? ""
        adPhone          = try c.decodeIfPresent(String.self, forKey: .adPhone) ?? ""
        contactNumber    = try c.decodeIfPresent(String.self, forKey: .contactNumber) ?? ""
        defaultLunchTime = try c.decodeIfPresent(String.self, forKey: .defaultLunchTime) ?? "01:30 PM"
        crew             = try c.decode([CrewMember].self, forKey: .crew)
        castList         = try c.decode([CastMember].self, forKey: .castList)
        locationRoster   = try c.decodeIfPresent([Location].self, forKey: .locationRoster) ?? []
        scheduleLock     = try c.decodeIfPresent(ScheduleLock.self, forKey: .scheduleLock)
    }
}

// MARK: - ScheduleLock

struct ScheduleLock: nonisolated Codable, Equatable {
    var lockedAt: Date
    var workingDays: [String: [Date]]
}

// MARK: - Day Type

/// What a calendar date is *for*. Only `.shoot` days can earn a production day number;
/// every other case is a whole-day note (travel, scout, weather hold, …) that the calendar
/// tints and labels and that the Stripboard, month PDF, and DOOD treat as a non-shoot day.
/// Scenes may still be dropped on a non-shoot day, but they are flagged the way scenes on
/// the old blackout days were.
///
/// This replaces the old `ShootDay.isBlackout` boolean: `.unavailable` is that flag, and
/// project files keep writing `isBlackout` so older builds still see unavailable days.
enum DayType: String, CaseIterable, nonisolated Codable {
    case shoot
    case travel
    case scout
    case prep
    case rehearsal
    case weatherHold
    case holiday
    case dayOff
    case unavailable

    /// True only for `.shoot`. Non-shoot days never get a "Day N" number.
    var isShootable: Bool { self == .shoot }

    var localizedName: String {
        switch self {
        case .shoot:       return L("Shoot Day")
        case .travel:      return L("Travel Day")
        case .scout:       return L("Scout Day")
        case .prep:        return L("Prep Day")
        case .rehearsal:   return L("Rehearsal Day")
        case .weatherHold: return L("Weather Hold")
        case .holiday:     return L("Holiday")
        case .dayOff:      return L("Day Off")
        case .unavailable: return L("Unavailable")
        }
    }

    var icon: String {
        switch self {
        case .shoot:       return "film"
        case .travel:      return "airplane"
        case .scout:       return "binoculars.fill"
        case .prep:        return "hammer.fill"
        case .rehearsal:   return "person.2.fill"
        case .weatherHold: return "cloud.rain.fill"
        case .holiday:     return "gift.fill"
        case .dayOff:      return "moon.zzz.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    /// Tint used by the calendar cell, the Stripboard badge, and the month PDF. Empty for
    /// `.shoot`, whose look comes from the theme's shoot-range highlight instead.
    var colorHex: String {
        switch self {
        case .shoot:       return ""
        case .travel:      return "D97706"
        case .scout:       return "14B8A6"
        case .prep:        return "10B981"
        case .rehearsal:   return "8B5CF6"
        case .weatherHold: return "0EA5E9"
        case .holiday:     return "EC4899"
        case .dayOff:      return "64748B"
        case .unavailable: return "EF4444"
        }
    }

    /// Unknown raw values (from a newer build) fall back to `.shoot` rather than failing
    /// the whole project load. Mirrors `BannerType`'s lenient decoder.
    nonisolated init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = DayType(rawValue: raw) ?? .shoot
    }
}

// MARK: - ShootDay

struct ShootDay: Identifiable, nonisolated Codable, Equatable {
    let id:        UUID
    var date:      Date
    var scenes:    [Scene]       = []
    var callSheet: CallSheetData = CallSheetData()
    var dayType:   DayType       = .shoot
    /// Free text shown under the day-type band, e.g. "Fly LAX → ABQ, crew van 6 AM".
    var dayNote:   String        = ""

    /// Legacy name for `dayType == .unavailable`. Read-only; set `dayType` instead.
    /// Nonisolated because the (nonisolated) encoder still writes it for older builds.
    nonisolated var isBlackout: Bool { dayType == .unavailable }

    init(date: Date, scenes: [Scene] = [], callSheet: CallSheetData = CallSheetData(),
         dayType: DayType = .shoot, dayNote: String = "", isBlackout: Bool = false) {
        self.id        = UUID()
        self.date      = date
        self.scenes    = scenes
        self.callSheet = callSheet
        self.dayType   = isBlackout ? .unavailable : dayType
        self.dayNote   = dayNote
    }

    enum CodingKeys: String, CodingKey {
        case id, date, scenes, callSheet, isBlackout, dayType, dayNote
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        date       = try c.decode(Date.self, forKey: .date)
        scenes     = try c.decode([Scene].self, forKey: .scenes)
        callSheet  = try c.decode(CallSheetData.self, forKey: .callSheet)
        dayNote    = try c.decodeIfPresent(String.self, forKey: .dayNote) ?? ""
        // Files written before day types only have `isBlackout`; files written after carry
        // both, and `dayType` wins so an old build can't silently downgrade a travel day.
        let legacyBlackout = try c.decodeIfPresent(Bool.self, forKey: .isBlackout) ?? false
        if let typed = try c.decodeIfPresent(DayType.self, forKey: .dayType) {
            dayType = typed
        } else {
            dayType = legacyBlackout ? .unavailable : .shoot
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(date,      forKey: .date)
        try c.encode(scenes,    forKey: .scenes)
        try c.encode(callSheet, forKey: .callSheet)
        try c.encode(dayType,   forKey: .dayType)
        try c.encode(dayNote,   forKey: .dayNote)
        // Kept for builds that predate `dayType`; they read this and ignore the rest.
        try c.encode(isBlackout, forKey: .isBlackout)
    }

    var totalDuration:      Int { scenes.reduce(0) { $0 + $1.duration } }
    var totalEstimatedTime: Int { scenes.reduce(0) { $0 + $1.estimatedTime } }

    var dayScenes:       [Scene] { scenes.filter { $0.dayNightType == .day } }
    var nightScenes:     [Scene] { scenes.filter { $0.dayNightType == .night } }
    var dawnScenes:      [Scene] { scenes.filter { $0.dayNightType == .dawn } }
    var duskScenes:      [Scene] { scenes.filter { $0.dayNightType == .dusk } }
    var afternoonScenes: [Scene] { scenes.filter { $0.dayNightType == .afternoon } }
    var customScenes:    [Scene] { scenes.filter { $0.dayNightType == .custom } }

    var totalDayDuration:       Int { dayScenes.reduce(0)       { $0 + $1.duration } }
    var totalNightDuration:     Int { nightScenes.reduce(0)     { $0 + $1.duration } }
    var totalDawnDuration:      Int { dawnScenes.reduce(0)      { $0 + $1.duration } }
    var totalDuskDuration:      Int { duskScenes.reduce(0)      { $0 + $1.duration } }
    var totalAfternoonDuration: Int { afternoonScenes.reduce(0) { $0 + $1.duration } }

    var allCast: [String] {
        Array(Set(scenes.flatMap { $0.cast })).sorted()
    }

    var hasCallSheetData: Bool {
        !callSheet.generalCallTime.isEmpty ||
        !callSheet.lunchTime.isEmpty       ||
        !callSheet.locations.isEmpty       ||
        !callSheet.castCallEntries.isEmpty ||
        !callSheet.notes.isEmpty
    }
}

// MARK: - ProjectData

struct ProjectData: nonisolated Codable, Equatable {
    var allScenes:          [Scene]
    var shootDays:          [ShootDay]
    var projectTitle:       String
    var createdDate:        Date
    var isShiftModeEnabled: Bool?
    var productionInfo:     ProductionInfo?
    /// The production's strip colors (#11). Nil in every file written before it and in a
    /// project that has neither adopted a device's overrides nor been edited in the
    /// color editor; resolve through `resolvedPalette`.
    var palette:            ScenePalette?

    /// Nonisolated so `ProjectCodec` can build one off the main actor.
    nonisolated init(
        allScenes:          [Scene],
        shootDays:          [ShootDay],
        projectTitle:       String = "Untitled Movie",
        isShiftModeEnabled: Bool?  = false,
        createdDate:        Date   = Date(),
        productionInfo:     ProductionInfo? = nil,
        palette:            ScenePalette? = nil
    ) {
        self.allScenes          = allScenes
        self.shootDays          = shootDays
        self.projectTitle       = projectTitle
        self.createdDate        = createdDate
        self.isShiftModeEnabled = isShiftModeEnabled
        self.productionInfo     = productionInfo
        self.palette            = palette
    }

    /// What every view and exporter draws with: the project's palette, or the standard
    /// code while it has none.
    nonisolated var resolvedPalette: ScenePalette { palette ?? .standard }

    /// The color editor's write: one slot's hex into the palette. A project that still has
    /// no palette gets the standard one with this slot changed, so a single pick never
    /// leaves a one-slot palette behind.
    mutating func setStripColor(_ hex: String, for slot: SceneColorSlot) {
        var palette = resolvedPalette
        palette.setHex(hex, for: slot)
        self.palette = palette
    }
}

// MARK: - Legacy Support

struct LegacyProjectData: nonisolated Codable {
    var allScenes: [Scene]
    var shootDays: [ShootDay]
}

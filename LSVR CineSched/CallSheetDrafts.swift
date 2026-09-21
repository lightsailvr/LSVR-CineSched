// CallSheetDrafts.swift
// The drafts of the two project-level editors (#20): what the call sheet editor holds
// for one shoot day between opening and Save, and what the production setup holds for
// the project. Pure and view-free, the same shape as `EditorDrafts.swift` (#19): the
// reading side carries every pre-fill the old sheets did on appear (the lunch default,
// the day's scene locations, the cast from the scenes, the crew from the setup, the
// notes from either field), the editing side is a handful of list mutations the rows
// and the detail pages call, and the writing side is one value back, so a Save is one
// `perform` and one undo step whatever the container. Every rule is pinned in
// `CallSheetDraftsTests`.
//
// A list entry added from the editor starts blank and is filled on its detail page, so
// `applied` drops the rows that stayed blank (no character and no actor, no role and
// no name, no location name) rather than writing an empty line onto the PDF; the old
// sheets refused such a row at the add button instead.

import Foundation

// MARK: - Call sheet

struct CallSheetDraft: Equatable {
    // General call and schedule
    var generalCallTime:  String
    var workDaySchedule:  String
    var quoteOfTheDay:    String

    // Milestones and meals
    var readyToShootTime: String
    var lunchTime:        String
    var snackTime:        String
    var dinnerTime:       String
    var wrapTime:         String
    var nearestHospital:  String

    // Weather
    var weatherTemp:       String
    var weatherCondition:  String
    var weatherPrecipWind: String
    var sunTimes:          String

    // Locations
    var basecampLocation: String
    var locations:        [Location]

    // Calls
    var castCalls: [CastCallEntry]
    var crewCalls: [CrewCallEntry]

    // Notes: the one text block; `productionNotes` is derived from it on write.
    var notes: String

    /// The day's call sheet as the editor shows it, with the pre-fills the old sheet
    /// did on appear: the production's default lunch when the day has none; the day's
    /// scene locations added to the day's list (address from the roster, else the
    /// scene's), and the roster's first location when the list is still empty; the cast
    /// from today's scenes when the sheet has no cast calls, else their scene numbers
    /// filled in where blank; the setup's crew when the sheet has no crew calls, else
    /// names and phones filled in by role where blank; and the notes from `notes` or,
    /// for older files, the joined `productionNotes`.
    init(day: ShootDay, productionInfo: ProductionInfo) {
        let sheet = day.callSheet
        generalCallTime   = sheet.generalCallTime
        workDaySchedule   = sheet.workDaySchedule
        quoteOfTheDay     = sheet.quoteOfTheDay
        readyToShootTime  = sheet.readyToShootTime
        lunchTime         = sheet.lunchTime.isEmpty ? productionInfo.defaultLunchTime : sheet.lunchTime
        snackTime         = sheet.snackTime
        dinnerTime        = sheet.dinnerTime
        wrapTime          = sheet.wrapTime
        nearestHospital   = sheet.nearestHospital
        weatherTemp       = sheet.weatherTemp
        weatherCondition  = sheet.weatherCondition
        weatherPrecipWind = sheet.weatherPrecipWind
        sunTimes          = sheet.sunTimes
        basecampLocation  = sheet.basecampLocation
        locations         = sheet.locations
        castCalls         = sheet.castCallEntries
        crewCalls         = sheet.crewCallEntries
        notes             = sheet.notes.isEmpty ? sheet.productionNotes.joined(separator: "\n") : sheet.notes

        // The day's scene locations, once each, then the roster's first as a fallback.
        for scene in day.scenes {
            let name = scene.realLocation.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !containsLocation(named: name) else { continue }
            let address = productionInfo.locationRoster
                .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
                .address ?? scene.locationAddress
            locations.append(Location(name: name, address: address))
        }
        if locations.isEmpty, let first = productionInfo.locationRoster.first {
            locations = [first]
        }

        if castCalls.isEmpty {
            populateCast(from: day, productionInfo: productionInfo)
        } else {
            for i in castCalls.indices where castCalls[i].sceneNumbers.isEmpty {
                castCalls[i].sceneNumbers = Self.sceneNumbers(for: castCalls[i].characterName, in: day)
            }
        }

        if crewCalls.isEmpty && !productionInfo.crew.isEmpty {
            loadCrew(from: productionInfo)
        } else {
            for i in crewCalls.indices {
                guard let matched = productionInfo.crew.first(where: {
                    $0.role.caseInsensitiveCompare(crewCalls[i].role) == .orderedSame
                }) else { continue }
                if crewCalls[i].name.trimmingCharacters(in: .whitespaces).isEmpty  { crewCalls[i].name  = matched.name }
                if crewCalls[i].phone.trimmingCharacters(in: .whitespaces).isEmpty { crewCalls[i].phone = matched.phone }
            }
        }
    }

    // MARK: Derived

    /// The on-set time a new cast call gets: ready-to-shoot, else the general call.
    var defaultOnSetTime: String { readyToShootTime.isEmpty ? generalCallTime : readyToShootTime }

    /// The roster locations not yet on the day, for the Add from Roster menu.
    func availableRosterLocations(in productionInfo: ProductionInfo) -> [Location] {
        productionInfo.locationRoster.filter { !containsLocation(named: $0.name) }
    }

    private func containsLocation(named name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return locations.contains { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }
    }

    /// The numbers of today's scenes the character is in, as the cast table shows them.
    static func sceneNumbers(for character: String, in day: ShootDay) -> String {
        let name = character.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "" }
        return day.scenes
            .filter { scene in scene.cast.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
            .map(\.extractedSceneNumber)
            .joined(separator: ", ")
    }

    // MARK: Locations

    /// Adds a location by name (blank is ignored); nothing stops a duplicate, as before.
    mutating func addLocation(name: String, address: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        locations.append(Location(name: clean, address: address.trimmingCharacters(in: .whitespaces)))
    }

    mutating func addRosterLocation(_ location: Location) {
        locations.append(location)
    }

    mutating func removeLocation(id: UUID) {
        locations.removeAll { $0.id == id }
    }

    // MARK: Cast calls

    /// Auto-populate from Scenes: every character in today's scenes, with the roster's
    /// actor and the scene numbers; an entry already there only gets its blanks filled.
    mutating func populateCast(from day: ShootDay, productionInfo: ProductionInfo) {
        for character in day.allCast {
            let actor = productionInfo.castList
                .first { $0.characterName.caseInsensitiveCompare(character) == .orderedSame }?
                .actorName ?? ""
            let scenes = Self.sceneNumbers(for: character, in: day)

            if let i = castCalls.firstIndex(where: { $0.characterName.caseInsensitiveCompare(character) == .orderedSame }) {
                if castCalls[i].sceneNumbers.isEmpty { castCalls[i].sceneNumbers = scenes }
                if castCalls[i].actorName.isEmpty    { castCalls[i].actorName    = actor }
            } else {
                castCalls.append(newCastCall(character: character, actor: actor, sceneNumbers: scenes))
            }
        }
    }

    /// A new cast call with the day's defaults (on set, wrap, location 1); returns its
    /// id so the editor can open its detail page. The scene numbers follow the character
    /// when one is given.
    @discardableResult
    mutating func addCastCall(character: String = "", actor: String = "", day: ShootDay) -> UUID {
        let clean = character.trimmingCharacters(in: .whitespaces)
        let entry = newCastCall(
            character:    clean,
            actor:        actor.trimmingCharacters(in: .whitespaces),
            sceneNumbers: Self.sceneNumbers(for: clean, in: day)
        )
        castCalls.append(entry)
        return entry.id
    }

    /// Fills a cast call's scene numbers from its character while they are blank (the
    /// detail page calls this as the character is typed).
    mutating func refreshSceneNumbers(ofCastCall id: UUID, in day: ShootDay) {
        guard let i = castCalls.firstIndex(where: { $0.id == id }), castCalls[i].sceneNumbers.isEmpty else { return }
        castCalls[i].sceneNumbers = Self.sceneNumbers(for: castCalls[i].characterName, in: day)
    }

    mutating func removeCastCall(id: UUID) {
        castCalls.removeAll { $0.id == id }
    }

    private func newCastCall(character: String, actor: String, sceneNumbers: String) -> CastCallEntry {
        CastCallEntry(
            characterName:   character,
            actorName:       actor,
            sceneNumbers:    sceneNumbers,
            ecdt:            "E",
            pickupTime:      "",
            hmuWardrobeTime: "",
            onSetTime:       defaultOnSetTime,
            wrapTime:        dinnerTime,
            locationIndex:   "1"
        )
    }

    // MARK: Crew calls

    /// Load Crew from Setup: every crew member not already listed by name and role, at
    /// the general call (07:30 AM when there is none).
    mutating func loadCrew(from productionInfo: ProductionInfo) {
        for member in productionInfo.crew {
            let listed = crewCalls.contains {
                $0.name.caseInsensitiveCompare(member.name) == .orderedSame &&
                $0.role.caseInsensitiveCompare(member.role) == .orderedSame
            }
            guard !listed else { continue }
            crewCalls.append(CrewCallEntry(
                role:     member.role,
                name:     member.name,
                callTime: generalCallTime.isEmpty ? "07:30 AM" : generalCallTime,
                phone:    member.phone
            ))
        }
    }

    /// A new crew call at the general call; returns its id for the detail page.
    @discardableResult
    mutating func addCrewCall(role: String = "", name: String = "", callTime: String = "", phone: String = "") -> UUID {
        let entry = CrewCallEntry(
            role:     role.trimmingCharacters(in: .whitespaces),
            name:     name.trimmingCharacters(in: .whitespaces),
            callTime: callTime.isEmpty ? generalCallTime : callTime,
            phone:    phone.trimmingCharacters(in: .whitespaces)
        )
        crewCalls.append(entry)
        return entry.id
    }

    mutating func removeCrewCall(id: UUID) {
        crewCalls.removeAll { $0.id == id }
    }

    // MARK: Writing back

    /// `sheet` with the draft applied. What the editor does not show (the contact
    /// overrides, the cast and crew overrides) is carried through; `productionNotes` is
    /// the notes' non-blank lines, as before; rows left blank are dropped.
    func applied(to sheet: CallSheetData) -> CallSheetData {
        var saved = sheet
        saved.generalCallTime   = generalCallTime
        saved.workDaySchedule   = workDaySchedule
        saved.quoteOfTheDay     = quoteOfTheDay
        saved.readyToShootTime  = readyToShootTime
        saved.lunchTime         = lunchTime
        saved.snackTime         = snackTime
        saved.dinnerTime        = dinnerTime
        saved.wrapTime          = wrapTime
        saved.basecampLocation  = basecampLocation
        saved.nearestHospital   = nearestHospital
        saved.weatherTemp       = weatherTemp
        saved.weatherCondition  = weatherCondition
        saved.weatherPrecipWind = weatherPrecipWind
        saved.sunTimes          = sunTimes
        saved.locations         = locations.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        saved.castCallEntries   = castCalls.filter {
            !$0.characterName.trimmingCharacters(in: .whitespaces).isEmpty ||
            !$0.actorName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        saved.crewCallEntries   = crewCalls.filter {
            !$0.role.trimmingCharacters(in: .whitespaces).isEmpty ||
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        saved.notes             = notes
        saved.productionNotes   = notes.isEmpty ? [] : notes
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return saved
    }
}

// MARK: - Production setup

struct ProductionSetupDraft: Equatable {
    var companyName:      String
    var directorName:     String
    var directorPhone:    String
    var producerName:     String
    var producerPhone:    String
    var adName:           String
    var adPhone:          String
    var defaultLunchTime: String
    var castList:         [CastMember]
    var crew:             [CrewMember]
    var locationRoster:   [Location]

    /// The production info as the editor shows it; an empty location roster is
    /// pre-filled from the scenes' breakdown, as the old sheet did on appear.
    init(info: ProductionInfo, scenes: [Scene]) {
        companyName      = info.companyName
        directorName     = info.directorName
        directorPhone    = info.directorPhone
        producerName     = info.producerName
        producerPhone    = info.producerPhone
        adName           = info.adName
        adPhone          = info.adPhone
        defaultLunchTime = info.defaultLunchTime
        castList         = info.castList
        crew             = info.crew
        locationRoster   = info.locationRoster
        if locationRoster.isEmpty {
            pullLocationsFromBreakdown(scenes: scenes)
        }
    }

    // MARK: Locations

    /// Pull from Breakdown: every distinct real location (or set, when a scene has no
    /// real location) of the script scenes, with its address, added once by name.
    mutating func pullLocationsFromBreakdown(scenes: [Scene]) {
        var names = Set(locationRoster.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        for scene in scenes where !scene.isBanner && !scene.isCalendarEvent {
            let real = scene.realLocation.trimmingCharacters(in: .whitespaces)
            let name = real.isEmpty ? scene.decoradoOnly.trimmingCharacters(in: .whitespaces) : real
            guard !name.isEmpty, names.insert(name.lowercased()).inserted else { continue }
            locationRoster.append(Location(name: name, address: scene.locationAddress.trimmingCharacters(in: .whitespaces)))
        }
    }

    @discardableResult
    mutating func addLocation(name: String = "", address: String = "") -> UUID {
        let location = Location(name: name.trimmingCharacters(in: .whitespaces), address: address.trimmingCharacters(in: .whitespaces))
        locationRoster.append(location)
        return location.id
    }

    mutating func removeLocation(id: UUID) {
        locationRoster.removeAll { $0.id == id }
    }

    // MARK: Cast

    @discardableResult
    mutating func addCastMember(actor: String = "", character: String = "") -> UUID {
        let member = CastMember(actorName: actor.trimmingCharacters(in: .whitespaces), characterName: character.trimmingCharacters(in: .whitespaces))
        castList.append(member)
        return member.id
    }

    mutating func removeCastMember(id: UUID) {
        castList.removeAll { $0.id == id }
    }

    /// Marks the member unavailable from `start` to `end` (a reversed pair is ordered).
    mutating func addUnavailableRange(start: Date, end: Date, toCastMember id: UUID) {
        guard let i = castList.firstIndex(where: { $0.id == id }) else { return }
        castList[i].unavailableRanges.append(DateRange(start: start, end: end))
    }

    mutating func removeUnavailableRange(id rangeID: UUID, fromCastMember id: UUID) {
        guard let i = castList.firstIndex(where: { $0.id == id }) else { return }
        castList[i].unavailableRanges.removeAll { $0.id == rangeID }
    }

    /// The character renames Save propagates into every scene's cast and the call
    /// sheets: members still in the roster whose character changed from a non-blank name
    /// to another non-blank name.
    func renamedCharacters(against original: ProductionInfo) -> [(old: String, new: String)] {
        let originals = Dictionary(original.castList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return castList.compactMap { member in
            guard let old = originals[member.id] else { return nil }
            let before = old.characterName.trimmingCharacters(in: .whitespaces)
            let after  = member.characterName.trimmingCharacters(in: .whitespaces)
            guard !before.isEmpty, !after.isEmpty, before != after else { return nil }
            return (before, after)
        }
    }

    // MARK: Crew

    @discardableResult
    mutating func addCrewMember(name: String = "", role: String = "", phone: String = "", isDailyDefault: Bool = false) -> UUID {
        let member = CrewMember(
            name:           name.trimmingCharacters(in: .whitespaces),
            role:           role.trimmingCharacters(in: .whitespaces),
            phone:          phone.trimmingCharacters(in: .whitespaces),
            isDailyDefault: isDailyDefault
        )
        crew.append(member)
        return member.id
    }

    mutating func removeCrewMember(id: UUID) {
        crew.removeAll { $0.id == id }
    }

    // MARK: Writing back

    /// `info` with the draft applied; the contact number and the schedule lock, which the
    /// editor does not show, are carried through. Rows left blank are dropped: a cast
    /// member with neither name, a crew member without a name, a location without one.
    func applied(to info: ProductionInfo) -> ProductionInfo {
        var saved = info
        saved.companyName      = companyName
        saved.directorName     = directorName
        saved.directorPhone    = directorPhone
        saved.producerName     = producerName
        saved.producerPhone    = producerPhone
        saved.adName           = adName
        saved.adPhone          = adPhone
        saved.defaultLunchTime = defaultLunchTime
        saved.castList         = castList.filter {
            !$0.actorName.trimmingCharacters(in: .whitespaces).isEmpty ||
            !$0.characterName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        saved.crew             = crew.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        saved.locationRoster   = locationRoster.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return saved
    }
}

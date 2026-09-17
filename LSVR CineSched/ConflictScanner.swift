// ConflictScanner.swift
// Cross-references the schedule against each cast member's marked unavailable dates
// and reports every scene where a character is scheduled to work while their actor is
// marked unavailable that day. Also detects duplicate scene numbers across the project.

import Foundation

struct ScheduleConflict: Identifiable {
    let id = UUID()
    let date: Date
    let sceneID: UUID
    let sceneTitle: String
    let character: String
    let actorDisplayName: String
}

struct ConflictScanner {

    /// Scans every scheduled scene against Production Setup's cast availability. A
    /// character only produces a conflict if they're matched to a cast member (by name)
    /// who has at least one unavailable range covering that day — unmatched/background
    /// character names are silently skipped, since there's no availability data for them.
    static func scan(shootDays: [ShootDay], productionInfo: ProductionInfo) -> [ScheduleConflict] {
        guard !productionInfo.castList.isEmpty else { return [] }
        var conflicts: [ScheduleConflict] = []

        // The roster keyed by normalized character name, with each member's unavailable
        // ranges already reduced to calendar days, built once. This runs on every change
        // to the project, and scanning the roster per character of every scene with two
        // trims and a compare each, then normalizing three dates per range, was most of
        // that cost (#34). The first roster entry for a name wins, as the linear search it
        // replaces did.
        let cal = Calendar.current
        var members: [String: (member: CastMember, unavailableDays: [ClosedRange<Date>])] = [:]
        for member in productionInfo.castList {
            let key = normalized(member.characterName)
            if members[key] == nil {
                // A range read from a file could be inverted; it matches nothing, as before.
                let days = member.unavailableRanges.compactMap { range -> ClosedRange<Date>? in
                    let first = cal.startOfDay(for: range.start), last = cal.startOfDay(for: range.end)
                    return first <= last ? first...last : nil
                }
                members[key] = (member, days)
            }
        }

        for day in shootDays {
            let dayStart = cal.startOfDay(for: day.date)
            for scene in day.scenes {
                for character in scene.cast {
                    guard let (member, unavailableDays) = members[normalized(character)], !unavailableDays.isEmpty else { continue }

                    if unavailableDays.contains(where: { $0.contains(dayStart) }) {
                        conflicts.append(ScheduleConflict(
                            date: day.date,
                            sceneID: scene.id,
                            sceneTitle: scene.displayTitle,
                            character: character,
                            actorDisplayName: member.displayString
                        ))
                    }
                }
            }
        }
        return conflicts.sorted { $0.date < $1.date }
    }

    /// The character-name join's key: trimmed and case-folded the same way
    /// `caseInsensitiveCompare` folds, so "ALEX MORGAN" and " alex morgan " match.
    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).folding(options: .caseInsensitive, locale: nil)
    }

    /// Just the set of dates with at least one conflict — cheap to check per date header
    /// when deciding whether to show a warning badge on the calendar.
    static func conflictDates(_ conflicts: [ScheduleConflict]) -> Set<Date> {
        let cal = Calendar.current
        return Set(conflicts.map { cal.startOfDay(for: $0.date) })
    }

    /// The IDs of scenes that specifically contain a conflicting cast member — used to
    /// turn just those scene strips red, rather than every strip on a day that merely
    /// happens to share a date with an unrelated conflict.
    static func conflictSceneIDs(_ conflicts: [ScheduleConflict]) -> Set<UUID> {
        Set(conflicts.map { $0.sceneID })
    }

    /// Scene IDs whose scene number collides with another scene's, anywhere in the
    /// project — the Boneyard or any scheduled day. Numbers are compared by their
    /// parsed (numeric, letter) value, so "3" and "03" count as the same number but
    /// "3" and "3A" don't; blank scene numbers are never flagged, since most scenes
    /// may not have one.
    static func duplicateSceneNumberIDs(allScenes: [Scene], shootDays: [ShootDay]) -> Set<UUID> {
        let scenes = allScenes + shootDays.flatMap { $0.scenes }
        var idsByNumber: [String: [UUID]] = [:]
        for scene in scenes {
            guard let parsed = Scene.parseSceneNumber(scene.sceneNumber) else { continue }
            let key = "\(parsed.number)\(parsed.letter)"
            idsByNumber[key, default: []].append(scene.id)
        }
        return Set(idsByNumber.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}

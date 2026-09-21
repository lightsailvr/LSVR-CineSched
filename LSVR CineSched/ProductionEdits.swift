// ProductionEdits.swift
// The production-wide edits the iPhone's Production tab makes (#28, the M4 review), as
// pure mutations of `ProjectData` so the tab stays thin and each is one `perform`: a
// character rename, which reaches every scene's cast in the Boneyard and on the days and
// every call sheet's cast override (the character name join, CONTEXT.md: the same name,
// compared without case, everywhere), and Lock Schedule / Unlock Schedule, which store
// and clear the snapshot of each character's working days that the Schedule Lock Report
// compares the board against. The rules are the ones `ContentView` applies on the Mac
// (`renameCastCharacter`, `lockSchedule`, `unlockSchedule`, which keep their own copies:
// switching the Mac over is a follow-up with pinning tests, see learnings 2026-09-21).
// Tested in `ProductionEditsTests`.

import Foundation

extension ProjectData {

    // MARK: - Character rename

    /// Renames the character `oldName` to `newName` in every scene's cast and every call
    /// sheet's cast override, matching without case. Returns false, changing nothing, when
    /// either name is blank or they differ only by case (the Mac's rule); a valid rename of
    /// a character nobody has is applied and returns true.
    @discardableResult
    mutating func renameCharacter(from oldName: String, to newName: String) -> Bool {
        let old = oldName.trimmingCharacters(in: .whitespaces)
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard !old.isEmpty, !new.isEmpty, old.caseInsensitiveCompare(new) != .orderedSame else { return false }

        func renamed(_ cast: [String]) -> [String] {
            cast.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }

        for i in allScenes.indices {
            allScenes[i].cast = renamed(allScenes[i].cast)
        }
        for d in shootDays.indices {
            for s in shootDays[d].scenes.indices {
                shootDays[d].scenes[s].cast = renamed(shootDays[d].scenes[s].cast)
            }
            if let override = shootDays[d].callSheet.castOverride {
                shootDays[d].callSheet.castOverride = renamed(override)
            }
        }
        return true
    }

    // MARK: - Schedule lock

    /// Lock Schedule: the working days of every character as the board stands, dated
    /// `now`, into the production info (created if the project has none). The report
    /// (`ScheduleLockScanner`) lists what moves from here.
    mutating func lockSchedule(now: Date = Date()) {
        let working = ScheduleLockScanner.currentWorkingDays(shootDays: shootDays)
        var stored: [String: [Date]] = [:]
        for (character, dates) in working { stored[character] = dates.sorted() }
        var info = productionInfo ?? ProductionInfo()
        info.scheduleLock = ScheduleLock(lockedAt: now, workingDays: stored)
        productionInfo = info
    }

    /// Unlock Schedule: the snapshot is dropped. Returns false, changing nothing, when the
    /// schedule was not locked.
    @discardableResult
    mutating func unlockSchedule() -> Bool {
        guard productionInfo?.scheduleLock != nil else { return false }
        productionInfo?.scheduleLock = nil
        return true
    }
}

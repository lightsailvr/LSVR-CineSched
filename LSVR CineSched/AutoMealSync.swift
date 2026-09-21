// AutoMealSync.swift
// The auto-meal strips a day carries follow its call sheet: one strip per milestone with
// a time (general call, ready to shoot, lunch, snack, dinner, wrap), retitled when the time
// changes, removed when the time is cleared, added at its place when a time appears. A
// pure function of the day, so the Stripboard runs it when a section appears and after its
// own call sheet editor saves, and the inspector's call sheet editor (#20, review) runs it
// inside the same edit as the save, so the strips and the times undo as one step and a
// visible section never shows last night's lunch.

import Foundation

extension ShootDay {

    /// The day's scenes with the auto-meal strips brought in line with `callSheet`.
    /// Equal to `scenes` when nothing needs to change, so a caller can skip the write.
    func scenesWithSyncedAutoMeals() -> [Scene] {
        let cs = callSheet
        let itemsToEnsure: [(kind: MealKind, time: String)] = [
            (.generalCall,  cs.generalCallTime),
            (.readyToShoot, cs.readyToShootTime),
            (.lunch,        cs.lunchTime),
            (.snack,        cs.snackTime),
            (.dinner,       cs.dinnerTime),
            (.wrap,         cs.wrapTime)
        ]

        var updatedScenes = scenes

        for item in itemsToEnsure {
            let timeClean = item.time.trimmingCharacters(in: .whitespaces)
            let existingIdx = updatedScenes.firstIndex(where: { $0.isAutoMeal && $0.mealKind == item.kind })

            if !timeClean.isEmpty {
                let colorHex: String
                switch item.kind {
                case .generalCall:  colorHex = "1E3A8A"
                case .readyToShoot: colorHex = "064E3B"
                case .lunch, .snack, .dinner: colorHex = "18181B"
                case .wrap:         colorHex = "991B1B"
                }

                if let idx = existingIdx {
                    let title = "\(item.kind.icon) \(item.kind.defaultTitle) (\(timeClean))"
                    updatedScenes[idx].title = title
                    updatedScenes[idx].bannerTitle = title
                    updatedScenes[idx].summary = timeClean
                    updatedScenes[idx].customStartTime = timeClean
                    updatedScenes[idx].bannerColorHex = colorHex
                } else {
                    let newStrip = Scene.createAutoMeal(kind: item.kind, timeString: timeClean)
                    if item.kind == .generalCall {
                        updatedScenes.insert(newStrip, at: 0)
                    } else if item.kind == .readyToShoot {
                        // Right after the general call strip when there is one, else first.
                        let insertIdx = updatedScenes.firstIndex(where: { $0.isAutoMeal && $0.mealKind == .generalCall }) != nil ? 1 : 0
                        updatedScenes.insert(newStrip, at: min(insertIdx, updatedScenes.count))
                    } else {
                        updatedScenes.append(newStrip)
                    }
                }
            } else if let idx = existingIdx {
                updatedScenes.remove(at: idx)
            }
        }

        return updatedScenes
    }
}

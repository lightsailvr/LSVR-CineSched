// BannerAppearance.swift
// How a banner strip looks (the M4 review): the fill and the label the Mac Stripboard's
// `BannerStripRow` has always drawn, as pure functions of the `Scene`, so the iPhone's
// `PhoneStripRow` draws the same strip for the same banner. The rules are the fork's:
// an auto-meal is filled by its kind (the general call navy, ready-to-shoot green, wrap
// crimson, the meals near black); any other banner is near black when it is a meal — by
// type, or by a meal word in its title in English or the fork's Spanish — or wears the
// legacy amber, else its own color, else slate. The label is an auto-meal's icon and
// kind; otherwise the title (never `bannerTitle`, which the Mac does not read) with the
// "(01:00 PM)" suffix the generated titles carry removed, the default notice titles
// folded to "Notice" and the fork's bilingual meal titles folded to their English word.
//
// Both rows draw per strip per redraw (#34), so the time-suffix pattern is one
// `NSRegularExpression` built once, not a `.regularExpression` replace per row. Tested
// in `BannerAppearanceTests`, pinned to the Mac row's output before the move.

import Foundation

extension Scene {

    // MARK: - Fill

    /// The banner strip's fill, as a hex string for `Color(hex:)`.
    var bannerFillHex: String {
        if isAutoMeal {
            switch mealKind {
            case .generalCall:  return "1E3A8A"
            case .readyToShoot: return "064E3B"
            case .wrap:         return "991B1B"
            case .lunch, .snack, .dinner, nil: return "18181B"
            }
        }
        if bannerType == .mealBreak || Self.mentionsAMeal(title) {
            return "18181B"
        }
        if bannerColorHex == "F59E0B" {
            return "18181B"
        }
        return bannerColorHex.isEmpty ? "334155" : bannerColorHex
    }

    /// The fork's meal words, in English and Spanish, anywhere in the title.
    private static let mealWords = ["almuerzo", "lunch", "cena", "dinner", "snack", "merienda"]

    private static func mentionsAMeal(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return mealWords.contains { lowered.contains($0) }
    }

    // MARK: - Label

    /// What the banner strip prints.
    var bannerDisplayLabel: String {
        if let kind = mealKind {
            return "\(kind.icon) \(kind.defaultTitle)"
        }
        let raw = Self.strippingTimeSuffix(from: title)
        if Self.defaultNoticeTitles.contains(raw) {
            return L("Notice")
        }
        if raw.contains("ALMUERZO / LUNCH") || raw.contains("LUNCH / ALMUERZO") {
            return "🍽️ \(L("LUNCH"))"
        }
        if raw.contains("MERIENDA / SNACK") || raw.contains("SNACK / MERIENDA") {
            return "☕ \(L("SNACK"))"
        }
        if raw.contains("CENA / DINNER") || raw.contains("DINNER / CENA") {
            return "🍕 \(L("DINNER"))"
        }
        if raw.contains("FIN DE RODAJE / WRAP") || raw.contains("WRAP / FIN DE RODAJE") {
            return "🎬 \(L("WRAP"))"
        }
        if raw.contains("READY TO SHOOT / EN SET") {
            return "🎬 \(L("READY TO SHOOT"))"
        }
        return raw
    }

    /// The titles the banner input and the fork gave an untitled notice.
    private static let defaultNoticeTitles: Set<String> = ["Notice / Note", "Aviso / Nota", "Notice", "Nota", "Aviso"]

    /// "(01:00 PM)", "( 1:00 pm )", "(13:00)" and the space before it, as the generated
    /// titles append them. Built once.
    private static let timeSuffix = try! NSRegularExpression(pattern: #"\s*\(\s*\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?\s*\)"#)

    private static func strippingTimeSuffix(from title: String) -> String {
        let range = NSRange(title.startIndex..., in: title)
        return timeSuffix.stringByReplacingMatches(in: title, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

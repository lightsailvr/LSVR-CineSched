//
//  BannerAppearanceTests.swift
//  LSVR CineSchedTests
//
//  The banner strip's fill and label (BannerAppearance.swift), pinned to what the Mac
//  Stripboard's `BannerStripRow` drew before the rules moved out of it: an auto-meal by
//  its kind, a meal banner by its type or by a meal word in its title (English and the
//  fork's Spanish), the legacy amber, the fallback slate; the label an auto-meal's kind,
//  otherwise the title without the "(01:00 PM)" suffix and with the fork's bilingual
//  titles folded to their English word. The phone's `PhoneStripRow` draws the same.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct BannerAppearanceTests {

    private func banner(_ title: String, type: BannerType = .notice, hex: String = "8B5CF6") -> Scene {
        Scene.createBanner(type: type, title: title, colorHex: hex)
    }

    // MARK: - Fill

    @Test func autoMealsFillByTheirKind() {
        #expect(Scene.createAutoMeal(kind: .generalCall,  timeString: "7:00 AM").bannerFillHex == "1E3A8A")
        #expect(Scene.createAutoMeal(kind: .readyToShoot, timeString: "7:30 AM").bannerFillHex == "064E3B")
        #expect(Scene.createAutoMeal(kind: .lunch,        timeString: "1:00 PM").bannerFillHex == "18181B")
        #expect(Scene.createAutoMeal(kind: .snack,        timeString: "4:00 PM").bannerFillHex == "18181B")
        #expect(Scene.createAutoMeal(kind: .dinner,       timeString: "7:00 PM").bannerFillHex == "18181B")
        #expect(Scene.createAutoMeal(kind: .wrap,         timeString: "8:00 PM").bannerFillHex == "991B1B")
    }

    @Test func anAutoMealWithNoKindIsDark() {
        var strip = Scene.createAutoMeal(kind: .lunch, timeString: "1:00 PM")
        strip.mealKind       = nil
        strip.bannerColorHex = "14B8A6"
        #expect(strip.bannerFillHex == "18181B")
    }

    @Test func aMealBreakBannerIsDarkWhateverItsColor() {
        #expect(banner("Catering", type: .mealBreak, hex: "14B8A6").bannerFillHex == "18181B")
    }

    @Test func aMealWordInTheTitleDarkensAnyBanner() {
        for word in ["Lunch", "almuerzo", "Dinner", "CENA", "snack", "Merienda"] {
            #expect(banner("Second \(word) call", type: .companyMove, hex: "14B8A6").bannerFillHex == "18181B", "\(word)")
        }
    }

    @Test func theLegacyAmberIsDark() {
        #expect(banner("Move", type: .companyMove, hex: "F59E0B").bannerFillHex == "18181B")
    }

    @Test func aBannerWithoutAColorIsSlate() {
        #expect(banner("Move", type: .companyMove, hex: "").bannerFillHex == "334155")
    }

    @Test func anyOtherBannerKeepsItsColor() {
        #expect(banner("Move to the yard", type: .companyMove, hex: "14B8A6").bannerFillHex == "14B8A6")
        #expect(banner("Notice", type: .notice, hex: "8B5CF6").bannerFillHex == "8B5CF6")
    }

    @Test func aCalendarEventIsNotABannerFillButStillResolves() {
        // Events are chips, not strips; the rule still answers with their color.
        #expect(Scene.createCalendarEvent(title: "Tech scout", time: "9:00 AM").bannerFillHex == "6366F1")
    }

    // MARK: - Label

    @Test func anAutoMealIsLabelledByItsKind() {
        #expect(Scene.createAutoMeal(kind: .lunch, timeString: "1:00 PM").bannerDisplayLabel == "🍽️ \(L("LUNCH"))")
        #expect(Scene.createAutoMeal(kind: .wrap,  timeString: "8:00 PM").bannerDisplayLabel == "🎬 \(L("WRAP"))")
    }

    @Test func theTimeSuffixIsDropped() {
        #expect(banner("Company Move (01:00 PM)").bannerDisplayLabel == "Company Move")
        #expect(banner("Company Move ( 1:00 pm )").bannerDisplayLabel == "Company Move")
        #expect(banner("Move (13:00)").bannerDisplayLabel == "Move")
        #expect(banner("  Move  ").bannerDisplayLabel == "Move")
    }

    @Test func theLabelReadsTheTitleNotTheBannerTitle() {
        // The Mac reads `title`; a banner whose two titles diverged shows the strip's.
        var strip = banner("Shown")
        strip.bannerTitle = "Hidden"
        #expect(strip.bannerDisplayLabel == "Shown")
    }

    @Test func theDefaultNoticeTitlesFoldToNotice() {
        for title in ["Notice / Note", "Aviso / Nota", "Notice", "Nota", "Aviso"] {
            #expect(banner(title).bannerDisplayLabel == L("Notice"), Comment(rawValue: title))
        }
    }

    @Test func theForksBilingualMealTitlesFoldToTheirEnglishWord() {
        #expect(banner("ALMUERZO / LUNCH (12:30 PM)").bannerDisplayLabel == "🍽️ \(L("LUNCH"))")
        #expect(banner("LUNCH / ALMUERZO").bannerDisplayLabel            == "🍽️ \(L("LUNCH"))")
        #expect(banner("MERIENDA / SNACK").bannerDisplayLabel            == "☕ \(L("SNACK"))")
        #expect(banner("SNACK / MERIENDA").bannerDisplayLabel            == "☕ \(L("SNACK"))")
        #expect(banner("CENA / DINNER").bannerDisplayLabel               == "🍕 \(L("DINNER"))")
        #expect(banner("DINNER / CENA").bannerDisplayLabel               == "🍕 \(L("DINNER"))")
        #expect(banner("FIN DE RODAJE / WRAP").bannerDisplayLabel        == "🎬 \(L("WRAP"))")
        #expect(banner("WRAP / FIN DE RODAJE").bannerDisplayLabel        == "🎬 \(L("WRAP"))")
        #expect(banner("READY TO SHOOT / EN SET").bannerDisplayLabel     == "🎬 \(L("READY TO SHOOT"))")
    }

    @Test func anyOtherTitleIsShownAsIs() {
        #expect(banner("Move to the yard").bannerDisplayLabel == "Move to the yard")
    }
}
